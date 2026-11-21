from pathlib import Path
import shutil
import tempfile
import unittest

try:
    from PIL import Image
    from tools.deadtown_unresolved_sprites import NAMES, best_union_alpha_error, run
    from tools.deadtown_sprite_order_evidence import declared_sprites
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
SOURCE = ROOT / 'deadtown-source'
UNRESOLVED = SOURCE / 'unresolved/sprites'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class UnresolvedTests(unittest.TestCase):
    def test_union_alpha_error_and_scaled_rejected(self):
        im = Image.new('RGBA', (2, 1), (0, 0, 0, 0))
        im.putpixel((1, 0), (0, 0, 0, 255))
        info = {'width': 2, 'height': 1}
        frame = [('unscaled_canvas', im, {})]
        self.assertEqual(best_union_alpha_error(info, b'\x40', frame), 0)
        self.assertEqual(best_union_alpha_error(info, b'\x80', frame), 1)
        with self.assertRaisesRegex(ValueError, 'unscaled'):
            best_union_alpha_error(info, b'\x80', [('scaled', im, {})])
        with self.assertRaisesRegex(ValueError, 'mask length'):
            best_union_alpha_error(info, b'', frame)

    def test_extract_refuses_existing_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'output exists'):
                run('nonexistent.apk', tmp, True)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_four_research_assets_match_pinned_apk_and_are_not_declared(self):
        report = run(APK, UNRESOLVED)
        self.assertEqual(len(report['sprites']), 4)
        self.assertEqual(sum(len(s['frames']) for s in report['sprites']), 12)
        self.assertTrue(set(NAMES).isdisjoint(declared_sprites(SOURCE / 'project')))
        self.assertTrue(all(s['native_mask']['best_union_alpha_threshold_bit_difference'] > 0 for s in report['sprites']))
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'unresolved'
            shutil.copytree(UNRESOLVED, dest)
            path = dest / 'ih_slingshot/mask.bin'
            data = bytearray(path.read_bytes()); data[0] ^= 1; path.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'mask changed'):
                run(APK, dest)


if __name__ == '__main__':
    unittest.main()
