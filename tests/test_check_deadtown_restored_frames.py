import shutil
import struct
import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

try:
    from PIL import Image
    from tools.check_deadtown_restored_frames import (RESTORED, REPLACED, alpha_mask, safe_asset,
                                                       verify, verify_precise_mask_candidate)
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

    def test_alpha_mask_is_msb_first_and_excludes_threshold(self):
        image = Image.new('RGBA', (9, 2), (0, 0, 0, 0))
        image.putpixel((0, 0), (0, 0, 0, 129))
        image.putpixel((7, 0), (0, 0, 0, 128))
        image.putpixel((8, 1), (0, 0, 0, 255))
        self.assertEqual(alpha_mask(image, 128), bytes([0x80, 0, 0, 0x80]))
        with self.assertRaises(ValueError):
            alpha_mask(image, 256)

    def test_precise_mask_candidate_rejects_wrong_setting_and_bits(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'frame.png'
            image = Image.new('RGBA', (9, 1), (0, 0, 0, 0))
            image.putpixel((8, 0), (0, 0, 0, 255))
            image.save(path)
            data = bytearray(70)
            struct.pack_into('<I', data, 64, 1)
            data[68:70] = b'\x00\x80'
            info = {'width': 9, 'height': 1, 'frames': 1}
            root = ET.fromstring('<sprite><colkind>0</colkind><coltolerance>128</coltolerance></sprite>')
            self.assertTrue(verify_precise_mask_candidate(data, 70, 0, info, path, root)['candidate_matches_native_packed_bytes'])
            data[69] = 0
            with self.assertRaisesRegex(ValueError, 'mask differs'):
                verify_precise_mask_candidate(data, 70, 0, info, path, root)
            root.find('colkind').text = '1'
            with self.assertRaisesRegex(ValueError, 'settings'):
                verify_precise_mask_candidate(data, 70, 0, info, path, root)

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
        self.assertEqual(result['sprite_count'], 24)
        self.assertEqual(result['frame_count'], 72)
        self.assertTrue(result['sprites']['spr_defence_house']['candidate_precise_mask']['candidate_matches_native_packed_bytes'])
        self.assertEqual(result['sprites']['spr_item_use']['known_metadata_differences']['bbox_top'],
                         {'apk': 2, 'gmx': 5})
        for name, (start, end) in RESTORED.items():
            self.assertEqual([r['index'] for r in result['sprites'][name]['restored']], list(range(start, end)))
        for name, (_, indices) in REPLACED.items():
            self.assertEqual([r['index'] for r in result['sprites'][name]['restored']], list(indices))
        self.assertEqual(result['sprites']['ih_dagger']['known_metadata_differences']['bbox_left'],
                         {'apk': 11, 'gmx': 9})

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
            shutil.copy2(SOURCE / 'project/sprites/spr_zombie_foot_left.sprite.gmx', desc)
            bbox = dest / 'project/sprites/spr_item_use.sprite.gmx'
            bbox.write_text(bbox.read_text().replace('<bbox_top>5</bbox_top>', '<bbox_top>6</bbox_top>'))
            with self.assertRaisesRegex(ValueError, 'metadata mismatch: spr_item_use'):
                verify(APK, dest)


if __name__ == '__main__':
    unittest.main()
