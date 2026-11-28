"""Exercise the protected force phases and real Linux lock ownership."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import muzeum_deploy as deploy
from test_workflow import FixtureHost, NEW, OLD

ARTIFACT = 'd' * 64
TOKEN = '1' * 32


class ForceHost(FixtureHost):
    @contextlib.contextmanager
    def force_backup_guard(self):
        yield 'shared-backup-exclusivity: verified unrelated CE capture'

    def verify_release_integrity(self, release, sha):
        return {'source_sha': sha, 'artifact_sha256': ARTIFACT}

    def publish_force(self, release, token):
        self.publish()


class ForceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def flow(self, **options):
        host = ForceHost(self.root, **options)
        return host, deploy.Deployment(host, self.root / 'audit')

    def begin(self, flow, digest=ARTIFACT):
        flow.run('begin', NEW, TOKEN, baseline=OLD, force_artifact=digest)

    def test_force_reconciles_only_untouched_failed_receipt_and_records_override(self):
        host, flow = self.flow()
        flow.root.mkdir()
        old_token = '2' * 32
        previous = dict(sha=NEW, token=old_token, phase='failed', failed_phase='prepare',
                        migrating=False, withdrawn=False, baseline={'revision': OLD})
        flow.save(previous)
        self.begin(flow)
        flow.run('prepare', NEW, TOKEN, str(host.candidate))
        flow.run('finish', NEW, TOKEN)
        complete = flow.run('complete', NEW, TOKEN)
        self.assertEqual(complete['phase'], 'complete')
        self.assertEqual(host.sha, NEW)
        self.assertEqual(complete['force']['overrides'],
                         ['shared-backup-exclusivity: verified unrelated CE capture'])
        self.assertEqual(complete['force']['artifact_sha256'], ARTIFACT)
        self.assertEqual(json.loads((flow.root / complete['force']['recovered_receipt']).read_text()), previous)
        self.assertFalse((flow.root / 'active.json').exists())

    def test_rejects_active_phase_owner(self):
        _, flow = self.flow()
        flow.root.mkdir()
        with (flow.root / 'phase.lock').open('a') as hold:
            fcntl.flock(hold, fcntl.LOCK_EX)
            with self.assertRaisesRegex(RuntimeError, 'owns the deployment phase lock'):
                self.begin(flow)

    def test_rejects_failed_receipt_with_migration_intent(self):
        host, flow = self.flow()
        flow.root.mkdir()
        flow.save(dict(sha=NEW, token='2' * 32, phase='failed', failed_phase='prepare',
                       migrating=True, withdrawn=False, baseline={'revision': OLD}))
        with self.assertRaisesRegex(RuntimeError, 'manual recovery'):
            self.begin(flow)
        self.assertEqual(host.sha, OLD)
        self.assertTrue((flow.root / 'active.json').exists())

    def test_rejects_pending_migration(self):
        host, flow = self.flow(migration=True)
        self.begin(flow)
        with self.assertRaises(RuntimeError):
            flow.run('prepare', NEW, TOKEN, str(host.candidate))
        self.assertEqual(host.sha, OLD)
        self.assertNotIn('migration', host.events)

    def test_rejects_wrong_artifact(self):
        host, flow = self.flow()
        self.begin(flow, 'e' * 64)
        with self.assertRaises(RuntimeError):
            flow.run('prepare', NEW, TOKEN, str(host.candidate))
        self.assertEqual(host.sha, OLD)


@unittest.skipUnless(sys.platform == 'linux' and os.geteuid() == 0, 'Disposable Linux root fixture required')
class KernelTests(unittest.TestCase):
    def test_verified_capture_keeps_running_and_excludes_same_app_workers(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.ExitStack() as stack:
            root = Path(tmp)
            ce_script = root / 'ce-capture'
            ce_script.write_text('exec 9<"$0.scratch"\nflock -n 9 || exit\necho locked\nread -r line\n')
            scratch = ce_script.with_suffix('.scratch')
            scratch.touch()
            scratch.rename(root / 'backup.lock')
            ce_script.with_suffix('.scratch').symlink_to(root / 'backup.lock')
            backups = root / 'muzeum'
            backups.mkdir()
            (backups / 'recovery.lock').touch()
            migration = root / 'migration.lock'
            migration.touch()
            ce = stack.enter_context(subprocess.Popen(['/bin/bash', str(ce_script), 'backup'],
                                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE))
            stack.callback(lambda: ce.kill() if ce.poll() is None else None)
            self.assertEqual(ce.stdout.readline(), b'locked\n')
            host = deploy.Host()
            stack.enter_context(patch.object(deploy, 'BACKUPS', backups))
            stack.enter_context(patch.object(deploy, 'APP', root))
            stack.enter_context(patch.object(deploy, 'MIGRATION_LOCK', migration))
            stack.enter_context(patch.object(deploy, 'CE_CAPTURE', os.fsencode(ce_script)))
            stack.enter_context(patch.object(host, 'command', return_value=str(ce.pid)))
            with host.force_backup_guard() as overridden:
                self.assertIn('verified unrelated CE', overridden)
                self.assertIsNone(ce.poll())
            for name in (backups / 'recovery.lock', migration):
                with name.open('r') as existing:
                    fcntl.flock(existing, fcntl.LOCK_EX)
                    with self.assertRaisesRegex(RuntimeError, 'owns its lock'):
                        with host.force_backup_guard():
                            self.fail('conflicting operation admitted')
            with patch.object(host, 'command', return_value='0'):
                with self.assertRaisesRegex(RuntimeError, 'not a verified CE'):
                    with host.force_backup_guard():
                        self.fail('unrecognized scratch holder admitted')
            self.assertIsNone(ce.poll())
            ce.stdin.write(b'done\n')
            ce.stdin.flush()
            self.assertEqual(ce.wait(timeout=5), 0)


    def test_verified_isolated_restore_preserves_capacity_and_scoped_locks(self):
        with tempfile.TemporaryDirectory(dir='/root') as tmp, contextlib.ExitStack() as stack:
            root = Path(tmp)
            backups = root / 'muzeum'
            backups.mkdir()
            recovery = backups / 'recovery.lock'
            migration = root / 'migration.lock'
            ce_lock = root / 'ce.lock'
            scratch = root / 'backup.lock'
            for path in (recovery, migration, ce_lock, scratch):
                path.touch()
            script = root / 'reviewed-restore'
            script.write_text(f'exec 8<{ce_lock}\nexec 9<{scratch}\nflock -n 8 && flock -n 9 || exit\necho locked\nread -r line\n')
            ce = stack.enter_context(subprocess.Popen(['/bin/bash', str(script)],
                                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE))
            stack.callback(lambda: ce.kill() if ce.poll() is None else None)
            self.assertEqual(ce.stdout.readline(), b'locked\n')
            host = deploy.Host()
            for name, value in {
                'BACKUPS': backups, 'APP': root, 'MIGRATION_LOCK': migration,
                'CE_ISOLATED_RESTORE': script, 'CE_RELEASE_LOCK': ce_lock,
                'CE_ISOLATED_RESTORE_SHA': hashlib.sha256(script.read_bytes()).hexdigest(),
            }.items():
                stack.enter_context(patch.object(deploy, name, value))
            stack.enter_context(patch.object(host, 'command', side_effect=lambda args, **_: (
                str(ce.pid) if args[-1] == deploy.CE_ISOLATED_RESTORE_UNIT else '0')))
            free = stack.enter_context(patch.object(deploy.shutil, 'disk_usage',
                                                   return_value=SimpleNamespace(free=110 * deploy.GIB)))
            with host.force_backup_guard() as override:
                self.assertIn('verified unrelated CE isolated restore', override)
                self.assertIsNone(ce.poll())
            for path in (recovery, migration):
                with path.open('r') as held:
                    fcntl.flock(held, fcntl.LOCK_EX)
                    with self.assertRaisesRegex(RuntimeError, 'owns its lock'):
                        with host.force_backup_guard():
                            self.fail('same-app conflict admitted')
            free.return_value = SimpleNamespace(free=90 * deploy.GIB)
            with self.assertRaisesRegex(RuntimeError, 'Insufficient capacity'):
                with host.force_backup_guard():
                    self.fail('insufficient restore capacity admitted')
            free.return_value = SimpleNamespace(free=110 * deploy.GIB)
            with patch.object(deploy, 'CE_ISOLATED_RESTORE_SHA', '0' * 64):
                with self.assertRaisesRegex(RuntimeError, 'not a verified CE'):
                    with host.force_backup_guard():
                        self.fail('unreviewed restore admitted')
            self.assertIsNone(ce.poll())
            ce.stdin.write(b'done\n')
            ce.stdin.flush()
            self.assertEqual(ce.wait(timeout=5), 0)


if __name__ == '__main__':
    unittest.main()
