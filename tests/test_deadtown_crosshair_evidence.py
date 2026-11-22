from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_crosshair_evidence import inspect, verify_source
from tools.deadtown_settings_particle_vm_probe import make_project, instrument, EXPECTED, check

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT/'deadtown-source/project'
APK = ROOT/'.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class CrosshairEvidenceTests(unittest.TestCase):
    def test_source_and_reject_mutations(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)/'project'
            (dest/'scripts').mkdir(parents=True)
            (dest/'sprites').mkdir()
            shutil.copy(PROJECT/'deadtown.project.gmx', dest)
            shutil.copy(PROJECT/'scripts/draw_line_crosshair.gml', dest/'scripts')
            shutil.copy(PROJECT/'sprites/spr_crosshair.sprite.gmx', dest/'sprites')
            verify_source(dest)
            file = dest/'scripts/draw_line_crosshair.gml'
            before = file.read_text()
            file.write_text(before.replace('__dt_distance > 100', '__dt_distance >= 100'))
            with self.assertRaises(ValueError):
                verify_source(dest)
            file.write_text(before)
            sprite = dest/'sprites/spr_crosshair.sprite.gmx'
            sprite.write_text(sprite.read_text().replace('index="1"', 'index="2"'))
            with self.assertRaises(ValueError):
                verify_source(dest)

    def test_mock_source_and_log(self):
        event = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        text = instrument([event], PROJECT)[0]['gml']
        self.assertIn('draw_line_crosshair(11, 22, 33, 44)', text)
        self.assertEqual(check('\n'.join(EXPECTED)), 42)
        with self.assertRaises(ValueError):
            check('\n'.join(EXPECTED).replace('crosshair-long:1:', 'crosshair-long:0:'))
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)/'mock'
            make_project(PROJECT, dest)
            script = (dest/'scripts/draw_line_crosshair.gml').read_text()
            self.assertIn('__dt_cross_draw_sprite_ext(181,', script)
            geometry = (dest/'scripts/__dt_cross_geometry.gml').read_text()
            self.assertIn('point_distance(argument0, argument1, argument2, argument3)', geometry)
            self.assertIn('point_direction(argument0, argument1, argument2, argument3)', geometry)
            self.assertNotIn('__dt_cross_point_distance', geometry)
            self.assertIn('__dt_cross_draw_sprite_ext(181,', geometry)
            self.assertIn('spr_crosshair', (PROJECT/'scripts/draw_line_crosshair.gml').read_text())

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_reject_bad_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'bad.apk'
            p.write_bytes(b'invalid')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires pinned APK and analysis dependencies')
    def test_native_evidence(self):
        report = inspect(APK)
        self.assertEqual(report['sprite_index_native'], 181)
        self.assertEqual(report['threshold_and_divisor'], 100)
        self.assertEqual((report['frame_below'], report['frame_above']), (0, 1))


if __name__ == '__main__':
    unittest.main()
