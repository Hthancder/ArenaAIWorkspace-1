import tempfile
import unittest
from pathlib import Path

from tools.deadtown_poison_evidence import inspect

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


class PoisonEvidenceTests(unittest.TestCase):
    @unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'not the pinned APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(path)

    @unittest.skipUnless(APK.is_file() and HAS_RE, 'requires pinned APK and RE dependencies')
    def test_known_native_path(self):
        evidence = inspect(APK)
        self.assertEqual(evidence['field'], 9)
        self.assertEqual(evidence['field_value_multiplied_by'], [30, 60])
        self.assertEqual(evidence['variable_index'], 32)
        self.assertEqual(evidence['adjacent_variable_symbols'][-1], 'g_VAR_buff_poison_protect')
        self.assertEqual(evidence['player_object_name'], 'obj_player')
        self.assertEqual(evidence['buff_step_add_call'], '0x6022cc')
        step = evidence['player_step_evidence']
        self.assertEqual(step['variable_index'], 32)
        self.assertEqual(step['comparison_fallthrough_zeroes_variable_index'], 171)
        self.assertEqual(step['branch_target_zeroes_variable_index'], 32)
        self.assertEqual(step['candidate_upper_bound_index'], 911)
        self.assertIn('not mapped', step['limitations'])
        self.assertEqual(evidence['g_vars_index_32']['symbol'], 'g_VAR_pointer')
        self.assertIn('not a verified', evidence['g_vars_index_32']['warning'])
        self.assertIn('unverified', evidence['interpretation'])


if __name__ == '__main__':
    unittest.main()
