from pathlib import Path
import tempfile
import unittest
from tools.deadtown_basic_string_evidence import inspect, verify_source

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class BasicStringTests(unittest.TestCase):
    def test_source(self):
        verify_source(ROOT / 'deadtown-source/project')

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'fake.apk'
            fake.write_bytes(b'incorrect')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(fake)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires analysis dependencies and pinned APK')
    def test_static_evidence(self):
        report = inspect(APK)
        self.assertEqual(report['iterations'], 20)
        self.assertEqual(report['result_normal_path'], 'A' * 20)
        self.assertIn('unverified', report['limitations'])


if __name__ == '__main__':
    unittest.main()
