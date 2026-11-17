#!/usr/bin/env python3
"""Provision the project management key through hidden terminal input only."""
import getpass
import os
from pathlib import Path
import re
import resource
import stat
import sys
import tempfile
import warnings

ROOT = Path('/etc/harvj-backups')
KEY = ROOT / 'healthchecks-api-key'


def validate_key(value):
    # Prevent whitespace/header/config injection without assuming a fixed length.
    if not re.fullmatch(r'[A-Za-z0-9_-]{20,256}', value):
        raise ValueError('Invalid key format')
    return value


def store_key(value):
    validate_key(value)
    info = ROOT.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
        raise RuntimeError('Unsafe configuration directory')
    fd, temporary = tempfile.mkstemp(prefix='.healthchecks-api-', dir=ROOT)
    try:
        with os.fdopen(fd, 'w') as handle:
            os.fchmod(handle.fileno(), 0o600)
            os.fchown(handle.fileno(), 0, 0)
            handle.write(value + '\n')
            handle.flush()
            os.fsync(handle.fileno())
        # Atomic no-clobber publication, including protection against symlinks.
        os.link(temporary, KEY)
        directory = os.open(ROOT, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    if len(sys.argv) != 1 or os.geteuid() != 0 or not sys.stdin.isatty():
        raise RuntimeError('Run without arguments as root in an interactive SSH terminal')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.umask(0o077)
    if KEY.exists() or KEY.is_symlink():
        raise RuntimeError('Key path already exists; refusing to overwrite it')
    # Never fall back to echoed input when terminal echo control is unavailable.
    with warnings.catch_warnings():
        warnings.simplefilter('error', getpass.GetPassWarning)
        value = validate_key(getpass.getpass('Healthchecks project read-write API key (hidden): '))
        confirmation = getpass.getpass('Confirm API key (hidden): ')
    if value != confirmation:
        raise RuntimeError('Key confirmation mismatch')
    store_key(value)
    print('Management API key stored at /etc/harvj-backups/healthchecks-api-key (root:root 0600).')
    print('No API requests or pings sent. No key value printed.')


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt):
        # No exception rendering: errors must never contain supplied credentials.
        print('Provisioning did not complete. Check terminal, key format, confirmation and existing path.', file=sys.stderr)
        raise SystemExit(1)
