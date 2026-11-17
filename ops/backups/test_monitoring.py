"""No network requests: exercise acknowledgement, privacy and failure semantics."""
import contextlib
import io
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch
import monitoring
import configure_healthchecks
import muzeum_backup


class Config:
    def lstat(self):
        return types.SimpleNamespace(st_uid=0, st_mode=stat.S_IFREG | 0o600)

    def read_text(self):
        return json.dumps({'backup': 'https://hc-ping.com/00000000-0000-0000-0000-000000000000'})


class MonitoringTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(monitoring, 'STATE', Path(self.temporary.name)))
        self.stack.enter_context(patch.object(monitoring, 'CONFIG', Config()))

    def test_secret_url_uses_stdin_not_argv_and_deadlines_are_bounded(self):
        with patch.object(monitoring.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0, stdout='OK')) as run:
            self.assertTrue(monitoring.signal('backup', 'success'))
        args, kwargs = run.call_args
        self.assertNotIn('hc-ping', ' '.join(args[0]))
        self.assertIn('hc-ping.com', kwargs['input'])
        self.assertEqual(kwargs['timeout'], 7)
        self.assertIn('--max-time', args[0])

    def test_http_200_not_found_is_not_success(self):
        with patch.object(monitoring.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0, stdout='OK (not found)')):
            self.assertFalse(monitoring.signal('backup', 'success'))

    def test_monitoring_timeout_cannot_hide_backup_error(self):
        with patch.object(monitoring.subprocess, 'run', side_effect=subprocess.TimeoutExpired('curl', 7)):
            with self.assertRaisesRegex(RuntimeError, 'original backup failure'):
                with monitoring.job_run('backup'):
                    raise RuntimeError('original backup failure')

    def test_success_signal_only_after_operation_completes(self):
        events = []
        with patch.object(monitoring, 'signal', side_effect=lambda job, phase, run_id: events.append(phase) or True):
            with monitoring.job_run('backup'):
                events.append('snapshot-verified')
        self.assertEqual(events, ['start', 'snapshot-verified', 'success'])

    def test_monitoring_outage_preserves_successful_backup(self):
        with patch.object(monitoring, 'signal', return_value=False):
            with monitoring.job_run('backup'):
                result = 0
        self.assertEqual(result, 0)

    def test_monitoring_fault_preserves_original_exit_code(self):
        with patch.object(monitoring, 'signal', side_effect=OSError('monitoring storage unavailable')):
            with self.assertRaises(SystemExit) as error:
                with monitoring.job_run('backup'):
                    raise SystemExit(12)
        self.assertEqual(error.exception.code, 12)

    def test_failed_snapshot_verification_never_sends_success(self):
        events = []
        with patch.object(monitoring, 'signal', side_effect=lambda job, phase, run_id: events.append(phase) or True):
            with self.assertRaisesRegex(RuntimeError, 'snapshot verification'):
                with monitoring.job_run('backup'):
                    raise RuntimeError('snapshot verification failed')
        self.assertEqual(events, ['start', 'failure'])

    def test_restic_exit_code_survives_monitoring_outage(self):
        failed = types.SimpleNamespace(returncode=12, stdout=b'', stderr=b'not logged')
        with patch.object(monitoring, 'signal', return_value=False), patch.object(muzeum_backup.subprocess, 'run', return_value=failed):
            with self.assertRaises(muzeum_backup.CommandFailure) as error:
                with monitoring.job_run('backup'):
                    muzeum_backup.invoke(['/restic', 'backup'], label='Restic backup')
        self.assertEqual(error.exception.exit_code, 12)

    def test_secure_provisioning_rejects_other_destinations_or_action_suffixes(self):
        base = 'https://hc-ping.com/00000000-0000-0000-0000-000000000000'
        self.assertEqual(configure_healthchecks.normalize_url(base), base)
        for value in [base.replace('https:', 'http:'), base + '/start', base + '?create=1',
                      base.replace('hc-ping.com', 'hc-ping.com.example.com')]:
            with self.assertRaises(ValueError):
                configure_healthchecks.normalize_url(value)

    def test_errors_do_not_log_credential_urls(self):
        output = io.StringIO()
        with patch.object(monitoring.subprocess, 'run', side_effect=RuntimeError('https://hc-ping.com/SECRET')), contextlib.redirect_stderr(output):
            self.assertFalse(monitoring.signal('backup', 'failure'))
        self.assertNotIn('SECRET', output.getvalue())
        self.assertNotIn('hc-ping.com', output.getvalue())


if __name__ == '__main__':
    unittest.main()
