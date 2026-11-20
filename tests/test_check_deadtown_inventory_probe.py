import unittest
from tools.check_deadtown_inventory_probe import NAMES, check_bytecode, check_log

LOG = '''
DT_INV|ammo|0|0|0|0|0|102|203|304|405|506|0
DT_INV|get|5
DT_INV|drop|0|1|4
DT_INV|last|1|0
DT_INV|epsilon|10|1|0|1|1
DT_INV|case1|1|1|2|2|2
DT_INV|cases234|1|1|1|1|1|1|1
DT_INV|equip_first|0|0|0
DT_INV|equip_swap|1|1|1|1
DT_INV|short|0|0|1|2|3
DT_INV|craft|1|0|1|0|2
DT_INV|optional|1|0|3
DT_INV_DONE
'''


class InventoryCheckTests(unittest.TestCase):
    def test_scenarios(self):
        check_log(LOG)
        for bad in (LOG.replace('DT_INV_DONE', ''), LOG.replace('get|5', 'get|4'),
                    LOG + 'DT_INV|get|5\n', LOG.replace('short|0|0', 'short|1|0'),
                    LOG.replace('epsilon|10|1|0|1|1', 'epsilon|10|1|1|1|1'),
                    LOG.replace('|102|203|304|405|506|0', '|102|203|304|405|506|1')):
            with self.assertRaises(ValueError):
                check_log(bad)

    def test_bytecode_checks_all_four(self):
        for name in NAMES:
            old = '; probe_' + name + '_old_unlinked locals\npush.v [array]stack.target_inven\n'
            new = '; gml_Script_' + name + ' locals\ncall.i ds_map_find_value(argc=2)\ncall.i ds_map_replace(argc=3)\n'
            check_bytecode(name, old, new)
            for before, after in ((old.replace('[array]', ''), new),
                                  (old, new.replace('ds_map_replace', 'other')),
                                  (old, new + 'push.v [array]self.target_inven\n')):
                with self.assertRaises(ValueError):
                    check_bytecode(name, before, after)


if __name__ == '__main__':
    unittest.main()
