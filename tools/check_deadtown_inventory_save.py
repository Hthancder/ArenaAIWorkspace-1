#!/usr/bin/env python3
"""Check disposable gmrunner inventory save/load, not native save compatibility.

GMRM is a private serialization of the pinned gmrunner, NOT the original
GameMaker format. Only numeric inventory keys/values are supported here.
"""
import argparse
import base64
import binascii
import configparser
import math
from pathlib import Path

EXPECTED = {'weapon': 11, 'equip': 22, 'use': 33, 'etc': 44}


def parse_numeric_gmrm(data):
    if not isinstance(data, bytes) or len(data) > 1_000_000 or not data.startswith(b'GMRM'):
        raise ValueError('invalid GMRM header')
    split = data.find(b';', 4)
    count_bytes = data[4:split] if split >= 0 else b''
    if not count_bytes or len(count_bytes) > 5 or not count_bytes.isdigit():
        raise ValueError('invalid GMRM count')
    count = int(count_bytes)
    if count > 10_000:
        raise ValueError('too many GMRM entries')
    pos = split + 1

    def real():
        nonlocal pos
        if data[pos:pos + 1] != b'r':
            raise ValueError('non-numeric GMRM inventory value')
        end = data.find(b';', pos + 1)
        if end < 0 or end - pos > 40:
            raise ValueError('truncated GMRM real')
        try:
            value = float(data[pos + 1:end].decode('ascii'))
        except (ValueError, UnicodeError) as exc:
            raise ValueError('invalid GMRM real') from exc
        if not math.isfinite(value):
            raise ValueError('nonfinite GMRM real')
        pos = end + 1
        return value

    values = {}
    for _ in range(count):
        key, value = real(), real()
        if key in values:
            raise ValueError('duplicate GMRM key')
        values[key] = value
    if pos != len(data):
        raise ValueError('trailing GMRM data')
    return values


def check(log, save_file):
    rows = {}
    for line in log.splitlines():
        offset = line.find('DT_INVENTORY_SAVE|')
        if offset < 0:
            continue
        fields = line[offset + len('DT_INVENTORY_SAVE|'):].strip().split('|')
        if fields[0] in rows:
            raise ValueError('duplicate inventory-save marker')
        rows[fields[0]] = fields[1:]
    if rows != {'loaded': ['11', '22', '33', '44'], 'cleared': ['0', '0', '0', '0']}:
        raise ValueError('inventory save/load or cleared-marker mismatch')
    weapon_rows = [line[line.find('DT_WEAPON_SAVE|'):].strip() for line in log.splitlines() if 'DT_WEAPON_SAVE|' in line]
    if weapon_rows != ['DT_WEAPON_SAVE|loaded|100001|100001']:
        raise ValueError('weapon save/load marker mismatch')
    try:
        raw = base64.b64decode(Path(save_file).read_bytes().strip(), validate=True)
        ini = configparser.ConfigParser(interpolation=None, strict=True)
        ini.read_string(raw.decode('utf-8'))
        weapon = ini.get('equip', 'weapon').strip()
        if len(weapon) >= 2 and weapon[0] == '"' and weapon[-1] == '"':
            weapon = weapon[1:-1]
        if float(weapon) != 100001 or ini.has_option('equip', 'weaponlevel'):
            raise ValueError('unexpected legacy weapon fields')
        for key, expected in EXPECTED.items():
            value = ini.get('inventory', key).strip()
            if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
                value = value[1:-1]
            decoded = parse_numeric_gmrm(value.encode('utf-8'))
            if decoded.get(0) != expected or 900 in decoded:
                raise ValueError('unexpected saved inventory entries: ' + key)
    except (OSError, ValueError, UnicodeError, binascii.Error, configparser.Error) as exc:
        raise ValueError('invalid disposable inventory save: ' + str(exc)) from exc
    return len(EXPECTED)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('save', type=Path)
    args = parser.parse_args()
    try:
        count = check(args.log.read_text(encoding='utf-8', errors='replace'), args.save)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'INVENTORY_SAVE_CHECK_FAIL: {exc}\n')
    print(f'INVENTORY_SAVE_CHECK_PASS: {count} forced map entries restored, stale entries cleared and save decoded')
    print('INVENTORY_SAVE_CHECK_LIMIT: incomplete gmrunner VM, private GMRM format, NOT native Android or iOS')


if __name__ == '__main__':
    main()
