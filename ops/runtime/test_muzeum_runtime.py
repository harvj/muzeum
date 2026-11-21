import hashlib
import json
import os
import pwd
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import muzeum_runtime as selection


class RuntimeTests(unittest.TestCase):
    def test_baseline_keeps_legacy_path_and_unreviewed_sha_fails(self):
        directory, _ = selection.runtime(selection.BASELINE)
        self.assertEqual(directory, Path('/opt/auth/ruby-3.4.12/bin'))
        with self.assertRaisesRegex(RuntimeError, 'reviewed release SHA'):
            selection.runtime('0' * 40)

    def test_both_patched_releases_require_matching_binary_digests(self):
        with tempfile.TemporaryDirectory() as work:
            directory = Path(work)
            checksums = {}
            for name in ('ruby', 'bundle'):
                content = name.encode()
                (directory / name).write_bytes(content)
                checksums[name] = hashlib.sha256(content).hexdigest()
            manifest = directory / 'runtime-sha256.json'
            manifest.write_text(json.dumps(checksums))
            with patch.object(selection, 'PATCHED', directory), patch.object(selection, 'MANIFEST', manifest), patch.object(selection, 'protected'):
                for sha in (selection.FORWARD, selection.HOTFIX, selection.ROLLBACK):
                    self.assertEqual(selection.runtime(sha)[0], directory)
                (directory / 'bundle').write_bytes(b'changed')
                with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                    selection.runtime(selection.FORWARD)

    def test_link_is_rejected_even_if_executable_bytes_match(self):
        with tempfile.TemporaryDirectory() as work:
            link = Path(work) / 'ruby'
            link.symlink_to('/usr/bin/true')
            with self.assertRaisesRegex(RuntimeError, 'Untrusted'):
                selection.protected(link)

    @unittest.skipUnless(sys.platform == 'linux' and os.geteuid() == 0, 'requires disposable Linux root fixture')
    def test_installed_layout_is_readable_but_not_writable_after_dropping_privileges(self):
        account = pwd.getpwnam(os.environ.get('MUZEUM_RUNTIME_TEST_USER', 'nobody'))
        with tempfile.TemporaryDirectory(dir='/var/lib') as work:
            parent = Path(work)
            parent.chmod(0o755)
            secure = parent / 'runtime'
            secure.mkdir(mode=0o755)
            manifest = secure / 'runtime-sha256.json'
            manifest.write_text('{}')
            manifest.chmod(0o644)
            probe = """
import os
from pathlib import Path
import sys
sys.path.insert(0, sys.argv[1])
import muzeum_runtime as selection
manifest = Path(sys.argv[2])
selection.protected(manifest, service_manifest=True)
assert manifest.read_text() == '{}'
if os.geteuid():
    assert not os.access(manifest, os.W_OK)
    assert not os.access(manifest.parent, os.W_OK)
    try:
        manifest.open('a')
    except PermissionError:
        pass
    else:
        raise AssertionError('Unprivileged writer opened manifest')
"""
            module = secure / 'muzeum_runtime.py'
            module.write_bytes(Path(selection.__file__).read_bytes())
            module.chmod(0o644)
            arguments = [sys.executable, '-B', '-c', probe, str(secure), str(manifest)]
            subprocess.run(arguments, check=True)
            subprocess.run(arguments, user=account.pw_uid, group=account.pw_gid, extra_groups=[],
                           check=True)

            secure.chmod(0o700)
            with self.assertRaisesRegex(RuntimeError, 'service-traversable'):
                selection.protected(manifest, service_manifest=True)
            secure.chmod(0o775)
            with self.assertRaisesRegex(RuntimeError, 'Untrusted'):
                selection.protected(manifest, service_manifest=True)
            secure.chmod(0o755)
            manifest.chmod(0o600)
            with self.assertRaisesRegex(RuntimeError, 'mode 0644'):
                selection.protected(manifest, service_manifest=True)
            manifest.chmod(0o644)
            os.chown(manifest, account.pw_uid, 0)
            with self.assertRaisesRegex(RuntimeError, 'Untrusted'):
                selection.protected(manifest, service_manifest=True)
            os.chown(manifest, 0, 0)
            link = parent / 'link'
            link.symlink_to(secure, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, 'Untrusted'):
                selection.protected(link / manifest.name, service_manifest=True)

    def test_environment_ignores_interpreter_and_bundle_overrides(self):
        environment = selection.runtime_environment({
            'RUBYOPT': '-r/tmp/override', 'GEM_HOME': '/tmp/untrusted',
            'LD_PRELOAD': '/tmp/untrusted', 'BUNDLE_PATH': '/tmp/untrusted',
            'PATH': '/tmp/untrusted', 'DATABASE_URL': 'fixture',
        }, Path('/runtime/bin'), Path('/bundles/approved'))
        self.assertEqual(environment, {
            'PATH': '/runtime/bin:/usr/bin:/bin', 'BUNDLE_PATH': '/bundles/approved', 'DATABASE_URL': 'fixture',
        })
