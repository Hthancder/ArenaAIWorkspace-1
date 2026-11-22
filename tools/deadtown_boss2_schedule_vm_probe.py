#!/usr/bin/env python3
"""Test the boss candidate's Alarm 0 scheduling in an isolated desktop VM.

This deliberately replaces Create/Step with fragments, forces choose to 1,
keeps the test instance persistent, and executes the real source Alarm event.
It is not original gameplay or an Android/iOS timing test.
"""
import argparse
import json
from pathlib import Path

try:
    from tools.deadtown_boss2_turn_evidence import fragments
    from tools.deadtown_item_schedule_vm_probe import find
except ModuleNotFoundError:
    from deadtown_boss2_turn_evidence import fragments
    from deadtown_item_schedule_vm_probe import find

PREFIX = 'BOSS2_SCHEDULE_VM:'


def instrument(events, project):
    init, _, alarm = fragments(project)
    boss_create = find(events, 'obj_boss2_ten', '0', '0')
    boss_step = find(events, 'obj_boss2_ten', '3', '0')
    boss_alarm = find(events, 'obj_boss2_ten', '2', '0')
    if alarm.strip() not in boss_alarm['gml']:
        raise ValueError('unexpected boss alarm event')
    boss_create['gml'] = 'persistent = true;\n' + init.replace('choose(1,0,0)', '1')
    boss_step['gml'] = '/// Isolated scheduler: no boss movement.\n'
    create = find(events, 'sys_global', '0', '0')
    step = find(events, 'sys_global', '3', '0')
    create['gml'] = '''global.__dt_boss_tick = 0; global.__dt_boss_reported = 0;
global.__dt_boss_last_alarm = -999; global.__dt_boss_flag = -999;
global.__dt_boss_instance = instance_create(0, 0, obj_boss2_ten);
with (global.__dt_boss_instance) { global.__dt_boss_flag = __dt_reverse_turn; global.__dt_boss_alarm = alarm[0]; }
show_debug_message("BOSS2_SCHEDULE_VM:init:" + string(global.__dt_boss_flag) + ":" + string(global.__dt_boss_alarm));
''' + create['gml']
    step['gml'] = '''global.__dt_boss_tick += 1;
if (!global.__dt_boss_reported && instance_exists(global.__dt_boss_instance))
{
    with (global.__dt_boss_instance) { global.__dt_boss_flag = __dt_reverse_turn; global.__dt_boss_alarm = alarm[0]; }
    if (global.__dt_boss_flag == 0)
    {
        global.__dt_boss_reported = 1;
        show_debug_message("BOSS2_SCHEDULE_VM:expired:" + string(global.__dt_boss_tick) + ":" + string(global.__dt_boss_last_alarm) + ":" + string(global.__dt_boss_alarm));
        with (global.__dt_boss_instance) instance_destroy();
    }
    else global.__dt_boss_last_alarm = global.__dt_boss_alarm;
}
''' + step['gml']
    return events


def check(log):
    lines = [s.strip() for s in log.splitlines() if s.strip().startswith(PREFIX)]
    if len(lines) != 2 or lines[0] != PREFIX+'init:1:20':
        raise ValueError(f'unexpected boss scheduling markers: {lines!r}')
    parts = lines[1].split(':')
    if len(parts) != 5 or parts[:2] != ['BOSS2_SCHEDULE_VM', 'expired']:
        raise ValueError('missing boss expiration marker')
    try:
        tick, last, current = map(int, parts[2:])
    except ValueError as exc:
        raise ValueError('non-integer boss scheduling marker') from exc
    # Some VM implementations expose zero for the remainder of the firing
    # frame and reset to -1 later; accept either while requiring the flag reset.
    if tick not in (19, 20, 21) or last != 1 or current not in (0, -1):
        raise ValueError(f'unexpected boss scheduling result: {lines[1]}')
    return {'expiration_step': tick, 'last_observed_alarm': last, 'current_alarm': current}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='mode', required=True)
    i = sub.add_parser('instrument')
    i.add_argument('project', type=Path)
    i.add_argument('input', type=Path)
    i.add_argument('output', type=Path)
    c = sub.add_parser('check')
    c.add_argument('log', type=Path)
    a = p.parse_args()
    if a.mode == 'instrument':
        if a.output.exists() or a.output.resolve() == a.input.resolve():
            raise ValueError('output must be new and distinct from input')
        events = json.loads(a.input.read_text(encoding='utf-8'))
        a.output.write_text(json.dumps(instrument(events, a.project), ensure_ascii=False), encoding='utf-8')
    else:
        print('BOSS2_SCHEDULE_VM:PASS ' + json.dumps(check(a.log.read_text(errors='replace'))) + '; isolated desktop VM only')


if __name__ == '__main__':
    main()
