import importlib.util,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import production_restore as module

class RecoveryIsolationTests(unittest.TestCase):
    def values(self):
        return {key:'postgresql://muzeum_runtime:fixture@127.0.0.1:5432/'+source for key,source in zip(
            ('DATABASE_URL','CACHE_DATABASE_URL','QUEUE_DATABASE_URL','CABLE_DATABASE_URL'),module.production_capture.DATABASES)}

    def test_every_connection_is_remapped_before_readonly_application_boot(self):
        targets={source:'muzeum_recovery_'+str(i)*16 for i,source in enumerate(module.production_capture.DATABASES)}
        env=module.recovery_environment(self.values(),targets,Path('/reviewed/release'))
        for key in self.values():self.assertIn('/muzeum_recovery_',env[key]);self.assertNotIn('/muzeum_production',env[key])
        self.assertIn('default_transaction_read_only=on',env['PGOPTIONS'])
        self.assertEqual(env['BUNDLE_WITHOUT'],'development:test')

    def test_rejects_production_or_missing_recovery_targets(self):
        with self.assertRaises(RuntimeError):module.recovery_environment(self.values(),{},Path('/reviewed/release'))
        targets={source:source for source in module.production_capture.DATABASES}
        with self.assertRaises(RuntimeError):module.recovery_environment(self.values(),targets,Path('/reviewed/release'))

if __name__=='__main__':unittest.main()
