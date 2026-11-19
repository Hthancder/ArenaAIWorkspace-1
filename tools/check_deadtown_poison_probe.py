#!/usr/bin/env python3
"""Check a forced, disposable desktop candidate probe; not APK equivalence."""
import argparse
import base64
import configparser
import math
from pathlib import Path
import sys

MARKER = 'DT_POISON|'


def check(log, save_file):
    records = {}
    for line in log.splitlines():
        pos = line.find(MARKER)
        if pos < 0:
            continue
        fields = line[pos:].strip().split('|')
        kind = fields[1]
        records.setdefault(kind, []).append(fields[2:])

    def one(kind, length):
        found = records.get(kind, [])
        if len(found) != 1 or len(found[0]) != length:
            raise ValueError(f'expected exactly one {kind} record of {length} fields')
        return found[0]

    def numbers(fields):
        try:
            result = [float(x) for x in fields]
        except ValueError as exc:
            raise ValueError('probe log contains a non-numeric field') from exc
        if any(not math.isfinite(value) for value in result):
            raise ValueError('probe log contains a non-finite number')
        return result

    if numbers(one('use', 3)) != [3, 0, 1]:
        raise ValueError('candidate mask database, consumption or player count mismatch')
    if [numbers(row) for row in records.get('transfer', [])] != [[5400]]:
        raise ValueError('candidate buff transfer did not happen exactly once')
    states = {}
    for fields in records.get('state', []):
        if len(fields) != 4:
            raise ValueError('invalid state record')
        tick, protection, poison, hp = numbers(fields)
        if not tick.is_integer() or tick in states:
            raise ValueError('duplicate or invalid state tick')
        states[int(tick)] = (protection, poison, hp)
    if set(states) != set(range(2, 10)):
        raise ValueError('missing or extra diagnostic state ticks')
    if states[3][0] not in (5398, 5399, 5400) or states[3][1] != 0:
        raise ValueError('candidate protection did not clear poison after transfer')
    if states[4][0] != states[3][0] - 1 or states[4][1] != 0:
        raise ValueError('candidate protection did not count down')
    if states[5][:2] != (18000, 0):
        raise ValueError('candidate protection cap failed')
    if states[7][:2] != (0, 0):
        raise ValueError('candidate protection expiry failed')
    if states[8][:2] != (0, 1) or states[9][:2] != (0, 0):
        raise ValueError('candidate poison countdown failed')
    one('save_start', 0)
    if numbers(one('save_done', 1)) != [1]:
        raise ValueError('candidate save file was not created')
    if numbers(one('load_done', 3)) != [1, 321, 2]:
        raise ValueError('candidate save/load field round-trip failed')
    try:
        raw = base64.b64decode(Path(save_file).read_bytes().strip(), validate=True)
        ini = configparser.ConfigParser(interpolation=None, strict=True)
        ini.read_string(raw.decode('utf-8'))
        fields = [ini.getfloat('player', key) for key in ('buffpoisonprotect', 'buffpoison')]
    except (OSError, ValueError, UnicodeError, configparser.Error) as exc:
        raise ValueError('could not decode candidate save data') from exc
    if fields != [321, 2]:
        raise ValueError('candidate encoded save has unexpected poison fields')
    return {'states': states, 'save_fields': fields,
            'limitations': 'Forced desktop VM scenario, incomplete reconstructed game, not original APK or iOS.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('save', type=Path)
    args = parser.parse_args()
    try:
        result = check(args.log.read_text(encoding='utf-8', errors='replace'), args.save)
    except (OSError, ValueError) as exc:
        print('PROBE_FAIL:', exc, file=sys.stderr)
        return 1
    print('PROBE_PASS: forced candidate mask, timer, cap and normal save/load in desktop VM.')
    print('PROBE_LIMIT:', result['limitations'])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
