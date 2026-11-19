import tempfile
import unittest
from pathlib import Path

from tools.stage_deadtown_gmx import stage


class StageDeadTownTest(unittest.TestCase):
    def test_stage_preserves_source_and_copies_exact_audio(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, output, audio = root / 'source', root / 'output', root / 'audio'
            (source / 'sound').mkdir(parents=True)
            audio.mkdir()
            (source / 'deadtown.project.gmx').write_text('<assets><sound>sound\\click</sound></assets>')
            (source / 'sound' / 'click.sound.gmx').write_text('<sound><data>click.wav</data></sound>')
            (audio / 'click.wav').write_bytes(b'original bytes')
            copied, _, missing = stage(source, output, audio)
            self.assertEqual(copied, 1)
            self.assertEqual(missing, [])
            self.assertEqual((output / 'sound/audio/click.wav').read_bytes(), b'original bytes')
            self.assertFalse((source / 'sound/audio').exists())
            with self.assertRaises(ValueError):
                stage(source, output, audio)

    def test_rejects_nested_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)
            (source / 'deadtown.project.gmx').write_text('<assets/>')
            with self.assertRaises(ValueError):
                stage(source, source / 'copy')


if __name__ == '__main__':
    unittest.main()
