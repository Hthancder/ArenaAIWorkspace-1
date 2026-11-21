from pathlib import Path
import tempfile
import unittest

try:
    from PIL import Image
    from tools.check_deadtown_bbox_candidates import alpha_bounds, verify
    from tools.materialize_deadtown_source import materialize
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
UPSTREAM = ROOT / '.cache/gmx/deadtown.gmx'
SOURCE = ROOT / 'deadtown-source'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class BoundsTests(unittest.TestCase):
    def test_union_alpha_bounds_inclusive(self):
        one = Image.new('RGBA', (4, 3))
        two = one.copy()
        one.putpixel((3, 1), (0, 0, 0, 1))
        two.putpixel((1, 2), (0, 0, 0, 255))
        self.assertEqual(alpha_bounds([one, two]), [1, 3, 1, 2])
        self.assertIsNone(alpha_bounds([Image.new('RGBA', (2, 2))]))
        with self.assertRaisesRegex(ValueError, 'no frames'):
            alpha_bounds([])
        with self.assertRaisesRegex(ValueError, 'size mismatch'):
            alpha_bounds([one, Image.new('RGBA', (1, 1))])

    @unittest.skipUnless(APK.is_file() and UPSTREAM.is_dir(), 'requires pinned APK and GMX')
    def test_materialized_candidates_and_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = Path(tmp) / 'workspace'
            materialize(UPSTREAM, APK, SOURCE, result)
            project = result / 'project'
            r = verify(APK, project)
            self.assertEqual(len(r['sprites']), 12)
            self.assertEqual(sum(x['frames_checked'] for x in r['sprites'].values()), 93)
            self.assertEqual(r['sprites']['ih_dagger']['bbox'], [11, 45, 11, 19])
            self.assertEqual(r['sprites']['mask_arrow']['native_mask']['shape'], 'full_canvas')
            self.assertEqual(r['sprites']['spr_item_use']['native_mask']['shape'], 'irregular')
            path = project / 'sprites/images/ih_dagger_0.png'
            with Image.open(path) as f:
                image = f.convert('RGBA')
            pixel = image.getpixel((0, 0))
            image.putpixel((0, 0), (*pixel[:3], pixel[3] ^ 255))
            image.save(path)
            with self.assertRaisesRegex(ValueError, 'frame alpha differs'):
                verify(APK, project)
            image.putpixel((0, 0), pixel)
            image.save(path)
            desc = project / 'sprites/mask_arrow.sprite.gmx'
            desc.write_text(desc.read_text().replace('<bboxmode>1</bboxmode>', '<bboxmode>0</bboxmode>'))
            # Verification sees metadata mismatch even without opening frames.
            with self.assertRaisesRegex(ValueError, 'metadata mismatch: mask_arrow'):
                verify(APK, project)


if __name__ == '__main__':
    unittest.main()
