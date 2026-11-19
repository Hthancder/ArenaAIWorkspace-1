import struct
import tempfile
import unittest
from pathlib import Path

from tools.deadtown_sprite_metadata import compare, native_sprites, source_sprites

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / '.cache/deadtown/deadtown.gmx'


def synthetic_sprite():
    data = bytearray(b'FORM\0\0\0\0')
    def chunk(name, payload):
        data.extend(name + struct.pack('<I', len(payload)))
        start = len(data)
        data.extend(payload)
        return start
    gen = chunk(b'GEN8', b'\0\x0f')
    tpag = chunk(b'TPAG', b'\0' * (8 + 22))
    sprite = chunk(b'SPRT', b'\0' * (8 + 60 + 4 + 4))
    strings = chunk(b'STRG', struct.pack('<I', 3) + b'abc\0')
    struct.pack_into('<II', data, tpag, 1, tpag + 8)
    struct.pack_into('<II', data, sprite, 1, sprite + 8)
    struct.pack_into('<IIIiiiiIIIIIiiI', data, sprite + 8, strings + 4, 12, 8,
                     1, 10, 7, 0, 0, 0, 0, 1, 1, -2, 3, 1)
    struct.pack_into('<I', data, sprite + 8 + 60, tpag + 8)
    struct.pack_into('<I', data, 4, len(data) - 8)
    return data, gen, sprite


class SpriteMetadataUnitTests(unittest.TestCase):
    def test_sprite_header_and_pointer_validation(self):
        data, gen, sprite = synthetic_sprite()
        record = native_sprites(bytes(data))['abc']
        self.assertEqual((record['width'], record['height'], record['origin_x'], record['origin_y']),
                         (12, 8, -2, 3))
        self.assertEqual((record['bbox_top'], record['bbox_bottom'], record['frames']), (0, 7, 1))
        bad = bytearray(data)
        struct.pack_into('<I', bad, sprite + 8 + 60, 0)
        with self.assertRaisesRegex(ValueError, 'outside TPAG'):
            native_sprites(bytes(bad))
        bad = bytearray(data)
        struct.pack_into('<I', bad, sprite + 8 + 56, 0xffffffff)
        with self.assertRaisesRegex(ValueError, 'frame count'):
            native_sprites(bytes(bad))
        bad = bytearray(data)
        bad[gen + 1] = 16
        with self.assertRaisesRegex(ValueError, 'version'):
            native_sprites(bytes(bad))

    def test_source_flags_and_bad_frame_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / 'sprites').mkdir()
            (project / 'deadtown.project.gmx').write_text('<assets><sprites><sprite>sprites\\s</sprite></sprites></assets>')
            path = project / 'sprites/s.sprite.gmx'
            xml = ('<sprite><width>10</width><height>9</height><xorig>1</xorig><yorigin>2</yorigin>'
                   '<bbox_left>0</bbox_left><bbox_right>9</bbox_right><bbox_top>0</bbox_top>'
                   '<bbox_bottom>8</bbox_bottom><bboxmode>0</bboxmode><sepmasks>-1</sepmasks>'
                   '<frames><frame index="0">x.png</frame></frames></sprite>')
            path.write_text(xml)
            self.assertEqual(source_sprites(project)['s']['separate_masks'], 1)
            path.write_text(xml.replace('index="0"', 'index="1"'))
            with self.assertRaisesRegex(ValueError, 'noncontiguous'):
                source_sprites(project)

    def test_wrong_apk_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / 'bad.apk'
            apk.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                compare(apk, tmp)


@unittest.skipUnless(APK.is_file() and (PROJECT / 'deadtown.project.gmx').is_file(),
                     'requires pinned APK and source')
class SpriteMetadataIntegrationTests(unittest.TestCase):
    def test_pinned_sprite_comparison(self):
        report = compare(APK, PROJECT)
        self.assertEqual((report['apk_sprites'], report['gmx_sprites'], report['matched_names']), (402, 291, 291))
        self.assertEqual((report['matching_metadata'], report['differing_metadata']), (267, 24))
        self.assertEqual(len(report['apk_only']), 111)
        self.assertEqual(report['differences']['spr_item_use']['frames'], {'apk': 22, 'gmx': 20})
        self.assertEqual(report['differences']['spr_setting_cradits']['width'], {'apk': 107, 'gmx': 247})
        self.assertEqual(report['differences']['spr_ui_buff']['frames'], {'apk': 7, 'gmx': 6})
        self.assertIn('not decoded image pixels', report['limitations'])


if __name__ == '__main__':
    unittest.main()
