#!/usr/bin/env python3
"""Compare candidate APK table strings with old GMX translation keys.

This is a static data audit, not a translation injection or a native runtime
trace. Assumes the old GMX name/description field positions for these rows.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import xml.etree.ElementTree as ET

try:
    from tools.deadtown_native_lang import GMX_CALL
    from tools.deadtown_native_tables import extract
except ModuleNotFoundError:
    from deadtown_native_lang import GMX_CALL
    from deadtown_native_tables import extract

FIELDS = {'db_weapon_add': (0, 3), 'db_equip_add': (0, 3), 'db_use_add': (0, 2),
          'db_etc_add': (0, 2), 'db_skill_add': (0, 1)}


def compare(table, source):
    action = '\n'.join(node.text or '' for node in ET.parse(Path(source) / 'objects/sys_global.object.gmx').iter('string'))
    old = GMX_CALL.findall(action)
    if not old:
        raise ValueError('no expected GMX translation literals')
    old_keys = {row[0] for row in old}
    if table['counts']['lang_add']['unresolved']:
        raise ValueError('unresolved native language candidates')
    langs = []
    for entry in table['entries']['lang_add']:
        args = entry['arguments']
        if len(args) != 4 or any(a.get('type') != 'string' or not isinstance(a.get('value'), str) for a in args):
            raise ValueError('unexpected language argument layout')
        langs.append(tuple(a['value'] for a in args))
    if not langs:
        raise ValueError('no native language candidates')
    native_keys = {row[0] for row in langs}
    counts = Counter(row[0] for row in langs)
    by_table, all_keys, total = {}, set(), 0
    for name, indexes in FIELDS.items():
        if table['counts'][name]['unresolved']:
            raise ValueError(f'unresolved {name} candidates')
        keys = []
        for entry in table['entries'][name]:
            args = entry['arguments']
            for index in indexes:
                if index >= len(args) or args[index].get('type') != 'string' or not isinstance(args[index].get('value'), str):
                    raise ValueError(f'unexpected {name} name/description layout')
                keys.append(args[index]['value'])
        distinct = set(keys)
        all_keys.update(distinct)
        total += len(keys)
        by_table[name] = {'rows': len(table['entries'][name]), 'references': len(keys),
                          'distinct_keys': len(distinct), 'absent_from_old_gmx': sorted(distinct - old_keys),
                          'absent_from_native_candidates': sorted(distinct - native_keys)}
    return {'apk_sha256': table['apk_sha256'],
            'candidate_language_calls': len(langs), 'candidate_distinct_english_keys': len(native_keys),
            'candidate_duplicate_english_keys': dict(sorted((k, v) for k, v in counts.items() if v > 1)),
            'candidate_empty_translations': {label: sum(row[i] == '' for row in langs)
                                             for i, label in ((1, 'korean'), (2, 'chinese'), (3, 'japanese'))},
            'old_language_calls': len(old),
            'old_empty_translations': {label: sum(row[i] == '' for row in old)
                                       for i, label in ((1, 'korean'), (2, 'chinese'), (3, 'japanese'))},
            'candidate_table_references': total, 'candidate_distinct_table_keys': len(all_keys),
            'table_keys_absent_from_old_gmx': sorted(all_keys - old_keys),
            'table_keys_absent_from_native_candidates': sorted(all_keys - native_keys),
            'tables': by_table,
            'limitations': 'Static linear ARM candidate extraction and literal GMX parsing; old field positions '
                           'assumed for native rows. Duplicates, control flow, native consumers, dynamic keys, '
                           'map insertion order and actual runtime behavior are not proven.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = compare(extract(args.apk), args.project)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"{report['candidate_distinct_table_keys']} candidate table keys: "
          f"{len(report['table_keys_absent_from_old_gmx'])} absent from GMX, "
          f"{len(report['table_keys_absent_from_native_candidates'])} absent from native candidates")
    print('Static candidate audit only; not a runtime translation test.')


if __name__ == '__main__':
    main()
