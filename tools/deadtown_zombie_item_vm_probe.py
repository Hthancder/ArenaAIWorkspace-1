#!/usr/bin/env python3
"""Run extracted zombie2/3/4/5 drop branches in an isolated desktop VM.

The event fragment is copied from source, with random(1) replaced by zero for
repeatability. It runs in sys_global, not the complete zombie event; this is
not a gameplay, native Android, scheduler, or iOS test.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ZOMBIES = ('zombie2', 'zombie3', 'zombie4', 'zombie5')
EXPECTED = [f'ZOMBIE_ITEM_VM:{obj}:{case}' for obj in ZOMBIES
            for case in ('zero:0', 'fraction:1:1', 'whole:1:2')]


def extract(project, obj):
    config = {'zombie2': ('3', '0', 8), 'zombie3': ('2', '6', 4),
              'zombie4': ('3', '0', 8), 'zombie5': ('3', '0', 8)}
    if obj not in config:
        raise ValueError('unsupported zombie')
    typ, sub, indent = config[obj]
    root = ET.parse(Path(project) / 'objects' / ('obj_' + obj + '.object.gmx'))
    events = root.findall(f'./events/event[@eventtype="{typ}"][@enumb="{sub}"]')
    if len(events) != 1:
        raise ValueError('expected one zombie event: ' + obj)
    text = '\n'.join(x.text or '' for x in events[0].findall('./action/arguments/argument/string'))
    begin = ' ' * indent + 'if item_number[ran]<1\n'
    end = '\n' + ' ' * indent + '\n' + ' ' * (indent-4) + '}\n' + ('\n' if indent == 4 else '    \n    ') + 'particle_burst'
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError('unexpected zombie drop fragment')
    fragment = text.split(begin, 1)[1].split(end, 1)[0]
    fragment = begin + fragment
    if fragment.count('random(1)') != 1 or fragment.count('ins.__dt_item_timed = 1') != 2:
        raise ValueError('unexpected zombie drop operations')
    return fragment.replace('random(1)', '0')


def instrument(events, fragments):
    found = [e for e in events if e.get('object') == 'sys_global'
             and e.get('attributes', {}).get('eventtype') == '0'
             and e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError('expected one sys_global Create')
    if set(fragments) != set(ZOMBIES):
        raise ValueError('expected all four zombie fragments')
    prefix = ''
    for obj in ZOMBIES:
        fragment = fragments[obj]
        prefix += '''ran = 0;
item_type[0] = 3;
item_index[0] = 0;
item_number[0] = 0;
'''+fragment+f'''
show_debug_message("ZOMBIE_ITEM_VM:{obj}:zero:" + string(instance_number(obj_item)));
item_number[0] = 0.5;
'''+fragment+f'''
show_debug_message("ZOMBIE_ITEM_VM:{obj}:fraction:" + string(ins.__dt_item_timed) + ":" + string(ins.item_number));
with (ins) instance_destroy();
item_number[0] = 2;
'''+fragment+f'''
show_debug_message("ZOMBIE_ITEM_VM:{obj}:whole:" + string(ins.__dt_item_timed) + ":" + string(ins.item_number));
with (ins) instance_destroy();
'''
    found[0]['gml'] = prefix + found[0]['gml']
    return events


def check(log):
    markers = [s.strip() for s in log.splitlines() if s.strip().startswith('ZOMBIE_ITEM_VM:')]
    if markers != EXPECTED:
        raise ValueError(f'unexpected zombie item markers: {markers!r}')
    return len(markers)


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
        fragments = {obj: extract(a.project, obj) for obj in ZOMBIES}
        a.output.write_text(json.dumps(instrument(events, fragments), ensure_ascii=False), encoding='utf-8')
    else:
        print(f'ZOMBIE_ITEM_VM:PASS {check(a.log.read_text(errors="replace"))} markers; fragment with deterministic random, desktop VM only')


if __name__ == '__main__':
    main()
