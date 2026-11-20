import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import muzeum_deploy as deploy


class RuntimeCommandTests(unittest.TestCase):
    def test_inspection_runs_as_scoped_identity_with_restricted_path_and_absolute_runuser(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root)
            (app / 'shared').mkdir()
            names = ('DATABASE_URL', 'CACHE_DATABASE_URL', 'QUEUE_DATABASE_URL', 'CABLE_DATABASE_URL')
            databases = ('muzeum_production', 'muzeum_production_cache', 'muzeum_production_queue', 'muzeum_production_cable')
            (app / 'shared/.env').write_text('\n'.join(key+'=postgresql://muzeum_runtime:fixture@127.0.0.1/'+database for key,database in zip(names,databases)))
            (app / 'REVISION').write_text('024ed4aecd98984c00323377389cde5a6a35d16d')
            runtime_library = Path(__file__).resolve().parents[1] / 'runtime/muzeum_runtime.py'
            host = deploy.Host()
            calls = []
            def command(argv, **kwargs):
                calls.append((argv,kwargs))
                return 'MUZEUM_DEPLOY_INSPECTION:'+json.dumps({'pending': []})
            host.command = command
            with patch.object(deploy, 'APP', app), patch.object(deploy, 'RUNTIME_LIBRARY', runtime_library):
                host.inspect(app)
            argv, kwargs = calls[0]
            self.assertEqual(argv[:4], ['/usr/sbin/runuser', '-u', 'muzeum', '--'])
            self.assertNotIn('/usr/sbin', kwargs['env']['PATH'].split(':'))
            self.assertIn('default_transaction_read_only=on', kwargs['env']['PGOPTIONS'])
            if sys.platform.startswith('linux'):
                # This failed before the fix: the real executable cannot be located by PATH.
                result = subprocess.run([argv[0], '--help'], env={'PATH':'/usr/bin:/bin'}, capture_output=True)
                self.assertEqual(result.returncode, 0)
