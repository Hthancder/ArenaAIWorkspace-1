import tempfile
import unittest
from pathlib import Path

from tools.deadtown_native_callgraph import extract

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


class NativeCallGraphTests(unittest.TestCase):
    @unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'not the pinned APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                extract(path)

    @unittest.skipUnless(APK.is_file() and HAS_RE, 'requires pinned APK and RE dependencies')
    def test_known_function_edges(self):
        graph = extract(APK)
        self.assertEqual(graph['function_count'], 1051)
        functions = graph['functions']
        ui = functions['gml_Object_sys_UI_Draw_64']['candidate_calls']
        self.assertEqual(ui['gml_Script_get_enchant_price']['count'], 1)
        self.assertEqual(ui['gml_Script_get_enchant_my_money']['count'], 1)
        view = functions['gml_Object_sys_view_Step_0']['candidate_calls']
        self.assertEqual(view['gml_Script_gp_axis_value']['count'], 3)
        global_calls = functions['gml_Object_sys_global_Create_0']['candidate_calls']
        self.assertEqual(global_calls['gml_Script_lang_add']['count'], 465)
        self.assertEqual(global_calls['gml_Script_db_spawn_add']['count'], 129)
        self.assertEqual(global_calls['gml_Script_db_craft_add']['count'], 91)
        for group in (ui, view, global_calls):
            for value in group.values():
                self.assertEqual(value['count'], len(value['sites']))


if __name__ == '__main__':
    unittest.main()
