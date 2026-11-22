from pathlib import Path
import shutil
import struct
import tempfile
import unittest

from tools.deadtown_empty_collision_evidence import elf_file_bytes, verify

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'


class EmptyCollisionTests(unittest.TestCase):
    def test_arm_elf_segment_bounds(self):
        data = bytearray(128)
        data[:7] = b'\x7fELF\x01\x01\x01'
        struct.pack_into('<H', data, 18, 40)
        struct.pack_into('<I', data, 28, 52)
        struct.pack_into('<HH', data, 42, 32, 1)
        struct.pack_into('<5I', data, 52, 1, 100, 0x5000, 0, 4)
        data[100:104] = b'abcd'
        self.assertEqual(elf_file_bytes(data, 0x5000, 4), b'abcd')
        with self.assertRaisesRegex(ValueError, 'not backed'):
            elf_file_bytes(data, 0x5001, 4)
        with self.assertRaisesRegex(ValueError, 'ELF32'):
            elf_file_bytes(b'bad', 0, 4)
        struct.pack_into('<I', data, 28, 110)
        with self.assertRaisesRegex(ValueError, 'program headers'):
            elf_file_bytes(data, 0, 1)

    def test_rejects_wrong_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'wrong.apk'
            fake.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                verify(fake, PROJECT)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_pinned_event_and_tampering(self):
        result = verify(APK, PROJECT)
        self.assertEqual([(x['object'], x['collision_target'], x['native_target_index']) for x in result['events']], [
            ('obj_player', 'par_action', 184), ('obj_zombie4', 'obj_player_body', 144),
            ('obj_zombie5', 'par_action_door', 187), ('obj_zombie5', 'par_action', 184)])
        self.assertTrue(all(x['native_arm_bytes'] == '1eff2fe1' for x in result['events']))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'objects').mkdir()
            for name in ('obj_player', 'obj_zombie4', 'obj_zombie5'):
                shutil.copy(PROJECT / 'objects' / (name+'.object.gmx'), root/'objects')
            path = root / 'objects/obj_player.object.gmx'
            text = path.read_text()
            path.write_text(text.replace('/// not inherited\n', 'x = 42;\n'))
            with self.assertRaisesRegex(ValueError, 'comment-only'):
                verify(APK, root)
            path.write_text(text.replace('eventtype="4" ename="par_action"', 'eventtype="4" ename="par_solid"'))
            with self.assertRaisesRegex(ValueError, 'source collision event'):
                verify(APK, root)
            path.write_text(text)
            zombie = root/'objects/obj_zombie5.object.gmx'
            zombie_text = zombie.read_text()
            zombie.write_text(zombie_text.replace('eventtype="4" ename="par_action_door"', 'eventtype="4" ename="par_solid"'))
            with self.assertRaisesRegex(ValueError, 'source collision event'):
                verify(APK, root)
            zombie.write_text(zombie_text.replace('/// not inherited\n', 'event_inherited();\n', 1))
            with self.assertRaisesRegex(ValueError, 'comment-only'):
                verify(APK, root)


if __name__ == '__main__':
    unittest.main()
