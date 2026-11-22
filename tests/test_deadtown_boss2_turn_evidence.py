from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_boss2_turn_evidence import INIT, TURN, ALARM, fragments, inspect

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT/'deadtown-source/project'
APK = ROOT/'.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class BossTurnTests(unittest.TestCase):
    def test_source_and_mutations(self):
        self.assertEqual(fragments(PROJECT), (INIT, TURN, ALARM))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'objects').mkdir()
            p = root/'objects/obj_boss2_ten.object.gmx'
            shutil.copy(PROJECT/'objects/obj_boss2_ten.object.gmx', p)
            original = p.read_text()
            for old, new in (('choose(1,0,0)', 'choose(1,0)'), ('alarm[0] = 20', 'alarm[0] = 21'),
                             ('move_speed = 8', 'move_speed = 7'), ('move_speed = 9', 'move_speed = 8'),
                             ('blood_speed = 0.4', 'blood_speed = 0.5'),
                             ('if type == 0', 'if type == 1'),
                             ('obj_player.hp -= blood_speed/2', 'obj_player.hp -= blood_speed'),
                             ('choose(1,0,0,0,0)', 'choose(1,0,0)'),
                             ('go_dir *= -1', 'go_dir *= 1'), ('eventtype="2" enumb="0"', 'eventtype="2" enumb="1"'),
                             ('slot 1201; original name unknown.\n__dt_reverse_turn = 0', 'slot 1201; original name unknown.\n__dt_reverse_turn = 1')):
                self.assertIn(old, original)
                p.write_text(original.replace(old, new, 1))
                with self.assertRaises(ValueError):
                    fragments(root)

    @unittest.skipUnless(HAS_DEPS, 'requires analysis dependencies')
    def test_bad_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'wrong.apk'
            p.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires pinned APK and analysis dependencies')
    def test_native(self):
        report = inspect(APK)
        self.assertEqual(report['flag_slot'], 1201)
        self.assertEqual(report['turn_slot'], 1088)
        self.assertEqual(report['choose_values'], [1, 0, 0])
        self.assertEqual((report['alarm'], report['alarm_steps']), (0, 20))
        self.assertEqual((report['speed_slot'], report['speed_initial'], report['speed_if_chosen']), (180, 8, 9))
        self.assertEqual(report['speed_choose_values'], [1, 0, 0, 0, 0])
        self.assertEqual((report['damage_slot'], report['damage_initial']), (1200, 0.4))
        self.assertEqual((report['target_object'], report['target_slot']), ('obj_player', 28))


if __name__ == '__main__':
    unittest.main()
