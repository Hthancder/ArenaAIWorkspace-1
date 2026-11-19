import tempfile
import unittest
from pathlib import Path

try:
    from PIL import Image
    from tools.deadtown_sprite_pixels import compare, compare_frame
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / '.cache/deadtown/deadtown.gmx'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class SpritePixelUnitTests(unittest.TestCase):
    def test_trimmed_frame_and_transparent_rgb(self):
        atlas = Image.new('RGBA', (5, 4), (0, 0, 0, 0))
        atlas.putpixel((2, 1), (10, 20, 30, 255))
        frame = Image.new('RGBA', (4, 4), (0, 0, 0, 0))
        frame.putpixel((1, 2), (10, 20, 30, 255))
        region = (2, 1, 1, 1, 1, 2, 1, 1, 4, 4, 0)
        self.assertEqual(compare_frame(atlas, region, frame), 'exact_rgba')
        frame.putpixel((0, 0), (220, 10, 5, 0))
        self.assertEqual(compare_frame(atlas, region, frame), 'transparent_rgb_only')
        frame.putpixel((1, 2), (11, 20, 30, 255))
        self.assertEqual(compare_frame(atlas, region, frame), 'visible_rgba_differs')
        frame.putpixel((1, 2), (10, 20, 30, 254))
        self.assertEqual(compare_frame(atlas, region, frame), 'visible_rgba_differs')

    def test_uncompared_and_invalid_regions(self):
        atlas = Image.new('RGBA', (5, 4))
        frame = Image.new('RGBA', (4, 4))
        region = (2, 1, 1, 1, 1, 2, 1, 1, 4, 4, 0)
        self.assertEqual(compare_frame(atlas, region, Image.new('RGBA', (3, 4))), 'dimension_mismatch')
        self.assertEqual(compare_frame(atlas, (2, 1, 1, 1, 1, 2, 2, 1, 4, 4, 0), frame), 'scaled_not_compared')
        with self.assertRaisesRegex(ValueError, 'outside'):
            compare_frame(atlas, (5, 1, 1, 1, 1, 2, 1, 1, 4, 4, 0), frame)
        with self.assertRaisesRegex(ValueError, 'empty'):
            compare_frame(atlas, (2, 1, 0, 1, 1, 2, 1, 1, 4, 4, 0), frame)

    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                compare(path, tmp)


@unittest.skipUnless(HAS_PILLOW and APK.is_file() and (PROJECT / 'deadtown.project.gmx').is_file(),
                     'requires Pillow and pinned inputs')
class SpritePixelIntegrationTests(unittest.TestCase):
    def test_pinned_atlases_and_shared_frames(self):
        report = compare(APK, PROJECT)
        self.assertEqual((report['atlas_count'], report['shared_sprites']), (6, 291))
        self.assertEqual(report['frame_counts'], {'dimension_mismatch': 3, 'exact_rgba': 221,
                         'transparent_rgb_only': 517, 'visible_rgba_differs': 5})
        self.assertEqual((report['apk_extra_frames'], report['gmx_extra_frames']), (63, 0))
        self.assertEqual(report['sprites']['spr_player']['frames'], ['exact_rgba'] * 4)
        self.assertEqual(report['sprites']['spr_item_use']['apk_extra_frames'], 2)
        self.assertEqual(report['sprites']['spr_ui_day']['frames'], ['visible_rgba_differs'])
        self.assertIn('runtime equivalence', report['limitations'])


if __name__ == '__main__':
    unittest.main()
