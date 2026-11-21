import shutil
import tempfile
import unittest
from pathlib import Path

try:
    from PIL import Image
    from tools.check_deadtown_restored_frames import RESTORED, safe_asset, verify
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
SOURCE = ROOT / 'deadtown-source'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class RestoredFrameUnitTests(unittest.TestCase):
    def test_safe_path_rejects_symlinks_and_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'actual').write_bytes(b'x')
            (root / 'link').symlink_to(root / 'actual')
            with self.assertRaisesRegex(ValueError, 'symlink'):
                safe_asset(root, Path('link'))
            with self.assertRaisesRegex(ValueError, 'missing'):
                safe_asset(root, Path('missing'))

    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.apk'
            path.write_bytes(b'not the APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                verify(path, SOURCE)


@unittest.skipUnless(HAS_PILLOW and APK.is_file(), 'requires Pillow and pinned APK')
class RestoredFrameIntegrationTests(unittest.TestCase):
    def test_pinned_frames_and_metadata(self):
        result = verify(APK, SOURCE)
        self.assertEqual(result['sprite_count'], 9)
        self.assertEqual(result['frame_count'], 47)
        for name, (start, end) in RESTORED.items():
            self.assertEqual([r['index'] for r in result['sprites'][name]['restored']], list(range(start, end)))

    def test_tampered_image_and_descriptor_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'source'
            shutil.copytree(SOURCE, dest)
            path = dest / 'assets/sprites/images/spr_zombie_foot_left_1.png'
            with Image.open(path) as im:
                image = im.convert('RGBA')
            original = image.getpixel((0, 0))
            image.putpixel((0, 0), (original[0] ^ 255, original[1], original[2], 255))
            image.save(path)
            with self.assertRaisesRegex(ValueError, 'frame differs'):
                verify(APK, dest)
            shutil.copy2(SOURCE / 'assets/sprites/images/spr_zombie_foot_left_1.png', path)
            desc = dest / 'project/sprites/spr_zombie_foot_left.sprite.gmx'
            desc.write_text(desc.read_text().replace('spr_zombie_foot_left_1.png', 'incorrect.png'))
            with self.assertRaisesRegex(ValueError, 'unexpected frame reference'):
                verify(APK, dest)


if __name__ == '__main__':
    unittest.main()
