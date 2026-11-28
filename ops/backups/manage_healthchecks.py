#!/usr/bin/env python3
"""Add missing Muzeum checks without changing existing Healthchecks settings."""
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import uuid

ROOT = Path('/etc/harvj-backups')
MONITORING = ROOT / 'muzeum/monitoring.json'
KEY = ROOT / 'healthchecks-api-key'
SPECS = {
    'verification': {'name': 'Muzeum — Integrity Verification', 'slug': 'muzeum-integrity-verification',
                     'schedule': '0 4 * * 0', 'tz': 'UTC', 'grace': 7200},
    'restoration': {'name': 'Muzeum — Restoration Verification', 'slug': 'muzeum-restoration-verification',
                    'schedule': '0 6 * * 0', 'tz': 'UTC', 'grace': 7200},
}


def secure_read(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
        raise RuntimeError('Unsafe credential/configuration permissions')
    return path.read_text()


def api_client(key):
    if not re.fullmatch(r'[A-Za-z0-9_-]{20,256}', key):
        raise RuntimeError('Invalid stored API key format')

    def request(method, endpoint, payload=None):
        if (method, endpoint) not in {('GET', 'checks/'), ('GET', 'channels/'), ('POST', 'checks/')}:
            raise RuntimeError('Only discovery and new-check creation are permitted')
        config = ('url = "https://healthchecks.io/api/v3/' + endpoint + '"\n' +
                  'header = ' + json.dumps('X-Api-Key: ' + key) + '\nrequest = ' + json.dumps(method) + '\n')
        if payload is not None:
            config += 'header = "Content-Type: application/json"\ndata = ' + json.dumps(json.dumps(payload)) + '\n'
        result = subprocess.run(['/usr/bin/curl', '--config', '-', '--proto', '=https',
                                 '--connect-timeout', '3', '--max-time', '10', '--retry', '0',
                                 '--silent', '--write-out', '\n%{http_code}'], input=config,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=12)
        if result.returncode:
            raise RuntimeError('API transport failed; rediscover before retrying creation')
        body, code = result.stdout.rsplit('\n', 1)
        if code != ('201' if method == 'POST' else '200'):
            raise RuntimeError('API request rejected; response suppressed')
        return json.loads(body)
    return request


def ping_url(check):
    value = check['ping_url']
    if not re.fullmatch(r'https://hc-ping\.com/[0-9a-f-]{36}', value):
        raise RuntimeError('Unexpected ping URL')
    uuid.UUID(value.rsplit('/', 1)[1])
    return value


def settings(check):
    # Status and last-ping timestamps can change independently of management.
    return {key: value for key, value in check.items()
            if key not in {'status', 'started', 'last_ping', 'next_ping', 'n_pings'}}


def reconcile(api, urls):
    checks = api('GET', 'checks/')['checks']
    channels = api('GET', 'channels/')['channels']
    daily = [check for check in checks if check.get('ping_url') == urls['backup']]
    if len(daily) != 1:
        raise RuntimeError('Expected project/daily check not uniquely identified')
    attached = set(daily[0].get('channels', '').split(','))
    email = [channel['id'] for channel in channels if channel['kind'] == 'email' and channel['id'] in attached]
    if len(email) != 1:
        raise RuntimeError('Daily check email integration is ambiguous or missing')
    before = {check['uuid']: settings(check) for check in checks}
    updated = dict(urls)
    created = []
    for job, spec in SPECS.items():
        # Refresh before each create; no upsert/update/delete endpoints are used.
        current = api('GET', 'checks/')['checks']
        matches = [check for check in current if check.get('slug') == spec['slug'] or
                   check.get('name', '').replace('—', '-').strip() == spec['name'].replace('—', '-')]
        if len(matches) > 1:
            raise RuntimeError('Duplicate verification checks; manual review required')
        if matches:
            check = matches[0]
        else:
            check = api('POST', 'checks/', {**spec, 'channels': email[0], 'tags': 'muzeum backup',
                        'desc': 'Signals only genuine completed verification; production timers require separate approval.'})
            created.append(job)
        if any(check.get(key) != value for key, value in spec.items() if key != 'name'):
            raise RuntimeError('Existing verification schedule differs; preserved without update')
        if email[0] not in check.get('channels', '').split(','):
            raise RuntimeError('Verification check lacks expected email integration; preserved without update')
        value = ping_url(check)
        if job in urls and urls[job] != value:
            raise RuntimeError('Existing local ping mapping differs; refusing replacement')
        updated[job] = value
    after = api('GET', 'checks/')['checks']
    by_id = {check['uuid']: check for check in after}
    if any(identifier not in by_id or settings(by_id[identifier]) != original for identifier, original in before.items()):
        raise RuntimeError('Existing remote check settings changed during reconciliation; review required')
    for job, spec in SPECS.items():
        found = [check for check in after if check.get('ping_url') == updated[job]]
        if len(found) != 1 or any(found[0].get(k) != v for k, v in spec.items() if k != 'name') or email[0] not in found[0].get('channels', '').split(','):
            raise RuntimeError('New check readback failed')
    return updated, created


def main():
    if os.geteuid() != 0 or len(sys.argv) != 1:
        raise RuntimeError('Run as root without arguments')
    os.umask(0o077)
    for directory in [ROOT, MONITORING.parent]:
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
            raise RuntimeError('Unsafe configuration directory')
    with Path('/var/lib/harvj-backups/muzeum-recovery.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        original = secure_read(MONITORING)
        updated, created = reconcile(api_client(secure_read(KEY).strip()), json.loads(original))
        if secure_read(MONITORING) != original:
            raise RuntimeError('Local monitoring configuration changed concurrently')
        fd, temporary = tempfile.mkstemp(prefix='.monitoring-', dir=MONITORING.parent)
        try:
            with os.fdopen(fd, 'w') as handle:
                os.fchmod(handle.fileno(), 0o600)
                os.fchown(handle.fileno(), 0, 0)
                json.dump(updated, handle, indent=2)
                handle.write('\n')
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, MONITORING)
        finally:
            Path(temporary).unlink(missing_ok=True)
    print('Existing check settings preserved; email integration reused.')
    print('Created jobs: ' + (', '.join(created) or 'none (already present)'))
    print('Verification/restoration ping mappings saved root:root 0600; no pings sent or timers changed.')


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt):
        print('Management reconciliation failed; details suppressed to protect credentials. Rediscover before retrying.', file=sys.stderr)
        raise SystemExit(1)
