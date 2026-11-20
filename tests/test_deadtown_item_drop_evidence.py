import tempfile
import unittest
from pathlib import Path

from tools.deadtown_item_drop_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


@unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
class ItemDropEvidenceTests(unittest.TestCase):
    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            wrong = Path(tmp) / 'wrong.apk'
            wrong.write_bytes(b'not an APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(wrong)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_pinned_arm_control_and_dataflow(self):
        evidence = inspect(APK)
        self.assertEqual((evidence['address'], evidence['size']), ('0x1a31e0', 2100))
        self.assertEqual((evidence['selector_argument'], evidence['key_argument']), (0, 1))
        self.assertEqual([c['selector'] for c in evidence['selector_cases']], [1, 2, 3, 4])
        self.assertEqual([c['global_index'] for c in evidence['selector_cases']], [0, 1, 2, 3])
        self.assertEqual([c['instance_slot'] for c in evidence['selector_cases']], [7, 7, 7, 7])
        self.assertEqual(evidence['missing_path']['return_value'], 0)
        self.assertEqual(evidence['present_path']['return_value'], 1)
        self.assertEqual(evidence['present_path']['subtract_integer'], 1)
        self.assertEqual(evidence['present_path']['set_symbol'], 'g_FUNC_ds_map_set')
        self.assertEqual(evidence['delete_comparison']['initial_value'], 1e-10)
        self.assertIn('no native execution', evidence['limitations'])


if __name__ == '__main__':
    unittest.main()
