#!/usr/bin/env python3
"""Run the two extracted zombie3 drop branches in an isolated desktop VM.

The event fragment is copied from source, with random(1) replaced by zero for
repeatability. It runs in sys_global, not the complete zombie event; this is
not a gameplay, native Android, scheduler, or iOS test.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

EXPECTED = ['ZOMBIE_ITEM_VM:zero:0', 'ZOMBIE_ITEM_VM:fraction:1:1', 'ZOMBIE_ITEM_VM:whole:1:2']


def extract(project):
    root = ET.parse(Path(project) / 'objects/obj_zombie3.object.gmx')
    events = root.findall('./events/event[@eventtype="2"][@enumb="6"]')
    if len(events) != 1:
        raise ValueError('expected one zombie3 Alarm 6')
    text = '\n'.join(x.text or '' for x in events[0].findall('./action/arguments/argument/string'))
    begin, end = '    if item_number[ran]<1\n', '\n    \n}\n\nparticle_burst'
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError('unexpected zombie drop fragment')
    fragment = text.split(begin, 1)[1].split(end, 1)[0]
    fragment = begin + fragment
    if fragment.count('random(1)') != 1 or fragment.count('ins.__dt_item_timed = 1') != 2:
        raise ValueError('unexpected zombie drop operations')
    return fragment.replace('random(1)', '0')


def instrument(events, fragment):
    found = [e for e in events if e.get('object') == 'sys_global'
             and e.get('attributes', {}).get('eventtype') == '0'
             and e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError('expected one sys_global Create')
    prefix = '''ran = 0;
item_type[0] = 3;
item_index[0] = 0;
item_number[0] = 0;
'''+fragment+'''
show_debug_message("ZOMBIE_ITEM_VM:zero:" + string(instance_number(obj_item)));
item_number[0] = 0.5;
'''+fragment+'''
show_debug_message("ZOMBIE_ITEM_VM:fraction:" + string(ins.__dt_item_timed) + ":" + string(ins.item_number));
with (ins) instance_destroy();
item_number[0] = 2;
'''+fragment+'''
show_debug_message("ZOMBIE_ITEM_VM:whole:" + string(ins.__dt_item_timed) + ":" + string(ins.item_number));
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
        a.output.write_text(json.dumps(instrument(events, extract(a.project)), ensure_ascii=False), encoding='utf-8')
    else:
        print(f'ZOMBIE_ITEM_VM:PASS {check(a.log.read_text(errors="replace"))} markers; fragment with deterministic random, desktop VM only')


if __name__ == '__main__':
    main()
