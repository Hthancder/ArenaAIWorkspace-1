from pathlib import Path
import tempfile
import unittest

from tools.deadtown_room_check_evidence import inspect

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
        self.assertIn('not a portable', report['limitations'])


if __name__ == '__main__':
    unittest.main()
