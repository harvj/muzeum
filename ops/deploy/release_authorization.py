"""Verify the one operator authorization used by the Muzeum deployment helpers."""
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

KEY = Path('/etc/muzeum/release-approval.pub')
OPENSSL = '/usr/bin/openssl'
SHA = re.compile(r'[0-9a-f]{40}')
DIGEST = re.compile(r'[0-9a-f]{64}')
VERSION = re.compile(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)')
MIGRATION_PATH = re.compile(r'db/(migrate|cache_migrate|queue_migrate|cable_migrate)/([0-9]+)_[a-z0-9_]+\.rb')
DATABASES = {'migrate': 'primary', 'cache_migrate': 'cache', 'queue_migrate': 'queue', 'cable_migrate': 'cable'}
FIELDS = {'format', 'application', 'sha', 'baseline', 'version', 'branch', 'scope', 'ci',
          'policy', 'migrations', 'rollback', 'issued_at', 'expires_at'}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def strict_json(raw):
    def pairs(entries):
        result = dict(entries)
        require(len(result) == len(entries), 'Duplicate authorization field')
        return result
    return json.loads(raw, object_pairs_hook=pairs)


def load_signed(encoded, key=KEY, clock=None):
    require(len(encoded) <= 32768, 'Release authorization too large')
    envelope = strict_json(base64.b64decode(encoded, validate=True))
    require(isinstance(envelope, dict) and set(envelope) == {'payload', 'signature'},
            'Invalid signed release envelope')
    raw = base64.b64decode(envelope['payload'], validate=True)
    signature = base64.b64decode(envelope['signature'], validate=True)
    require(len(signature) == 64, 'Invalid release signature')
    with tempfile.TemporaryDirectory(prefix='muzeum-authorization-') as directory:
        data, sig = (Path(directory) / name for name in ('payload', 'signature'))
        data.write_bytes(raw)
        sig.write_bytes(signature)
        checked = subprocess.run([OPENSSL, 'pkeyutl', '-verify', '-pubin', '-inkey', str(key),
                                  '-rawin', '-in', str(data), '-sigfile', str(sig)],
                                 capture_output=True, timeout=5)
    require(checked.returncode == 0, 'Release approval signature could not be verified')
    value = strict_json(raw)
    require(isinstance(value, dict) and set(value) == FIELDS and type(value['format']) is int
            and value['format'] == 1 and value['application'] == 'muzeum', 'Invalid release approval fields')
    require(all(isinstance(value[field], str) for field in FIELDS - {'format', 'migrations'}),
            'Invalid scalar release approval fields')
    require(SHA.fullmatch(value['sha']) and SHA.fullmatch(value['baseline']) and value['sha'] != value['baseline']
            and VERSION.fullmatch(value['version'])
            and value['branch'] in ('main', 'release/' + value['version']), 'Invalid approved release identity')
    require(re.fullmatch(r'https://github\.com/harvj/muzeum/issues/[0-9]+#issuecomment-[0-9]+', value['scope'])
            and re.fullmatch(r'https://github\.com/harvj/muzeum/actions/runs/[0-9]+', value['ci']),
            'Invalid release review or CI reference')
    issued, expiry = (datetime.fromisoformat(value[field]) for field in ('issued_at', 'expires_at'))
    require(issued.tzinfo is not None and expiry.tzinfo is not None, 'Release approval times need a timezone')
    now = clock or datetime.now(timezone.utc)
    require(issued <= now < expiry and (expiry - issued).total_seconds() <= 86400,
            'Release approval expired, not yet effective, or exceeds 24 hours')
    migrations = value['migrations']
    require(isinstance(migrations, dict) and len(migrations) <= 32
            and all(MIGRATION_PATH.fullmatch(path) and isinstance(digest, str) and DIGEST.fullmatch(digest)
                    for path, digest in migrations.items()), 'Invalid approved migration inventory')
    require(value['policy'] == ('additive-verified' if migrations else 'code-only')
            and value['rollback'] in ('stop', 'verified-forward-compatible'), 'Unsupported release safety policy')
    return value, hashlib.sha256(raw).hexdigest()


def verify_migrations(release, pending, approval):
    inventory = {}
    for item in pending:
        name = item['path']
        match = MIGRATION_PATH.fullmatch(name)
        require(match and item['database'] == DATABASES[match[1]] and item['version'] == match[2]
                and name not in inventory, 'Invalid pending migration identity')
        path = release / name
        require(path.resolve(strict=True) == path and path.is_file(), 'Invalid migration file path')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        require(digest == item['sha256'], 'Approved migration bytes changed')
        inventory[name] = digest
    require(inventory == approval['migrations'], 'Pending migration scope differs from release approval')
