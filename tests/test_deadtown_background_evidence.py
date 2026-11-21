from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

try:
    from PIL import Image
    from tools.deadtown_background_evidence import compare
    from tools.materialize_deadtown_source import materialize
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
UPSTREAM = ROOT / '.cache/gmx/deadtown.gmx'
SOURCE = ROOT / 'deadtown-source'


@unittest.skipUnless(HAS_PILLOW, 'requires Pillow')
class BackgroundEvidenceTests(unittest.TestCase):
    def test_candidate_descriptor_settings_are_explicit(self):
        root = ET.parse(SOURCE / 'project/background/tile_sewer.background.gmx').getroot()
        for field, value in {'width': '130', 'height': '130', 'data': 'images\\tile_sewer.png',
                             'istileset': '-1', 'tilewidth': '128', 'tileheight': '128',
                             'tilexoff': '0', 'tileyoff': '0', 'tilehsep': '0', 'tilevsep': '0'}.items():
            self.assertEqual(root.findtext(field), value)

    @unittest.skipUnless(APK.is_file() and UPSTREAM.is_dir(), 'requires pinned APK and GMX')
    def test_all_backgrounds_and_candidate_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'work'
            materialize(UPSTREAM, APK, SOURCE, out)
            project = out / 'project'
            report = compare(APK, project)
            self.assertEqual((report['native_count'], report['declared_count'], report['shared_count']), (30, 30, 30))
            self.assertEqual(report['pixel_counts'], {'exact_rgba': 30})
            self.assertEqual(report['native_only'], [])
            self.assertEqual(report['xml_order_inversions'], 29)
            tile = report['backgrounds']['tile_sewer']
            self.assertEqual((tile['native_index'], tile['xml_index'], tile['native_size']), (0, 29, [130, 130]))
            self.assertEqual(tile['atlas_region'], [1092, 1384, 130, 130, 0, 0, 130, 130, 130, 130, 4])
            path = project / 'background/images/tile_sewer.png'
            with Image.open(path) as img:
                image = img.convert('RGBA')
            pixel = image.getpixel((0, 0))
            image.putpixel((0, 0), (pixel[0] ^ 255, *pixel[1:]))
            image.save(path)
            changed = compare(APK, project)
            self.assertEqual(changed['backgrounds']['tile_sewer']['pixels'], 'visible_rgba_differs')
            desc = project / 'background/tile_sewer.background.gmx'
            desc.write_text(desc.read_text().replace('images\\tile_sewer.png', '../outside.png'))
            with self.assertRaisesRegex(ValueError, 'unexpected background path'):
                compare(APK, project)


if __name__ == '__main__':
    unittest.main()
