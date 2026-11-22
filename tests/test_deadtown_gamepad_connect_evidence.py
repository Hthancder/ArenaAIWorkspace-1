from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_gamepad_connect_evidence import inspect, verify_source

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'deadtown-source/project'
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class ConnectEvidenceTests(unittest.TestCase):
    def test_source_and_reject_changed_candidate(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / 'project'
            project.mkdir()
            shutil.copy(PROJECT / 'deadtown.project.gmx', project)
            (project / 'scripts').mkdir()
            for name in ('gp_connect_check', 'setting_load', 'setting_save'):
                shutil.copy(PROJECT / 'scripts' / (name + '.gml'), project / 'scripts')
            verify_source(project)
            p = project / 'scripts/setting_load.gml'
            p.write_text(p.read_text().replace('"gamepad",0', '"gamepad",1'))
            with self.assertRaises(ValueError):
                verify_source(project)
            p.write_text((PROJECT / 'scripts/setting_load.gml').read_text())
            p = project / 'scripts/gp_connect_check.gml'
            p.write_text(p.read_text().replace('0.2', '0.3'))
            with self.assertRaises(ValueError):
                verify_source(project)

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_reject_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'other.apk'
            p.write_bytes(b'not an APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires pinned APK and analysis dependencies')
    def test_native_evidence(self):
        evidence = inspect(APK)
        self.assertEqual(evidence['global_slot'], 88)
        self.assertEqual(evidence['settings_key'], ['control', 'gamepad'])
        self.assertEqual(evidence['deadzone'], 0.2)


if __name__ == '__main__':
    unittest.main()
