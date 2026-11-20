import base64
import tempfile
import unittest
from pathlib import Path

from tools.check_deadtown_inventory_save import check, parse_numeric_gmrm

LOG = '''
DT_INVENTORY_SAVE|loaded|11|22|33|44
DT_INVENTORY_SAVE|cleared|0|0|0|0
'''
SAVE = b'''[inventory]
weapon="GMRM1;r0;r11;"
equip="GMRM1;r0;r22;"
use="GMRM1;r0;r33;"
etc="GMRM1;r0;r44;"
'''


class InventorySaveCheckTests(unittest.TestCase):
    def test_numeric_maps_and_validation(self):
        self.assertEqual(parse_numeric_gmrm(b'GMRM2;r0;r11;r17;r1.5;'), {0: 11, 17: 1.5})
        for bad in (b'wrong', b'GMRM;', b'GMRM10001;', b'GMRM1;r0;', b'GMRM1;r0;rnan;',
                    b'GMRM1;s1:ar1;', b'GMRM1;r0;r1;trailing', b'GMRM2;r0;r1;r0;r2;'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                parse_numeric_gmrm(bad)

    def test_roundtrip_check_and_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'probe.sav'
            path.write_bytes(base64.b64encode(SAVE))
            self.assertEqual(check(LOG, path), 4)
            with self.assertRaisesRegex(ValueError, 'marker'):
                check(LOG.replace('cleared|0|0|0|0', 'cleared|0|1|0|0'), path)
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                check(LOG + 'DT_INVENTORY_SAVE|loaded|11|22|33|44\n', path)
            path.write_bytes(base64.b64encode(SAVE.replace(b'r33;', b'r34;')))
            with self.assertRaisesRegex(ValueError, 'inventory'):
                check(LOG, path)
            path.write_bytes(b'!invalid!')
            with self.assertRaisesRegex(ValueError, 'invalid disposable'):
                check(LOG, path)


if __name__ == '__main__':
    unittest.main()
