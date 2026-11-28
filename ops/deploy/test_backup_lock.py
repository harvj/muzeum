import fcntl
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import muzeum_deploy as deploy
from test_workflow import FixtureHost, OLD, NEW


class BackupLockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.backups = self.root / 'muzeum'
        self.backups.mkdir()
        (self.backups / 'recovery.lock').touch()
        self.lock = self.backups / 'recovery.lock'
        self.lock.touch()
        self.patch = patch.object(deploy, 'BACKUPS', self.backups)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.host = deploy.Host()
        sys.path.insert(0, str(Path(__file__).parents[1] / 'backups'))
        self.addCleanup(lambda: sys.path.remove(str(Path(__file__).parents[1] / 'backups')))
        self.api = runpy.run_path(str(Path(__file__).parents[1] / 'backups/muzeum_backup.py'))
        self.api['do_action'].__globals__['BASE'] = self.backups
        (self.backups / 'state').mkdir()
        self.receipt = self.backups / 'state/last-backup.json'
        self.receipt.write_text(json.dumps({'mode': 'production', 'completed_at': deploy.now()}))
        self.host.backup_api = lambda: (self.api, {'mode': 'production'})

    def nested_cli(self):
        code = "import fcntl;f=open(" + repr(str(self.lock)) + ",'a');fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)"
        return subprocess.run([sys.executable, '-c', code], capture_output=True)

    def test_original_nested_cli_lock_is_refused(self):
        with self.host.backup_lock():
            with patch.object(sys, 'argv', ['muzeum-backup', 'monitor']):
                with self.assertRaises(BlockingIOError):
                    self.api['main']()
            self.assertNotEqual(self.nested_cli().returncode, 0)
        self.assertEqual(self.nested_cli().returncode, 0)

    def test_existing_monitor_action_works_under_coordinator_lock_without_releasing_it(self):
        with self.host.backup_lock():
            self.host.check_backup_freshness()
            self.assertNotEqual(self.nested_cli().returncode, 0)
        self.assertEqual(self.nested_cli().returncode, 0)

    def test_external_contention_refuses_acquisition(self):
        with self.lock.open('a') as held:
            fcntl.flock(held, fcntl.LOCK_EX|fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, 'recovery lock'):
                with self.host.backup_lock():
                    self.fail('must not enter')
        with self.host.backup_lock():
            pass

    def test_freshness_failure_releases_host_lock_and_retains_failed_application_receipt(self):
        self.receipt.write_text(json.dumps({'mode': 'production', 'completed_at': '2000-01-01T00:00:00+00:00'}))
        fixture = FixtureHost(self.root)
        fixture.backup_lock = self.host.backup_lock
        fixture.preflight = lambda: self.host.check_backup_freshness()
        flow = deploy.Deployment(fixture, self.root / 'audit')
        with self.assertRaises(RuntimeError):
            flow.run('begin', NEW, '1' * 32)
        self.assertEqual(self.nested_cli().returncode, 0)
        state = json.loads((self.root / 'audit/active.json').read_text())
        self.assertEqual(state['phase'], 'failed')
        self.assertTrue(fixture.running and fixture.public)

    def test_cancel_before_deploy_preserves_availability_and_releases_application_lock(self):
        fixture = FixtureHost(self.root)
        flow = deploy.Deployment(fixture, self.root / 'audit')
        flow.run('begin', NEW, '2' * 32)
        result = flow.run('cancel', NEW, '2' * 32)
        self.assertEqual(result['phase'], 'cancelled')
        self.assertFalse((self.root / 'audit/active.json').exists())
        self.assertTrue(fixture.running and fixture.public)
