from pathlib import Path
import shutil
import tempfile
import unittest

try:
    from PIL import Image
    from tools.recover_deadtown_font import collapse_ranges, extract, verify
    from tools.materialize_deadtown_source import materialize
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
UPSTREAM = ROOT / '.cache/gmx/deadtown.gmx'
SOURCE = ROOT / 'deadtown-source'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class FontTests(unittest.TestCase):
    def test_ranges_collapse_and_validation(self):
        self.assertEqual(collapse_ranges([4, 1, 3, 9, 2]), [[1, 4], [9, 9]])
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            collapse_ranges([1, 2, 2])
        with self.assertRaisesRegex(ValueError, 'codepoint'):
            collapse_ranges([65536])

    @unittest.skipUnless(APK.is_file() and UPSTREAM.is_dir(), 'requires pinned APK and legacy GMX')
    def test_extract_verify_materialize_and_tampering(self):
        result = verify(APK, SOURCE)
        self.assertEqual((result['glyph_count'], result['range_count']), (2499, 1615))
        self.assertEqual(result['atlas_rgba_sha256'], '6dd099d5bae4d540fe553890965f3f245927200718e0d0894bbf78cd795ee733')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            generated = root / 'generated'
            info = extract(APK, UPSTREAM / 'fonts', generated)
            self.assertEqual((info['legacy_count'], info['native_count']), (490, 2499))
            self.assertEqual((generated / 'font_24.font.gmx').read_bytes(),
                             (SOURCE / 'project/fonts/font_24.font.gmx').read_bytes())
            with self.assertRaisesRegex(ValueError, 'output exists'):
                extract(APK, UPSTREAM / 'fonts', generated)
            result_root = root / 'work'
            status = materialize(UPSTREAM, APK, SOURCE, result_root)
            self.assertEqual(status['resource_reference_counts']['font_data'], 1)
            self.assertFalse(status['missing_referenced_files'])
            project = result_root / 'project'
            self.assertEqual((project / 'fonts/font_24.png').read_bytes(),
                             (SOURCE / 'assets/fonts/font_24.png').read_bytes())
            # Minimal copied source allows checking corruption without modifying source.
            shadow = root / 'shadow'
            (shadow / 'project/fonts').mkdir(parents=True)
            (shadow / 'assets/fonts').mkdir(parents=True)
            (shadow / 'project/deadtown.project.gmx').write_text('<assets><fonts><font>fonts\\font_24</font></fonts></assets>')
            desc = shadow / 'project/fonts/font_24.font.gmx'
            png = shadow / 'assets/fonts/font_24.png'
            shutil.copy2(SOURCE / 'project/fonts/font_24.font.gmx', desc)
            shutil.copy2(SOURCE / 'assets/fonts/font_24.png', png)
            original = desc.read_text()
            desc.write_text(original.replace('character="32" x="121"', 'character="32" x="122"', 1))
            with self.assertRaisesRegex(ValueError, 'glyph records'):
                verify(APK, shadow)
            desc.write_text(original)
            with Image.open(png) as f:
                image = f.convert('RGBA')
            px = image.getpixel((0, 0))
            image.putpixel((0, 0), (px[0] ^ 255, *px[1:]))
            image.save(png)
            with self.assertRaisesRegex(ValueError, 'atlas differs'):
                verify(APK, shadow)


if __name__ == '__main__':
    unittest.main()
