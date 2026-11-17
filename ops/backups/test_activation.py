import hashlib,importlib.util,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('activation',Path(__file__).parent.parent/'provision/activate-site.py')
activation=importlib.util.module_from_spec(spec);spec.loader.exec_module(activation)

class ActivationTests(unittest.TestCase):
    def test_concurrent_shared_change_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as root:
            config=Path(root)/'Caddyfile';config.write_bytes(b'changed by another application')
            with patch.object(activation,'CADDY',config),patch.object(activation,'run') as run:
                with self.assertRaises(RuntimeError):activation.replace_config(b'candidate',hashlib.sha256(b'old').hexdigest())
                self.assertEqual(config.read_bytes(),b'changed by another application');run.assert_not_called()

    def test_validation_failure_preserves_original_bytes(self):
        with tempfile.TemporaryDirectory() as root:
            config=Path(root)/'Caddyfile';config.write_bytes(b'existing sites')
            with patch.object(activation,'CADDY',config),patch.object(activation,'run',side_effect=RuntimeError('invalid')):
                with self.assertRaises(RuntimeError):activation.replace_config(b'candidate',activation.digest(b'existing sites'))
                self.assertEqual(config.read_bytes(),b'existing sites')
                self.assertFalse(config.with_name('Caddyfile.muzeum-candidate').exists())

if __name__=='__main__':unittest.main()
