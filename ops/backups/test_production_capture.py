import importlib.util,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('production',Path(__file__).with_name('production_capture.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class ProductionCaptureTests(unittest.TestCase):
    def test_refuses_other_app_sources(self):
        with self.assertRaises(RuntimeError):module.validate({'mode':'production','databases':list(module.DATABASES),'sources':['/etc/auth/keys']})

    def test_refuses_unvalidated_cleanup_and_symlinks(self):
        with tempfile.TemporaryDirectory() as root:
            base=Path(root);(base/'captures').mkdir();outside=base/'outside';outside.mkdir()
            with self.assertRaises(RuntimeError):module.cleanup_capture(outside,base)
            link=base/'captures/20261117T000000000000Z';link.symlink_to(outside)
            with self.assertRaises(RuntimeError):module.cleanup_capture(link,base)
            self.assertTrue(outside.exists())

    def test_cleans_only_validated_run_directory(self):
        with tempfile.TemporaryDirectory() as root:
            base=Path(root);run=base/'captures/20261117T000000000000Z';run.mkdir(parents=True)
            module.cleanup_capture(run,base)
            self.assertFalse(run.exists());self.assertTrue(run.parent.exists())

if __name__=='__main__':unittest.main()
