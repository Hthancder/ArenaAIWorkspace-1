import math
import unittest

from tools.check_deadtown_layer_probe import analyze, compare, expected_vertices, parse
from tools.prepare_deadtown_layer_probe import patch


def make_log(moving=False):
    lines = []
    for tick in range(1, 31):
        x, y = 100 + (tick if moving else 0), 200
        lines.append(f'DT_LAYER_EVENT|{tick}|{x}|{y}|2|3|-4|5|0|0|1232|693|-56|0|1')
        for seq, (name, dx, dy) in enumerate((('spr_player_foot_right', 2, 3),
                                               ('spr_player_foot_left', -4, 5), ('spr_player', 0, 0)), 1):
            s = {'x': x+dx, 'y': y+dy, 'xs': 1.0, 'ys': 1.0, 'rotation': 30,
                 'origin_x': 10, 'origin_y': 12, 'target_x': 3, 'target_y': 4,
                 'target_w': 20, 'target_h': 24, 'alpha': 1, 'color': 16777215}
            vals = '|'.join(str(v) for v in s.values())
            lines.append(f'DT_LAYER_SPRITE|{tick}|{seq}|{name}|{vals}')
            verts = '|'.join(f'{v:.9f}' for pair in expected_vertices(s) for v in pair)
            lines.append(f'DT_LAYER_VERT|{tick}|{seq}|{verts}')
    return '\n'.join(lines)


class LayerTests(unittest.TestCase):
    def test_full_pair(self):
        result = compare(make_log(), make_log(True))
        self.assertEqual(result['moving']['event_count'], 30)
        self.assertAlmostEqual(result['max_player_displacement_from_still'], 30)
        self.assertAlmostEqual(result['moving']['foot_anchor_offset_range']['right'][0], math.sqrt(13))

    def test_wrong_source_and_nonmoving(self):
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            patch('wrong source')
        with self.assertRaisesRegex(ValueError, 'movement'):
            compare(make_log(), make_log())

    def test_corrupt_or_missing_trace_fails(self):
        log = make_log()
        with self.assertRaisesRegex(ValueError, 'sprite/quad mismatch'):
            parse('\n'.join(row for row in log.splitlines() if not row.startswith('DT_LAYER_VERT|1|1|')))
        with self.assertRaisesRegex(ValueError, 'nonfinite'):
            parse(log.replace('DT_LAYER_EVENT|1|100|', 'DT_LAYER_EVENT|1|nan|', 1))
        with self.assertRaisesRegex(ValueError, 'geometry'):
            analyze(log.replace('DT_LAYER_EVENT|1|100|200|2|3|', 'DT_LAYER_EVENT|1|100|200|8|3|', 1))
        with self.assertRaisesRegex(ValueError, 'geometry'):
            analyze(log.replace('DT_LAYER_SPRITE|1|1|spr_player_foot_right|102|', 'DT_LAYER_SPRITE|1|1|spr_player_foot_right|112|', 1))


if __name__ == '__main__':
    unittest.main()
