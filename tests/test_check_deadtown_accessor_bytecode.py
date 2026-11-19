import unittest
from tools.check_deadtown_accessor_bytecode import check

LEGACY = '''; probe_item_use_legacy_unlinked  locals=4 args=0 length=592 entry=00000
  00034  push.v [array]stack.target_inven
  00044  pop.i.v [array]stack.target_inven
  0005c  push.v [array]stack.target_inven
  00080  call.i ds_map_delete(argc=2)
'''
CANDIDATE = '''; gml_Script_item_use  locals=5 args=0 length=896 entry=00000
  000a8  call.i ds_map_find_value(argc=2)
  000d8  call.i ds_map_replace(argc=3)
  00108  call.i ds_map_delete(argc=2)
'''


class AccessorBytecodeTests(unittest.TestCase):
    def test_observed_bytecode(self):
        check(LEGACY, CANDIDATE)

    def test_rejects_wrong_or_changed_code(self):
        with self.assertRaisesRegex(ValueError, 'unexpected legacy'):
            check(LEGACY.replace('probe_item_use_legacy_unlinked', 'different'), CANDIDATE)
        with self.assertRaisesRegex(ValueError, 'array write'):
            check(LEGACY.replace('pop.i.v [array]', 'pop.i.v [other]'), CANDIDATE)
        with self.assertRaisesRegex(ValueError, 'no longer'):
            check(LEGACY.replace('  00080', '  00070  call.i ds_map_find_value(argc=2)\n  00080'), CANDIDATE)
        with self.assertRaisesRegex(ValueError, 'operations missing'):
            check(LEGACY, CANDIDATE.replace('ds_map_replace', 'other'))


if __name__ == '__main__':
    unittest.main()
