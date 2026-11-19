import unittest
from tools.check_deadtown_language_probe import check

OLD = '''
DT_LANG|0|__DT_LANG_KNOWN__|__DT_LANG_EMPTY__|__DT_LANG_UNKNOWN__
DT_LANG|1|KO||<undefined>
DT_LANG|2|ZH||<undefined>
DT_LANG|3|JA||<undefined>
DT_LANG_DONE
'''
CANDIDATE = OLD.replace('<undefined>', '__DT_LANG_UNKNOWN__')


class LanguageProbeTests(unittest.TestCase):
    def test_accepts_expected_cases(self):
        self.assertEqual(check(OLD, CANDIDATE)['cases'], 4)

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
