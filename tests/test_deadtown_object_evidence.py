import hashlib
from pathlib import Path
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

from tools.deadtown_native_lang import APK_SHA256
from tools.deadtown_object_evidence import FIELDS, compare, event_counts, native_objects, reference, source_object

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'


class ObjectEvidenceTests(unittest.TestCase):
    def test_resource_references_fail_closed(self):
        self.assertEqual(reference(['one'], 0, {-1}), 'one')
        self.assertIsNone(reference(['one'], -100, {-100}))
        with self.assertRaisesRegex(ValueError, 'outside'):
            reference(['one'], -2, {-1})
        with self.assertRaisesRegex(ValueError, 'outside'):
            reference(['one'], 1, {-1})

    def test_native_event_counts_bounds_and_event_types(self):
        data = bytearray(220)
        struct.pack_into('<I', data, 80, 12)
        for i in range(12):
            struct.pack_into('<I', data, 84 + 4 * i, 140 + 4 * i)
        self.assertEqual(event_counts(data, 0, (0, 220)), [0] * 12)
        struct.pack_into('<I', data, 80, 11)
        with self.assertRaisesRegex(ValueError, 'event type'):
            event_counts(data, 0, (0, 220))
        struct.pack_into('<I', data, 80, 12)
        struct.pack_into('<I', data, 84, 219)
        with self.assertRaisesRegex(ValueError, 'outside'):
            event_counts(data, 0, (0, 220))

    def test_source_defaults_and_missing_field(self):
        text = '''<object><spriteName>&lt;undefined&gt;</spriteName><visible>-1</visible><solid>0</solid>
        <depth>-2</depth><persistent>0</persistent><parentName>par</parentName>
        <maskName>mask</maskName><PhysicsObject>0</PhysicsObject></object>'''
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'o.gmx'
            path.write_text(text)
            obj = source_object(path)
            self.assertEqual(obj['sprite'], None)
            self.assertTrue(obj['visible'])
            self.assertEqual(obj['parent'], 'par')
            path.write_text(text.replace('<depth>-2</depth>', ''))
            with self.assertRaisesRegex(ValueError, 'missing object field depth'):
                source_object(path)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_restored_parent_and_children_match_pinned_static_defaults(self):
        self.assertEqual(hashlib.sha256(APK.read_bytes()).hexdigest(), APK_SHA256)
        with zipfile.ZipFile(APK) as z:
            native = native_objects(z.read('assets/game.droid'))
        empty = ('par_action_nosolid', 'par_defence_shop', 'par_map_door', 'obj_defence_house')
        for name in empty:
            self.assertEqual(native[name]['event_counts'], [0] * 12)
            self.assertFalse(ET.parse(PROJECT / 'objects' / (name + '.object.gmx')).findall('./events/event'))
        for name in (*empty, 'obj_trap', 'obj_gps'):
            source = source_object(PROJECT / 'objects' / (name + '.object.gmx'))
            self.assertEqual({field: native[name][field] for field in FIELDS}, source)
        report = compare(APK, PROJECT)
        self.assertEqual((report['apk_count'], report['gmx_declared_count'], report['common_count']), (240, 154, 150))
        self.assertEqual(report['differing_defaults_count'], 3)
        self.assertEqual(set(report['differences']), {'obj_lobby_ach', 'obj_lobby_leader', 'sys_player_equipment'})


if __name__ == '__main__':
    unittest.main()
