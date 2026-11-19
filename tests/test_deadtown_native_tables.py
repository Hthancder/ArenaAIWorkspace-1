import re
import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

from tools.deadtown_native_tables import extract, multi_store_offset
from tools.deadtown_native_lang import extract as extract_languages

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'


def has_re_dependencies():
    try:
        import capstone  # noqa: F401
        import elftools  # noqa: F401
        return True
    except ImportError:
        return False


class NativeTableUnitTests(unittest.TestCase):
    def test_arm_stm_addressing(self):
        self.assertEqual(multi_store_offset('stm', 3), 0)
        self.assertEqual(multi_store_offset('stmib', 3), 4)
        self.assertEqual(multi_store_offset('stmda', 3), -8)
        self.assertEqual(multi_store_offset('stmdb', 3), -12)
        for args in [('stmda', 0), ('ldm', 2)]:
            with self.assertRaises(ValueError):
                multi_store_offset(*args)

    @unittest.skipUnless(has_re_dependencies(), 'requires capstone and pyelftools')
    def test_fails_closed_on_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'wrong.apk'
            p.write_bytes(b'not the pinned APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                extract(p)


@unittest.skipUnless(APK.is_file() and has_re_dependencies(), 'requires pinned APK and RE dependencies')
class NativeTableIntegrationTests(unittest.TestCase):
    def test_known_binary_counts_arguments_and_independent_language_scanner(self):
        result = extract(APK)
        counts = {'db_weapon_add': 35, 'db_equip_add': 27, 'db_use_add': 22,
                  'db_craft_add': 91, 'db_etc_add': 65, 'db_skill_add': 23,
                  'db_spawn_add': 129, 'lang_add': 465}
        for name, count in counts.items():
            self.assertEqual(result['counts'][name], {'resolved': count, 'unresolved': 0})
        values = lambda row: [arg['value'] for arg in row['arguments']]
        rows = result['entries']
        self.assertEqual(values(rows['db_weapon_add'][0]),
                         ['Dagger', 0.0, 257.0, 'Small keen knife', 7.0, 45.0,
                          7.0, 0.0, 0.0, 0.0, 1.0, 40.0, 15.0])
        self.assertEqual(values(rows['db_equip_add'][0]),
                         ['Cotton clothes', 0.0, 0.0, 'Clothes made from cotton', 1.0, 2.0, 0.0])
        self.assertEqual(values(rows['db_use_add'][0]),
                         ['Raw meat', 0.0, 'Kind of meat', 15.0, 5.0, 0.0, 0.0, 0.0, 1.0, 0.0])
        self.assertEqual(values(rows['db_spawn_add'][2]), [0.0, 4.0, 25.0, 3.0, 5.0])
        self.assertEqual(len(rows['db_craft_add'][0]['arguments']), 15)
        for group in rows.values():
            for row in group:
                self.assertTrue(all(arg['symbol'] and arg['relocation_address'] for arg in row['arguments']))
        prior = extract_languages(APK)
        self.assertEqual([(x['call_address'], values(x)) for x in rows['lang_add']],
                         [(x['call_address'], x['candidate_arguments']) for x in prior['entries']])

    @unittest.skipUnless((ROOT / '.cache/deadtown/deadtown.gmx/objects/sys_global.object.gmx').is_file(),
                         'requires pinned GMX source')
    def test_numeric_tables_against_old_source(self):
        result = extract(APK)
        tree = ET.parse(ROOT / '.cache/deadtown/deadtown.gmx/objects/sys_global.object.gmx')
        source = '\n'.join(node.text or '' for node in tree.iter('string'))
        for function, old_calls, old_distinct, common in (
                ('db_craft_add', 76, 76, 71), ('db_spawn_add', 127, 126, 109)):
            literal_calls = re.findall(r'(?m)^\s*' + function + r'\(([^\n)]*)\)', source)
            self.assertEqual(len(literal_calls), old_calls)
            old = {tuple(float(v.strip()) for v in call.split(',')) for call in literal_calls}
            native = {tuple(arg['value'] for arg in row['arguments']) for row in result['entries'][function]}
            self.assertEqual(len(old), old_distinct)
            self.assertEqual(len(old & native), common)
        self.assertIn('db_weapon_add("Dagger",spr_noone,ih_dagger,"Small keen knife",7,40,7', source)
        self.assertIn('db_equip_add("Cotton clothes",spr_noone,spr_noone,"Clothes made from cotton",1,1,0)', source)
        self.assertIn('db_spawn_add(0,4,25,2,5)', source)
        self.assertIn('db_use_add("Raw meat",spr_noone,"Kind of meat",20,5,0,0,0,1)', source)


if __name__ == '__main__':
    unittest.main()
