import tempfile
import unittest
from pathlib import Path

from tools.deadtown_native_inventory import exported_name, parse_nm, project_names, source_events


def mangled(name):
    return f'_Z{len(name)}{name}P9CInstance'


class NativeInventoryTests(unittest.TestCase):
    def test_exported_names_use_itanium_length_not_type_suffix(self):
        name = 'gml_Object_sys_global_Create_0'
        self.assertEqual(exported_name(mangled(name)), name)
        self.assertIsNone(exported_name('_Z4testv'))
        self.assertIsNone(exported_name('_Z99too_short'))

    def test_nm_event_and_script(self):
        script = mangled('gml_Script_lang_get')
        event = mangled('gml_Object_sys_UI_Draw_64')
        scripts, events = parse_nm(f'{script} T 100 20\n{event} T 200 40\n')
        self.assertEqual(scripts['lang_get'], {'address': 0x100, 'size': 0x20})
        self.assertEqual(events[('sys_UI', 'Draw', 64)], {'address': 0x200, 'size': 0x40})
        with self.assertRaises(ValueError):
            parse_nm(f'{script} T 100 20\n{event} T 200 40\n{event} T 200 40\n')

    def test_gmx_declared_names_and_collision_ids(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'objects').mkdir()
            (root / 'deadtown.project.gmx').write_text(
                '<assets><scripts><script>scripts\\lang_get.gml</script></scripts>'
                '<objects><object>objects\\obj_player</object></objects></assets>')
            (root / 'objects' / 'obj_player.object.gmx').write_text(
                '<object><events><event eventtype="0" enumb="0"/>'
                '<event eventtype="4" ename="obj_enemy"/>'
                '<event eventtype="4" ename="missing"/></events></object>')
            self.assertEqual(project_names(root, 'scripts', 'script'), {'lang_get'})
            self.assertEqual(project_names(root, 'objects', 'object'), {'obj_player'})
            events, unresolved = source_events(root, {'obj_player'}, {'obj_enemy': 123})
            self.assertEqual(events, {('obj_player', 'Create', 0), ('obj_player', 'Collision', 123)})
            self.assertEqual(unresolved, ['obj_player:Collision:missing'])


if __name__ == '__main__':
    unittest.main()
