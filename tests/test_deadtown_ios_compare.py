import tempfile
import unittest
from pathlib import Path

try:
    import PIL  # noqa: F401
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

if HAS_PIL:
    from tools.deadtown_ios_compare import compare, ogg_without_serial_and_crc

ROOT = Path(__file__).resolve().parents[1]
IPA = ROOT / '.cache/ios-original/Dead Town-1.4.2.ipa'
APK = ROOT / '.cache/ios-original/android-original.apk'


def page(body=b'abc', serial=b'abcd', crc=b'efgh'):
    return (b'OggS\0' + b'\0' + bytes(8) + serial + bytes(4) + crc + b'\x01' +
            bytes([len(body)]) + body)


@unittest.skipUnless(HAS_PIL, 'requires Pillow')
class IosCompareTests(unittest.TestCase):
    def test_ogg_normalization_only_changes_serial_and_crc(self):
        left = page() + page(b'xyz')
        right = page(serial=b'1234', crc=b'5678') + page(b'xyz', b'1234', b'5678')
        self.assertNotEqual(left, right)
        self.assertEqual(ogg_without_serial_and_crc(left), ogg_without_serial_and_crc(right))
        self.assertNotEqual(ogg_without_serial_and_crc(left), ogg_without_serial_and_crc(page(b'abz') + page(b'xyz')))
        for bad in (b'', b'OggS\0', page()[:-1], page() + b'x'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                ogg_without_serial_and_crc(bad)

    def test_rejects_wrong_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'x'
            path.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                compare(path, path)

    @unittest.skipUnless(IPA.is_file() and APK.is_file(), 'requires pinned iOS IPA and Android APK')
    def test_pinned_asset_comparison(self):
        data = compare(IPA, APK)
        for kind, count in [('SOND', 90), ('SPRT', 402), ('BGND', 30), ('SCPT', 192),
                            ('FONT', 1), ('OBJT', 240), ('ROOM', 15)]:
            entry = data['resources'][kind]
            self.assertEqual((entry['android_count'], entry['ios_count']), (count, count))
            self.assertTrue(entry['same_ordered_names'])
        self.assertEqual(data['sprites']['metadata_differ'], [])
        self.assertEqual(data['sprites']['packed_masks_differ'], [])
        self.assertEqual(len(data['sprites']['page_entries_differ']), 17)
        self.assertEqual(data['texture_png']['byte_identical_same_index'], [0, 1, 2])
        self.assertEqual(data['texture_png']['different_same_index'], [3, 4, 5])
        self.assertEqual(data['sprite_pixels']['frame_counts'],
                         {'android_scaled_not_compared': 1, 'exact_rgba': 1028})
        self.assertEqual(data['sprite_pixels']['exceptional_frames'][0]['sprite'], 'mask_noone')
        self.assertEqual(data['sounds']['byte_identical'], 3)
        self.assertEqual(data['sounds']['equal_after_ogg_serial_crc_zeroed'], 90)
        self.assertEqual(data['sounds']['format_counts'], {'ogg': 87, 'wav': 3})
        self.assertIn('not prove native code', data['limitations'])


if __name__ == '__main__':
    unittest.main()
