#!/usr/bin/env python3
"""Probe the candidate item's alarm scheduling in a disposable desktop VM.

This replaces obj_item Step with a no-op to avoid pickup/motion side effects.
It is not original gameplay, a native Android comparison, or iOS validation.
"""
import argparse
import json
from pathlib import Path

PREFIX = 'ITEM_SCHEDULE_VM:'


def find(events, obj, typ, sub):
    found = [e for e in events if e.get('object') == obj
             and e.get('attributes', {}).get('eventtype') == typ
             and e.get('attributes', {}).get('enumb') == sub]
    if len(found) != 1:
        raise ValueError(f'expected one {obj} event {typ}:{sub}')
    return found[0]


def instrument(events):
    create = find(events, 'sys_global', '0', '0')
    step = find(events, 'sys_global', '3', '0')
    item_step = find(events, 'obj_item', '3', '0')
    # Leave item Create and Alarm 0 unchanged, but deliberately suppress Step.
    item_step['gml'] = '/// Disposable alarm scheduling probe: suppress item Step.\n'
    create['gml'] = '''global.__dt_schedule_tick = 0;
global.__dt_schedule_last_alarm = -999;
global.__dt_schedule_reported = 0;
global.__dt_schedule_timed = instance_create(0, 0, obj_item);
global.__dt_schedule_untimed = instance_create(0, 0, obj_item);
with (global.__dt_schedule_timed) { __dt_item_timed = 1; global.__dt_schedule_init_timed = alarm[0]; }
with (global.__dt_schedule_untimed) global.__dt_schedule_init_untimed = alarm[0];
show_debug_message("ITEM_SCHEDULE_VM:init:" + string(global.__dt_schedule_init_timed) + ":" + string(global.__dt_schedule_init_untimed));
''' + create['gml']
    step['gml'] = '''global.__dt_schedule_tick += 1;
if (!global.__dt_schedule_reported)
{
    if (instance_exists(global.__dt_schedule_timed))
    {
        with (global.__dt_schedule_timed) global.__dt_schedule_last_alarm = alarm[0];
    }
    else
    {
        global.__dt_schedule_reported = 1;
        show_debug_message("ITEM_SCHEDULE_VM:expired:" + string(global.__dt_schedule_tick) + ":" + string(global.__dt_schedule_last_alarm) + ":" + string(instance_exists(global.__dt_schedule_untimed)));
    }
}
if (global.__dt_schedule_tick == 905)
{
    global.__dt_schedule_final_alarm = -999;
    with (global.__dt_schedule_untimed) global.__dt_schedule_final_alarm = alarm[0];
    show_debug_message("ITEM_SCHEDULE_VM:after:" + string(instance_exists(global.__dt_schedule_timed)) + ":" + string(instance_exists(global.__dt_schedule_untimed)) + ":" + string(global.__dt_schedule_final_alarm));
    with (global.__dt_schedule_untimed) instance_destroy();
}
''' + step['gml']
    return events


def check(log):
    lines = [s.strip() for s in log.splitlines() if s.strip().startswith(PREFIX)]
    if len(lines) != 3 or lines[0] != PREFIX+'init:900:900' or lines[2] != PREFIX+'after:0:1:-1':
        raise ValueError(f'unexpected schedule markers: {lines!r}')
    parts = lines[1].split(':')
    if len(parts) != 5 or parts[:2] != ['ITEM_SCHEDULE_VM', 'expired']:
        raise ValueError('missing expiration marker')
    try:
        tick, last, other_alive = map(int, parts[2:])
    except ValueError as exc:
        raise ValueError('non-integer scheduling marker') from exc
    # One-step tolerance for event ordering, while also requiring last=1.
    if tick not in (899, 900, 901) or last != 1 or other_alive != 1:
        raise ValueError(f'unexpected scheduling result: {lines[1]}')
    return {'expiration_step': tick, 'last_observed_alarm': last}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='mode', required=True)
    i = sub.add_parser('instrument')
    i.add_argument('input', type=Path)
    i.add_argument('output', type=Path)
    c = sub.add_parser('check')
    c.add_argument('log', type=Path)
    a = p.parse_args()
    if a.mode == 'instrument':
        if a.output.exists() or a.output.resolve() == a.input.resolve():
            raise ValueError('output must be new and distinct from input')
        events = json.loads(a.input.read_text(encoding='utf-8'))
        a.output.write_text(json.dumps(instrument(events), ensure_ascii=False), encoding='utf-8')
    else:
        print('ITEM_SCHEDULE_VM:PASS ' + json.dumps(check(a.log.read_text(errors='replace'))) + '; isolated desktop VM only')


if __name__ == '__main__':
    main()
