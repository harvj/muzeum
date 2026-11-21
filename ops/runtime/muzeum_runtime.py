"""Select Muzeum's reviewed runtime from a fixed release identity."""
import hashlib
import json
import re
import stat
from pathlib import Path

BASELINE = '024ed4aecd98984c00323377389cde5a6a35d16d'
FORWARD = '1633c96d63c1a44e678e95292466ab49c0442103'
HOTFIX = '8aa4b92e11d6e826ef7d5073398fe4cdfd4f1f6e'
ROLLBACK = '1abfe5a791c254a03e5e03a2ae4c4ecfe8459cd1'
PATCHED = Path('/opt/muzeum/ruby-3.4.13/bin')
MANIFEST = Path('/usr/local/lib/muzeum-runtime/runtime-sha256.json')
APP = Path('/var/www/muzeum')


def protected(path, *, service_manifest=False):
    for component in (path, *path.parents):
        info = component.lstat()
        if info.st_uid != 0 or stat.S_ISLNK(info.st_mode) or info.st_mode & 0o022:
            raise RuntimeError('Untrusted Muzeum runtime path')
        if service_manifest and component != path and not info.st_mode & stat.S_IXOTH:
            raise RuntimeError('Muzeum runtime manifest parent must be service-traversable')
    if service_manifest:
        info = path.lstat()
        if info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o644:
            raise RuntimeError('Muzeum runtime manifest must be root:root mode 0644')
    if not path.is_file():
        raise RuntimeError('Muzeum runtime file required')


def runtime(sha):
    if sha == BASELINE:
        return Path('/opt/auth/ruby-3.4.12/bin'), APP / 'shared/bundle'
    if sha not in (FORWARD, HOTFIX, ROLLBACK):
        raise RuntimeError('Muzeum runtime requires an explicitly reviewed release SHA')
    protected(MANIFEST, service_manifest=True)
    checksums = json.loads(MANIFEST.read_text())
    if set(checksums) != {'ruby', 'bundle'}:
        raise RuntimeError('Expected reviewed Muzeum runtime manifest')
    for executable, digest in checksums.items():
        path = PATCHED / executable
        protected(path)
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if not re.fullmatch(r'[a-f0-9]{64}', digest) or actual != digest:
            raise RuntimeError('Muzeum runtime checksum mismatch')
    return PATCHED, APP / 'shared/bundle/ruby-3.4.13'


def release_runtime(release, sha=None):
    revision = (release / 'REVISION').read_text().strip()
    if sha is not None and sha != revision:
        raise RuntimeError('Muzeum runtime revision mismatch')
    return runtime(revision)


def runtime_environment(values, directory, bundle_path):
    # Loader and Bundler overrides never come from application configuration.
    env = {key: value for key, value in values.items()
           if not key.startswith(('LD_', 'DYLD_', 'BUNDLE_', 'RUBY', 'GEM_', 'RBENV_'))}
    return dict(env, PATH=f'{directory}:/usr/bin:/bin', BUNDLE_PATH=str(bundle_path))
