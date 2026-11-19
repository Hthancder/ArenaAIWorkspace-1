import hashlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.recover_deadtown_audio import apply, chunks, extract


def chunk(name, payload):
    return name + struct.pack('<I', len(payload)) + payload


def form(*parts):
    payload = b''.join(parts)
    return b'FORM' + struct.pack('<I', len(payload)) + payload


def audio_group(payload):
    return form(chunk(b'AUDO', struct.pack('<II', 1, 24) + struct.pack('<I', len(payload)) + payload))


def make_apk(path):
    gen = chunk(b'GEN8', b'\0\x0f')
    snd_offset = 8 + len(gen)
    str_offset = snd_offset + 8 + 4 + 4 + 36 + 8
    values = [b'snd_test', b'.mp3', b'snd_test.mp3']
    strings, refs = b'', []
    for value in values:
        refs.append(str_offset + len(strings) + 4)
        strings += struct.pack('<I', len(value)) + value + b'\0'
    sound_ptr = snd_offset + 8 + 8
    sound = struct.pack('<II9I', 1, sound_ptr, refs[0], 103, refs[1], refs[2], 0, 0, 0, 1, 0)
    game = form(gen, chunk(b'SOND', sound), chunk(b'STRG', strings), chunk(b'AUDO', struct.pack('<I', 0)))
    ogg = b'OggS\x00fixture-original'
    empty_group = form(chunk(b'AUDO', struct.pack('<I', 0)))
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('assets/game.droid', game)
        z.writestr('assets/audiogroup1.dat', audio_group(ogg))
        z.writestr('assets/audiogroup2.dat', empty_group)
    return ogg


class RecoverAudioTest(unittest.TestCase):
    def test_extract_and_apply_preserves_original_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            original = make_apk(p / 'game.apk')
            result = extract(p / 'game.apk', p / 'audio')
            self.assertEqual(result[0]['file'], 'snd_test.ogg')
            self.assertEqual((p / 'audio/snd_test.ogg').read_bytes(), original)
            self.assertEqual(result[0]['sha256'], hashlib.sha256(original).hexdigest())
            project = p / 'project'
            (project / 'sound').mkdir(parents=True)
            (project / 'deadtown.project.gmx').write_text('<assets><sound>sound\\snd_test</sound></assets>')
            descriptor = project / 'sound/snd_test.sound.gmx'
            descriptor.write_text('<sound><extension>.mp3</extension><origname>x</origname><data>snd_test.mp3</data></sound>')
            self.assertEqual(apply(project, p / 'audio'), 1)
            self.assertEqual((project / 'sound/audio/snd_test.ogg').read_bytes(), original)
            self.assertIn('snd_test.ogg', descriptor.read_text())
            with self.assertRaises(ValueError):
                extract(p / 'game.apk', p / 'audio')

    def test_tampered_audio_is_rejected_before_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            make_apk(p / 'game.apk')
            extract(p / 'game.apk', p / 'audio')
            (p / 'audio/snd_test.ogg').write_bytes(b'tampered')
            project = p / 'project'
            (project / 'sound').mkdir(parents=True)
            (project / 'deadtown.project.gmx').write_text('<assets><sound>sound\\snd_test</sound></assets>')
            desc = project / 'sound/snd_test.sound.gmx'
            original = '<sound><extension>.mp3</extension><origname>x</origname><data>x</data></sound>'
            desc.write_text(original)
            with self.assertRaises(ValueError):
                apply(project, p / 'audio')
            self.assertEqual(desc.read_text(), original)

    def test_invalid_container(self):
        with self.assertRaises(ValueError):
            chunks(b'FORM\x00\x00\x00\x00junk')


if __name__ == '__main__':
    unittest.main()
