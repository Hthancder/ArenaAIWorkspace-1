import tempfile
import unittest
from pathlib import Path

from tools.deadtown_lang_fallback_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


@unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
class LanguageFallbackTests(unittest.TestCase):
    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(path)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_pinned_language_branches(self):
        result = inspect(APK)
        self.assertEqual((result['selector_global_index'], result['case_zero_returns_argument']), (62, 0))
        self.assertEqual([c['candidate_map_global_index'] for c in result['cases']], [63, 64, 65])
        self.assertEqual([c['missing_branch_target'] for c in result['cases']],
                         ['0x2dfcb8', '0x2dfcd0', '0x2dfce8'])
        self.assertTrue(all(c['map_exists']['symbol'] == 'g_FUNC_ds_map_exists' and
                            c['map_find_value']['symbol'] == 'g_FUNC_ds_map_find_value' and
                            c['fallback_argument'] == 0 for c in result['cases']))
        self.assertIn('no native execution', result['limitations'])


if __name__ == '__main__':
    unittest.main()
