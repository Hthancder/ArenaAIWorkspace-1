from pathlib import Path
import math
import tempfile
import unittest

from tools.deadtown_item_kind_evidence import inspect, numeric_rule, RANGES, verify_source
from tools.deadtown_item_kind_vm_probe import cases, check, instrument

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class ItemKindEvidenceTests(unittest.TestCase):
    def test_integer_boundaries_and_fractional_epsilon(self):
        for low, high in RANGES.values():
            for x in range(low - 2, high + 3):
                self.assertEqual(numeric_rule(x, low, high, 1e-10), int(low <= x <= high))
            for x, expected in ((low - 5e-11, 1), (low - 2e-10, 0),
                                (high + 5e-11, 1), (high + 2e-10, 0)):
                self.assertEqual(numeric_rule(x, low, high, 1e-10), expected)
            for x in (math.nan, math.inf, -math.inf):
                with self.assertRaises(ValueError):
                    numeric_rule(x, low, high, 1e-10)

    def test_candidate_is_declared_and_matches(self):
        verify_source(PROJECT)

    def test_vm_probe_rejects_missing_or_incorrect_markers(self):
        event = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        instrument([event])
        self.assertTrue(event['gml'].endswith('original();'))
        markers = [f'ITEM_KIND_VM:{name}:{value}:{answer}' for name, value, answer in cases()]
        markers.append('ITEM_KIND_VM:basic_string:' + 'A' * 20)
        self.assertEqual(check('\n'.join(markers)), len(markers))
        with self.assertRaises(ValueError):
            check('\n'.join(markers[:-1]))
        with self.assertRaises(ValueError):
            instrument([])

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_rejects_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'fake.apk'
            path.write_bytes(b'not the original APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(path)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires analysis dependencies and pinned APK')
    def test_native_instructions_and_relocations(self):
        result = inspect(APK)
        self.assertEqual(result['static_epsilon_initializer'], 1e-10)
        self.assertEqual((result['scripts']['item_check_pet']['lower'], result['scripts']['item_check_pet']['upper']), (17, 22))
        self.assertEqual((result['scripts']['item_check_skin']['lower'], result['scripts']['item_check_skin']['upper']), (23, 26))
        self.assertIn('no proof', result['limitations'])


if __name__ == '__main__':
    unittest.main()
