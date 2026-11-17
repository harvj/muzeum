import contextlib
import getpass
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import configure_healthchecks_api as provision


class ApiProvisioningTests(unittest.TestCase):
    def test_rejects_injection_and_whitespace(self):
        for value in ['x' * 30 + '\nheader', 'x' * 30 + '"', ' ' + 'x' * 30, 'short']:
            with self.assertRaises(ValueError):
                provision.validate_key(value)

    def test_hidden_input_failure_never_stores_key(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(provision, 'KEY', Path(directory) / 'absent'), \
                    mock.patch.object(provision.os, 'geteuid', return_value=0), \
                    mock.patch.object(provision.sys, 'argv', ['configure-healthchecks-api']), \
                    mock.patch.object(provision.sys.stdin, 'isatty', return_value=True), \
                    mock.patch.object(provision.resource, 'setrlimit'), \
                    mock.patch.object(provision.getpass, 'getpass', side_effect=getpass.GetPassWarning), \
                    mock.patch.object(provision, 'store_key') as store:
                with self.assertRaises(getpass.GetPassWarning):
                    provision.main()
                store.assert_not_called()

    def test_existing_key_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / 'key'
            key.write_text('existing')
            with mock.patch.object(provision, 'KEY', key), \
                    mock.patch.object(provision.os, 'geteuid', return_value=0), \
                    mock.patch.object(provision.sys, 'argv', ['configure-healthchecks-api']), \
                    mock.patch.object(provision.sys.stdin, 'isatty', return_value=True), \
                    mock.patch.object(provision.resource, 'setrlimit'), \
                    mock.patch.object(provision.getpass, 'getpass') as prompt:
                with self.assertRaises(RuntimeError):
                    provision.main()
                prompt.assert_not_called()
                self.assertEqual(key.read_text(), 'existing')

    def test_success_does_not_print_key(self):
        value = 'test-only-placeholder-' + 'x' * 32
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(provision, 'KEY', Path(directory) / 'absent'), \
                    mock.patch.object(provision.os, 'geteuid', return_value=0), \
                    mock.patch.object(provision.sys, 'argv', ['configure-healthchecks-api']), \
                    mock.patch.object(provision.sys.stdin, 'isatty', return_value=True), \
                    mock.patch.object(provision.resource, 'setrlimit'), \
                    mock.patch.object(provision.getpass, 'getpass', return_value=value), \
                    mock.patch.object(provision, 'store_key') as store, \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                provision.main()
                store.assert_called_once_with(value)
                self.assertNotIn(value, output.getvalue())


if __name__ == '__main__':
    unittest.main()
