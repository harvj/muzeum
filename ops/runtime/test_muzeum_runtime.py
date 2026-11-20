import hashlib
import json
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
                for sha in (selection.FORWARD, selection.ROLLBACK):
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

    def test_environment_ignores_interpreter_and_bundle_overrides(self):
        environment = selection.runtime_environment({
            'RUBYOPT': '-r/tmp/override', 'GEM_HOME': '/tmp/untrusted',
            'LD_PRELOAD': '/tmp/untrusted', 'BUNDLE_PATH': '/tmp/untrusted',
            'PATH': '/tmp/untrusted', 'DATABASE_URL': 'fixture',
        }, Path('/runtime/bin'), Path('/bundles/approved'))
        self.assertEqual(environment, {
            'PATH': '/runtime/bin:/usr/bin:/bin', 'BUNDLE_PATH': '/bundles/approved', 'DATABASE_URL': 'fixture',
        })
