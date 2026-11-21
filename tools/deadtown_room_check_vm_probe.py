#!/usr/bin/env python3
"""Instrument a disposable VM to check the room-name candidate on transitions.

This data is incomplete and not for gameplay or packaging. The target room is
read from the APK, not reconstructed source, and its behavior is unavailable.
"""
import argparse
import json
from pathlib import Path

MARKER = 'ROOM_CHECK_VM:'


def event(events, typ):
    found = [e for e in events if e.get('object') == 'sys_global'
             and e.get('attributes', {}).get('eventtype') == typ
             and e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError(f'expected one sys_global event type {typ}')
    return found[0]


def instrument(events):
    create, step = event(events, '0'), event(events, '3')
    create['gml'] = 'global.__room_check_probe_previous = -999;\n' + create['gml']
    step['gml'] = '''if (global.__room_check_probe_previous != room)
{
    global.__room_check_probe_previous = room;
    show_debug_message("ROOM_CHECK_VM:" + room_get_name(room) + ":" + string(check_room_is_multiplay_room()));
}
''' + step['gml']
    return events


def check(log):
    markers = [line.strip()[len(MARKER):] for line in log.splitlines() if line.strip().startswith(MARKER)]
    if not markers:
        raise ValueError('no room check markers')
    parsed = []
    for marker in markers:
        name, sep, result = marker.rpartition(':')
        if not sep or not name or result not in ('0', '1') or int(result) != int(name == 'rom_play_defence'):
            raise ValueError(f'unexpected room marker: {marker}')
        parsed.append((name, int(result)))
    if not any(result == 0 for _, result in parsed) or ('rom_play_defence', 1) not in parsed:
        raise ValueError(f'missing positive or negative room case: {parsed!r}')
    return parsed


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
        print(f'{MARKER}PASS {check(args.log.read_text(errors="replace"))!r}; disposable desktop VM only')


if __name__ == '__main__':
    main()
