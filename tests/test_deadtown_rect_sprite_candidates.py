import json
from pathlib import Path
import shutil
import tempfile
import unittest

try:
    from PIL import Image
    from tools.deadtown_rect_sprite_candidates import CATALOGUE, descriptor, extract, qualifies, verify
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
SOURCE = ROOT / 'deadtown-source'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class RectCandidateTests(unittest.TestCase):
    def test_rectangle_and_alpha_bounds_must_agree(self):
        info = {'width': 3, 'height': 2, 'bbox_left': 0, 'bbox_right': 2, 'bbox_top': 0,
                'bbox_bottom': 1, 'separate_masks': 0}
        im = Image.new('RGBA', (3, 2), (0, 0, 0, 255))
        frames = [('unscaled_canvas', im, {})]
        self.assertTrue(qualifies(info, [b'\xe0\xe0'], frames))
        self.assertFalse(qualifies(info, [b'\xe1\xe0'], frames))  # padding bit
        self.assertFalse(qualifies(info, [b'\xc0\xe0'], frames))  # irregular
        self.assertFalse(qualifies(info, [b'\xe0\xe0'], [('scaled', im, {})]))
        im.putpixel((2, 0), (0, 0, 0, 0)); im.putpixel((2, 1), (0, 0, 0, 0))
        self.assertFalse(qualifies(info, [b'\xe0\xe0'], frames))
        self.assertFalse(qualifies({**info, 'separate_masks': 1}, [b'\xe0\xe0'], frames * 2))

    def test_existing_output_and_bad_manifest_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, 'exists'):
                extract('missing.apk', 'missing-project', root)
            for bad in ({'format': 1, 'names': ['../oops']}, {'format': 1, 'names': ['x', 'x']},
                        {'format': 1, 'names': [[]]}, {'format': 2, 'names': ['x']}):
                (root / CATALOGUE).write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    verify('missing.apk', root)


@unittest.skipUnless(HAS_PILLOW and APK.is_file(), 'requires Pillow and pinned APK')
class RectCandidateIntegrationTests(unittest.TestCase):
    def test_pinned_candidates(self):
        report = verify(APK, SOURCE)
        self.assertEqual((report['sprite_count'], report['frame_count']), (105, 206))

    def test_tampered_descriptor_or_image_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'source'
            shutil.copytree(SOURCE, dest)
            desc = dest / 'project/sprites/spr_lobby_ach.sprite.gmx'
            original = desc.read_text()
            desc.write_text(original.replace('<colkind>1</colkind>', '<colkind>0</colkind>'))
            with self.assertRaisesRegex(ValueError, 'collision settings'):
                verify(APK, dest)
            desc.write_text(original)
            path = dest / 'assets/sprites/images/spr_lobby_ach_0.png'
            with Image.open(path) as img:
                image = img.convert('RGBA')
            image.putpixel((0, 0), (255, 0, 0, 255))
            image.save(path)
            with self.assertRaisesRegex(ValueError, 'frame differs'):
                verify(APK, dest)


if __name__ == '__main__':
    unittest.main()
