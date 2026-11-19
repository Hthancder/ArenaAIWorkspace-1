import base64
import tempfile
import unittest
from pathlib import Path

from tools.check_deadtown_poison_probe import check

LOG = '''
[room] -> rom_play
DT_POISON|use|3|0|1
DT_POISON|transfer|5400
DT_POISON|state|2|5399|0|80
DT_POISON|state|3|5398|0|80
DT_POISON|state|4|5397|0|80
DT_POISON|state|5|18000|0|80
DT_POISON|state|6|17999|0|80
DT_POISON|stack|1
DT_POISON|state|7|0|0|80
DT_POISON|state|8|0|1|80
DT_POISON|state|9|0|0|80
DT_POISON|save_start
DT_POISON|save_done|1
DT_POISON|load_done|1|321|2
DT_POISON|damage|11|0|100|100
DT_POISON|damage|12|1|100|50
'''
# GameMaker-style INI serialization quotes numeric values.
SAVE = b'[player]\r\nbuffpoisonprotect="321.000000"\r\nbuffpoison="2.000000"\r\n'


class PoisonLogTests(unittest.TestCase):
    def test_accepts_complete_forced_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'save'
            path.write_bytes(base64.b64encode(SAVE))
            report = check(LOG, path)
            self.assertEqual(report['save_fields'], [321, 2])
            self.assertIn('not original APK', report['limitations'])

    def test_rejects_incomplete_or_tampered_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'save'
            path.write_bytes(base64.b64encode(SAVE))
            with self.assertRaisesRegex(ValueError, 'count down'):
                check(LOG.replace('|4|5397|', '|4|5398|'), path)
            with self.assertRaisesRegex(ValueError, 'round-trip'):
                check(LOG.replace('load_done|1|321|2', 'load_done|1|0|2'), path)
            with self.assertRaisesRegex(ValueError, 'resistance skill'):
                check(LOG.replace('damage|12|1|100|50', 'damage|12|1|100|100'), path)
            with self.assertRaisesRegex(ValueError, 'damage measurements'):
                check(LOG.replace('DT_POISON|damage|11|0|100|100\n', ''), path)
            path.write_bytes(base64.b64encode(SAVE.replace(b'321.000000', b'0')))
            with self.assertRaisesRegex(ValueError, 'unexpected poison'):
                check(LOG, path)


if __name__ == '__main__':
    unittest.main()
