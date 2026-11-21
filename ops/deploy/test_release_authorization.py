"""Exercise the signed installed-helper contract without production credentials."""
import base64
from datetime import datetime, timedelta, timezone
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

import muzeum_deploy as deploy
import release_authorization as auth
from test_migration_process import migration
from test_workflow import DatabaseHost

BASELINE = 'c37a00dcf058e87fdc59644e9e444c001e29622f'
CANDIDATE = '96597aa6f94e64b6bb9cfdb7399de1ed98124a11'
MIGRATION = 'db/migrate/20261121160000_index_resolution_decisions_by_recording.rb'
INDEX = 'index_resolution_decisions_on_recording_and_listener'


class AuthorizationTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name).resolve()
        self.key, self.public = (self.root / name for name in ('private.pem', 'public.pem'))
        self.openssl = shutil.which('openssl')
        self.openssl_run('genpkey', '-algorithm', 'ED25519', '-out', self.key)
        self.openssl_run('pkey', '-in', self.key, '-pubout', '-out', self.public)
        self.now = datetime.now(timezone.utc)
        self.approval = self.review(BASELINE, CANDIDATE, 'v0.4.0')

    def openssl_run(self, *args):
        return subprocess.check_output([self.openssl, *args], stderr=subprocess.PIPE)

    def review(self, prior, candidate, version, migrations=None):
        return {'format': 1, 'application': 'muzeum', 'sha': candidate, 'baseline': prior,
                'branch': 'release/' + version, 'version': version,
                'scope': 'https://github.com/harvj/muzeum/issues/28#issuecomment-7069804291',
                'ci': 'https://github.com/harvj/muzeum/actions/runs/1',
                'policy': 'additive-verified' if migrations else 'code-only',
                'migrations': migrations or {}, 'rollback': 'verified-forward-compatible',
                'issued_at': (self.now - timedelta(minutes=1)).isoformat(),
                'expires_at': (self.now + timedelta(hours=1)).isoformat()}

    def sign(self, value):
        payload = json.dumps(value).encode()
        data = self.root / 'payload'
        data.write_bytes(payload)
        signature = self.openssl_run('pkeyutl', '-sign', '-inkey', self.key, '-rawin', '-in', data)
        return base64.b64encode(json.dumps({'payload': base64.b64encode(payload).decode(),
                                           'signature': base64.b64encode(signature).decode()}).encode())

    def verify(self, envelope, clock=None):
        with patch.object(auth, 'OPENSSL', self.openssl):
            return auth.load_signed(envelope, key=self.public, clock=clock or self.now)

    def test_approval_signature_expiry_and_policy_fail_closed(self):
        envelope = self.sign(self.approval)
        value, digest = self.verify(envelope)
        self.assertEqual(value['sha'], CANDIDATE)
        self.assertEqual(len(digest), 64)
        with self.assertRaisesRegex(RuntimeError, 'expired'):
            self.verify(envelope, self.now + timedelta(hours=2))
        data = json.loads(base64.b64decode(envelope))
        data['payload'] = base64.b64encode(json.dumps(self.approval | {'sha': 'd' * 40}).encode()).decode()
        with self.assertRaisesRegex(RuntimeError, 'signature'):
            self.verify(base64.b64encode(json.dumps(data).encode()))
        with self.assertRaisesRegex(RuntimeError, 'policy'):
            self.verify(self.sign(self.approval | {'policy': 'additive-verified'}))


class CutoverHost(DatabaseHost):
    """Rehearse actual schemas, inspector and migrator with simulated OS service/route boundaries."""
    fingerprint_tables = [('deployment_fixture', 'id,evidence')]

    def __init__(self, root, audit):
        super().__init__(root)
        self.audit = audit
        self.bundle_path = self.invoke(['bundle', 'exec', 'ruby', '-e',
                                        'path = Bundler.settings[:path]; print File.expand_path(path) if path'])
        self.releases = self.root / 'releases'
        self.releases.mkdir()
        self.paths = {sha: self.releases / timestamp for sha, timestamp in (
            (BASELINE, '20261121000000'), (CANDIDATE, '20261122000000'))}
        for sha, path in self.paths.items():
            path.mkdir()
            archive = subprocess.check_output(['git', 'archive', sha])
            subprocess.run(['tar', '-xf', '-', '-C', path], input=archive, check=True)
            (path / 'REVISION').write_text(sha + '\n')
            if (path / 'Gemfile.lock').read_bytes() != Path('Gemfile.lock').read_bytes():
                raise RuntimeError('Install archived fixture dependencies before running the cutover rehearsal')
        self.candidate = self.paths[CANDIDATE]
        self.sha = BASELINE
        (self.root / 'current').symlink_to(self.paths[BASELINE])
        for database in self.databases:
            self.query(database, 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;')
        self.invoke(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-d', 'postgres', '-c',
                     "CREATE ROLE muzeum_runtime LOGIN PASSWORD 'p0-disposable'; "
                     "CREATE ROLE muzeum_migrator LOGIN PASSWORD 'p0-disposable'; CREATE ROLE muzeum_owner NOLOGIN;"])
        self.rails(self.paths[BASELINE], ['db:migrate:primary'])
        self.rails(self.paths[BASELINE], ['runner', '-'], input="""%w[cache queue cable].each do |name|
  config = ActiveRecord::Base.configurations.configs_for(env_name: 'production', name: name)
  ActiveRecord::Base.establish_connection(config)
  load Rails.root.join('db', name + '_schema.rb')
end""")
        for database in self.databases:
            self.query(database, "CREATE TABLE deployment_fixture(id integer PRIMARY KEY, evidence text); "
                       "INSERT INTO deployment_fixture VALUES (1, 'retained source evidence'); "
                       "GRANT USAGE ON SCHEMA public TO muzeum_runtime; "
                       "GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO muzeum_runtime;")
        self.query(self.databases[0], "GRANT USAGE, CREATE ON SCHEMA public TO muzeum_migrator; "
                   "ALTER TABLE resolution_decisions OWNER TO muzeum_migrator; "
                   "GRANT SELECT, INSERT ON schema_migrations TO muzeum_migrator; "
                   "GRANT SELECT, INSERT, UPDATE ON ar_internal_metadata TO muzeum_migrator;")
        self.runtime_environment = dict(self.migration_env())
        for name, database in self.connections():
            self.runtime_environment[name] = f'postgresql://muzeum_runtime:p0-disposable@127.0.0.1:{self.env["PGPORT"]}/{database}'

    def cleanup(self):
        try:
            super().cleanup()
        finally:
            self.invoke(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-d', 'postgres', '-c',
                         'DROP ROLE IF EXISTS muzeum_runtime, muzeum_migrator, muzeum_owner;'])

    def connections(self):
        return zip(('DATABASE_URL', 'CACHE_DATABASE_URL', 'QUEUE_DATABASE_URL', 'CABLE_DATABASE_URL'),
                   self.databases)

    def migration_env(self):
        from urllib.parse import quote
        env = dict(self.env, RAILS_ENV='production', SECRET_KEY_BASE_DUMMY='1', BOOTSNAP_READONLY='1',
                   SCHEMA=str(self.root / 'test-structure.sql'), BUNDLE_FROZEN='true')
        if self.bundle_path:
            env['BUNDLE_PATH'] = self.bundle_path
        user = quote(self.env.get('PGUSER', os.environ.get('USER', 'postgres')))
        for name, database in self.connections():
            env[name] = f'postgresql://{user}@127.0.0.1:{self.env["PGPORT"]}/{database}'
        return env

    def rails(self, release, argv, env=None, input=None):
        result = subprocess.run(['bundle', 'exec', 'rails', *argv], cwd=release,
                                env=env or self.migration_env(), input=input, capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise RuntimeError(result.stderr[-2500:])
        return result.stdout

    def inspect(self, release, health=False):
        self.event('inspect')
        revision = (release / 'REVISION').read_text().strip()
        compatibility = self.audit / ('compatible-schema-' + revision + '.json')
        env = dict(self.runtime_environment,
                   MUZEUM_VERIFIED_FORWARD_SCHEMA=compatibility.read_text() if compatibility.exists() else '{}')
        output = self.rails(release, ['runner', '-'], env=env,
                            input=Path(deploy.__file__).with_name('inspect.rb').read_text())
        line = next(line for line in output.splitlines() if line.startswith('MUZEUM_DEPLOY_INSPECTION:'))
        return json.loads(line.split(':', 1)[1])

    def health(self):
        super().health()
        report = self.inspect((self.root / 'current').resolve())
        if report['pending']:
            raise RuntimeError('Disposable current release has pending migrations')

    release = deploy.Host.release
    published = deploy.Host.published
    restore_pointer = deploy.Host.restore_pointer
    replace_current = deploy.Host.replace_current
    promote = deploy.Host.promote
    record_compatible_schema = deploy.Host.record_compatible_schema

    def revision(self):
        return (self.root / 'current/REVISION').read_text().strip()

    def preflight(self):
        self.event('preflight')
        return {'revision': self.revision(), 'health': 'passed'}

    def migrate(self, release, sha, token):
        self.event('migration')
        migrations = migration.authorized_migrations(release, sha, token, self.audit / 'active.json')
        directory = Path(shutil.which('ruby')).parent
        if directory != Path(shutil.which('bundle')).parent:
            raise RuntimeError('Expected Ruby and Bundler from same disposable runtime')
        env = self.migration_env()
        env['DATABASE_URL'] = f'postgresql://muzeum_migrator:p0-disposable@127.0.0.1:{self.env["PGPORT"]}/{self.databases[0]}'
        migration.execute_migrations(migrations, directory, release, env,
                                     prefix=(), diagnostic=self.root / 'migration-error')



@unittest.skipUnless(os.environ.get('MUZEUM_DEPLOY_TEST_PGPORT'), 'Disposable PostgreSQL and Restic required')
class ExactCutoverTests(AuthorizationTests):
    def test_exact_releases_refusal_cutover_safe_rollback_and_next_operation(self):
        audit = self.root / 'audit'
        host = CutoverHost(self.root, audit)
        self.addCleanup(host.cleanup)
        flow = deploy.Deployment(host, audit)
        approved = self.review(BASELINE, CANDIDATE, 'v0.4.0', {MIGRATION: hashlib.sha256((host.candidate / MIGRATION).read_bytes()).hexdigest()})

        def begin(review):
            value, digest = self.verify(self.sign(review))
            token = secrets.token_hex(16)
            with patch.object(auth, 'OPENSSL', self.openssl):
                record = flow.begin_authorized(token, self.sign(review), self.public)
            self.assertEqual(record['sha'], value['sha'])
            self.assertEqual(record['authorization_sha256'], digest)
            return token

        with patch.object(deploy, 'APP', host.root), patch.object(deploy, 'STATE', audit):
            wrong = begin(approved | {'migrations': {MIGRATION: 'f' * 64}})
            with self.assertRaises(RuntimeError):
                flow.run('prepare', CANDIDATE, wrong, str(host.candidate))
            self.assertEqual(host.revision(), BASELINE)
            self.assertNotIn('withdraw', host.events)

            token = begin(approved)
            flow.run('prepare', CANDIDATE, token, str(host.candidate))
            self.assertEqual(host.query(host.databases[0], f"SELECT indisvalid FROM pg_index WHERE indexrelid = '{INDEX}'::regclass"), 't')

            original = host.backup_restore
            def interrupted(sha):
                verified = original(sha)
                if sha == CANDIDATE:
                    self.assertEqual(verified['databases_verified'], 4)
                    raise KeyboardInterrupt()
                return verified
            host.backup_restore = interrupted
            with self.assertRaisesRegex(RuntimeError, 'Prior release healthy'):
                flow.run('finish', CANDIDATE, token)
            record = flow.run('fail', CANDIDATE, token)
            self.assertEqual(record['rollback']['revision'], BASELINE)
            self.assertEqual(record['rollback']['schema'], 'retained')
            self.assertEqual(host.revision(), BASELINE)
            self.assertTrue(host.running and host.public)
            compatibility = json.loads((audit / ('compatible-schema-' + BASELINE + '.json')).read_text())
            self.assertEqual(compatibility, {'primary': ['20261121160000']})

            host.backup_restore = original
            retry = begin(self.review(BASELINE, CANDIDATE, 'v0.4.0'))
            flow.run('prepare', CANDIDATE, retry, str(host.candidate))
            flow.run('finish', CANDIDATE, retry)
            self.assertEqual(flow.run('complete', CANDIDATE, retry)['health'], 'passed')

            next_sha = 'e' * 40
            next_release = host.releases / '20261123000000'
            shutil.copytree(host.candidate, next_release)
            (next_release / 'REVISION').write_text(next_sha + '\n')
            host.paths[next_sha] = next_release
            later = begin(self.review(CANDIDATE, next_sha, 'v0.4.1'))
            flow.run('prepare', next_sha, later, str(next_release))
            flow.run('finish', next_sha, later)
            self.assertEqual(flow.run('complete', next_sha, later)['health'], 'passed')
