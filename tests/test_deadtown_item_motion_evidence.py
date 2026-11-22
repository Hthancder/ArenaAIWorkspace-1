from pathlib import Path
import shutil
import tempfile
import unittest
from tools.deadtown_event_probe import extract_events
from tools.deadtown_item_motion_evidence import inspect, verify_source
from tools.deadtown_item_motion_vm_probe import MARKER, instrument, check

ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'deadtown-source/project'
APK=ROOT/'.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    DEPS=True
except ImportError:
    DEPS=False


class ItemMotionTests(unittest.TestCase):
    def test_source_and_mutation(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            dest=Path(tmp)/'objects';dest.mkdir()
            path=dest/'obj_item.object.gmx';shutil.copy(PROJECT/'objects/obj_item.object.gmx',path)
            original=path.read_text(encoding='utf-8')
            for a,b in [('x+xx-20','x+xx-10'),('par_action,1,1','par_solid,1,1'),('if sp &gt; 0','if sp &gt; 1')]:
                self.assertIn(a,original);path.write_text(original.replace(a,b,1),encoding='utf-8')
                with self.assertRaises(ValueError):verify_source(Path(tmp))
                path.write_text(original,encoding='utf-8')

    def test_probe(self):
        ev=extract_events(PROJECT);instrument(ev,PROJECT)
        self.assertEqual(check(MARKER),1)
        with self.assertRaises(ValueError):check('ITEM_MOTION_VM:1:1:0')

    @unittest.skipUnless(DEPS and APK.is_file(),'requires pinned APK and analysis dependencies')
    def test_native(self):
        self.assertEqual(inspect(APK)['event'],'obj_item:Step:0')

if __name__=='__main__':unittest.main()
