import tempfile
import unittest
from pathlib import Path

from tools.deadtown_lang_coverage import FIELDS, compare
from tools.deadtown_native_tables import extract

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / '.cache/deadtown/deadtown.gmx'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


def arg(value, kind='string'):
    return {'type': kind, 'value': value}


def synthetic():
    table = {'apk_sha256': 'fixture', 'counts': {}, 'entries': {}}
    rows = [dict(arguments=[arg('Key'), arg('Korean'), arg(''), arg('')]),
            dict(arguments=[arg('Key'), arg('Alternate'), arg(''), arg('')])]
    table['counts']['lang_add'] = {'resolved': 2, 'unresolved': 0}
    table['entries']['lang_add'] = rows
    for name, indexes in FIELDS.items():
        arguments = [arg(0, 'number') for _ in range(max(indexes) + 1)]
        arguments[indexes[0]] = arg('Key')
        arguments[indexes[1]] = arg('Missing')
        table['counts'][name] = {'resolved': 1, 'unresolved': 0}
        table['entries'][name] = [dict(arguments=arguments)]
    return table


class LanguageCoverageUnitTests(unittest.TestCase):
    def test_distinct_missing_and_empty_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / 'objects').mkdir()
            (project / 'objects/sys_global.object.gmx').write_text('<object><string>lang_add("Key","ko","","")</string></object>')
            report = compare(synthetic(), project)
            self.assertEqual(report['candidate_language_calls'], 2)
            self.assertEqual(report['candidate_duplicate_english_keys'], {'Key': 2})
            self.assertEqual(report['candidate_empty_translations'], {'korean': 0, 'chinese': 2, 'japanese': 2})
            self.assertEqual((report['candidate_table_references'], report['candidate_distinct_table_keys']), (10, 2))
            self.assertEqual(report['table_keys_absent_from_old_gmx'], ['Missing'])
            self.assertEqual(report['table_keys_absent_from_native_candidates'], ['Missing'])
            table = synthetic()
            table['counts']['db_use_add']['unresolved'] = 1
            with self.assertRaisesRegex(ValueError, 'unresolved db_use_add'):
                compare(table, project)


@unittest.skipUnless(HAS_RE and APK.is_file() and PROJECT.is_dir(), 'requires pinned APK, source and RE dependencies')
class LanguageCoverageIntegrationTests(unittest.TestCase):
    def test_pinned_coverage(self):
        report = compare(extract(APK), PROJECT)
        self.assertEqual((report['candidate_language_calls'], report['candidate_distinct_english_keys']), (465, 463))
        self.assertEqual(report['candidate_duplicate_english_keys'], {'Heavy machine gun': 2, 'Light machine gun': 2})
        self.assertEqual(report['candidate_empty_translations'], {'korean': 0, 'chinese': 465, 'japanese': 465})
        self.assertEqual(report['old_empty_translations'], {'korean': 0, 'chinese': 362, 'japanese': 362})
        self.assertEqual((report['candidate_table_references'], report['candidate_distinct_table_keys']), (344, 340))
        self.assertEqual(len(report['table_keys_absent_from_old_gmx']), 52)
        self.assertEqual(report['table_keys_absent_from_native_candidates'], [])
        self.assertIn('Gas mask', report['tables']['db_use_add']['absent_from_old_gmx'])
        self.assertIn('native consumers', report['limitations'])


if __name__ == '__main__':
    unittest.main()
