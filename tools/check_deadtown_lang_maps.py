#!/usr/bin/env python3
"""Compare all forced candidate VM translation maps with static APK candidates.

Parses the pinned gmrunner's GMRM string format, not GameMaker's native save
format. Test files are disposable; this is NOT Android or iOS execution.
"""
import argparse
from pathlib import Path

try:
    from tools.deadtown_native_tables import extract
except ModuleNotFoundError:
    from deadtown_native_tables import extract


def parse_gmrm(data):
    if not isinstance(data, bytes) or len(data) > 1_000_000 or not data.startswith(b'GMRM'):
        raise ValueError('invalid GMRM map header')
    pos = 4

    def number(delimiter):
        nonlocal pos
        end = data.find(delimiter, pos)
        if end < 0 or end == pos or end - pos > 9 or not data[pos:end].isdigit():
            raise ValueError('invalid GMRM length')
        result = int(data[pos:end])
        pos = end + 1
        return result

    count = number(b';')
    if count > 10_000:
        raise ValueError('too many GMRM entries')

    def string():
        nonlocal pos
        if data[pos:pos + 1] != b's':
            raise ValueError('expected GMRM string value')
        pos += 1
        size = number(b':')
        if pos + size > len(data):
            raise ValueError('truncated GMRM string')
        value = data[pos:pos + size].decode('utf-8')
        pos += size
        return value

    result = {}
    for _ in range(count):
        key, value = string(), string()
        if key in result:
            raise ValueError('duplicate GMRM key')
        result[key] = value
    if pos != len(data):
        raise ValueError('trailing GMRM bytes')
    return result


def expected_maps(entries):
    maps = ({}, {}, {})
    for entry in entries:
        args = entry.get('arguments', [])
        if len(args) != 4 or any(a.get('type') != 'string' or not isinstance(a.get('value'), str) for a in args):
            raise ValueError('unexpected candidate language arguments')
        key = args[0]['value']
        for index, target in enumerate(maps, 1):
            # The pinned gmrunner ds_map_add rejects duplicate keys. This is
            # the candidate VM's observed rule, not proof of Android behavior.
            target.setdefault(key, args[index]['value'])
    return maps


def check(apk, save_dir):
    native = extract(apk)
    if native['counts']['lang_add'] != {'resolved': 465, 'unresolved': 0}:
        raise ValueError('unexpected candidate language table')
    expected = expected_maps(native['entries']['lang_add'])
    for label, target in zip(('ko', 'zh', 'ja'), expected):
        data = (Path(save_dir) / f'dt_lang_{label}.dat').read_bytes()
        actual = parse_gmrm(data)
        if actual != target:
            raise ValueError(f'candidate {label} map does not match inferred entries')
    return len(expected[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('save_dir', type=Path)
    args = parser.parse_args()
    try:
        count = check(args.apk, args.save_dir)
    except (OSError, UnicodeError, ValueError) as exc:
        parser.exit(1, f'LANG_MAP_CHECK_FAIL: {exc}\n')
    print(f'LANG_MAP_CHECK_PASS: {count} keys match static candidates in each of 3 disposable maps')
    print('LANG_MAP_CHECK_LIMIT: gmrunner GMRM and first-insertion behavior; not original Android or iOS')


if __name__ == '__main__':
    main()
