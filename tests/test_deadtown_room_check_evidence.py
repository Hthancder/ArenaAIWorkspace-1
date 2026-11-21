from pathlib import Path
import tempfile
import unittest

from tools.deadtown_room_check_evidence import inspect, verify_source
from tools.deadtown_room_check_vm_probe import instrument, check

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


@unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
class RoomCheckEvidenceTests(unittest.TestCase):
    def test_source_candidate(self):
        verify_source(ROOT / 'deadtown-source/project')

    def test_instrument_and_require_positive_and_negative(self):
        events = [{'object': 'sys_global', 'attributes': {'eventtype': t, 'enumb': '0'}, 'gml': 'original();'} for t in ('0', '3')]
        instrument(events)
        self.assertTrue(all(e['gml'].endswith('original();') for e in events))
        log = 'ROOM_CHECK_VM:rom_lemon:0\nROOM_CHECK_VM:rom_play_defence:1\n'
        self.assertEqual(len(check(log)), 2)
        with self.assertRaises(ValueError):
            check('ROOM_CHECK_VM:rom_play_defence:0\n')
        with self.assertRaises(ValueError):
            check('ROOM_CHECK_VM:rom_lemon:0\n')
        with self.assertRaises(ValueError):
            instrument([])

    def test_rejects_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'fake.apk'
            path.write_bytes(b'not a pinned APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(path)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_native_room_check(self):
        report = inspect(APK)
        self.assertEqual(report['builtin_variable'], 'room')
        self.assertEqual(report['compared_native_room_index'], 14)
        self.assertEqual(report['room_name_at_native_index'], 'rom_play_defence')
        self.assertEqual(report['epsilon_static_initializer'], 1e-10)
        self.assertEqual(len(report['native_room_names']), 15)
        self.assertTrue(report['all_room_indices_agree_at_default_epsilon'])
        self.assertIn('not a portable', report['limitations'])


if __name__ == '__main__':
    unittest.main()
