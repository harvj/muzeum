#!/usr/bin/env python3
"""Retrieve the exact off-host readiness snapshot and restore only a disposable DB."""
import datetime as dt
import json
import fcntl
import os
from pathlib import Path
import re
import runpy
import secrets
import shutil
import subprocess
import sys
import time
import monitoring

api = runpy.run_path('/usr/local/lib/harvj-backups/muzeum-backup')
base = api['BASE']
recovery = (base / 'recovery.lock').open('r')
fcntl.flock(recovery, fcntl.LOCK_EX | fcntl.LOCK_NB)
lock = (base.parent / 'backup.lock').open('a')
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
api['invoke'].__globals__['recovery_fds'] = (recovery.fileno(), lock.fileno())
config_path = Path(sys.argv[1]) if len(sys.argv) == 2 else Path('/etc/harvj-backups/muzeum/config.json')
config = api['load_config'](config_path)
if config['mode'] == 'production':
    import production_restore
    production_restore.restore(config, api)
    raise SystemExit(0)

record = json.loads((base / 'state/last-backup.json').read_text())
if not re.fullmatch('[a-f0-9]{64}', record['snapshot_id']):
    raise SystemExit('Invalid snapshot identifier')
original = Path(record['capture_path'])
if not original.is_relative_to(base / 'captures'):
    raise SystemExit('Unexpected capture path')
os.umask(0o077)
target = base / 'restores' / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
used = sum(p.stat().st_size for p in (base / 'restores').rglob('*') if p.is_file())
if used > 2 * 1024**3 or shutil.disk_usage(base).free < 8 * 1024**3:
    raise SystemExit('Restore staging budget/headroom exhausted')
target.mkdir(parents=True, mode=0o700)
with monitoring.job_run('restoration'):
    started = time.monotonic()
    api['restic'](config, ['restore', record['snapshot_id'], '--target', str(target), '--verify'])
    restored = target / str(original).lstrip('/')
    manifest = json.loads((restored / 'manifest.json').read_text())
    if manifest != json.loads((original / 'manifest.json').read_text()):
        raise SystemExit('Restored manifest differs from independent capture manifest')
    for relative, expected in manifest.items():
        file = (restored / relative).resolve()
        if not file.is_relative_to(restored) or api['file_hash'](file) != expected:
            raise SystemExit('Restored file checksum failed')
    file_seconds = time.monotonic() - started
    if len(config['databases']) != 1:
        raise SystemExit('Readiness verifier expects exactly one disposable fixture database')
    source = config['databases'][0]
    database = 'muzeum_backup_restore_' + secrets.token_hex(6)
    subprocess.run(['/usr/sbin/runuser', '-u', 'postgres', '--', '/usr/bin/createdb', '--template=template0', database], check=True)
    with (restored / 'databases' / (source + '.dump')).open('rb') as archive:
        result = subprocess.run(['/usr/sbin/runuser', '-u', 'postgres', '--', '/usr/bin/pg_restore',
                                 '--no-owner', '--no-acl', '--exit-on-error', '--dbname', database],
                                stdin=archive, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=300)
        if result.returncode:
            raise SystemExit('Disposable PostgreSQL restoration failed')
    sql = "SELECT count(*)::text || '|' || md5(string_agg(id::text || ':' || value, '|' ORDER BY id)) FROM backup_probe"
    def query(db, statement):
        return subprocess.check_output(['/usr/sbin/runuser', '-u', 'postgres', '--', '/usr/bin/psql',
                                        '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', statement], text=True).strip()
    if query(source, sql) != query(database, sql) or not query(database, sql).startswith('1000|'):
        raise SystemExit('Restored PostgreSQL row count/content checksum mismatch')
    if query(database, "SELECT count(*) FROM pg_indexes WHERE tablename='backup_probe'") != '2':
        raise SystemExit('Restored PostgreSQL indexes missing')
    row_checksum = query(database, sql).split('|')[1]
    subprocess.run(['/usr/sbin/runuser', '-u', 'postgres', '--', '/usr/bin/dropdb', database], check=True)
    result = {'disposable_database_cleaned_after_verification': True, 'snapshot_id': record['snapshot_id'], 'restored_directory': str(target),
              'disposable_restored_database': database, 'files_verified': len(manifest),
              'database_rows_verified': 1000, 'row_checksum': row_checksum,
              'files_restore_seconds': round(file_seconds, 3),
              'total_restore_seconds': round(time.monotonic() - started, 3),
              'verified_at': dt.datetime.now(dt.timezone.utc).isoformat()}
    api['atomic_json'](base / 'state/last-restore.json', result)
    print(json.dumps(result))
