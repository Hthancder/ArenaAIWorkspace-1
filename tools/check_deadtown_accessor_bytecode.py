#!/usr/bin/env python3
"""Check a narrowly scoped UTMT/gmrunner disassembly experiment, not APK behavior."""
import argparse
from pathlib import Path
import re


def check(legacy, candidate):
    if not legacy.startswith('; probe_item_use_legacy_unlinked '):
        raise ValueError('unexpected legacy code entry')
    if not candidate.startswith('; gml_Script_item_use '):
        raise ValueError('unexpected candidate code entry')
    # These checks describe the specific compiled local map-access sequence;
    # they are not a general bytecode verifier or an APK equivalence check.
    prefix, separator, _ = legacy.partition('call.i ds_map_delete(')
    if not separator:
        raise ValueError('legacy map deletion call missing')
    if not re.search(r'push\.v \[array\]stack\.target_inven', prefix):
        raise ValueError('legacy array read missing')
    if not re.search(r'pop\.i\.v \[array\]stack\.target_inven', prefix):
        raise ValueError('legacy array write missing')
    if 'call.i ds_map_find_value(' in prefix or 'call.i ds_map_replace(' in prefix:
        raise ValueError('legacy accessor no longer compiles solely as an array')
    if not all('call.i ' + name + '(' in candidate for name in
               ('ds_map_find_value', 'ds_map_replace', 'ds_map_delete')):
        raise ValueError('candidate explicit DS-map operations missing')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('legacy', type=Path)
    parser.add_argument('candidate', type=Path)
    args = parser.parse_args()
    try:
        check(args.legacy.read_text(), args.candidate.read_text())
    except (OSError, ValueError) as exc:
        parser.exit(1, f'ACCESSOR_CHECK_FAIL: {exc}\n')
    print('ACCESSOR_CHECK_PASS: legacy array lowering versus explicit DS-map candidate')
    print('ACCESSOR_CHECK_LIMIT: compiled desktop candidate only; not APK execution')


if __name__ == '__main__':
    main()
