from pathlib import Path
import tempfile
import unittest

from tools.deadtown_gps_colour_evidence import inspect, verify_source

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class GPSColourEvidenceTests(unittest.TestCase):
    def test_declared_candidate(self):
        verify_source(ROOT / 'deadtown-source/project')

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_reject_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'fake.apk'
            fake.write_bytes(b'not an APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(fake)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires dependencies and pinned APK')
    def test_relocations_constants_and_calls(self):
        report = inspect(APK)
        self.assertEqual(report['static_call'], 'make_colour_hsv(irandom(255), 180, 120)')
        self.assertIn('not tested', report['limitations'])


if __name__ == '__main__':
    unittest.main()
