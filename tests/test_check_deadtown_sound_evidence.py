from pathlib import Path
import tempfile
import unittest

from tools.check_deadtown_sound_evidence import native_metadata, safe_asset, verify
from tools.materialize_deadtown_source import materialize

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
UPSTREAM = ROOT / '.cache/gmx/deadtown.gmx'
SOURCE = ROOT / 'deadtown-source'


class SoundEvidenceTests(unittest.TestCase):
    def test_rejects_bad_inputs(self):
        with self.assertRaises(ValueError):
            native_metadata(b'invalid')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'file').write_bytes(b'fake')
            (root / 'link').symlink_to(root / 'file')
            with self.assertRaisesRegex(ValueError, 'symlink'):
                safe_asset(root, Path('link'))
            with self.assertRaisesRegex(ValueError, 'unsafe'):
                safe_asset(root, Path('../file'))
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                verify(root / 'file', root)

    @unittest.skipUnless(APK.is_file() and UPSTREAM.is_dir(), 'requires pinned APK and GMX')
    def test_all_payloads_and_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'work'
            materialize(UPSTREAM, APK, SOURCE, out)
            project = out / 'project'
            report = verify(APK, project)
            self.assertEqual(report['sound_count'], 90)
            self.assertEqual(report['sound_groups'], {'0': 2, '1': 86, '2': 2})
            self.assertEqual(report['native_flags'], {'101': 3, '103': 87})
            path = project / 'sound/audio/snd_eating.wav'
            content = path.read_bytes()
            path.write_bytes(content + b'bad')
            with self.assertRaisesRegex(ValueError, 'payload differs: snd_eating'):
                verify(APK, project)
            path.write_bytes(content)
            descriptor = project / 'sound/snd_eating.sound.gmx'
            text = descriptor.read_text()
            descriptor.write_text(text.replace('<audioGroup>1</audioGroup>', '<audioGroup>2</audioGroup>'))
            with self.assertRaisesRegex(ValueError, 'metadata differs: snd_eating'):
                verify(APK, project)
            descriptor.write_text(text.replace('<compressed>0</compressed>', '<compressed>1</compressed>'))
            with self.assertRaisesRegex(ValueError, 'candidate audio options'):
                verify(APK, project)


if __name__ == '__main__':
    unittest.main()
