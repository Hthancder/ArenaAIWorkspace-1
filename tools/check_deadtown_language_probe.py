#!/usr/bin/env python3
"""Check old-source vs forced candidate language behavior in disposable VM logs."""
import argparse
from pathlib import Path

PREFIX = 'DT_LANG|'
KEY = '__DT_LANG_KNOWN__'
EMPTY = '__DT_LANG_EMPTY__'
MISSING = '__DT_LANG_UNKNOWN__'


def records(log):
    if 'DT_LANG_ERROR|' in log:
        raise ValueError('probe key collision')
    if log.count('DT_LANG_DONE') != 1:
        raise ValueError('probe did not complete exactly once')
    output = {}
    for line in log.splitlines():
        pos = line.find(PREFIX)
        if pos < 0:
            continue
        parts = line[pos + len(PREFIX):].strip().split('|')
        if len(parts) != 4 or parts[0] not in ('0', '1', '2', '3') or parts[0] in output:
            raise ValueError('invalid or duplicate language record')
        output[parts[0]] = parts[1:]
    if set(output) != {'0', '1', '2', '3'}:
        raise ValueError('missing language cases')
    return output


def check(old, candidate):
    old, candidate = records(old), records(candidate)
    english = [KEY, EMPTY, MISSING]
    if old['0'] != english or candidate['0'] != english:
        raise ValueError('English source-key behavior mismatch')
    for case, translation in (('1', 'KO'), ('2', 'ZH'), ('3', 'JA')):
        if old[case] != [translation, '', '<undefined>']:
            raise ValueError('legacy lookup differs from expected forced probe')
        if candidate[case] != [translation, '', MISSING]:
            raise ValueError('candidate known/empty/missing lookup mismatch')
    return {'cases': 4, 'limitations': 'Forced synthetic map keys in incomplete desktop VM only; not APK or iOS.'}


def check_table(log):
    if log.count('DT_LANG_TABLE_DONE') != 1:
        raise ValueError('candidate table probe did not complete exactly once')
    if 'DT_LANG_ERROR|' in log:
        raise ValueError('candidate table probe key collision')
    rows = {}
    for line in log.splitlines():
        pos = line.find('DT_LANG_TABLE|')
        if pos < 0:
            continue
        fields = line[pos + len('DT_LANG_TABLE|'):].strip().split('|')
        if not fields or fields[0] in rows:
            raise ValueError('invalid or duplicate table record')
        rows[fields[0]] = fields[1:]
    if rows != {'sizes': ['463', '463', '463'],
                'ko': ['방독면', '부목', '라이트 머신건', '헤비 머신건'],
                'zh': ['1', '0'], 'ja': ['1', '0']}:
        raise ValueError('candidate table translation, map size or duplicate behavior mismatch')
    return {'limitations': 'Inferred APK literal order in incomplete desktop VM; not native or iOS behavior.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('legacy', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('table', type=Path, nargs='?', help='optional candidate-table VM log')
    args = parser.parse_args()
    try:
        result = check(args.legacy.read_text(errors='replace'), args.candidate.read_text(errors='replace'))
        if args.table:
            table_log = args.table.read_text(errors='replace')
            check(args.legacy.read_text(errors='replace'), table_log)
            table_result = check_table(table_log)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'LANG_PROBE_FAIL: {exc}\n')
    print('LANG_PROBE_PASS: known, empty and missing synthetic keys for selectors 0..3')
    print('LANG_PROBE_LIMIT:', result['limitations'])
    if args.table:
        print('LANG_TABLE_PROBE_PASS: candidate maps, translations, empty values and duplicate keys')
        print('LANG_TABLE_PROBE_LIMIT:', table_result['limitations'])


if __name__ == '__main__':
    main()
