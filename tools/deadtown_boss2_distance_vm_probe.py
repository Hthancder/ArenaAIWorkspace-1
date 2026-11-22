#!/usr/bin/env python3
"""Exercise the boss End Step distance candidate in an isolated desktop VM.

Player and boss Create/Step/Destroy behavior is replaced. This is not gameplay.
"""
import argparse
import json
from pathlib import Path

try:
    from tools.deadtown_boss2_distance_evidence import CANDIDATE, verify_source
    from tools.deadtown_item_schedule_vm_probe import find
except ModuleNotFoundError:
    from deadtown_boss2_distance_evidence import CANDIDATE, verify_source
    from deadtown_item_schedule_vm_probe import find

MARKER = 'BOSS2_DISTANCE_VM:1:1:0'


def instrument(events, project):
    verify_source(project)
    for obj, types in (('obj_player', [('0','0'), ('1','0'), ('3','0'), ('3','1'), ('3','2')]),
                       ('obj_boss2', [('0','0'), ('1','0'), ('3','0')])):
        for typ, sub in types:
            find(events, obj, typ, sub)['gml'] = '/// Isolated distance probe: disabled.\n'
    end = find(events, 'obj_boss2', '3', '2')
    if CANDIDATE.strip() not in end['gml']:
        raise ValueError('unexpected boss End Step')
    create = find(events, 'sys_global', '0', '0')
    create['gml'] = '''global.__dt_distance_tick = 0;
global.__dt_distance_player = instance_create(0, 0, obj_player);
with (global.__dt_distance_player) persistent = true;
global.__dt_distance_near = instance_create(7999, 0, obj_boss2);
global.__dt_distance_edge = instance_create(8000, 0, obj_boss2);
global.__dt_distance_far = instance_create(8001, 0, obj_boss2);
with (global.__dt_distance_near) persistent = true;
with (global.__dt_distance_edge) persistent = true;
with (global.__dt_distance_far) persistent = true;
''' + create['gml']
    step = find(events, 'sys_global', '3', '0')
    step['gml'] = '''global.__dt_distance_tick += 1;
if (global.__dt_distance_tick == 2)
{
    show_debug_message("BOSS2_DISTANCE_VM:" + string(instance_exists(global.__dt_distance_near)) + ":" + string(instance_exists(global.__dt_distance_edge)) + ":" + string(instance_exists(global.__dt_distance_far)));
    with (global.__dt_distance_near) instance_destroy();
    with (global.__dt_distance_edge) instance_destroy();
    with (global.__dt_distance_far) instance_destroy();
    with (global.__dt_distance_player) instance_destroy();
}
''' + step['gml']
    return events


def check(log):
    lines = [line.strip() for line in log.splitlines() if line.strip().startswith('BOSS2_DISTANCE_VM:')]
    if lines != [MARKER]:
        raise ValueError(f'unexpected boss distance markers: {lines!r}')
    return len(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    i = sub.add_parser('instrument')
    i.add_argument('project', type=Path)
    i.add_argument('input', type=Path)
    i.add_argument('output', type=Path)
    c = sub.add_parser('check')
    c.add_argument('log', type=Path)
    args = parser.parse_args()
    if args.mode == 'instrument':
        if args.output.exists() or args.input.resolve() == args.output.resolve():
            raise ValueError('output must be new and distinct from input')
        events = json.loads(args.input.read_text(encoding='utf-8'))
        args.output.write_text(json.dumps(instrument(events, args.project), ensure_ascii=False), encoding='utf-8')
    else:
        print('BOSS2_DISTANCE_VM:PASS '+str(check(args.log.read_text(errors='replace'))) + ' marker; isolated desktop only')


if __name__ == '__main__':
    main()
