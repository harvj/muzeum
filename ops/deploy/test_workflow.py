import contextlib
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit

import muzeum_deploy as deploy

OLD, NEW = 'a' * 40, 'b' * 40


class FixtureHost:
    """Disposable filesystem/services adapter; exercises the actual deployment state machine."""
    def __init__(self, root, migration=False, fail=None):
        self.root, self.fail = Path(root).resolve(), fail
        self.sha, self.running, self.public = OLD, True, True
        self.events = []
        self.pending = []
        self.candidate = self.root / 'candidate'
        (self.candidate / 'config/deploy').mkdir(parents=True)
        (self.candidate / 'db/migrate').mkdir(parents=True)
        if migration:
            path = 'db/migrate/20261118000000_add_operator_note.rb'
            body = 'class AddOperatorNote < ActiveRecord::Migration[8.1]\n def change\n add_column :scrobbles, :operator_note, :text\n end\nend\n'
            (self.candidate / path).write_text(body)
            self.pending = [{'database': 'primary', 'version': '20261118000000', 'path': path, 'sha256': hashlib.sha256(body.encode()).hexdigest()}]
        reviews = {item['path']: dict(sha256=item['sha256'], risk='additive', quiesce=True, review='fixture-reviewed-additive') for item in self.pending}
        (self.candidate / 'config/deploy/migrations.json').write_text(json.dumps({'format': 1, 'migrations': reviews}))

    def event(self, name):
        self.events.append(name)
        if name == self.fail:
            raise RuntimeError('Injected ' + name + ' failure')

    @contextlib.contextmanager
    def backup_lock(self):
        yield

    def revision(self):
        return self.sha

    def release(self, path, sha):
        if Path(path) != self.candidate or sha != NEW:
            raise RuntimeError('Wrong fixture release')
        return self.candidate

    def published(self, release, sha):
        return (self.root / 'current').resolve() == Path(release) and self.sha == sha

    def preflight(self):
        self.event('preflight')
        return {'revision': OLD, 'health': 'passed'}

    def inspect(self, release):
        self.event('inspect')
        return {'pending': self.pending, 'databases': {'primary': {'triggers': ['immutable_source']}}}

    def fingerprint(self, specification=None):
        self.event('fingerprint')
        return {'source': 'preserved'}

    def backup_restore(self, sha):
        self.event('backup')
        self.event('restore')
        return {'snapshot_id': 'c' * 64, 'release_sha': sha}

    def withdraw(self, sha):
        self.event('withdraw')
        self.public, self.running = False, False

    def migrate(self, release, sha):
        self.event('migration')
        self.pending = []

    def publish(self):
        self.event('publication')
        self.sha = NEW
        (self.root / 'current').symlink_to(self.candidate)

    def start(self):
        self.event('restart')
        self.running = True

    def health(self):
        self.event('health')
        if not self.running:
            raise RuntimeError('Fixture is stopped')

    def activate(self, sha):
        self.event('activation')
        self.public = True

    def stop(self):
        self.event('stop')
        self.running = False


class FixtureDeployment(deploy.Deployment):
    def run(self, *args, **kwargs):
        try:
            return super().run(*args, **kwargs)
        except RuntimeError as error:
            active = self.root / 'active.json'
            diagnostic = json.loads(active.read_text()).get('diagnostic', '') if active.exists() else ''
            raise RuntimeError(str(error) + '; synthetic fixture diagnostic: ' + diagnostic) from error


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.token = secrets.token_hex(16)

    def workflow(self, migration=False, fail=None):
        host = FixtureHost(self.root, migration, fail)
        return host, FixtureDeployment(host, self.root / 'audit')

    def success(self, host, flow):
        flow.run('begin', NEW, self.token)
        flow.run('prepare', NEW, self.token, str(host.candidate))
        host.publish()
        flow.run('finish', NEW, self.token)
        return flow.run('complete', NEW, self.token)

    def test_code_only_skips_backup_and_migration_and_keeps_route_available(self):
        host, flow = self.workflow()
        receipt = self.success(host, flow)
        self.assertEqual(receipt['phase'], 'complete')
        self.assertTrue(host.public and host.running)
        self.assertFalse({'backup', 'restore', 'withdraw', 'migration'} & set(host.events))
        self.assertFalse((self.root / 'audit/active.json').exists())

    def test_additive_migration_has_two_fresh_recovery_gates(self):
        host, flow = self.workflow(True)
        receipt = self.success(host, flow)
        self.assertEqual(host.events.count('restore'), 2)
        self.assertLess(host.events.index('restore'), host.events.index('migration'))
        self.assertLess(host.events.index('migration'), host.events.index('publication'))
        self.assertLess(host.events.index('health'), host.events.index('activation'))
        self.assertEqual(receipt['pre_backup']['release_sha'], OLD)
        self.assertEqual(receipt['post_backup']['release_sha'], NEW)
        self.assertTrue(host.public and host.running)

    def test_failures_never_roll_back_or_restore_live_data(self):
        for failure in ('backup', 'restore', 'migration', 'publication', 'restart', 'health', 'activation'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as root:
                host = FixtureHost(root, True, failure)
                flow = FixtureDeployment(host, Path(root) / 'audit')
                flow.run('begin', NEW, self.token)
                with self.assertRaises(RuntimeError):
                    flow.run('prepare', NEW, self.token, str(host.candidate))
                    try:
                        host.publish()
                    except RuntimeError:
                        flow.run('fail', NEW, self.token)
                    flow.run('finish', NEW, self.token)
                self.assertFalse(host.public or host.running)
                record = json.loads((Path(root) / 'audit/active.json').read_text())
                self.assertEqual(record['phase'], 'failed')
                self.assertNotIn('complete', host.events)

    def test_code_only_publication_failure_keeps_old_service_and_restart_failure_withdraws_new(self):
        for failure in ('publication', 'restart', 'health'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as root:
                host = FixtureHost(root, False, failure)
                flow = FixtureDeployment(host, Path(root) / 'audit')
                flow.run('begin', NEW, self.token)
                flow.run('prepare', NEW, self.token, str(host.candidate))
                with self.assertRaises(RuntimeError):
                    try:
                        host.publish()
                    except RuntimeError:
                        flow.run('fail', NEW, self.token)
                    flow.run('finish', NEW, self.token)
                if failure == 'publication':
                    self.assertTrue(host.public and host.running)
                    self.assertEqual(host.sha, OLD)
                else:
                    self.assertFalse(host.public or host.running)
                    self.assertEqual(host.sha, NEW)

    def test_post_backup_failure_stops_published_candidate(self):
        host, flow = self.workflow(True)
        flow.run('begin', NEW, self.token)
        flow.run('prepare', NEW, self.token, str(host.candidate))
        host.publish()
        host.fail = 'backup'
        with self.assertRaises(RuntimeError):
            flow.run('finish', NEW, self.token)
        self.assertEqual(host.sha, NEW)
        self.assertFalse(host.running or host.public)

    def test_dirty_migration_hash_and_destructive_reviews_are_refused_before_withdrawal(self):
        for kind in ('hash', 'destructive', 'missing'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as root:
                host = FixtureHost(root, True)
                path = host.candidate / 'config/deploy/migrations.json'
                data = json.loads(path.read_text())
                review = next(iter(data['migrations'].values()))
                if kind == 'hash':
                    review['sha256'] = '0' * 64
                elif kind == 'destructive':
                    review['risk'] = 'destructive'
                else:
                    data['migrations'] = {}
                path.write_text(json.dumps(data))
                flow = FixtureDeployment(host, Path(root) / 'audit')
                flow.run('begin', NEW, self.token)
                with self.assertRaises(RuntimeError):
                    flow.run('prepare', NEW, self.token, str(host.candidate))
                self.assertTrue(host.public and host.running)
                self.assertNotIn('migration', host.events)

    def test_crash_lock_and_wrong_token_cannot_be_overridden(self):
        host, flow = self.workflow()
        flow.run('begin', NEW, self.token)
        with self.assertRaises(RuntimeError):
            flow.run('begin', NEW, secrets.token_hex(16))
        with self.assertRaises(RuntimeError):
            flow.run('prepare', NEW, secrets.token_hex(16), str(host.candidate))
        self.assertTrue((self.root / 'audit/active.json').exists())

    def test_evidence_or_source_protection_changes_block_publication(self):
        for altered in ('evidence', 'triggers'):
            with self.subTest(altered=altered), tempfile.TemporaryDirectory() as root:
                host = FixtureHost(root, True)
                original = host.migrate
                def changed(release, sha):
                    original(release, sha)
                    if altered == 'evidence':
                        host.fingerprint = lambda specification=None: {'source': 'corrupted'}
                    else:
                        host.inspect = lambda release: {'pending': [], 'databases': {'primary': {'triggers': []}}}
                host.migrate = changed
                flow = FixtureDeployment(host, Path(root) / 'audit')
                flow.run('begin', NEW, self.token)
                with self.assertRaises(RuntimeError):
                    flow.run('prepare', NEW, self.token, str(host.candidate))
                self.assertFalse(host.public or host.running)
                self.assertEqual(host.sha, OLD)


@unittest.skipUnless(os.environ.get('MUZEUM_DEPLOY_TEST_PGPORT'), 'Dedicated disposable PostgreSQL port required')
class DatabaseRehearsalTests(WorkflowTests):
    """Real four-database dumps/restores, Restic encryption and Rails additive migration."""
    def workflow(self, migration=False, fail=None):
        host = DatabaseHost(self.root, migration, fail)
        self.addCleanup(host.cleanup)
        return host, FixtureDeployment(host, self.root / 'audit')

    def test_real_migration_failure_keeps_source_data_and_committed_schema(self):
        host, flow = self.workflow(True)
        flow.run('begin', NEW, self.token)
        original = host.migrate
        def committed_then_failed(release, sha):
            original(release, sha)
            raise RuntimeError('Simulated failure after committed migration')
        host.migrate = committed_then_failed
        with self.assertRaises(RuntimeError):
            flow.run('prepare', NEW, self.token, str(host.candidate))
        self.assertEqual(host.query(host.databases[0], 'SELECT count(*) FROM scrobbles'), '1000')
        self.assertEqual(host.query(host.databases[0], "SELECT count(*) FROM information_schema.columns WHERE table_name='scrobbles' AND column_name='operator_note'"), '1')
        self.assertFalse(host.running or host.public)

    def test_real_backup_failure_does_not_run_migration(self):
        host, flow = self.workflow(True)
        host.restic = '/usr/bin/false'
        flow.run('begin', NEW, self.token)
        with self.assertRaises(RuntimeError):
            flow.run('prepare', NEW, self.token, str(host.candidate))
        self.assertNotIn('migration', host.events)
        self.assertEqual(host.query(host.databases[0], 'SELECT count(*) FROM scrobbles'), '1000')
        self.assertFalse(host.running or host.public)

    def test_real_failed_rails_transaction_is_not_reversed_or_published(self):
        host, flow = self.workflow(True)
        item = host.pending[0]
        path = host.candidate / item['path']
        path.write_text(path.read_text().replace('add_column :scrobbles, :operator_note, :text', 'add_column :scrobbles, :operator_note, :text; execute "SELECT missing_fixture_function()"'))
        item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest = host.candidate / 'config/deploy/migrations.json'
        data = json.loads(manifest.read_text())
        data['migrations'][item['path']]['sha256'] = item['sha256']
        manifest.write_text(json.dumps(data))
        flow.run('begin', NEW, self.token)
        with self.assertRaises(RuntimeError):
            flow.run('prepare', NEW, self.token, str(host.candidate))
        self.assertEqual(host.query(host.databases[0], 'SELECT count(*) FROM scrobbles'), '1000')
        self.assertEqual(host.query(host.databases[0], "SELECT count(*) FROM information_schema.columns WHERE table_name='scrobbles' AND column_name='operator_note'"), '0')
        self.assertNotIn('publication', host.events)
        self.assertFalse(host.running or host.public)


class DatabaseHost(FixtureHost):
    def __init__(self, root, migration=False, fail=None):
        super().__init__(root, migration, fail)
        self.pg = Path(os.environ.get('MUZEUM_DEPLOY_TEST_PGBIN', '/usr/bin'))
        self.env = dict(os.environ, PGHOST='127.0.0.1', PGPORT=os.environ['MUZEUM_DEPLOY_TEST_PGPORT'])
        self.databases = ['muzeum_deploy_test_' + secrets.token_hex(6) for _ in range(4)]
        self.restic = os.environ.get('MUZEUM_DEPLOY_TEST_RESTIC', 'restic')
        password = self.root / 'password'
        password.write_text(secrets.token_hex(32))
        password.chmod(0o600)
        self.restic_env = dict(self.env, RESTIC_PASSWORD_FILE=str(password), RESTIC_REPOSITORY=str(self.root / 'repository'))
        self.invoke([self.restic, 'init'], env=self.restic_env)
        for database in self.databases:
            self.invoke([str(self.pg / 'createdb'), database])
            self.query(database, '''CREATE TABLE scrobbles(id bigint PRIMARY KEY,payload jsonb NOT NULL,played_at timestamptz NOT NULL);
INSERT INTO scrobbles SELECT i,jsonb_build_object('artist','Synthetic','track','Fixture '||i), '2025-01-01Z'::timestamptz+(i||' seconds')::interval FROM generate_series(1,1000) i;
CREATE TABLE import_pages(id bigint PRIMARY KEY, raw_body text NOT NULL);
INSERT INTO import_pages VALUES(1,'<synthetic/>');
CREATE TABLE users(id bigint PRIMARY KEY,oidc_issuer text,oidc_subject text);
INSERT INTO users VALUES(1,'https://auth.example.test','synthetic-principal');
CREATE TABLE decisions(id bigint PRIMARY KEY,actor text,evidence jsonb);
INSERT INTO decisions VALUES(1,'fixture-operator','{"reason":"preserve interpretation history"}');
CREATE FUNCTION retain_source() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'immutable'; END; $$;
CREATE TRIGGER immutable_source BEFORE UPDATE OR DELETE ON scrobbles FOR EACH ROW EXECUTE FUNCTION retain_source();''')

    def invoke(self, argv, env=None, input=None):
        result = subprocess.run(argv, env=env or self.env, input=input, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError('Disposable fixture subprocess failed: ' + result.stderr[-1500:])
        return result.stdout.strip()

    def query(self, database, sql):
        assert database.startswith('muzeum_deploy_test_')
        return self.invoke([str(self.pg / 'psql'), '-XAt', '-v', 'ON_ERROR_STOP=1', '-d', database], input=sql)

    def fingerprint(self, specification=None):
        self.event('fingerprint')
        return {database: {table: self.query(database, 'SELECT md5(string_agg(row_to_json(t)::text,\'\' ORDER BY id)) FROM (SELECT ' + columns + ' FROM ' + table + ') t')
                           for table, columns in [('scrobbles', 'id,payload,played_at'), ('import_pages', 'id,raw_body'), ('users', 'id,oidc_issuer,oidc_subject'), ('decisions', 'id,actor,evidence')]}
                for database in self.databases}

    def backup_restore(self, sha):
        self.event('backup')
        capture = self.root / ('capture-' + secrets.token_hex(4))
        capture.mkdir()
        fingerprints = self.fingerprint()
        for database in self.databases:
            self.invoke([str(self.pg / 'pg_dump'), '-Fc', '-f', str(capture / (database + '.dump')), database])
        output = self.invoke([self.restic, 'backup', '--json', str(capture)], env=self.restic_env)
        snapshot = json.loads(output.splitlines()[-1])['snapshot_id']
        self.invoke([self.restic, 'check', '--read-data'], env=self.restic_env)
        shutil.rmtree(capture)
        self.event('restore')
        restored = self.root / ('restore-' + secrets.token_hex(4))
        self.invoke([self.restic, 'restore', snapshot, '--target', str(restored), '--verify'], env=self.restic_env)
        for database in self.databases:
            target = 'muzeum_deploy_test_' + secrets.token_hex(6)
            self.invoke([str(self.pg / 'createdb'), target])
            try:
                self.invoke([str(self.pg / 'pg_restore'), '--no-owner', '--no-acl', '--exit-on-error', '-d', target, str(restored / str(capture).lstrip('/') / (database + '.dump'))])
                for table, columns in [('scrobbles', 'id,payload,played_at'), ('import_pages', 'id,raw_body'), ('users', 'id,oidc_issuer,oidc_subject'), ('decisions', 'id,actor,evidence')]:
                    actual = self.query(target, 'SELECT md5(string_agg(row_to_json(t)::text,\'\' ORDER BY id)) FROM (SELECT ' + columns + ' FROM ' + table + ') t')
                    if actual != fingerprints[database][table]:
                        raise RuntimeError('Disposable restored fingerprint mismatch')
            finally:
                self.invoke([str(self.pg / 'dropdb'), target])
        return {'snapshot_id': snapshot, 'release_sha': sha, 'databases_verified': 4}

    def migrate(self, release, sha):
        self.event('migration')
        env = dict(self.env, DATABASE_URL='postgresql://127.0.0.1:' + self.env['PGPORT'] + '/' + self.databases[0], FIXTURE_MIGRATIONS=str(release / 'db/migrate'))
        script = "require 'active_record'; ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL')); ActiveRecord::MigrationContext.new(ENV.fetch('FIXTURE_MIGRATIONS')).migrate"
        self.invoke(['bundle', 'exec', 'ruby', '-e', script], env=env)
        self.pending = []

    def cleanup(self):
        for database in self.databases:
            assert database.startswith('muzeum_deploy_test_')
            self.invoke([str(self.pg / 'dropdb'), '--if-exists', database])


if __name__ == '__main__':
    unittest.main()
