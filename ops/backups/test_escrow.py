import importlib.util,io,tarfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('escrow',Path(__file__).with_name('prepare_muzeum_escrow.py'))
escrow=importlib.util.module_from_spec(spec);spec.loader.exec_module(escrow)

class EscrowTests(unittest.TestCase):
    def archive(self,entries):
        buffer=io.BytesIO()
        with tarfile.open(fileobj=buffer,mode='w:gz') as archive:
            for name,value in entries.items():
                entry=tarfile.TarInfo(name);entry.size=len(value)
                archive.addfile(entry,io.BytesIO(value))
        return buffer.getvalue()

    def test_exact_current_document(self):
        values={'key':b'fixture-key','password':b'fixture-password'}
        escrow.validate(self.archive(values),values)

    def test_rejects_stale_and_extra_members(self):
        with self.assertRaises(RuntimeError):escrow.validate(self.archive({'key':b'old'}),{'key':b'new'})
        with self.assertRaises(RuntimeError):escrow.validate(self.archive({'key':b'new','extra':b'x'}),{'key':b'new'})

    def test_rejects_traversal(self):
        with self.assertRaises(RuntimeError):escrow.validate(self.archive({'../key':b'value'}),{'key':b'value'})

if __name__=='__main__':unittest.main()
