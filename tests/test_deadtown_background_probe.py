import tempfile
import unittest
from pathlib import Path
try:
    import PIL  # noqa: F401
    from tools.prepare_deadtown_background_probe import patch_source, prepare, START, END, RECT, FINISH
    from tools.check_deadtown_background_probe import check
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


@unittest.skipUnless(HAS_PIL, 'requires Pillow')
class BackgroundProbeTests(unittest.TestCase):
    def test_patch_is_single_use_and_hash_pinned(self):
        source = START + '\n' + RECT + '\n' + END + '\n' + FINISH
        patched = patch_source(source)
        self.assertIn('DT_BG_COVERAGE', patched)
        with self.assertRaises(ValueError):
            patch_source(patched)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Graphics.cpp'; path.write_text(source)
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                prepare(path)
            self.assertEqual(path.read_text(), source)

    def test_validate_coverage_and_negative_cases(self):
        zero = 'DT_BG_COVERAGE|zero|0|1232|693|0\nDT_BG_FINAL|zero|0|0\n'
        live = 'DT_BG_COVERAGE|live|-56.32|1232|693|277000\nDT_BG_FINAL|live|277000|50000\n'
        fix = 'DT_BG_COVERAGE|fix|-56.32|1232|693|0\nDT_BG_FINAL|fix|0|0\n'
        result = check(zero, live, fix)
        self.assertGreater(result['rotated']['observed_fraction'], 0.3)
        self.assertEqual(result['rotated']['after_room_draw']['remaining_after_room_draw'], 50000)
        for bad in (live + live, live.replace('277000', '0'), live.replace('-56.32', 'nan'),
                    live.replace('1232', '0')):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                check(zero, bad, fix)


if __name__ == '__main__':
    unittest.main()
