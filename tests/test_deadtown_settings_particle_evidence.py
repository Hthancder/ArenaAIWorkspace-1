from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_settings_particle_evidence import SETTINGS, PARTICLES, inspect, verify_source
from tools.deadtown_settings_particle_vm_probe import EXPECTED, check, instrument, make_project

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'deadtown-source/project'
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class SettingsParticleEvidenceTests(unittest.TestCase):
    def test_source_and_mutations(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'project'
            dest.mkdir()
            shutil.copy(PROJECT/'deadtown.project.gmx', dest)
            (dest/'scripts').mkdir()
            for name in (*PARTICLES, 'setting_load', 'setting_save'):
                shutil.copy(PROJECT/'scripts'/(name+'.gml'), dest/'scripts')
            verify_source(dest)
            p = dest/'scripts/setting_load.gml'
            p.write_text(p.read_text().replace('"particle",1', '"particle",0'))
            with self.assertRaises(ValueError):
                verify_source(dest)
            p.write_text((PROJECT/'scripts/setting_load.gml').read_text())
            p = dest/'scripts/particle_burst.gml'
            p.write_text(p.read_text().replace('> 0.5', '>= 0.5'))
            with self.assertRaises(ValueError):
                verify_source(dest)

    def test_mock_project_and_markers(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'mock'
            make_project(PROJECT, dest)
            self.assertIn('__dt_probe_part_emitter_burst', (dest/'scripts/particle_burst.gml').read_text())
            self.assertIn('sys_particle.p_system', (PROJECT/'scripts/particle_burst.gml').read_text())
            self.assertIn('__dt_probe_ini_read_real', (dest/'scripts/setting_load.gml').read_text())
            with self.assertRaises(ValueError):
                make_project(PROJECT, dest)
        event = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        self.assertTrue(instrument([event])[0]['gml'].endswith('original();'))
        self.assertEqual(check('\n'.join(EXPECTED)), 6)
        with self.assertRaises(ValueError):
            check('\n'.join(EXPECTED).replace('threshold:0', 'threshold:123'))
        with self.assertRaises(ValueError):
            instrument([])

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_reject_bad_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'bad.apk'
            p.write_bytes(b'incorrect')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires pinned APK and analysis dependencies')
    def test_native(self):
        report = inspect(APK)
        self.assertEqual(len(report['settings']), 7)
        self.assertEqual(report['settings'][-1]['native_slot'], 49)
        self.assertEqual(set(report['particle_gates']), set(PARTICLES))
        self.assertEqual(len(SETTINGS), 7)


if __name__ == '__main__':
    unittest.main()
