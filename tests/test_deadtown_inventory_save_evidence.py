import tempfile
import unittest
from pathlib import Path

from tools.deadtown_inventory_save_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


@unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
class InventorySaveEvidenceTests(unittest.TestCase):
    def test_wrong_apk_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            wrong = Path(tmp) / 'wrong.apk'
            wrong.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(wrong)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_four_pinned_mappings(self):
        report = inspect(APK)
        self.assertEqual(report['address'], '0x1d97f8')
        self.assertEqual([(r['selector'], r['global_index'], r['save_section'], r['save_key'])
                          for r in report['mapping']],
                         [(1, 0, 'inventory', 'weapon'), (2, 1, 'inventory', 'equip'),
                          (3, 2, 'inventory', 'use'), (4, 3, 'inventory', 'etc')])
        self.assertEqual([x['map_write_call'] for x in report['mapping']],
                         ['0x1dab04', '0x1dac6c', '0x1dadd4', '0x1daf3c'])
        self.assertIn('not global registration', report['limitations'])


if __name__ == '__main__':
    unittest.main()
