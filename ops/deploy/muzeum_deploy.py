#!/usr/bin/python3 -I
"""Muzeum-only guarded Capistrano phases. Install only after separate safety review."""
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import pwd
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_authorization import KEY as AUTHORIZATION_KEY, load_signed, verify_migrations

APP = Path('/var/www/muzeum')
STATE = Path('/var/lib/muzeum-deploy')
BACKUPS = Path('/var/lib/harvj-backups/muzeum')
UNITS = ('muzeum-web.service', 'muzeum-worker.service')
SHA = re.compile(r'[a-f0-9]{40}')
TOKEN = re.compile(r'[a-f0-9]{32}')
RELEASE_VERSION = re.compile(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)')
RELEASE_SCOPE = re.compile(r'https://github\.com/harvj/muzeum/issues/[0-9]+#issuecomment-[0-9]+')
RELEASE_CI = re.compile(r'https://github\.com/harvj/muzeum/actions/runs/[0-9]+')
RUNTIME_LIBRARY = Path('/usr/local/lib/muzeum-runtime/muzeum_runtime.py')
MIGRATOR = Path('/usr/local/sbin/muzeum-migrate')
AUTHORIZATION_LIBRARY = Path(__file__).resolve().with_name('release_authorization.py')
ROUTE_HELPER = Path('/usr/local/sbin/harvj-muzeum-route')


class RouteRefused(RuntimeError):
    """The route helper confirmed that the original route was retained."""


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as output:
        os.fchmod(output.fileno(), 0o600)
        json.dump(value, output, indent=2)
        output.write('\n')
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)


class Host:
    def command(self, argv, *, env=None, cwd=None, input=None, timeout=900):
        # Capture everything. Neither argv from a failure nor environment/stderr reaches logs.
        result = subprocess.run(argv, env=env, cwd=cwd, input=input, capture_output=True, timeout=timeout)
        if result.returncode:
            STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
            diagnostic = STATE / 'command-last-error'
            diagnostic.write_bytes(result.stderr[-65536:])
            diagnostic.chmod(0o600)
            raise RuntimeError('Command failed; inspect protected command-last-error')
        return result.stdout.decode()

    def revision(self):
        sha = (APP / 'current/REVISION').read_text().strip()
        if not SHA.fullmatch(sha):
            raise RuntimeError('Invalid current revision')
        return sha

    def release(self, path, sha):
        release = Path(path).resolve(strict=True)
        if release.parent != APP / 'releases' or not re.fullmatch(r'[0-9]{14}', release.name):
            raise RuntimeError('Unexpected release path')
        if (release / 'REVISION').read_text().strip() != sha:
            raise RuntimeError('Release revision mismatch')
        return release

    def published(self, release, sha):
        return (APP / 'current').resolve(strict=True) == self.release(release, sha) and self.revision() == sha

    def preflight(self):
        for helper in (Path(__file__).resolve(), Path(__file__).resolve().with_name('inspect.rb'), MIGRATOR, AUTHORIZATION_LIBRARY, AUTHORIZATION_KEY, RUNTIME_LIBRARY, ROUTE_HELPER):
            info = helper.stat()
            if info.st_uid != 0 or info.st_mode & 0o022:
                raise RuntimeError('Deployment/migration helpers must be root-owned and immutable to runtime')
        runtime_uid = pwd.getpwnam('muzeum').pw_uid
        for cache in (APP / 'releases').glob('*/tmp/cache/bootsnap'):
            if any(path.is_dir() and path.stat().st_uid != runtime_uid for path in [cache, *cache.rglob('*')]):
                raise RuntimeError('Legacy Bootsnap cache ownership requires operator repair before deployment')
        for name in ('/var/www/muzeum/shared/.env', '/etc/muzeum/migrate.env',
                     '/etc/muzeum/backup.pgpass', '/etc/harvj-backups/muzeum/config.json'):
            path = Path(name)
            if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o077:
                raise RuntimeError('Protected configuration unavailable or unsafe')
        if shutil.disk_usage(APP).free < 8 * 1024**3:
            raise RuntimeError('Insufficient deployment/recovery headroom')
        self.check_backup_freshness()
        self.health()
        backup = json.loads((BACKUPS / 'state/last-backup.json').read_text())
        restored = json.loads((BACKUPS / 'state/last-production-restore.json').read_text())
        if restored.get('databases_verified') != 4:
            raise RuntimeError('Existing four-database recovery evidence required')
        return {'revision': self.revision(), 'health': 'passed', 'backup_reference': backup['snapshot_id'],
                'recovery_reference': restored['snapshot_id'], 'recovered_at': restored['verified_at']}

    def check_backup_freshness(self):
        # Caller owns the host lock. The CLI entry point would try to lock it again.
        api, config = self.backup_api()
        api['do_action'](config, 'monitor')

    def health(self):
        for attempt in range(10):
            try:
                self.health_once()
                return
            except RuntimeError:
                if attempt == 9:
                    raise
                time.sleep(1)

    def health_once(self):
        self.command(['systemctl', 'is-active', *UNITS])
        self.command(['curl', '--fail', '--silent', '--show-error', '--max-time', '10',
                      '--retry', '10', '--retry-connrefused', '--retry-delay', '1',
                      '-H', 'Host: muzeum.fm', '-H', 'X-Forwarded-Proto: https', 'http://127.0.0.1:3011/up'])
        self.command(['/usr/local/sbin/check-muzeum-runtime', 'status'])
        # Runtime verifies all four database connections, grants, versions and source protections.
        inspection = self.inspect((APP / 'current').resolve(), health=True)
        if inspection['pending']:
            raise RuntimeError('Published application has pending migrations')

    def record_compatible_schema(self, baseline, migrations):
        compatibility = STATE / ('compatible-schema-' + baseline + '.json')
        prior = json.loads(compatibility.read_text()) if compatibility.exists() else {}
        for migration in migrations:
            versions = set(prior.get(migration['database'], []))
            prior[migration['database']] = sorted(versions | {migration['version']})
        write_json(compatibility, prior)

    def inspect(self, release, health=False):
        revision = (release / 'REVISION').read_text().strip()
        if not SHA.fullmatch(revision):
            raise RuntimeError('Invalid inspection revision')
        compatibility = STATE / ('compatible-schema-' + revision + '.json')
        values = {}
        for line in (APP / 'shared/.env').read_text().splitlines():
            if line.strip():
                key, value = line.split('=', 1)
                values[key] = value
        from urllib.parse import urlsplit
        for key, database in zip(('DATABASE_URL', 'CACHE_DATABASE_URL', 'QUEUE_DATABASE_URL', 'CABLE_DATABASE_URL'),
                                 ('muzeum_production', 'muzeum_production_cache', 'muzeum_production_queue', 'muzeum_production_cable')):
            url = urlsplit(values[key])
            if url.hostname != '127.0.0.1' or url.username != 'muzeum_runtime' or url.path != '/' + database:
                raise RuntimeError('Unexpected runtime database boundary')
        env = dict(values, HOME='/home/muzeum',
                   BUNDLE_GEMFILE=str(release / 'Gemfile'), BUNDLE_IGNORE_CONFIG='1', BUNDLE_DEPLOYMENT='true',
                   BUNDLE_FROZEN='true', BUNDLE_WITHOUT='development:test', BOOTSNAP_READONLY='1',
                   PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=120000',
                   MUZEUM_DEPLOY_CHECK_HEALTH='1' if health else '0',
                   MUZEUM_VERIFIED_FORWARD_SCHEMA=compatibility.read_text() if compatibility.exists() else '{}')
        sys.path.insert(0, str(RUNTIME_LIBRARY.parent))
        from muzeum_runtime import release_runtime, runtime_environment
        directory, bundle_path = release_runtime(release)
        env = runtime_environment(env, directory, bundle_path)
        env.update(BUNDLE_IGNORE_CONFIG='1', BUNDLE_DEPLOYMENT='true', BUNDLE_FROZEN='true', BUNDLE_WITHOUT='development:test')
        script = Path(__file__).resolve().with_name('inspect.rb').read_bytes()
        output = self.command(['/usr/sbin/runuser', '-u', 'muzeum', '--', str(directory / 'bundle'),
                               'exec', 'rails', 'runner', '-'], cwd=release, env=env, input=script)
        line = next(line for line in output.splitlines() if line.startswith('MUZEUM_DEPLOY_INSPECTION:'))
        return json.loads(line.split(':', 1)[1])

    def backup_api(self):
        sys.path.insert(0, '/usr/local/lib/harvj-backups')
        import production_capture
        api = runpy.run_path('/usr/local/lib/harvj-backups/muzeum-backup')
        config = api['load_config'](Path('/etc/harvj-backups/muzeum/config.json'))
        production_capture.validate(config)
        return api, config

    @contextlib.contextmanager
    def backup_lock(self):
        # Existing host lock also excludes scheduled capture/restore pauses during each phase.
        with (BACKUPS.parent / 'backup.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield

    def backup_restore(self, sha):
        api, config = self.backup_api()
        import monitoring
        import production_restore
        # Existing implementations, same encryption/escrow/monitoring; caller owns the host lock.
        before = now()
        with monitoring.job_run('backup'):
            api['do_action'](config, 'backup')
        receipt = json.loads((BACKUPS / 'state/last-backup.json').read_text())
        if receipt['completed_at'] < before or not re.fullmatch(r'[a-f0-9]{64}', receipt['snapshot_id']):
            raise RuntimeError('Fresh production backup receipt required')
        production_restore.restore(config, api)
        restored = json.loads((BACKUPS / 'state/last-production-restore.json').read_text())
        if (restored['snapshot_id'] != receipt['snapshot_id'] or restored['release_sha'] != sha
                or restored['databases_verified'] != 4 or restored['verified_at'] < before):
            raise RuntimeError('Matching fresh four-database recovery receipt required')
        return {'snapshot_id': receipt['snapshot_id'], 'manifest_sha256': receipt['manifest_sha256'],
                'restored_at': restored['verified_at'], 'release_sha': sha}

    def fingerprint(self, specification=None):
        # SELECT-only backup identity. Compare original columns, so additive columns are permitted.
        import production_capture as capture
        result = {}
        for database in capture.DATABASES:
            old = specification.get(database) if specification else None
            tables = old or {table: None for table in capture.query(database,
                "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename NOT IN ('schema_migrations','ar_internal_metadata') ORDER BY tablename").splitlines()}
            result[database] = {}
            for table, original in tables.items():
                if not re.fullmatch(r'[a-z_][a-z0-9_]*', table):
                    raise RuntimeError('Unexpected evidence table')
                columns = original['columns'] if original else capture.query(database,
                    "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='" + table + "' ORDER BY ordinal_position").splitlines()
                if not columns or any(not re.fullmatch(r'[a-z_][a-z0-9_]*', col) for col in columns):
                    raise RuntimeError('Unexpected evidence columns')
                projection = ','.join('"' + col + '"' for col in columns)
                sql = 'COPY (SELECT row_to_json(t)::text FROM (SELECT ' + projection + ' FROM "' + table + '") t ORDER BY row_to_json(t)::text COLLATE "C") TO STDOUT'
                argv = ['psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-U', 'muzeum_backup', '-d', database, '-c', sql]
                digest = hashlib.sha256()
                with subprocess.Popen(argv, env=capture.environment(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
                    for chunk in iter(lambda: process.stdout.read(65536), b''):
                        digest.update(chunk)
                    if process.wait(timeout=180):
                        raise RuntimeError('Evidence fingerprint failed')
                result[database][table] = {'columns': columns, 'sha256': digest.hexdigest()}
        return result

    def route(self, action, sha):
        if self.revision() != sha:
            raise RouteRefused('Published SHA changed before route operation')
        result = subprocess.run([str(ROUTE_HELPER), action], capture_output=True, timeout=180)
        if result.returncode:
            with tempfile.NamedTemporaryFile(dir=STATE, prefix='route-error-', delete=False) as diagnostic:
                diagnostic.write(result.stderr[-65536:])
                reference = Path(diagnostic.name).name
            if result.returncode == 3:
                raise RouteRefused(f'Muzeum route operation refused; inspect protected {reference}')
            raise RuntimeError(f'Muzeum route state requires operator inspection; protected {reference}')

    def check_withdrawal(self, sha):
        self.route('check-withdraw', sha)

    def withdraw(self, sha):
        self.route('withdraw', sha)

    def migrate(self, release, sha, token):
        self.command([str(MIGRATOR), str(release), sha, token])

    def replace_current(self, release):
        with tempfile.TemporaryDirectory(dir=APP, prefix='.muzeum-pointer-') as directory:
            temporary = Path(directory) / 'current'
            temporary.symlink_to(release)
            temporary.replace(APP / 'current')

    def promote(self, release, sha, prior):
        if self.revision() != prior:
            raise RuntimeError('Live baseline changed before guarded promotion')
        self.replace_current(self.release(release, sha))

    def restore_pointer(self, prior, expected, sha):
        if not self.published(expected, sha):
            raise RuntimeError('Current release changed before rollback')
        self.replace_current(prior)

    def start(self):
        self.command(['systemctl', 'restart', *UNITS])

    def activate(self, sha):
        self.route('activate', sha)
        self.command(['curl', '--fail', '--silent', '--max-time', '10', 'https://muzeum.fm/up'])

    def stop(self):
        self.command(['systemctl', 'stop', *UNITS])


def reviewed_migrations(release, pending):
    manifest = json.loads((release / 'config/deploy/migrations.json').read_text())
    if manifest.get('format') != 1:
        raise RuntimeError('Unsupported migration review manifest')
    for item in pending:
        path = item['path']
        if not re.fullmatch(r'db/(?:migrate|cache_migrate|queue_migrate|cable_migrate)/[0-9]+_[a-z0-9_]+\.rb', path):
            raise RuntimeError('Unexpected migration path')
        review = manifest['migrations'].get(path, {})
        if (review.get('sha256') != item['sha256'] or review.get('risk') != 'additive'
                or review.get('quiesce') is not True or not review.get('review')):
            raise RuntimeError('Pending migration needs a matching additive review manifest')


def runtime_proof(sha):
    sys.path.insert(0, str(RUNTIME_LIBRARY.parent))
    from muzeum_runtime import BASELINE, MANIFEST, runtime
    directory, _ = runtime(sha)
    return {'ruby': str(directory / 'ruby'),
            'manifest_sha256': None if sha == BASELINE else hashlib.sha256(MANIFEST.read_bytes()).hexdigest()}


class Deployment:
    def __init__(self, host, root=STATE, prove_runtime=None):
        self.host, self.root = host, root
        self.prove_runtime = prove_runtime

    def save(self, record):
        write_json(self.root / (record['token'] + '.json'), record)
        write_json(self.root / 'active.json', record)

    def release_preflight(self, baseline):
        if not SHA.fullmatch(baseline):
            raise RuntimeError('Immutable production baseline required')
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.root / 'phase.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if (self.root / 'active.json').exists():
                raise RuntimeError('Deployment lock retained; inspect active.json before operator recovery')
            with self.host.backup_lock():
                if self.host.revision() != baseline:
                    raise RuntimeError('Live production baseline differs from release review')
                evidence = self.host.preflight()
                if evidence['revision'] != baseline:
                    raise RuntimeError('Live production baseline differs from release review')
                return evidence

    def recover_verified_baseline(self, record):
        approval = record.get('release_review', {})
        if (not record.get('authorization_sha256') or not record.get('baseline')
                or record.get('route_transition') == 'withdrawing'
                or (record['migrating'] and (not record.get('schema_verified_at')
                    or approval.get('rollback') != 'verified-forward-compatible'))):
            return False
        before = record['baseline']['revision']
        with self.host.backup_lock():
            current = self.host.revision()
            if current not in (before, record['sha']):
                return False
            if current == before and not record['withdrawn'] and not record['migrating']:
                self.host.health()
            else:
                if not record['withdrawn']:
                    self.host.withdraw(current)
                    record['withdrawn'] = True
                    self.save(record)
                self.host.stop()
                previous = self.host.release(record['rollback_release'], before)
                if record['migrating']:
                    self.host.record_compatible_schema(before, record['migrations'])
                if current != before:
                    self.host.restore_pointer(previous, record['release'], record['sha'])
                self.host.start()
                self.host.health()
                self.host.activate(before)
                record['withdrawn'] = False
        record['rollback'] = {'revision': before, 'health': 'passed',
                              'schema': 'retained' if record['migrating'] else 'unchanged'}
        record['safe_state'] = 'Prior release healthy; no database restore performed'
        return True

    def begin_authorized(self, token, encoded, key=AUTHORIZATION_KEY):
        review, digest = load_signed(encoded, key)
        return self.run('begin', review['sha'], token, release_review=review, authorization_digest=digest)

    def run(self, phase, sha, token, path=None, release_review=None, authorization_digest=None, require_authorized=False):
        if not SHA.fullmatch(sha) or not TOKEN.fullmatch(token):
            raise RuntimeError('Immutable SHA and deployment token required')
        if release_review:
            version = release_review['version']
            if (phase != 'begin' or not RELEASE_VERSION.fullmatch(version) or
                    release_review['branch'] not in ('main', 'release/' + version) or
                    not SHA.fullmatch(release_review['baseline']) or release_review['baseline'] == sha or
                    not RELEASE_SCOPE.fullmatch(release_review['scope']) or not RELEASE_CI.fullmatch(release_review['ci'])):
                raise RuntimeError('Invalid release approval metadata')
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.root / 'phase.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            active = self.root / 'active.json'
            if phase == 'begin':
                if active.exists():
                    raise RuntimeError('Deployment lock retained; inspect active.json before operator recovery')
                if release_review and self.host.revision() != release_review['baseline']:
                    raise RuntimeError('Live production baseline differs from release review')
                record = {'sha': sha, 'token': token, 'started_at': now(), 'phase': 'preflight', 'migrating': False, 'withdrawn': False}
                if self.prove_runtime:
                    record['runtime'] = self.prove_runtime(sha)
                if release_review:
                    record['release_review'] = release_review
                if authorization_digest:
                    record['authorization_sha256'] = authorization_digest
                    previous = (APP / 'current').resolve(strict=True)
                    record['rollback_release'] = str(self.host.release(previous, release_review['baseline']))
                self.save(record)
            else:
                if phase == 'fail' and not active.exists():
                    previous = self.root / (token + '.json')
                    if previous.exists():
                        record = json.loads(previous.read_text())
                        if (record.get('sha'), record.get('token'), record.get('phase')) == (sha, token, 'failed'):
                            return record
                record = json.loads(active.read_text())
                if require_authorized and not record.get('authorization_sha256'):
                    raise RuntimeError('Active deployment has no verified release authorization')
                if record['sha'] != sha or record['token'] != token:
                    raise RuntimeError('Deployment lock identity mismatch')
                if self.prove_runtime and phase not in ('fail', 'cancel') and record.get('runtime') != self.prove_runtime(sha):
                    raise RuntimeError('Runtime proof changed during deployment')
                if record['phase'] == 'failed' and phase == 'fail':
                    return record
                if record['phase'] == 'failed' and phase != 'fail':
                    raise RuntimeError('Failed deployment requires operator recovery')
            try:
                # Serialize against scheduled backups; never test health during an intentional pause.
                with self.host.backup_lock():
                    if phase == 'begin':
                        record['baseline'] = self.host.preflight()
                        if release_review and record['baseline']['revision'] != release_review['baseline']:
                            raise RuntimeError('Live production baseline differs from release review')
                        record['phase'] = 'prepared_checkout'
                    elif phase == 'prepare':
                        if record['phase'] != 'prepared_checkout':
                            raise RuntimeError('Unexpected prepare transition')
                        if record.get('authorization_sha256') and self.host.revision() != record['baseline']['revision']:
                            raise RuntimeError('Live baseline changed before staging')
                        release = self.host.release(path, sha)
                        record['release'] = str(release)
                        before = self.host.inspect(release)
                        reviewed_migrations(release, before['pending'])
                        if record.get('authorization_sha256'):
                            verify_migrations(release, before['pending'], record['release_review'])
                        record['migrations'] = before['pending']
                        if before['pending']:
                            self.host.check_withdrawal(record['baseline']['revision'])
                            record['route_transition'] = 'withdrawing'
                            self.save(record)
                            try:
                                self.host.withdraw(record['baseline']['revision'])
                            except RouteRefused:
                                record['route_transition'] = 'refused'
                                raise
                            record['withdrawn'] = True
                            record['route_transition'] = 'withdrawn'
                            self.save(record)
                            self.host.stop()
                            record['pre_backup'] = self.host.backup_restore(record['baseline']['revision'])
                            record['evidence'] = self.host.fingerprint()
                            # Persist intent immediately before issuing any migration.
                            record['migrating'] = True
                            self.save(record)
                            self.host.migrate(release, sha, token)
                            after = self.host.inspect(release)
                            if after['pending'] or self.host.fingerprint(record['evidence']) != record['evidence']:
                                raise RuntimeError('Migration changed existing evidence or left pending migrations')
                            for name, database in before['databases'].items():
                                for kind in ('triggers', 'indexes', 'constraints'):
                                    if any(value not in after['databases'][name].get(kind, []) for value in database.get(kind, [])):
                                        raise RuntimeError('Existing source protections/indexes/constraints changed')
                            record['schema_verified_at'] = now()
                            record['schema_versions'] = {name: value['versions'] for name, value in after['databases'].items() if 'versions' in value}
                        record['phase'] = 'ready_to_publish'
                    elif phase == 'finish':
                        if record['phase'] != 'ready_to_publish':
                            raise RuntimeError('Unexpected publication transition')
                        if record.get('authorization_sha256'):
                            record['promotion_started_at'] = now()
                            self.save(record)
                            self.host.promote(record['release'], sha, record['baseline']['revision'])
                        if not self.host.published(record['release'], sha):
                            raise RuntimeError('Publication did not select the exact candidate')
                        self.host.release(record['release'], sha)
                        self.host.start()
                        self.host.health()
                        if record['migrating']:
                            record['post_backup'] = self.host.backup_restore(sha)
                            self.host.health()
                            record['withdrawn'] = False
                            self.save(record)
                            self.host.activate(sha)
                        record['health'] = 'passed'
                        record['phase'] = 'verified'
                    elif phase == 'complete':
                        if record['phase'] != 'verified' or not self.host.published(record['release'], sha):
                            raise RuntimeError('Unexpected completion transition')
                        self.host.health()
                        record['phase'] = 'complete'
                        record['completed_at'] = now()
                    elif phase == 'cancel':
                        if record['phase'] != 'prepared_checkout' or record['migrating'] or record.get('route_transition') or self.host.revision() != record['baseline']['revision']:
                            raise RuntimeError('Only an untouched pre-deployment attempt can be cancelled')
                        self.host.health()
                        record['phase'] = 'cancelled'
                        record['completed_at'] = now()
                    elif phase == 'fail':
                        raise RuntimeError('Capistrano reported a deployment failure')
                    else:
                        raise RuntimeError('Unknown deployment phase')
                self.save(record)
                if record['phase'] in ('complete', 'cancelled'):
                    active.unlink()
                return record
            except (Exception, KeyboardInterrupt) as error:
                # Restore only verified compatible code. Never reverse schema or restore live data.
                record['failed_phase'] = phase
                record['phase'] = 'failed'
                record['failure_at'] = now()
                record['diagnostic'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
                self.save(record)
                try:
                    recovered = self.recover_verified_baseline(record)
                except Exception:
                    recovered = False
                if recovered:
                    self.save(record)
                    active.unlink()
                    raise RuntimeError('Deployment failed; ' + record['safe_state'] +
                                       '; receipt ' + token + '.json') from None
                # If schema compatibility is uncertain, old code must never resume. After publication,
                # withdraw the exact current candidate if its restart/health checks failed.
                if record['migrating'] or record['withdrawn'] or (record.get('baseline') and self.host.revision() != record['baseline']['revision']):
                    route_ok = record['withdrawn']
                    try:
                        if not route_ok:
                            self.host.withdraw(self.host.revision())
                            record['withdrawn'] = route_ok = True
                    except Exception:
                        pass
                    try:
                        self.host.stop()
                        record['safe_state'] = ('route withdrawn; ' if route_ok else 'route requires operator inspection; ') + 'Muzeum services stopped; data retained'
                    except Exception:
                        record['safe_state'] = 'Manual Muzeum-only withdrawal required; inspect services and route immediately'
                elif record.get('route_transition') == 'withdrawing':
                    record['safe_state'] = 'Route requires operator inspection; service state preserved; migration not attempted'
                else:
                    record['safe_state'] = 'Prior application retained; verify health before releasing lock'
                self.save(record)
                raise RuntimeError('Deployment stopped; root-only receipt ' + str(self.root / (token + '.json')) + '; ' + record['safe_state']) from None


def main():
    os.umask(0o077)
    if os.geteuid() != 0:
        raise RuntimeError('Root-owned installed helper required')
    if sys.argv[1:] == ['version']:
        components = (Path(__file__).resolve(), Path(__file__).resolve().with_name('inspect.rb'),
                      RUNTIME_LIBRARY, AUTHORIZATION_LIBRARY, MIGRATOR)
        print(hashlib.sha256(b''.join(path.read_bytes() for path in components)).hexdigest())
        return
    if sys.argv[1:] == ['preflight']:
        host = Host()
        with host.backup_lock():
            print(json.dumps(host.preflight()))
        return
    if len(sys.argv) in (3, 4) and sys.argv[1] == 'release-preflight':
        if len(sys.argv) == 4:
            runtime_proof(sys.argv[3])
        print(json.dumps(Deployment(Host()).release_preflight(sys.argv[2])))
        return
    if len(sys.argv) == 4 and sys.argv[1] == 'receipt':
        sha, token = sys.argv[2:]
        if not SHA.fullmatch(sha) or not TOKEN.fullmatch(token):
            raise RuntimeError('Invalid receipt identity')
        record = json.loads((STATE / (token + '.json')).read_text())
        if record['sha'] != sha or record['token'] != token:
            raise RuntimeError('Receipt identity mismatch')
        print(json.dumps({key: record[key] for key in ('sha', 'token', 'phase', 'health', 'release_review', 'runtime', 'authorization_sha256', 'rollback', 'safe_state') if key in record}))
        return
    if len(sys.argv) == 4 and sys.argv[1] == 'begin-authorized':
        sys.path.insert(0, str(RUNTIME_LIBRARY.parent))
        import muzeum_runtime
        muzeum_runtime.protected(AUTHORIZATION_KEY)
        token, encoded = sys.argv[2:]
        record = Deployment(Host(), prove_runtime=runtime_proof).begin_authorized(token, encoded)
    else:
        if len(sys.argv) not in (4, 5) or sys.argv[1] not in ('prepare', 'finish', 'complete', 'fail', 'cancel'):
            raise RuntimeError('Expected a signed begin or guarded deployment phase')
        record = Deployment(Host(), prove_runtime=runtime_proof).run(*sys.argv[1:], require_authorized=True)
    # No subprocess output, environments or opaque grants are published.
    print(json.dumps({key: record[key] for key in ('sha', 'token', 'phase', 'baseline', 'release_review', 'migrations', 'pre_backup', 'post_backup', 'health', 'safe_state', 'runtime', 'authorization_sha256', 'rollback') if key in record}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Deployment stopped; protected operator inspection required', file=sys.stderr)
        raise SystemExit(1)
