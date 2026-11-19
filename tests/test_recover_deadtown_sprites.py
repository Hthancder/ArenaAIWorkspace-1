import io
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import zipfile

try:
    from PIL import Image
    from tools.recover_deadtown_sprites import extract, frame_image, verify
    from tools.recover_deadtown_audio import chunks, pointers, read_zip_member, u32
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class SpriteRecoveryUnitTests(unittest.TestCase):
    def test_canvas_and_scaled_region_are_distinct(self):
        atlas = Image.new('RGBA', (6, 6), (0, 0, 0, 0))
        atlas.putpixel((3, 1), (21, 32, 43, 128))
        region = (2, 1, 2, 1, 1, 2, 2, 1, 4, 4, 0)
        mode, image = frame_image(atlas, region, (4, 4))
        self.assertEqual((mode, image.size, image.getpixel((2, 2))),
                         ('unscaled_canvas', (4, 4), (21, 32, 43, 128)))
        self.assertEqual(image.getpixel((0, 0)), (0, 0, 0, 0))
        mode, image = frame_image(atlas, (2, 1, 2, 1, 1, 2, 1, 1, 4, 4, 0), (4, 4))
        self.assertEqual((mode, image.size, image.getpixel((1, 0))),
                         ('atlas_region_only_scaled_target', (2, 1), (21, 32, 43, 128)))
        with self.assertRaisesRegex(ValueError, 'bounds differ'):
            frame_image(atlas, region, (3, 4))
        with self.assertRaisesRegex(ValueError, 'outside'):
            frame_image(atlas, (5, 1, 2, 1, 1, 2, 2, 1, 4, 4, 0), (4, 4))

    def test_rejects_existing_output_and_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root / 'existing'
            original.mkdir()
            (original / 'keep').write_text('untouched')
            with self.assertRaisesRegex(ValueError, 'already exists'):
                extract(root / 'bad.apk', original)
            self.assertEqual((original / 'keep').read_text(), 'untouched')
            apk = root / 'bad.apk'
            apk.write_bytes(b'bad')
            out = root / 'out'
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                extract(apk, out)
            self.assertFalse(out.exists())

    def test_failed_extraction_cleans_only_new_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'out'
            with patch('tools.recover_deadtown_sprites.open_apk', return_value=(None, None, None, None)), \
                 patch('tools.recover_deadtown_sprites.iter_sprites', side_effect=ValueError('bad layout')):
                with self.assertRaisesRegex(ValueError, 'bad layout'):
                    extract('ignored', out)
            self.assertFalse(out.exists())


@unittest.skipUnless(HAS_PILLOW and APK.is_file(), 'requires Pillow and pinned APK')
class SpriteRecoveryIntegrationTests(unittest.TestCase):
    def test_export_verify_and_detect_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'export'
            result = extract(APK, out)
            self.assertEqual(len(result['sprites']), 402)
            self.assertEqual(sum(len(s['frames']) for s in result['sprites']), 1029)
            self.assertEqual(sum(len(s['masks']) for s in result['sprites']), 402)
            scaled = [(s['name'], f) for s in result['sprites'] for f in s['frames'] if f['mode'] != 'unscaled_canvas']
            self.assertEqual(len(scaled), 1)
            self.assertEqual((scaled[0][0], scaled[0][1]['mode'], scaled[0][1]['width'], scaled[0][1]['height']),
                             ('mask_noone', 'atlas_region_only_scaled_target', 32, 32))
            self.assertEqual(verify(APK, out), result)
            first = result['sprites'][0]
            with zipfile.ZipFile(APK) as archive:
                data = read_zip_member(archive, 'assets/game.droid')
            regions = chunks(data)
            pos = pointers(data, regions[b'SPRT'])[0]
            width, height = struct.unpack_from('<II', data, pos + 4)
            count = u32(data, pos + 56)
            start = pos + 64 + count * 4
            raw_mask = data[start:start + ((width + 7) // 8) * height]
            self.assertEqual((out / first['masks'][0]['file']).read_bytes(), raw_mask)
            # Independently compare the exported pixels within the declared
            # trimmed rectangle to the original decoded atlas rectangle.
            page = first['frames'][0]['atlas_region']
            tex_entry = pointers(data, regions[b'TXTR'])[page['atlas_index']]
            tex_ptr = u32(data, tex_entry + 4)
            atlas = Image.open(io.BytesIO(data[tex_ptr:regions[b'TXTR'][1]])).convert('RGBA')
            image = Image.open(out / first['frames'][0]['file']).convert('RGBA')
            sx, sy, tx, ty = (page[k] for k in ('source_x', 'source_y', 'target_x', 'target_y'))
            w, h = page['source_width'], page['source_height']
            self.assertEqual(atlas.crop((sx, sy, sx + w, sy + h)).tobytes(),
                             image.crop((tx, ty, tx + w, ty + h)).tobytes())
            mask = out / first['masks'][0]['file']
            original = mask.read_bytes()
            mask.write_bytes(b'altered')
            with self.assertRaisesRegex(ValueError, 'mask does not match'):
                verify(APK, out)
            mask.write_bytes(original)
            png = out / first['frames'][0]['file']
            png_bytes = png.read_bytes()
            with Image.open(png) as im:
                changed = im.convert('RGBA')
            changed.putpixel((0, 0), (1, 2, 3, 4))
            changed.save(png)
            with self.assertRaisesRegex(ValueError, 'frame does not match'):
                verify(APK, out)
            png.write_bytes(png_bytes)
            manifest = out / 'manifest.json'
            changed_manifest = json.loads(manifest.read_text())
            changed_manifest['sprites'][0]['id'] = 99
            manifest.write_text(json.dumps(changed_manifest))
            with self.assertRaisesRegex(ValueError, 'manifest does not match'):
                verify(APK, out)
            manifest.write_text(json.dumps(result))
            png.unlink()
            target = Path(tmp) / 'frame.png'
            target.write_bytes(png_bytes)
            png.symlink_to(target)
            with self.assertRaisesRegex(ValueError, 'symlinked export path'):
                verify(APK, out)


if __name__ == '__main__':
    unittest.main()
