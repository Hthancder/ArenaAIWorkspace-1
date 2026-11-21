import tempfile
import unittest
from pathlib import Path

from tools.deadtown_draw_call_evidence import compare, native_calls, scrub_non_code, source_calls

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
GMX = ROOT / '.cache/deadtown/deadtown.gmx'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


class DrawEvidenceTests(unittest.TestCase):
    def test_scrubs_comments_and_strings_not_code(self):
        text = 'draw_sprite_ext(x); // draw_sprite_ext(x)\n"draw_sprite_ext(x)"; /* draw_sprite_ext(x)\n */ draw_sprite_ext(y)'
        code = scrub_non_code(text)
        self.assertEqual(len(code), len(text))
        self.assertEqual(code.count('\n'), text.count('\n'))
        self.assertEqual(code.count('draw_sprite_ext('), 2)
        self.assertEqual(scrub_non_code('"escaped \\" and // text"\nfoo()').count('foo()'), 1)

    def test_wrong_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'objects'
            p.mkdir()
            (p / 'obj_player.object.gmx').write_text('<object/>')
            with self.assertRaisesRegex(ValueError, 'source SHA-256'):
                source_calls(tmp)

    @unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
    def test_wrong_apk_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'APK SHA-256'):
                native_calls(path)

    @unittest.skipUnless(APK.is_file() and GMX.is_dir() and HAS_RE, 'requires pinned inputs and RE dependencies')
    def test_pinned_static_callsites(self):
        events = compare(APK, GMX)['events']
        player = events['gml_Object_obj_player_Draw_0']
        self.assertEqual(len(player['native']['candidate_sites']['draw_sprite_ext']), 12)
        self.assertEqual(player['old_source_lexical_counts']['draw_sprite_ext'], 12)
        view = events['gml_Object_sys_view_Draw_64']
        self.assertEqual(len(view['native']['candidate_sites']['draw_sprite_ext']), 13)
        self.assertEqual(view['old_source_lexical_counts']['draw_sprite_ext'], 8)
        light = events['gml_Object_sys_spawn_time_light_Draw_74']
        self.assertEqual(len(light['native']['candidate_sites']['draw_surface_part_ext']), 1)
        self.assertEqual(light['old_source_lexical_counts']['draw_surface_part_ext'], 2)


if __name__ == '__main__':
    unittest.main()
