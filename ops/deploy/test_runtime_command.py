import json
import os
from pathlib import Path
import subprocess
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch

import muzeum_deploy as deploy


class RuntimeCommandTests(unittest.TestCase):
    def test_inspection_runs_as_scoped_identity_with_restricted_path_and_absolute_runuser(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root).resolve()
            (app / 'shared').mkdir()
            names = ('DATABASE_URL', 'CACHE_DATABASE_URL', 'QUEUE_DATABASE_URL', 'CABLE_DATABASE_URL')
            databases = ('muzeum_production', 'muzeum_production_cache', 'muzeum_production_queue', 'muzeum_production_cable')
            (app / 'shared/.env').write_text('\n'.join(key+'=postgresql://muzeum_runtime:fixture@127.0.0.1/'+database for key,database in zip(names,databases)))
            host = deploy.Host()
            calls = []
            def command(argv, **kwargs):
                calls.append((argv,kwargs))
                return 'MUZEUM_DEPLOY_INSPECTION:'+json.dumps({'pending': []})
            host.command = command
            runtime = app / 'runtime'
            runtime.mkdir()
            for executable in ('ruby', 'bundle'):
                (runtime / executable).touch()
            real_lstat = Path.lstat
            def trusted_lstat(path):
                info = real_lstat(path)
                return SimpleNamespace(st_uid=0, st_mode=info.st_mode & ~0o022)
            with patch.object(deploy, 'APP', app), patch.object(deploy, 'RUBY_BIN', runtime), patch.object(Path, 'lstat', trusted_lstat):
                host.inspect(app)
                sanitized = deploy.runtime_environment({'LD_PRELOAD': 'fixture', 'BUNDLE_PATH': 'fixture', 'RUBYOPT': 'fixture'})
            self.assertNotIn('LD_PRELOAD', sanitized)
            self.assertNotIn('RUBYOPT', sanitized)
            self.assertEqual(sanitized['BUNDLE_PATH'], deploy.BUNDLE_PATH)
            argv, kwargs = calls[0]
            self.assertEqual(argv[:6], ['/usr/sbin/runuser', '-u', 'muzeum', '--', str(runtime/'ruby'), str(runtime/'bundle')])
            self.assertNotIn('/usr/sbin', kwargs['env']['PATH'].split(':'))
            self.assertIn('default_transaction_read_only=on', kwargs['env']['PGOPTIONS'])
            if sys.platform.startswith('linux'):
                # This failed before the fix: the real executable cannot be located by PATH.
                result = subprocess.run([argv[0], '--help'], env={'PATH':'/usr/bin:/bin'}, capture_output=True)
                self.assertEqual(result.returncode, 0)
