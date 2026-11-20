import tempfile
import unittest
from pathlib import Path
from tools.deadtown_weapon_save_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


@unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
class WeaponSaveEvidenceTests(unittest.TestCase):
    def test_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(path)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_save_load_and_cap(self):
        evidence = inspect(APK)
        self.assertEqual([(x['global_index'], x['section'], x['key'], x['default'])
                          for x in evidence['keys']],
                         [(5, 'equip', 'weapon', -1.0), (6, 'equip', 'weaponlevel', 0.0)])
        self.assertEqual(evidence['level_cap']['global_index'], 24)
        self.assertEqual(evidence['level_cap']['static_create_value'], 20.0)
        self.assertEqual(evidence['level_cap']['conditional_copy'], '0x21ede4')
        self.assertIn('no native or iOS execution', evidence['limitations'])


if __name__ == '__main__':
    unittest.main()
