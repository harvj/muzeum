#!/usr/bin/env python3
"""Manual live test: disposable backup, actual curl connection failure, isolated monitor state."""
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys
import time

def main():
    sys.path.insert(0, '/usr/local/lib/harvj-backups')
    import monitoring

    os.environ['ALLOW_BOOTSTRAP_TEST'] = 'yes'
    os.environ['HTTPS_PROXY'] = 'http://127.0.0.1:9'
    os.environ['ALL_PROXY'] = 'http://127.0.0.1:9'
    os.environ['NO_PROXY'] = ''
    monitoring.STATE = Path('/var/lib/harvj-backups/muzeum/state/outage-test')
    monitoring.STATE.mkdir(mode=0o700, exist_ok=True)
    api = runpy.run_path('/usr/local/lib/harvj-backups/muzeum-backup')
    config = '/etc/harvj-backups/muzeum/bootstrap.json'
    started = time.monotonic()
    sys.argv = ['muzeum-backup', 'backup', '--config', config]
    api['main']()
    ack = json.loads((monitoring.STATE / 'last-monitoring-backup.json').read_text())
    assert not ack['acknowledged']
    print('PASS: actual monitoring connection failure was logged; verified disposable backup exit remains 0')
    state = Path('/var/lib/harvj-backups/muzeum/state/last-backup.json')
    before = hashlib.sha256(state.read_bytes()).hexdigest()
    sys.argv = ['muzeum-backup', 'backup', '--config', '/etc/harvj-backups/muzeum/live-failure-test.json']
    try:
        api['main']()
    except api['CommandFailure'] as error:
        assert error.exit_code == 12
    else:
        raise SystemExit('Expected disposable Restic failure absent')
    assert hashlib.sha256(state.read_bytes()).hexdigest() == before
    print('PASS: simultaneous backup and monitoring failures retain Restic exit 12 and genuine last-success state')
    print(json.dumps({'monitoring_outage_test_seconds': round(time.monotonic() - started, 3)}))


if __name__ == '__main__':
    main()
