import unittest
from tools.check_deadtown_language_probe import check, check_table

OLD = '''
DT_LANG|0|__DT_LANG_KNOWN__|__DT_LANG_EMPTY__|__DT_LANG_UNKNOWN__
DT_LANG|1|KO||<undefined>
DT_LANG|2|ZH||<undefined>
DT_LANG|3|JA||<undefined>
DT_LANG_DONE
'''
CANDIDATE = OLD.replace('<undefined>', '__DT_LANG_UNKNOWN__')
TABLE = CANDIDATE + '''
DT_LANG_TABLE|sizes|463|463|463
DT_LANG_TABLE|ko|방독면|부목|라이트 머신건|헤비 머신건
DT_LANG_TABLE|zh|1|0
DT_LANG_TABLE|ja|1|0
DT_LANG_TABLE_DONE
'''


class LanguageProbeTests(unittest.TestCase):
    def test_accepts_expected_cases(self):
        self.assertEqual(check(OLD, CANDIDATE)['cases'], 4)

    def test_table_and_duplicate_key_outcomes(self):
        check_table(TABLE)
        check(OLD, TABLE)
        with self.assertRaisesRegex(ValueError, 'translation'):
            check_table(TABLE.replace('라이트 머신건', '라이트 머신 건'))
        with self.assertRaisesRegex(ValueError, 'translation'):
            check_table(TABLE.replace('DT_LANG_TABLE|zh|1|0', 'DT_LANG_TABLE|zh|1|1'))
        with self.assertRaisesRegex(ValueError, 'complete'):
            check_table(TABLE.replace('DT_LANG_TABLE_DONE', ''))

    def test_fails_missing_duplicate_and_changed_cases(self):
        with self.assertRaisesRegex(ValueError, 'missing language'):
            check(OLD.replace('DT_LANG|2|ZH||<undefined>\n', ''), CANDIDATE)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            check(OLD.replace('DT_LANG_DONE', 'DT_LANG|3|JA||<undefined>\nDT_LANG_DONE'), CANDIDATE)
        with self.assertRaisesRegex(ValueError, 'candidate'):
            check(OLD, CANDIDATE.replace('DT_LANG|1|KO||', 'DT_LANG|1|KO|wrong|'))
        with self.assertRaisesRegex(ValueError, 'collision'):
            check('DT_LANG_ERROR|unexpected\n' + OLD, CANDIDATE)
        with self.assertRaisesRegex(ValueError, 'complete'):
            check(OLD, CANDIDATE.replace('DT_LANG_DONE', ''))


if __name__ == '__main__':
    unittest.main()
