import tempfile
import unittest
from pathlib import Path

from tools.deadtown_item_equip_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


@unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
class ItemEquipEvidenceTests(unittest.TestCase):
    def test_wrong_apk_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            wrong = Path(tmp) / 'wrong.apk'
            wrong.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(wrong)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_key_split_and_pet_guard(self):
        report = inspect(APK)
        self.assertEqual((report['address'], report['size']), ('0x1a0d8c', 6668))
        self.assertEqual((report['key_argument'], report['divisor_global_index']), (1, 18))
        self.assertEqual((report['quotient_instance_slot'], report['remainder_instance_slot']), (5, 6))
        self.assertEqual((report['target_map_instance_slot'], report['skip_consumption_instance_slot']), (7, 8))
        self.assertEqual((report['field_array_global_index'], report['field_array_column']), (19, 4))
        self.assertEqual(report['pet_helper']['finite_integer_range'], [17, 22])
        self.assertEqual(report['pet_helper']['initial_epsilon'], 1e-10)
        self.assertEqual(report['consumption'], {'read': '0x1a1474', 'set': '0x1a14cc',
                                                  'reread': '0x1a1560', 'delete': '0x1a1610',
                                                  'skip_target': '0x1a1660'})
        self.assertIn('Android/iOS execution', report['limitations'])


if __name__ == '__main__':
    unittest.main()
