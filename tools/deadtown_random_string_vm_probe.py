#!/usr/bin/env python3
"""Instrument a separate disposable desktop VM for a seeded random-string test.

The reference values use the pinned desktop gmrunner's WELL512 implementation;
matching them is not evidence of the Android or iOS RNG. Instrumentation resets
RNG state and therefore must not be used as a normal gameplay diagnostic.
"""
import argparse
import json
from pathlib import Path

# Derived from the pinned gmrunner's Random.h / Core.cpp, independently running
# 20 iterations of three irandom_range draws followed by one choose draw.
EXPECTED = {
    1: ('7k7GO6WVSn64xqAtj0GE', 116),
    42: ('3RFz6tZGXk9Bl7XNtBh0', 220),
    12345: ('0cLQ8ne301Vnlz67yuP8', 80),
    -1: ('e4n3H243e95EF91v9Am8', 127),
}
MARKER = 'RANDOM_STRING_VM:'


def instrument(events):
    found = [e for e in events if e.get('object') == 'sys_global'
             and e.get('attributes', {}).get('eventtype') == '0'
             and e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError('expected exactly one sys_global Create')
    lines = ['var probe_string, probe_next;']
    for seed in EXPECTED:
        lines += [f'random_set_seed({seed});', 'probe_string = generate_random_string();',
                  'probe_next = irandom_range(0, 255);',
                  f'show_debug_message("{MARKER}{seed}:" + probe_string + ":" + string(probe_next));']
    found[0]['gml'] = '\n'.join(lines) + '\n' + found[0]['gml']
    return events


def check(log):
    expected = [f'{MARKER}{seed}:{value}:{n}' for seed, (value, n) in EXPECTED.items()]
    observed = [line.strip() for line in log.splitlines() if line.strip().startswith(MARKER)]
    if observed != expected:
        raise ValueError(f'VM markers differ: expected {expected!r}, observed {observed!r}')
    return len(observed)


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
        print(f'{MARKER}PASS {check(args.log.read_text(errors="replace"))} seeds, disposable desktop VM only')


if __name__ == '__main__':
    main()
