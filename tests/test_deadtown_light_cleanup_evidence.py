from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_light_cleanup_evidence import TARGETS, candidate, inspect, verify_source
from tools.deadtown_light_cleanup_vm_probe import EXPECTED, check, instrument

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT/'deadtown-source/project'
APK = ROOT/'.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


def event(obj, typ, text='original();'):
    return {'object': obj, 'attributes': {'eventtype': typ, 'enumb': '0'}, 'gml': text}


class LightCleanupTests(unittest.TestCase):
    def test_source_and_mutations(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)
            shutil.copy(PROJECT/'deadtown.project.gmx', dest)
            shutil.copytree(PROJECT/'objects', dest/'objects')
            for name, row in TARGETS.items():
                p = dest/'objects'/(name+'.object.gmx')
                original = p.read_text()
                for old, new in ((candidate(row[0]), candidate(row[0]).replace('instance_destroy()', 'instance_deactivate_object()')),
                                 ('eventtype="1" enumb="0"', 'eventtype="1" enumb="1"')):
                    self.assertIn(old, original)
                    p.write_text(original.replace(old, new, 1))
                    with self.assertRaises(ValueError):
                        verify_source(dest)
                    p.write_text(original)

    def test_probe(self):
        events = [event('sys_global', '0'), event('obj_light', '0')]
        for name, row in TARGETS.items():
            events.extend([event(name, '0'), event(name, '1', '{\n'+candidate(row[0])+'\n}')])
        instrument(events, PROJECT)
        self.assertIn('LIGHT_CLEANUP_VM:obj_cooker:', events[0]['gml'])
        self.assertEqual(check('\n'.join(EXPECTED)), 6)
        with self.assertRaises(ValueError):
            check('\n'.join(EXPECTED).replace(':1:0', ':1:1', 1))
        with self.assertRaises(ValueError):
            instrument(events[1:], PROJECT)

    @unittest.skipUnless(HAS_DEPS, 'requires analysis dependencies')
    def test_bad_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'bad.apk'
            p.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires pinned APK and analysis dependencies')
    def test_native(self):
        report = inspect(APK)
        self.assertEqual(len(report['events']), 6)
        self.assertEqual([item['native_instance_slot'] for item in report['events']], [344, 344, 1162, 1162, 1162, 1162])


if __name__ == '__main__':
    unittest.main()
