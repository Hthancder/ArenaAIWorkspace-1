from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_item_lifetime_evidence import inspect, verify_source
from tools.deadtown_item_lifetime_vm_probe import EXPECTED, check, instrument
from tools.deadtown_zombie_item_vm_probe import EXPECTED as ZOMBIE_EXPECTED, check as check_zombie, extract, instrument as instrument_zombie

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class ItemLifetimeEvidenceTests(unittest.TestCase):
    def test_source_and_tamper(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / 'objects').mkdir()
            for name in ('obj_item', 'obj_parcel', 'obj_zombie3'):
                shutil.copyfile(PROJECT / 'objects' / (name + '.object.gmx'), project / 'objects' / (name + '.object.gmx'))
            path = project / 'objects/obj_item.object.gmx'
            path.write_text(path.read_text().replace('alarm[0] = 900', 'alarm[0] = 1'))
            with self.assertRaises(ValueError):
                verify_source(project)
            shutil.copyfile(PROJECT / 'objects/obj_item.object.gmx', path)
            path = project / 'objects/obj_zombie3.object.gmx'
            text = path.read_text()
            path.write_text(text.replace('ins.__dt_item_timed = 1', 'ins.__dt_item_timed = 0', 1))
            with self.assertRaises(ValueError):
                verify_source(project)

    def test_instrumented_vm_markers(self):
        e = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        self.assertTrue(instrument([e])[0]['gml'].endswith('original();'))
        self.assertEqual(check('\n'.join(EXPECTED)), 2)
        with self.assertRaises(ValueError):
            check('\n'.join(EXPECTED).replace('alive:1:1:0', 'alive:1:0:0'))
        with self.assertRaises(ValueError):
            instrument([])

    def test_zombie_fragment_probe(self):
        fragment = extract(PROJECT)
        self.assertEqual(fragment.count('ins.__dt_item_timed = 1'), 2)
        self.assertNotIn('random(1)', fragment)
        e = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        self.assertTrue(instrument_zombie([e], fragment)[0]['gml'].endswith('original();'))
        self.assertEqual(check_zombie('\n'.join(ZOMBIE_EXPECTED)), 3)
        with self.assertRaises(ValueError):
            check_zombie('\n'.join(ZOMBIE_EXPECTED).replace('whole:1:2', 'whole:0:2'))
        with self.assertRaises(ValueError):
            instrument_zombie([], fragment)

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'fake.apk'
            fake.write_bytes(b'incorrect')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(fake)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires analysis dependencies and pinned APK')
    def test_native(self):
        result = inspect(APK)
        self.assertEqual(result['native_item_object_index'], 161)
        self.assertEqual(result['native_flag_slot'], 1096)
        self.assertEqual(result['native_delay_slot'], 1097)
        self.assertIn('two drop paths', result['zombie3_alarm_6'])
        self.assertIn('Alarm 1 are missing', result['limitations'])


if __name__ == '__main__':
    unittest.main()
