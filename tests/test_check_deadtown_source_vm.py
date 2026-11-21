import hashlib
from pathlib import Path
import unittest
import zipfile

try:
    from tools.check_deadtown_source_vm import GAME_DATA_SHA256, parse_probe, summarize_runtime
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

LOG = '''PROBE: attempting 138 staged offline source scripts; APK scripts absent from source=68, source scripts absent from APK=14
PROBE: compiling 539 translated event bodies; event behavior is not yet verified
PROBE: compile_success=True, code_entries=677, variables=100, functions=200
PROBE: linked 504 events to matching APK objects; skipped 35 missing objects or collision targets
PROBE: removed 68 unresolved native code IDs; behaviors are not restored
'''


@unittest.skipUnless(HAS_PIL, 'requires Pillow')
class SourceVMTests(unittest.TestCase):
    def test_compile_summary_retains_missing_behavior_counts(self):
        summary = parse_probe(LOG, 138, 539)
        self.assertEqual(summary['source_script_files_compiled'], 138)
        self.assertEqual(summary['event_links_skipped'], 35)
        self.assertEqual(summary['native_code_references_cleared'], 68)
        with self.assertRaisesRegex(ValueError, 'do not add up'):
            parse_probe(LOG.replace('skipped 35', 'skipped 34'), 138, 539)
        with self.assertRaisesRegex(ValueError, 'compilation failure'):
            parse_probe(LOG.replace('compile_success=True', 'compile_success=False'), 138, 539)
        with self.assertRaisesRegex(ValueError, 'one compile'):
            parse_probe(LOG + 'PROBE: compile_success=True,\n', 138, 539)
        with self.assertRaisesRegex(ValueError, 'do not add up'):
            parse_probe(LOG, 137, 539)

    @unittest.skipUnless((Path(__file__).resolve().parents[1] / '.cache/deadtown-original.apk').is_file(),
                         'requires pinned APK')
    def test_game_data_hash_matches_pinned_apk(self):
        apk = Path(__file__).resolve().parents[1] / '.cache/deadtown-original.apk'
        with zipfile.ZipFile(apk) as archive:
            self.assertEqual(hashlib.sha256(archive.read('assets/game.droid')).hexdigest(), GAME_DATA_SHA256)

    def test_runtime_errors_not_hidden_and_room_required(self):
        sample = ('[runner] 2 functions are not implemented yet: foo bar\n'
                  '[room] -> rom_play\n[gml] error in probe_obj_player: issue\n'
                  '[gml] error in probe_obj_player: issue\n[gml] call to unknown function foo\n'
                  '[stats] frame 360 room rom_play: step 1.20 ms, 10 draw calls, 20 instances\n')
        summary = summarize_runtime(sample, 'rom_play', 360)
        self.assertEqual(summary['diagnostic_lines'], 2)
        self.assertEqual(summary['distinct_diagnostics'][0]['occurrences'], 2)
        self.assertEqual(summary['unknown_function_lines'], 1)
        self.assertEqual(summary['unsupported_function_names'], ['foo', 'bar'])
        self.assertEqual(summary['last_stats']['instances'], 20)
        with self.assertRaisesRegex(ValueError, 'expected room'):
            summarize_runtime(sample, 'rom_lobby', 360)
        with self.assertRaisesRegex(ValueError, 'expected stats'):
            summarize_runtime(sample, 'rom_play', 400)
        with self.assertRaisesRegex(ValueError, 'does not match'):
            summarize_runtime(sample.replace('2 functions', '3 functions'), 'rom_play', 360)


if __name__ == '__main__':
    unittest.main()
