#!/usr/bin/env python3
"""Isolated Muzeum backup readiness tooling; production capture is gated off."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import resource
import re
import shutil
import stat
import subprocess
import sys
import time
import monitoring

BASE = Path('/var/lib/harvj-backups/muzeum')
RESTIC = '/usr/local/lib/harvj-backups/restic-0.19.1'
MAX_CAPTURE = 2 * 1024**3


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path, data):
    temporary = path.with_suffix('.new')
    with temporary.open('w') as handle:
        json.dump(data, handle, indent=2)
        handle.write('\n')
    os.chmod(temporary, 0o600)
    temporary.replace(path)


class CommandFailure(RuntimeError):
    def __init__(self, label, code):
        self.exit_code = code if code > 0 else 128 + abs(code)
        super().__init__(f'{label} failed (exit {self.exit_code}); no success recorded')


def invoke(argv, *, env=None, output=None, timeout=7200, file_limit=None, label=None):
    def limit():
        resource.setrlimit(resource.RLIMIT_FSIZE, (file_limit, file_limit))
    result = subprocess.run(argv, stdin=subprocess.DEVNULL,
                            stdout=output if output is not None else subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, timeout=timeout,
                            preexec_fn=limit if file_limit else None)
    if result.returncode:
        raise CommandFailure(label or Path(argv[0]).name, result.returncode)
    return result.stdout.decode() if output is None else ''


def load_config(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
        raise RuntimeError('Configuration must be root-owned regular file, mode 0600')
    config = json.loads(path.read_text())
    if config['mode'] == 'production':
        import production_capture
        production_capture.validate(config)
    elif config['mode'] != 'readiness':
        raise RuntimeError('Unknown capture mode')
    if len(config['databases']) > 4:
        raise RuntimeError('At most four databases permitted')
    if config.get('credential_scope') == 'subaccount':
        if not re.fullmatch(r'u720116-sub[0-9]+', config['ssh_user']) or config['ssh_host'] not in {
                'u720116.your-storagebox.de', config['ssh_user'] + '.your-storagebox.de'}:
            raise RuntimeError('Expected dedicated Storage Box subaccount')
    for database in config['databases']:
        if config['mode'] == 'readiness' and not database.startswith('muzeum_backup_readiness_') or not database.replace('_', '').isalnum():
            raise RuntimeError('Only allowlisted disposable readiness databases permitted')
    for source in config['sources']:
        location = Path(source).resolve()
        if config['mode'] == 'readiness' and not location.is_relative_to(BASE / 'fixtures'):
            raise RuntimeError('Readiness sources must be within the dedicated fixture directory')
    for name in ('password_file', 'ssh_key', 'known_hosts'):
        info = Path(config[name]).lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o077:
            raise RuntimeError(f'Unsafe credential/host-key file: {name}')
    return config


def restic(config, arguments):
    command = ['ssh', '-F', '/dev/null', '-p', '23', '-i', config['ssh_key'],
               '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
               '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlgorithms=ssh-ed25519',
               '-o', 'UserKnownHostsFile=' + config['known_hosts'],
               '-o', 'ConnectTimeout=15', config['ssh_user'] + '@' + config['ssh_host'], '-s', 'sftp']
    import shlex
    env = os.environ.copy()
    env['RESTIC_PASSWORD_FILE'] = config['password_file']
    env['RESTIC_CACHE_DIR'] = str(BASE / 'cache')
    env['GOMAXPROCS'] = '1'
    return invoke([RESTIC, '--no-cache', '--repo', config['repository'], '-o', 'sftp.command=' + shlex.join(command),
                   '-o', 'sftp.connections=2', '--limit-upload', '10240', *arguments], env=env, label='Restic ' + arguments[0] + (' snapshot readback' if arguments[:2] == ['cat', 'snapshot'] else ''))


def capture(config):
    if config['mode'] == 'production':
        import production_capture
        return production_capture.capture(config, BASE, invoke, atomic_json, file_hash, MAX_CAPTURE)
    root = BASE / 'captures'
    root.mkdir(exist_ok=True, mode=0o700)
    used = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
    if used > 6 * 1024**3 or shutil.disk_usage(BASE).free < 8 * 1024**3:
        raise RuntimeError('Staging budget/headroom exhausted; refusing capture')
    path = root / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    path.mkdir(mode=0o700)
    (path / 'databases').mkdir(mode=0o700)
    (path / 'files').mkdir(mode=0o700)
    for database in config['databases']:
        remaining = MAX_CAPTURE - sum(p.stat().st_size for p in path.rglob('*') if p.is_file())
        if remaining <= 0:
            raise RuntimeError('Capture size limit exceeded')
        with (path / 'databases' / (database + '.dump')).open('xb') as archive:
            invoke(['/usr/sbin/runuser', '-u', 'postgres', '--', '/usr/bin/pg_dump',
                    '--format=custom', '--compress=1', '--dbname', database], output=archive, file_limit=remaining)
    total = sum(p.stat().st_size for p in path.rglob('*') if p.is_file())
    for source in config['sources']:
        source = Path(source)
        if not source.is_dir() or source.is_symlink():
            raise RuntimeError('Required readiness fixture directory missing/unsafe')
        for item in source.rglob('*'):
            if item.is_symlink():
                raise RuntimeError('Fixture symlink rejected')
            if item.is_file():
                total += item.stat().st_size
                if total > MAX_CAPTURE:
                    raise RuntimeError('Capture size limit exceeded')
                destination = path / 'files' / source.name / item.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                shutil.copyfile(item, destination)
    manifest = {str(p.relative_to(path)): file_hash(p)
                for p in path.rglob('*') if p.is_file()}
    atomic_json(path / 'manifest.json', manifest)
    return path


def do_action(config, action):
    state = BASE / 'state'
    state.mkdir(exist_ok=True, mode=0o700)
    started = time.monotonic()
    if action in ('backup', 'check', 'retention-plan'):
        repository_id = json.loads(restic(config, ['cat', 'config']))['id']
        if config.get('repository_id') != repository_id:
            raise RuntimeError('Expected repository identity is not pinned or does not match')
    if action == 'init':
        print(restic(config, ['init']).strip())
    elif action == 'backup':
        path = capture(config)
        output = restic(config, ['backup', '--json', '--host', 'harvj-muzeum',
                                '--tag', 'app:muzeum', '--tag', 'env:' + config['mode'], str(path)])
        summary = next(json.loads(line) for line in output.splitlines()
                       if json.loads(line).get('message_type') == 'summary')
        snapshot_id = summary['snapshot_id']
        snapshot = json.loads(restic(config, ['cat', 'snapshot', snapshot_id]))
        if snapshot.get('hostname') != 'harvj-muzeum' or str(path) not in snapshot.get('paths', []) or not {'app:muzeum', 'env:' + config['mode']}.issubset(snapshot.get('tags', [])):
            raise RuntimeError('Repository snapshot verification failed')
        record = {'snapshot_id': snapshot_id, 'capture_path': str(path),
                  'completed_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'seconds': round(time.monotonic() - started, 3), 'mode': config['mode'],
                  'credential_scope': config['credential_scope'], 'manifest_sha256': file_hash(path / 'manifest.json')}
        atomic_json(state / 'last-backup.json', record)
        print(json.dumps(record))
        if config['mode'] == 'production':
            import production_capture
            production_capture.cleanup_capture(path, BASE)
    elif action == 'check':
        restic(config, ['check', '--read-data'])
        record = {'completed_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'seconds': round(time.monotonic() - started, 3)}
        atomic_json(state / 'last-check.json', record)
        print(json.dumps(record))
    elif action == 'retention-plan':
        print(restic(config, ['forget', '--tag', 'app:muzeum,env:' + config['mode'], '--group-by', 'host,tags',
                             '--keep-daily', '30', '--keep-weekly', '12', '--keep-monthly', '12', '--dry-run']))
    elif action == 'monitor':
        record = json.loads((state / 'last-backup.json').read_text())
        age = (dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(record['completed_at'])).total_seconds()
        if age > 26 * 3600:
            raise RuntimeError('Backup success is stale (older than 26 hours)')
        print('Last ' + config['mode'] + ' backup is within 26 hours')
    else:
        raise RuntimeError('Unsupported action')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'backup', 'check', 'retention-plan', 'monitor'])
    parser.add_argument('--config', type=Path, default=Path('/etc/harvj-backups/muzeum/config.json'))
    args = parser.parse_args()
    os.umask(0o077)
    BASE.mkdir(exist_ok=True, mode=0o700)
    with (BASE.parent / 'backup.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another backup/verification job holds the host backup lock')
        config = load_config(args.config)
        if config.get('credential_scope') != 'subaccount' and os.environ.get('ALLOW_BOOTSTRAP_TEST') != 'yes':
            raise RuntimeError('Restricted subaccount required for unattended operation')
        job = {'backup': 'backup', 'check': 'verification'}.get(args.action)
        if args.action == 'backup' and 'monitoring_job' in config:
            if config['monitoring_job'] != 'missed-run-test' or os.environ.get('ALLOW_NOTIFICATION_TEST') != 'yes':
                raise RuntimeError('Notification-test profile requires explicit manual opt-in')
            job = 'missed-run-test'
        if job:
            with monitoring.job_run(job):
                do_action(config, args.action)
        else:
            try:
                do_action(config, args.action)
            except Exception:
                if args.action == 'monitor':
                    monitoring.safe_signal('backup', 'failure')
                raise


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # No subprocess stderr, environment values, passwords or arbitrary argv are logged.
        print('Muzeum backup FAILED: ' + str(error), file=sys.stderr)
        raise SystemExit(error.exit_code if isinstance(error, CommandFailure) else 1)
