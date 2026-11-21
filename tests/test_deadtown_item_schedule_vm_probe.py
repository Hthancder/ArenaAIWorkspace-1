import unittest

from tools.deadtown_item_schedule_vm_probe import check, instrument


def event(obj, typ, text):
    return {'object': obj, 'attributes': {'eventtype': typ, 'enumb': '0'}, 'gml': text}


class ItemScheduleProbeTests(unittest.TestCase):
    def test_instrumentation_is_isolated(self):
        events = [event('sys_global', '0', 'original_create();'),
                  event('sys_global', '3', 'original_step();'),
                  event('obj_item', '3', 'item_step();'),
                  event('obj_item', '2', 'item_alarm();')]
        instrument(events)
        self.assertTrue(events[0]['gml'].endswith('original_create();'))
        self.assertTrue(events[1]['gml'].endswith('original_step();'))
        self.assertNotIn('item_step();', events[2]['gml'])
        self.assertEqual(events[3]['gml'], 'item_alarm();')
        with self.assertRaises(ValueError):
            instrument([])

    def test_positive_and_negative_markers(self):
        good = ('ITEM_SCHEDULE_VM:init:900:900\n'
                'ITEM_SCHEDULE_VM:expired:900:1:1\n'
                'ITEM_SCHEDULE_VM:after:0:1:-1\n')
        self.assertEqual(check(good)['expiration_step'], 900)
        for bad in (good.replace('expired:900', 'expired:700'),
                    good.replace('expired:900:1:1', 'expired:900:2:1'),
                    good.replace('after:0:1:-1', 'after:0:0:-1'),
                    good + good):
            with self.assertRaises(ValueError):
                check(bad)


if __name__ == '__main__':
    unittest.main()
