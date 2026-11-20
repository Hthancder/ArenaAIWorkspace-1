import tempfile
import unittest
from pathlib import Path

try:
    import PIL  # noqa: F401
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

if HAS_PIL:
    from tools.deadtown_test3_graphics_evidence import compare, room_background_defaults

ROOT = Path(__file__).resolve().parents[1]
IPA = ROOT / 'DeadTown-iOS15-RE-test3.ipa'
APK = ROOT / '.cache/ios-original/android-original.apk'


@unittest.skipUnless(HAS_PIL, 'requires Pillow')
class Test3GraphicsEvidenceTests(unittest.TestCase):
    def test_rejects_wrong_files_and_room_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / 'bad'
            bad.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                compare(bad, bad)
        with self.assertRaises(ValueError):
            room_background_defaults(b'bad')

    @unittest.skipUnless(IPA.is_file() and APK.is_file(), 'requires pinned test3 IPA and APK')
    def test_static_comparison(self):
        result = compare(IPA, APK)
        self.assertEqual(result['resource_names']['SPRT'],
                         {'apk_count': 402, 'test_count': 402, 'names_same_order': True})
        self.assertEqual(result['sprite']['shared'], 402)
        self.assertEqual(result['sprite']['metadata_differ'], [])
        self.assertEqual(result['sprite']['texture_page_entries_differ'], [])
        self.assertEqual(result['sprite']['mask_differ'], [])
        self.assertEqual(result['texture_png'], {'apk_count': 6, 'test_count': 6,
                                                 'all_identical_in_order': True})
        self.assertEqual(result['apk_room_background_defaults'], result['test_room_background_defaults'])
        for room in ('rom_play', 'rom_play_sewer', 'rom_play_defence'):
            self.assertTrue(result['test_room_background_defaults'][room]['show_color'])
        self.assertIn('test builds 1, 2 and 3', result['limitations'])


if __name__ == '__main__':
    unittest.main()
