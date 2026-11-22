from pathlib import Path
import unittest

from tools.deadtown_boss2_schedule_vm_probe import instrument, check
from tools.deadtown_boss2_turn_evidence import ALARM

PROJECT = Path(__file__).resolve().parents[1]/'deadtown-source/project'


def event(obj, typ, sub, text='original();'):
    return {'object': obj, 'attributes': {'eventtype': typ, 'enumb': sub}, 'gml': text}


class BossScheduleTests(unittest.TestCase):
    def events(self):
        return [event('obj_boss2_ten', '0', '0'), event('obj_boss2_ten', '3', '0'),
                event('obj_boss2_ten', '2', '0', '{\n'+ALARM+'\n}'),
                event('sys_global', '0', '0'), event('sys_global', '3', '0')]

    def test_instrument_and_reject_missing_alarm(self):
        events = instrument(self.events(), PROJECT)
        self.assertIn('persistent = true', events[0]['gml'])
        self.assertIn('if (1 > 0.5)', events[0]['gml'])
        self.assertNotIn('choose(', events[0]['gml'])
        self.assertIn('no boss movement', events[1]['gml'])
        self.assertEqual(events[2]['gml'], '{\n'+ALARM+'\n}')
        self.assertIn('BOSS2_SCHEDULE_VM:init:', events[3]['gml'])
        self.assertIn('BOSS2_SCHEDULE_VM:expired:', events[4]['gml'])
        bad = self.events()
        bad[2]['gml'] = 'other();'
        with self.assertRaisesRegex(ValueError, 'unexpected boss alarm'):
            instrument(bad, PROJECT)
        with self.assertRaises(ValueError):
            instrument(self.events()[1:], PROJECT)

    def test_markers_and_rejections(self):
        text = 'BOSS2_SCHEDULE_VM:init:1:20\nBOSS2_SCHEDULE_VM:expired:20:1:-1\n'
        self.assertEqual(check(text)['expiration_step'], 20)
        self.assertEqual(check(text.replace(':20:1:-1', ':20:1:0'))['current_alarm'], 0)
        for mutation in (text.replace(':20:1:-1', ':18:1:-1'),
                         text.replace('init:1:20', 'init:0:20'),
                         text.replace(':20:1:-1', ':20:2:-1'), text+'BOSS2_SCHEDULE_VM:init:1:20\n'):
            with self.assertRaises(ValueError):
                check(mutation)


if __name__ == '__main__':
    unittest.main()
