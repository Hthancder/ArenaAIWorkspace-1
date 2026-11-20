import unittest
from tools.check_deadtown_lang_maps import expected_maps, parse_gmrm


def s(value):
    encoded = value.encode('utf-8')
    return b's' + str(len(encoded)).encode() + b':' + encoded


def row(*values):
    return {'arguments': [{'type': 'string', 'value': value} for value in values]}


class LanguageMapTests(unittest.TestCase):
    def test_utf8_byte_lengths_and_empty_values(self):
        data = b'GMRM2;' + s('Gas mask') + s('방독면') + s('empty') + s('')
        self.assertEqual(parse_gmrm(data), {'Gas mask': '방독면', 'empty': ''})

    def test_rejects_corrupt_or_ambiguous_data(self):
        for data in (b'bad', b'GMRM1;' + s('key'), b'GMRM1;s2:a',
                     b'GMRM2;' + s('x') + s('1') + s('x') + s('2'),
                     b'GMRM0;extra', b'GMRM10001;', b'GMRM1;r2;s0:'):
            with self.subTest(data=data), self.assertRaises(ValueError):
                parse_gmrm(data)
        with self.assertRaises(UnicodeError):
            parse_gmrm(b'GMRM1;s1:\xffs0:')

    def test_duplicate_keys_keep_first_vm_value(self):
        data = [row('key', 'first', '', ''), row('key', 'second', '', ''),
                row('other', '한글', '', '')]
        ko, zh, ja = expected_maps(data)
        self.assertEqual(ko, {'key': 'first', 'other': '한글'})
        self.assertEqual(zh, {'key': '', 'other': ''})
        self.assertEqual(ja, zh)
        with self.assertRaisesRegex(ValueError, 'unexpected candidate'):
            expected_maps([row('missing')])


if __name__ == '__main__':
    unittest.main()
