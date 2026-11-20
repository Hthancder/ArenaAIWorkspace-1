import tempfile
import unittest
from pathlib import Path
try:
    from PIL import Image
    from tools.check_deadtown_motion_probe import parse, compare, FRAMES
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


def log(moving=False):
    rows = []
    for tick in range(1, 31):
        key = int(moving and 8 <= tick <= 20)
        x = min(max(tick - 7, 0), 13) * 3 if moving else 0
        vals = [tick, x, 0, max(0, x - 3), 0, 1, 0, 0, 1120, 630, 1120, 630, 0, 1120, 630, key, 1]
        rows.append('DT_MOTION|' + '|'.join(map(str, vals)))
    return '\n'.join(rows)


@unittest.skipUnless(HAS_PIL, 'requires Pillow')
class MotionProbeTests(unittest.TestCase):
    def test_rejects_invalid_markers(self):
        self.assertEqual(len(parse(log())), 30)
        for invalid in (log() + '\n' + log().splitlines()[0], log().replace('DT_MOTION|5|', 'DT_MOTION|nan|'),
                        '\n'.join(log().splitlines()[1:]), log().replace('|1120|630|0|1120|630|0|1', '|1120|630|0|1120|630|0|2')):
            with self.subTest(value=invalid[:40]), self.assertRaises(ValueError):
                parse(invalid)

    def test_compare_and_detect_no_movement(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / 'a', Path(tmp) / 'b'
            a.mkdir(); b.mkdir()
            for frame in FRAMES:
                Image.new('RGB', (16, 16), (0, 0, 0)).save(a / f'shot_{frame}.png')
                Image.new('RGB', (16, 16), (0, 0, 1)).save(b / f'shot_{frame}.png')
            result = compare(log(), log(True), a, b)
            self.assertGreater(result['max_player_distance_from_baseline'], 1)
            self.assertEqual(result['screenshots']['175']['different_pixels'], 256)
            with self.assertRaisesRegex(ValueError, 'keyboard'):
                compare(log(), log(), a, b)


if __name__ == '__main__':
    unittest.main()
