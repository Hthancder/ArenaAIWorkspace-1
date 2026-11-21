import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools import deadtown_unresolved_rooms as rooms

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
ARCHIVE = ROOT / 'deadtown-source/unresolved/rooms'


class UnresolvedRoomsTests(unittest.TestCase):
    def test_extract_verify_and_tamper(self):
        sample = {'rooms': [{'views': [(True, 1)], 'instances': [], 'tiles': []}]}
        with tempfile.TemporaryDirectory() as tmp, patch.object(rooms, 'collect', return_value=sample):
            folder = Path(tmp) / 'rooms'
            rooms.run('unused', folder, write=True)
            self.assertEqual(rooms.run('unused', folder)['rooms'][0]['views'], [[True, 1]])
            with self.assertRaises(FileExistsError):
                rooms.run('unused', folder, write=True)
            path = folder / 'rooms.json'
            data = json.loads(path.read_text())
            data['rooms'][0]['views'][0][1] = 2
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'archive mismatch'):
                rooms.run('unused', folder)
            path.unlink()
            path.symlink_to(Path(tmp) / 'elsewhere')
            with self.assertRaisesRegex(ValueError, 'invalid research file'):
                rooms.run('unused', folder)

    def test_rejects_unpinned_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.apk'
            path.write_bytes(b'not the pinned APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                rooms.collect(path)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_archive_matches_pinned_apk(self):
        records = rooms.run(APK, ARCHIVE)['rooms']
        self.assertEqual({r['name'] for r in records}, rooms.NAMES)
        self.assertEqual(sum(len(r['instances']) for r in records), 120)
        self.assertEqual(sum(len(r['tiles']) for r in records), 239)
        self.assertTrue(all(r['room_creation_code_index'] == -1 for r in records))
        self.assertTrue(all(i['creation_code_index'] == -1 for r in records for i in r['instances']))
        defence = next(r for r in records if r['name'] == 'rom_play_defence')
        self.assertEqual((defence['native_room_index'], len(defence['instances']), len(defence['tiles'])), (14, 56, 239))
        self.assertTrue(all(len(v) == 14 for r in records for v in r['views']))
        self.assertTrue(all(len(b) == 10 for r in records for b in r['backgrounds']))


if __name__ == '__main__':
    unittest.main()
