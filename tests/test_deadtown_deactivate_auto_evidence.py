from pathlib import Path
import tempfile
import unittest

from tools.deadtown_deactivate_auto_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


@unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
class DeactivateAutoEvidenceTests(unittest.TestCase):
    def test_rejects_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'fake.apk'
            fake.write_bytes(b'incorrect APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(fake)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_unresolved_global_and_calls(self):
        report = inspect(APK)
        self.assertEqual(report['native_global_slot'], 48)
        self.assertEqual(report['object_native_ids'], {'sys_global': 38, 'sys_multi': 74})
        self.assertEqual(report['true_branch_calls_in_order'], [
            'instance_deactivate_all(1)', 'instance_activate_object(sys_global)', 'instance_activate_object(sys_multi)'])
        self.assertIn('Global slot name not identified', report['limitations'])


if __name__ == '__main__':
    unittest.main()
