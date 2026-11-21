import hashlib
import io
from pathlib import Path
import struct
import unittest
import wave
import xml.etree.ElementTree as ET
import zipfile

from tools.deadtown_native_inventory import project_names
from tools.deadtown_native_lang import APK_SHA256
from tools.recover_deadtown_audio import chunks, pointers, read_string, recover, u32

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'deadtown-source'
PROJECT = SOURCE / 'project'
APK = ROOT / '.cache/deadtown-original.apk'


class EatingSoundTests(unittest.TestCase):
    def test_descriptor_and_unencoded_wav(self):
        self.assertIn('snd_eating', project_names(PROJECT, 'sounds', 'sound'))
        root = ET.parse(PROJECT / 'sound/snd_eating.sound.gmx').getroot()
        for key, value in {'kind': '0', 'extension': '.wav', 'origname': 'sound\\audio\\snd_eating.wav',
                           'data': 'snd_eating.wav', 'compressed': '0', 'streamed': '0',
                           'uncompressOnLoad': '0', 'audioGroup': '1'}.items():
            self.assertEqual(root.findtext(key), value)
        payload = (SOURCE / 'assets/sound/audio/snd_eating.wav').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), '27d5de6a73dee0cfcc2e604d2c14cf68a0a5fa88080054f8941f89807deb4cfe')
        with wave.open(io.BytesIO(payload), 'rb') as wav:
            self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()), (1, 2, 44100, 9585))
            self.assertEqual(len(wav.readframes(wav.getnframes())), 19170)

    @unittest.skipUnless(APK.is_file(), 'requires pinned APK')
    def test_sound_payload_and_selected_native_metadata(self):
        self.assertEqual(hashlib.sha256(APK.read_bytes()).hexdigest(), APK_SHA256)
        records = [x for x in recover(APK) if x[0] == 'snd_eating']
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0][1:6], ('snd_eating.wav', '.wav', 1, 80, '.wav'))
        self.assertEqual(records[0][-1], (SOURCE / 'assets/sound/audio/snd_eating.wav').read_bytes())
        with zipfile.ZipFile(APK) as z:
            data = z.read('assets/game.droid')
        chunks_ = chunks(data)
        pos = [p for p in pointers(data, chunks_[b'SOND'])
               if read_string(data, u32(data, p), chunks_[b'STRG']) == 'snd_eating']
        self.assertEqual(len(pos), 1)
        _, flags, _, _, effects, volume, pitch, group, index = struct.unpack_from('<IIIIIffII', data, pos[0])
        self.assertEqual((flags, effects, volume, pitch, group, index), (101, 0, 1.0, 0.0, 1, 80))


if __name__ == '__main__':
    unittest.main()
