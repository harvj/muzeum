#!/usr/bin/env python3
"""Securely provision one Healthchecks ping URL via an interactive SSH terminal."""
import getpass
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import urllib.parse
import uuid

JOBS = {'backup', 'verification', 'restoration', 'missed-run-test'}
ROOT = Path('/etc/harvj-backups/muzeum')


def normalize_url(value):
    parsed = urllib.parse.urlsplit(value.strip())
    if (parsed.scheme != 'https' or parsed.netloc != 'hc-ping.com' or
            parsed.query or parsed.fragment):
        raise ValueError('Use the base HTTPS UUID ping URL from the check')
    identifier = str(uuid.UUID(parsed.path.strip('/')))
    return 'https://hc-ping.com/' + identifier


def main():
    if os.geteuid() != 0 or not sys.stdin.isatty():
        raise SystemExit('Run as root in an interactive SSH terminal')
    if len(sys.argv) != 2 or sys.argv[1] not in JOBS:
        raise SystemExit('Usage: configure-healthchecks backup|verification|restoration|missed-run-test')
    for directory in (ROOT.parent, ROOT):
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
            raise SystemExit('Backup configuration directories must be root-owned mode 0700')
    path = ROOT / 'monitoring.json'
    values = {}
    if path.exists() or path.is_symlink():
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
            raise SystemExit('Refusing unsafe existing monitoring configuration')
        values = json.loads(path.read_text())
    try:
        url = normalize_url(getpass.getpass('Healthchecks ping URL (hidden; not tested or signaled here): '))
    except (ValueError, EOFError):
        raise SystemExit('Invalid or missing base HTTPS UUID ping URL; configuration unchanged')
    values[sys.argv[1]] = url
    fd, temporary = tempfile.mkstemp(prefix='.monitoring-', dir=ROOT)
    try:
        with os.fdopen(fd, 'w') as handle:
            os.fchmod(handle.fileno(), 0o600)
            json.dump(values, handle, indent=2)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print('Configured ' + sys.argv[1] + ' ping URL at ' + str(path) + ' (root:root 0600).')
    print('No ping was sent. The URL was not echoed or stored in command arguments.')


if __name__ == '__main__':
    main()
