#!/usr/bin/env python3
"""Isolated desktop VM check of six linked-light Destroy candidates.

Create is replaced for all test objects and light; full gameplay is not run.
"""
import argparse
import json
from pathlib import Path

try:
    from tools.deadtown_light_cleanup_evidence import TARGETS, candidate, verify_source
    from tools.deadtown_item_schedule_vm_probe import find
except ModuleNotFoundError:
    from deadtown_light_cleanup_evidence import TARGETS, candidate, verify_source
    from deadtown_item_schedule_vm_probe import find

PREFIX = 'LIGHT_CLEANUP_VM:'
EXPECTED = [PREFIX+name+':1:0' for name in TARGETS]


def instrument(events, project):
    verify_source(project)
    find(events, 'obj_light', '0', '0')['gml'] = '/// Isolated dummy light.\n'
    lines = ['/// Isolated linked-light Destroy test; not gameplay.']
    for name, row in TARGETS.items():
        variable = row[0]
        find(events, name, '0', '0')['gml'] = variable+' = noone;\n'
        destroy = find(events, name, '1', '0')
        if candidate(variable).strip() not in destroy['gml']:
            raise ValueError('unexpected Destroy event: '+name)
        lines.extend([
            'global.__dt_cleanup_light = instance_create(0, 0, obj_light);',
            f'global.__dt_cleanup_owner = instance_create(0, 0, {name});',
            f'with (global.__dt_cleanup_owner) {variable} = global.__dt_cleanup_light;',
            'global.__dt_cleanup_before = instance_exists(global.__dt_cleanup_light);',
            'with (global.__dt_cleanup_owner) instance_destroy();',
            f'show_debug_message("{PREFIX}{name}:" + string(global.__dt_cleanup_before) + ":" + string(instance_exists(global.__dt_cleanup_light)));',
            # Also exercise missing light reference without a crash.
            f'global.__dt_cleanup_owner = instance_create(0, 0, {name});',
            'with (global.__dt_cleanup_owner) instance_destroy();',
        ])
    create = find(events, 'sys_global', '0', '0')
    create['gml'] = '\n'.join(lines)+'\n'+create['gml']
    return events


def check(log):
    lines = [line.strip() for line in log.splitlines() if line.strip().startswith(PREFIX)]
    if lines != EXPECTED:
        raise ValueError(f'unexpected linked-light markers: {lines!r}')
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
        print('LIGHT_CLEANUP_VM:PASS '+str(check(args.log.read_text(errors='replace')))+' isolated events; desktop only')


if __name__ == '__main__':
    main()
