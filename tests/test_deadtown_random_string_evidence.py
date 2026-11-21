from pathlib import Path
import tempfile
import unittest

from tools.deadtown_random_string_evidence import inspect, verify_source
from tools.deadtown_random_string_vm_probe import EXPECTED, instrument, check

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


class RandomStringTests(unittest.TestCase):
    def test_source(self):
        verify_source(ROOT / 'deadtown-source/project')

    def test_seeded_probe_validates_all_values_and_rng_next(self):
        event = {'object': 'sys_global', 'attributes': {'eventtype': '0', 'enumb': '0'}, 'gml': 'original();'}
        instrument([event])
        self.assertTrue(event['gml'].endswith('original();'))
        lines = [f'RANDOM_STRING_VM:{seed}:{value}:{n}' for seed, (value, n) in EXPECTED.items()]
        self.assertEqual(check('\n'.join(lines)), 4)
        with self.assertRaises(ValueError):
            check('\n'.join(lines[:-1]))
        with self.assertRaises(ValueError):
            check('\n'.join(lines).replace(':116', ':117'))
        with self.assertRaises(ValueError):
            instrument([])

    @unittest.skipUnless(HAS_DEPS, 'requires capstone and pyelftools')
    def test_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'fake.apk'
            fake.write_bytes(b'incorrect')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(fake)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires analysis dependencies and pinned APK')
    def test_static_evidence(self):
        report = inspect(APK)
        self.assertEqual(report['iterations'], 20)
        self.assertEqual(report['random_ranges_in_order'], [[65, 90], [97, 122], [48, 57]])
        self.assertIn('iOS unverified', report['limitations'])


if __name__ == '__main__':
    unittest.main()
