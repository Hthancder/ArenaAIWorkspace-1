#!/usr/bin/env python3
"""Instrument a disposable VM to probe a partial timed-item event candidate.

This calls the Alarm 0 event manually; it does not test 900-frame scheduling,
parcel execution, original Android/iOS, or the still-missing Alarm 1 behavior.
"""
import argparse
import json
from pathlib import Path

EXPECTED = ['ITEM_LIFETIME_VM:init:0:900', 'ITEM_LIFETIME_VM:alive:1:1:0']


def instrument(events):
    found = [e for e in events if e.get('object') == 'sys_global'
             and e.get('attributes', {}).get('eventtype') == '0'
             and e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError('expected one sys_global Create')
    prefix = '''var life_a, life_b, life_c;
life_a = instance_create(0, 0, obj_item);
life_b = instance_create(0, 0, obj_item);
life_c = instance_create(0, 0, obj_item);
with (life_a) show_debug_message("ITEM_LIFETIME_VM:init:" + string(__dt_item_timed) + ":" + string(alarm[0]));
with (life_b) __dt_item_timed = 0.5;
with (life_c) __dt_item_timed = 1;
with (life_a) event_perform(2, 0);
with (life_b) event_perform(2, 0);
with (life_c) event_perform(2, 0);
show_debug_message("ITEM_LIFETIME_VM:alive:" + string(instance_exists(life_a)) + ":" + string(instance_exists(life_b)) + ":" + string(instance_exists(life_c)));
with (life_a) instance_destroy();
with (life_b) instance_destroy();
'''
    found[0]['gml'] = prefix + found[0]['gml']
    return events


def check(log):
    lines = [s.strip() for s in log.splitlines() if s.strip().startswith('ITEM_LIFETIME_VM:')]
    if lines != EXPECTED:
        raise ValueError(f'unexpected item-lifetime markers: {lines!r}')
    return len(lines)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='mode', required=True)
    i = sub.add_parser('instrument')
    i.add_argument('input', type=Path)
    i.add_argument('output', type=Path)
    c = sub.add_parser('check')
    c.add_argument('log', type=Path)
    args = p.parse_args()
    if args.mode == 'instrument':
        if args.input.resolve() == args.output.resolve() or args.output.exists():
            raise ValueError('output must be new and distinct from input')
        events = json.loads(args.input.read_text(encoding='utf-8'))
        args.output.write_text(json.dumps(instrument(events), ensure_ascii=False), encoding='utf-8')
    else:
        print(f'ITEM_LIFETIME_VM:PASS {check(args.log.read_text(errors="replace"))} markers; manual event, desktop VM only')


if __name__ == '__main__':
    main()
