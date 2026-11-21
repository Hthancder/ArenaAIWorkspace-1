from pathlib import Path
import shutil
import tempfile
import unittest

try:
    from PIL import Image
    from tools.check_deadtown_empty_mask import require_zero_image, verify
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
SOURCE = ROOT / 'deadtown-source'


@unittest.skipUnless(HAS_PIL, 'requires Pillow')
class EmptyMaskTests(unittest.TestCase):
    def test_nonzero_or_wrong_sized_input_fails(self):
        img = Image.new('RGBA', (32, 32))
        require_zero_image(img)
        img.putpixel((5, 1), (0, 0, 1, 0))
        with self.assertRaisesRegex(ValueError, 'zero RGBA'):
            require_zero_image(img)
        with self.assertRaisesRegex(ValueError, '32x32'):
            require_zero_image(Image.new('RGBA', (1, 1)))

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_pinned_and_tampered(self):
        r = verify(APK, SOURCE)
        self.assertTrue(r['native_mask_all_zero'])
        self.assertEqual(r['native_target_size'], [1, 1])
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'source'
            shutil.copytree(SOURCE, dest)
            path = dest / 'assets/sprites/images/mask_noone_0.png'
            image = Image.new('RGBA', (32, 32), (1, 0, 0, 0))
            image.save(path)
            with self.assertRaisesRegex(ValueError, 'zero RGBA'):
                verify(APK, dest)


if __name__ == '__main__':
    unittest.main()
