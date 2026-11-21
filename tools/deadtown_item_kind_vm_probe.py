#!/usr/bin/env python3
"""Instrument disposable VM boot to test candidate scripts on integer indices.

Never modify source or package instrumented data. This is a desktop runner probe,
not Android execution, a GameMaker build, or a test of iOS/gameplay.
"""
import argparse
import json
from pathlib import Path

try:
    from tools.deadtown_item_kind_evidence import RANGES
except ModuleNotFoundError:
    from deadtown_item_kind_evidence import RANGES

MARKER = 'ITEM_KIND_VM:'


def cases():
    return [(name, value, int(low <= value <= high))
            for name, (low, high) in RANGES.items()
            for value in range(low - 2, high + 3)]


def instrument(events):
    matches = [e for e in events if e.get('object') == 'sys_global'
               and e.get('attributes', {}).get('eventtype') == '0'
               and e.get('attributes', {}).get('enumb') == '0']
    if len(matches) != 1:
        raise ValueError('expected exactly one sys_global Create')
    lines = [f'show_debug_message("{MARKER}{name}:{value}:" + string({name}({value})));'
             for name, value, _ in cases()]
    matches[0]['gml'] = '\n'.join(lines) + '\n' + matches[0]['gml']
    return events


def check(log):
    expected = [f'{MARKER}{name}:{value}:{answer}' for name, value, answer in cases()]
    observed = [line.strip() for line in log.splitlines() if line.strip().startswith(MARKER)]
    if observed != expected:
        raise ValueError(f'VM markers differ: expected {expected!r}, observed {observed!r}')
    return len(observed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    p = sub.add_parser('instrument')
    p.add_argument('input', type=Path)
    p.add_argument('output', type=Path)
    p = sub.add_parser('check')
    p.add_argument('log', type=Path)
    args = parser.parse_args()
    if args.mode == 'instrument':
        if args.input.resolve() == args.output.resolve() or args.output.exists():
            raise ValueError('output must be a new file, distinct from input')
        events = json.loads(args.input.read_text(encoding='utf-8'))
        args.output.write_text(json.dumps(instrument(events), ensure_ascii=False), encoding='utf-8')
    else:
        print(f'{MARKER}PASS {check(args.log.read_text(errors="replace"))} integer cases, disposable desktop VM only')


if __name__ == '__main__':
    main()
