#!/usr/bin/env python3
"""Check a forced old-source inventory candidate; never an APK-equivalence test."""
import argparse
from pathlib import Path
import re

NAMES = ('item_get', 'item_drop', 'item_equip', 'item_make')


def check_bytecode(name, old, candidate):
    if not old.startswith('; probe_' + name + '_old_unlinked '):
        raise ValueError('unexpected old entry: ' + name)
    if not candidate.startswith('; gml_Script_' + name + ' '):
        raise ValueError('unexpected candidate entry: ' + name)
    if not re.search(r'\[array\][^\s]*target_inven', old):
        raise ValueError('old array lowering missing: ' + name)
    if not all('call.i ' + function + '(' in candidate for function in ('ds_map_find_value', 'ds_map_replace')):
        raise ValueError('candidate map operations missing: ' + name)
    if re.search(r'\[array\][^\s]*target_inven', candidate):
        raise ValueError('candidate target inventory array accessor remains: ' + name)


def check_log(log):
    expected = {
        'get': ['5'], 'drop': ['0', '1', '4'], 'last': ['1', '0'],
        'short': ['0', '0', '1', '2', '3'], 'craft': ['1', '0', '1', '0', '2'],
    }
    if log.count('DT_INV_DONE') != 1:
        raise ValueError('probe completion missing or duplicated')
    rows = {}
    for line in log.splitlines():
        marker = line.find('DT_INV|')
        if marker < 0:
            continue
        fields = line[marker + len('DT_INV|'):].strip().split('|')
        if fields[0] in rows:
            raise ValueError('duplicate inventory marker')
        rows[fields[0]] = fields[1:]
    if rows != expected:
        raise ValueError('unexpected inventory scenario outcomes: ' + repr(rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('disassembly', type=Path)
    args = parser.parse_args()
    try:
        check_log(args.log.read_text(errors='replace'))
        for name in NAMES:
            check_bytecode(name, (args.disassembly / (name + '-old.log')).read_text(),
                           (args.disassembly / (name + '-candidate.log')).read_text())
    except (OSError, ValueError) as exc:
        parser.exit(1, f'INVENTORY_CHECK_FAIL: {exc}\n')
    print('INVENTORY_CHECK_PASS: four bytecode comparisons; forced get/drop/craft scenarios')
    print('INVENTORY_CHECK_LIMIT: old-source candidate on incomplete desktop VM, not APK or iOS')


if __name__ == '__main__':
    main()
