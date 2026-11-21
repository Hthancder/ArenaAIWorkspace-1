from pathlib import Path
import tempfile
import unittest

from tools.deadtown_gamepad_evidence import FUNCTIONS, inspect, verify_source
from tools.deadtown_gamepad_vm_probe import EXPECTED, check, instrument, make_project

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class GamepadEvidenceTests(unittest.TestCase):
    def test_source_and_mock_copy(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'probe'
            make_project(PROJECT, dest)
            text = (dest / 'scripts/gp_axis_value.gml').read_text()
            self.assertIn('__dt_probe_gamepad_axis_value', text)
            self.assertNotIn('__dt_probe_gamepad_', (PROJECT / 'scripts/gp_axis_value.gml').read_text())
            with self.assertRaises(ValueError):
                make_project(PROJECT, dest)
            (dest / 'scripts/gp_axis_value.gml').write_text('return 0;\n')
            # Copied probe deliberately has no project declaration and cannot
            # be passed off as the editable source project.
            with self.assertRaises((ValueError, FileNotFoundError)):
                verify_source(dest)

    def test_instrument_and_negative_markers(self):
        evt = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        self.assertTrue(instrument([evt])[0]['gml'].endswith('original();'))
        self.assertEqual(check('\n'.join(EXPECTED)), 3)
        with self.assertRaises(ValueError):
            check('\n'.join(EXPECTED).replace('111:211', '131:231'))
        with self.assertRaises(ValueError):
            instrument([])

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'fake.apk'
            p.write_bytes(b'incorrect')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires analysis dependencies and pinned APK')
    def test_native(self):
        r = inspect(APK)
        self.assertEqual(set(r['scripts']), set(FUNCTIONS))
        self.assertIn('first connected device', r['behavior'])


if __name__ == '__main__':
    unittest.main()
