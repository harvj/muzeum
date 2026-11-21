import importlib.machinery
import importlib.util
import os
import signal
import threading
from pathlib import Path
import sys
import tempfile
import time
import unittest

loader = importlib.machinery.SourceFileLoader('muzeum_migration_helper', str(Path(__file__).parents[1] / 'provision/muzeum-migrate'))
spec = importlib.util.spec_from_loader(loader.name, loader)
migration = importlib.util.module_from_spec(spec)
loader.exec_module(migration)


class MigrationProcessTests(unittest.TestCase):
    def test_timeout_terminates_the_entire_migration_process_group(self):
        with tempfile.TemporaryDirectory() as root:
            marker = Path(root) / 'orphan-wrote-data'
            child = "import time;from pathlib import Path;time.sleep(1);Path(" + repr(str(marker)) + ").write_text('unsafe orphan')"
            parent = "import subprocess,sys,time;subprocess.Popen([sys.executable,'-c'," + repr(child) + "]);time.sleep(30)"
            result = migration.run_bounded([sys.executable, '-c', parent], cwd=root, env=os.environ.copy(), timeout=0.2)
            self.assertEqual(result.returncode, 124)
            time.sleep(1.1)
            self.assertFalse(marker.exists())

    def test_completed_process_retains_exit_status_without_printing_output(self):
        with tempfile.TemporaryDirectory() as root:
            result = migration.run_bounded([sys.executable, '-c', "import sys;print('private diagnostic',file=sys.stderr);sys.exit(3)"], cwd=root, env=os.environ.copy(), timeout=5)
            self.assertEqual(result.returncode, 3)
            self.assertIn(b'private diagnostic', result.stderr)

    def test_operator_interrupt_terminates_the_migration_process_group(self):
        with tempfile.TemporaryDirectory() as root:
            marker = Path(root) / 'orphan-wrote-data'
            child = "import time;from pathlib import Path;time.sleep(1);Path(" + repr(str(marker)) + ").touch()"
            parent = "import subprocess,sys,time;subprocess.Popen([sys.executable,'-c'," + repr(child) + "]);time.sleep(30)"
            previous = signal.signal(signal.SIGTERM, migration.interrupt)
            timer = threading.Timer(0.2, os.kill, args=(os.getpid(), signal.SIGTERM))
            try:
                timer.start()
                result = migration.run_bounded([sys.executable, '-c', parent], cwd=root, env=os.environ.copy(), timeout=10)
            finally:
                timer.cancel()
                timer.join()
                signal.signal(signal.SIGTERM, previous)
            self.assertEqual(result.returncode, 130)
            time.sleep(1.1)
            self.assertFalse(marker.exists())
