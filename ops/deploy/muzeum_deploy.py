#!/usr/bin/env python3
"""Muzeum-only guarded Capistrano phases. Install only after separate safety review."""
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import stat
import subprocess
import sys
import tempfile
import time

APP = Path('/var/www/muzeum')
STATE = Path('/var/lib/muzeum-deploy')
BACKUPS = Path('/var/lib/harvj-backups/muzeum')
MIGRATION_LOCK = Path('/etc/muzeum/migration.lock')
CE_CAPTURE = b'/var/lib/harvj-backups/ce/capture-qualified-inputs'
UNITS = ('muzeum-web.service', 'muzeum-worker.service')
SHA = re.compile(r'[a-f0-9]{40}')
TOKEN = re.compile(r'[a-f0-9]{32}')
RUBY_BIN = Path('/opt/muzeum/ruby-3.4.13/bin')
BUNDLE_PATH = '/var/www/muzeum/shared/bundle/ruby-3.4.13'
MIGRATOR_SHA256 = 'eb995010d7ea215fed5b03a33d69c91795ab5bbbc921a4818204dd81965f2736'
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
    protected_fds = ()

    def command(self, argv, *, env=None, cwd=None, input=None, timeout=900):
        # Capture everything. Neither argv from a failure nor environment/stderr reaches logs.
        result = subprocess.run(argv, env=env, cwd=cwd, input=input, capture_output=True, timeout=timeout,
                                pass_fds=self.protected_fds)
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
        for helper in (Path(__file__).resolve(), Path(__file__).resolve().with_name('inspect.rb'), Path('/usr/local/sbin/muzeum-migrate'), ROUTE_HELPER):
            info = helper.stat()
            if info.st_uid != 0 or info.st_mode & 0o022:
                raise RuntimeError('Deployment/migration helpers must be root-owned and immutable to runtime')
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
        # Runtime verifies all four database connections, grants, versions and source protections.
        inspection = self.inspect((APP / 'current').resolve(), health=True)
        if inspection['pending']:
            raise RuntimeError('Published application has pending migrations')

    def inspect(self, release, health=False):
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
        env = runtime_environment(values, HOME='/home/muzeum', BUNDLE_GEMFILE=str(release / 'Gemfile'),
                                  PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=120000',
                                  MUZEUM_DEPLOY_CHECK_HEALTH='1' if health else '0')
        script = Path(__file__).resolve().with_name('inspect.rb').read_bytes()
        output = self.command(['/usr/sbin/runuser', '-u', 'muzeum', '--', str(RUBY_BIN / 'ruby'), str(RUBY_BIN / 'bundle'),
                               'exec', 'rails', 'runner', '-'], cwd=release, env=env, input=script)
        line = next(line for line in output.splitlines() if line.startswith('MUZEUM_DEPLOY_INSPECTION:'))
        return json.loads(line.split(':', 1)[1])

    def verify_release_integrity(self, release, sha):
        output = self.command(
            ['/usr/sbin/runuser', '-u', 'muzeum', '--', str(RUBY_BIN / 'ruby'),
             'script/muzeum_release_identity.rb', 'verify', sha],
            cwd=release, env={'PATH': '/usr/bin:/bin', 'HOME': '/home/muzeum'})
        candidate = json.loads(output)
        digest = candidate.get('artifact_sha256')
        if candidate.get('source_sha') != sha or not isinstance(digest, str) or not re.fullmatch(r'[a-f0-9]{64}', digest):
            raise RuntimeError('REL-01 exact artifact verification failed')
        checker = Path('/usr/local/libexec/harvj/release-integrity')
        for path in (checker, *checker.parents):
            info = path.lstat()
            if info.st_uid != 0 or stat.S_ISLNK(info.st_mode) or info.st_mode & 0o022:
                raise RuntimeError('Untrusted REL-01 checker path')
        result = json.loads(self.command([str(checker), 'harvj/muzeum', sha, digest], timeout=850))
        if (result.get('result'), result.get('source_sha'), result.get('artifact_sha256')) != ('pass', sha, digest):
            raise RuntimeError('REL-01 could not verify protected main ancestry')
        return result

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

    def ce_backup_holds_scratch(self, scratch):
        try:
            pid = int(self.command(['systemctl', 'show', '--property=MainPID', '--value',
                                    'ce-storage-box-initial.service'], timeout=10))
            if pid <= 1:
                return False
            process = Path('/proc') / str(pid)
            argv = (process / 'cmdline').read_bytes().split(b'\0')
            if (process.stat().st_uid != 0 or argv[-3:-1] !=
                    [CE_CAPTURE, b'backup']):
                return False
            descriptor = (process / 'fd/9').stat()
            held = os.fstat(scratch.fileno())
            return ((descriptor.st_dev, descriptor.st_ino) == (held.st_dev, held.st_ino)
                    and any(re.search(r'FLOCK\s+ADVISORY\s+WRITE', line) for line in
                            (process / 'fdinfo/9').read_text().splitlines() if line.startswith('lock:')))
        except (LookupError, OSError, RuntimeError, ValueError):
            return False

    @contextlib.contextmanager
    def force_backup_guard(self):
        with (BACKUPS / 'recovery.lock').open('r') as recovery, \
                MIGRATION_LOCK.open('r') as migration, \
                (BACKUPS.parent / 'backup.lock').open('r') as scratch:
            for guard, label in ((recovery, 'Muzeum backup or restore'), (migration, 'Muzeum migration')):
                if os.fstat(guard.fileno()).st_uid != 0 or os.fstat(guard.fileno()).st_mode & 0o022:
                    raise RuntimeError('Untrusted ' + label + ' lock')
                try:
                    fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError(label + ' owns its lock') from None
            previous_fds = self.protected_fds
            self.protected_fds = (*previous_fds, recovery.fileno(), migration.fileno())
            try:
                try:
                    fcntl.flock(scratch, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    if not self.ce_backup_holds_scratch(scratch):
                        raise RuntimeError('Shared backup lock owner is not a verified CE-only capture') from None
                    if shutil.disk_usage(APP).free < 8 * 1024**3:
                        raise RuntimeError('Insufficient deployment/recovery headroom during CE backup')
                    yield 'shared-backup-exclusivity: verified unrelated CE capture'
                else:
                    self.protected_fds = (*self.protected_fds, scratch.fileno())
                    yield None
            finally:
                self.protected_fds = previous_fds

    def publish_force(self, release, token):
        temporary = APP / ('.force-current-' + token)
        if temporary.exists() or temporary.is_symlink():
            raise RuntimeError('Force publication temporary pointer already exists')
        self.command(['/usr/sbin/runuser', '-u', 'muzeum', '--',
                      '/usr/bin/ln', '-s', '--', str(release), str(temporary)])
        self.command(['/usr/sbin/runuser', '-u', 'muzeum', '--',
                      '/usr/bin/mv', '-Tf', '--', str(temporary), str(APP / 'current')])

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

    def migrate(self, release, sha):
        expected = MIGRATOR_SHA256
        if hashlib.sha256(Path('/usr/local/sbin/muzeum-migrate').read_bytes()).hexdigest() != expected:
            raise RuntimeError('Reviewed migration helper must be installed first')
        self.command(['/usr/local/sbin/muzeum-migrate', str(release), sha])

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
        if item.get('database') != 'primary':
            raise RuntimeError('Auxiliary schema changes require a separate procedure')
        if not re.fullmatch(r'db/(?:migrate|cache_migrate|queue_migrate|cable_migrate)/[0-9]+_[a-z0-9_]+\.rb', path):
            raise RuntimeError('Unexpected migration path')
        review = manifest['migrations'].get(path, {})
        if (review.get('sha256') != item['sha256'] or review.get('risk') != 'additive'
                or review.get('quiesce') is not True or not review.get('review')):
            raise RuntimeError('Pending migration needs a matching additive review manifest')


def verify_schema_preservation(before, after):
    for name, database in before['databases'].items():
        for kind in ('tables', 'columns', 'triggers', 'indexes', 'constraints'):
            if any(value not in after['databases'][name].get(kind, []) for value in database.get(kind, [])):
                raise RuntimeError(f'Existing schema objects changed: {name}.{kind}')


def runtime_environment(values, **settings):
    # Match the fixed systemd runtime and discard loader overrides from app configuration.
    for name in ('ruby', 'bundle'):
        executable = RUBY_BIN / name
        for path in (executable, *executable.parents):
            info = path.lstat()
            if info.st_uid != 0 or stat.S_ISLNK(info.st_mode) or info.st_mode & 0o022:
                raise RuntimeError('Untrusted Muzeum runtime path')
        if not executable.is_file():
            raise RuntimeError('Muzeum runtime executable missing')
    env = {key: value for key, value in values.items()
           if not key.startswith(('LD_', 'DYLD_', 'BUNDLE_', 'RUBY', 'GEM_', 'RBENV_'))}
    return dict(env, PATH=f'{RUBY_BIN}:/usr/bin:/bin', BUNDLE_PATH=BUNDLE_PATH,
                BUNDLE_IGNORE_CONFIG='1', BUNDLE_DEPLOYMENT='true', BUNDLE_FROZEN='true',
                BUNDLE_WITHOUT='development:test', DISABLE_BOOTSNAP='1', **settings)


class Deployment:
    def __init__(self, host, root=STATE):
        self.host, self.root = host, root

    def save(self, record):
        write_json(self.root / (record['token'] + '.json'), record)
        write_json(self.root / 'active.json', record)

    def recover_force(self, active, baseline):
        previous = json.loads(active.read_text())
        token = previous.get('token')
        require_untouched = (
            TOKEN.fullmatch(token if isinstance(token, str) else '')
            and previous.get('phase') == 'failed'
            and previous.get('failed_phase') in ('begin', 'prepare')
            and previous.get('migrating') is False and previous.get('withdrawn') is False
            and not previous.get('route_transition')
            and previous.get('baseline', {}).get('revision') == baseline
            and self.host.revision() == baseline
        )
        if not require_untouched:
            raise RuntimeError('Existing Muzeum attempt requires manual recovery')
        with self.host.force_backup_guard():
            self.host.preflight()
            self.host.check_withdrawal(baseline)
            archived = self.root / ('active.' + token + '.force-recovered.json')
            if archived.exists():
                raise RuntimeError('Recovery archive already exists')
            active.rename(archived)
        return archived.name

    def run(self, phase, sha, token, path=None, *, baseline=None, rollback=False, force_artifact=None):
        if not SHA.fullmatch(sha) or not TOKEN.fullmatch(token):
            raise RuntimeError('Immutable SHA and deployment token required')
        if force_artifact is not None and (phase != 'begin' or rollback or not SHA.fullmatch(baseline or '')
                                           or not re.fullmatch(r'[0-9a-f]{64}', force_artifact)):
            raise RuntimeError('Force requires an explicit baseline and exact qualified artifact digest')
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.root / 'phase.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('An active Muzeum operation owns the deployment phase lock') from None
            active = self.root / 'active.json'
            if phase == 'begin':
                recovered = None
                if active.exists():
                    if force_artifact is None:
                        raise RuntimeError('Deployment lock retained; inspect active.json before operator recovery')
                    recovered = self.recover_force(active, baseline)
                if baseline is not None and (not SHA.fullmatch(baseline) or self.host.revision() != baseline):
                    raise RuntimeError('Live production baseline differs from selected release')
                record = {'sha': sha, 'token': token, 'started_at': now(), 'phase': 'preflight', 'migrating': False, 'withdrawn': False}
                if rollback:
                    record['rollback'] = True
                if force_artifact is not None:
                    record['force'] = {'operator': os.environ.get('SUDO_USER', 'root'),
                                       'authorized_at': now(), 'artifact_sha256': force_artifact,
                                       'overrides': [], 'recovered_receipt': recovered}
                self.save(record)
            else:
                record = json.loads(active.read_text())
                if record['sha'] != sha or record['token'] != token:
                    raise RuntimeError('Deployment lock identity mismatch')
                if record['phase'] == 'failed' and phase == 'fail':
                    return record
                if record['phase'] == 'failed' and phase != 'fail':
                    raise RuntimeError('Failed deployment requires operator recovery')
            try:
                # Serialize against scheduled backups; never test health during an intentional pause.
                force = record.get('force')
                guard = self.host.force_backup_guard() if force else self.host.backup_lock()
                with guard as overridden:
                    if force and overridden and overridden not in force['overrides']:
                        force['overrides'].append(overridden)
                        self.save(record)
                    if phase == 'begin':
                        record['baseline'] = self.host.preflight()
                        if baseline is not None and record['baseline']['revision'] != baseline:
                            raise RuntimeError('Live production baseline differs from selected release')
                        record['phase'] = 'prepared_checkout'
                    elif phase == 'prepare':
                        if record['phase'] != 'prepared_checkout':
                            raise RuntimeError('Unexpected prepare transition')
                        release = self.host.release(path, sha)
                        record['release'] = str(release)
                        if not record.get('rollback'):
                            record['release_integrity'] = self.host.verify_release_integrity(release, sha)
                        before = self.host.inspect(release)
                        if force and (before['pending'] or record['release_integrity']['artifact_sha256']
                                      != force['artifact_sha256']):
                            raise RuntimeError('Force requires a code-only candidate with the approved artifact digest')
                        reviewed_migrations(release, before['pending'])
                        if record.get('rollback') and before['pending']:
                            raise RuntimeError('Rollback artifact requires a migration')
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
                            self.host.migrate(release, sha)
                            after = self.host.inspect(release)
                            if after['pending'] or self.host.fingerprint(record['evidence']) != record['evidence']:
                                raise RuntimeError('Migration changed existing evidence or left pending migrations')
                            verify_schema_preservation(before, after)
                            record['schema_verified_at'] = now()
                            record['schema_versions'] = {name: value['versions'] for name, value in after['databases'].items() if 'versions' in value}
                        record['phase'] = 'ready_to_publish'
                    elif phase == 'finish':
                        if force and record['phase'] == 'ready_to_publish':
                            release = self.host.release(record['release'], sha)
                            if self.host.revision() != record['baseline']['revision'] or self.host.inspect(release)['pending']:
                                raise RuntimeError('Force publication baseline or migration state changed')
                            integrity = self.host.verify_release_integrity(release, sha)
                            if integrity['artifact_sha256'] != force['artifact_sha256']:
                                raise RuntimeError('Force publication artifact digest differs')
                            record['release_integrity'] = integrity
                            self.host.publish_force(release, token)
                        if record['phase'] != 'ready_to_publish' or not self.host.published(record['release'], sha):
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
            except Exception as error:
                # Never roll back code/schema or restore data. Preserve a root-only audit and lock.
                record['failed_phase'] = phase
                record['phase'] = 'failed'
                record['failure_at'] = now()
                record['diagnostic'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
                self.save(record)
                # Once migration may have run, old code must never resume. After publication,
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
        print(hashlib.sha256(Path(__file__).resolve().read_bytes() + Path(__file__).resolve().with_name('inspect.rb').read_bytes()).hexdigest())
        return
    if sys.argv[1:] == ['preflight']:
        host = Host()
        with host.backup_lock():
            print(json.dumps(host.preflight()))
        return
    if len(sys.argv) == 4 and sys.argv[1] == 'receipt':
        sha, token = sys.argv[2:]
        if not SHA.fullmatch(sha) or not TOKEN.fullmatch(token):
            raise RuntimeError('Invalid receipt identity')
        record = json.loads((STATE / (token + '.json')).read_text())
        if record['sha'] != sha or record['token'] != token:
            raise RuntimeError('Receipt identity mismatch')
        print(json.dumps({key: record[key] for key in ('sha', 'token', 'phase', 'health', 'release_integrity', 'force') if key in record}))
        return
    if len(sys.argv) == 6 and sys.argv[1] == 'begin-force':
        _, _, sha, token, baseline, artifact = sys.argv
        record = Deployment(Host()).run('begin', sha, token, baseline=baseline, force_artifact=artifact)
    elif len(sys.argv) == 5 and sys.argv[1] in ('begin-operator', 'begin-rollback'):
        action, sha, token, baseline = sys.argv[1:]
        record = Deployment(Host()).run(
            'begin', sha, token, baseline=baseline, rollback=action == 'begin-rollback')
    else:
        if len(sys.argv) not in (4, 5):
            raise RuntimeError('Expected phase SHA token [release]')
        record = Deployment(Host()).run(*sys.argv[1:])
    # No subprocess output, environments or opaque grants are published.
    print(json.dumps({key: record[key] for key in ('sha', 'token', 'phase', 'baseline', 'migrations', 'pre_backup', 'post_backup', 'health', 'safe_state', 'force') if key in record}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Deployment stopped; protected operator inspection required', file=sys.stderr)
        raise SystemExit(1)
