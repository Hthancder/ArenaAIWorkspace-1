import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from tools.deadtown_native_lang import APK_SHA256
from tools.deadtown_room_evidence import (compare, instance_comparison, item_name,
                                          nested_pointers, normalize_float, source_room)

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'


class RoomEvidenceTests(unittest.TestCase):
    def test_multiset_comparison_preserves_duplicate_instances(self):
        a = ('obj', 10, 20, 1.0, 1.0, 0xffffffff, 0.0)
        b = ('obj', 11, 20, 1.0, 1.0, 0xffffffff, 0.0)
        result = instance_comparison([a, a, b], [a, b, b])
        self.assertEqual((result['apk_count'], result['gmx_count'], result['matched_count']), (3, 3, 2))
        self.assertEqual(result['apk_only'][0]['x'], 10)
        self.assertEqual(result['gmx_only'][0]['x'], 11)

    def test_bounded_pointer_lists_and_resource_indices(self):
        data = bytearray(64)
        struct.pack_into('<III', data, 8, 2, 28, 36)
        self.assertEqual(nested_pointers(data, 8, (8, 64), 8), [28, 36])
        struct.pack_into('<I', data, 16, 28)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            nested_pointers(data, 8, (8, 64), 8)
        struct.pack_into('<I', data, 16, 60)
        with self.assertRaisesRegex(ValueError, 'outside'):
            nested_pointers(data, 8, (8, 64), 8)
        self.assertIsNone(item_name(['obj'], -1, True))
        with self.assertRaisesRegex(ValueError, 'invalid resource'):
            item_name(['obj'], -1)
        with self.assertRaisesRegex(ValueError, 'non-finite'):
            normalize_float('nan')

    def test_source_room_reads_boolean_and_float_fields(self):
        xml = '''<room><width>1</width><height>2</height><speed>30</speed><persistent>0</persistent>
        <colour>4</colour><showcolour>-1</showcolour><enableViews>-1</enableViews><code></code>
        <backgrounds/><views/><tiles/><instances><instance objName="obj" x="1" y="2" scaleX="0.1"
        scaleY="1" colour="-1" rotation="0" code=""/></instances></room>'''
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'room.gmx'
            path.write_text(xml)
            r = source_room(path)
        self.assertTrue(r['fields']['enable_views'])
        self.assertTrue(r['fields']['showcolour'])
        self.assertEqual(r['instances'][0][3], struct.unpack('<f', struct.pack('<f', .1))[0])
        self.assertEqual(r['instances'][0][5], 0xffffffff)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_pinned_room_evidence(self):
        self.assertEqual(hashlib.sha256(APK.read_bytes()).hexdigest(), APK_SHA256)
        r = compare(APK, PROJECT)
        self.assertEqual((len(r['apk_rooms']), len(r['gmx_declared_rooms']), len(r['shared'])), (15, 7, 7))
        play = r['shared']['rom_play']
        self.assertEqual(play['apk_views'][0][3:5], (1232, 693))
        self.assertEqual(play['gmx_views'][0][3:5], (1232, 693))
        self.assertTrue(play['views_equal'])
        self.assertEqual((play['instances']['apk_count'], play['instances']['gmx_count'], play['instances']['matched_count']), (1664, 1658, 1658))
        tiles = play['tiles']
        self.assertEqual((tiles['apk_count'], tiles['gmx_count'], tiles['matched_count']), (17175, 17175, 17175))


if __name__ == '__main__':
    unittest.main()
