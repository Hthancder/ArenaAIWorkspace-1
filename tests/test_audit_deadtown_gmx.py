import tempfile
import unittest
from pathlib import Path

from tools.audit_deadtown_gmx import audit


class DeadTownAuditTest(unittest.TestCase):
    def test_missing_font_atlas_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / 'fonts').mkdir()
            (p / 'fonts/font_24.font.gmx').write_text('<font><image>font_24.png</image></font>')
            (p / 'deadtown.project.gmx').write_text('<assets><font>fonts\\font_24</font></assets>')
            totals, missing = audit(p)
            self.assertEqual(totals['font_data'], 1)
            self.assertEqual(missing, [('font_data', 'fonts/font_24.png')])
            (p / 'fonts/font_24.png').write_bytes(b'present')
            self.assertFalse(audit(p)[1])

    def test_resource_and_asset_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / 'scripts').mkdir()
            (p / 'sound').mkdir()
            (p / 'scripts' / 'hello.gml').write_text('')
            (p / 'sound' / 'click.sound.gmx').write_text('<sound><data>click.wav</data></sound>')
            (p / 'deadtown.project.gmx').write_text(
                '<assets><script>scripts\\hello.gml</script>'
                '<sound>sound\\click</sound>'
                '<extension>extensions\\ads</extension></assets>')
            totals, missing = audit(p)
            self.assertEqual(totals['script'], 1)
            self.assertEqual(missing, [('sound_data', 'sound/audio/click.wav'),
                                       ('extension', 'extensions/ads.extension.gmx')])


if __name__ == '__main__':
    unittest.main()
