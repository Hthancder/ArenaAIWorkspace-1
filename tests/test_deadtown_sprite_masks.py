import tempfile
import unittest
from pathlib import Path

from tools.deadtown_sprite_masks import inspect, summarize_mask

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'


class SpriteMasksUnitTests(unittest.TestCase):
    def test_msb_order_stride_bounds_and_padding(self):
        mask = summarize_mask(bytes([0x80, 0x81, 0x40, 0x00]), 9, 2)
        self.assertEqual(mask['set_pixels'], 3)
        self.assertEqual(mask['bounds'], [0, 8, 0, 1])
        self.assertEqual(mask['shape'], 'irregular')
        self.assertEqual(mask['row_padding_set_bits'], 1)

    def test_empty_full_and_rectangle(self):
        self.assertEqual(summarize_mask(b'\0\0', 8, 2)['shape'], 'empty')
        self.assertEqual(summarize_mask(b'\xff\xff', 8, 2)['shape'], 'full_canvas')
        mask = summarize_mask(bytes([0x38, 0x38]), 8, 2)
        self.assertEqual((mask['shape'], mask['bounds'], mask['set_pixels']), ('rectangular', [2, 4, 0, 1], 6))
        with self.assertRaisesRegex(ValueError, 'byte length'):
            summarize_mask(b'\0', 8, 2)
        with self.assertRaisesRegex(ValueError, 'dimensions'):
            summarize_mask(b'', 0, 2)

    def test_wrong_apk_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / 'bad.apk'
            apk.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(apk)


@unittest.skipUnless(APK.is_file(), 'requires pinned original APK')
class SpriteMasksIntegrationTests(unittest.TestCase):
    def test_pinned_mask_summary(self):
        report = inspect(APK)
        self.assertEqual((report['sprite_count'], report['mask_count']), (402, 402))
        self.assertEqual(report['shape_counts'], {'empty': 1, 'full_canvas': 62, 'irregular': 37, 'rectangular': 302})
        self.assertEqual(report['bbox_counts'], {'differs': 3, 'empty': 1, 'matches': 398})
        self.assertEqual(sum(m['row_padding_set_bits'] for s in report['sprites'] for m in s['masks']), 0)
        sprites = {item['name']: item for item in report['sprites']}
        self.assertEqual((sprites['mask_player']['masks'][0]['set_pixels'], sprites['mask_player']['raw_bbox']),
                         (225, [0, 14, 0, 14]))
        self.assertEqual(sprites['mask_noone']['masks'][0]['shape'], 'empty')
        self.assertEqual({s['name'] for s in report['sprites'] if s['masks'][0]['matches_sprite_bbox'] is False},
                         {'mask_zombie', 'mask_boss3', 'mask_boss4'})
        self.assertIn('not verified against Android', report['limitations'])


if __name__ == '__main__':
    unittest.main()
