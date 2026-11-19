import tempfile
import unittest
from pathlib import Path

from tools.deadtown_native_lang import compare_source, extract

ROOT = Path(__file__).resolve().parents[1]


class NativeLanguageTests(unittest.TestCase):
    def test_compare_source_uses_distinct_literal_tuples(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / 'objects').mkdir()
            (p / 'objects/sys_global.object.gmx').write_text(
                '<object><string>lang_add("Craft","제작","","")\n'
                'lang_add("Item","아이템","","")\n'
                'lang_add("Item","아이템","","")</string></object>', encoding='utf-8')
            entries = [
                {'candidate_arguments': ['Craft', '제작', '', '']},
                {'candidate_arguments': ['Extra', '', '', '']},
            ]
            self.assertEqual(compare_source(entries, p), {
                'source_distinct_literal_tuples': 2,
                'recovered_distinct_candidate_tuples': 2,
                'source_tuples_matching_candidates': 1,
                'source_tuples_not_seen': 1,
                'candidate_tuples_not_in_source': 1,
            })

    def test_rejects_unrecognized_apk(self):
        try:
            import capstone  # noqa: F401
            import elftools  # noqa: F401
        except ImportError:
            self.skipTest('requires optional capstone and pyelftools')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'other.apk'
            path.write_bytes(b'not the original')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                extract(path)

    @unittest.skipUnless((ROOT / '.cache/deadtown-original.apk').is_file() and
                         (ROOT / '.cache/deadtown/deadtown.gmx/deadtown.project.gmx').is_file(),
                         'requires pinned APK and source in local cache')
    def test_known_apk_reproduces_language_inventory(self):
        try:
            import capstone  # noqa: F401
            import elftools  # noqa: F401
        except ImportError:
            self.skipTest('requires optional capstone and pyelftools')
        result = extract(ROOT / '.cache/deadtown-original.apk')
        self.assertEqual(result['candidate_call_count'], 465)
        self.assertEqual(result['unresolved_call_count'], 0)
        self.assertEqual(result['entries'][0]['candidate_arguments'], ['Craft', '제작', '', ''])
        counts = compare_source(result['entries'], ROOT / '.cache/deadtown/deadtown.gmx')
        self.assertEqual(counts['source_tuples_matching_candidates'], 362)
        self.assertEqual(counts['source_tuples_not_seen'], 0)
        self.assertEqual(counts['candidate_tuples_not_in_source'], 103)


if __name__ == '__main__':
    unittest.main()
