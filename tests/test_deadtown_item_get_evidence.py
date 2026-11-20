import tempfile
import unittest
from pathlib import Path

from tools.deadtown_item_get_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


@unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
class ItemGetEvidenceTests(unittest.TestCase):
    def test_rejects_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            wrong = Path(tmp) / 'wrong.apk'
            wrong.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(wrong)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_special_routes(self):
        evidence = inspect(APK)
        self.assertEqual((evidence['address'], evidence['size']), ('0x19f528', 4952))
        self.assertEqual(evidence['selector_global_indices'], [0, 1, 2, 3])
        self.assertEqual(evidence['map_equality_global_index'], 3)
        self.assertEqual([(x['item_index'], x['global_index'], x['return_value'])
                          for x in evidence['special_cases']],
                         [(44, 12, 0), (45, 13, 0), (46, 14, 0), (47, 15, 0), (48, 16, 0)])
        self.assertEqual([x['add_call'] for x in evidence['special_cases']],
                         ['0x1a037c', '0x1a03c0', '0x1a0404', '0x1a0448', '0x1a04a4'])
        self.assertEqual(evidence['epsilon_initial'], 1e-10)
        self.assertIn('global name registration', evidence['limitations'])


if __name__ == '__main__':
    unittest.main()
