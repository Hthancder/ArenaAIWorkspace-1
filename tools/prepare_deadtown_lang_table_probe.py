#!/usr/bin/env python3
"""Create a disposable candidate event JSON with APK language table literals.

NOT a release patch or GMX rewrite. The APK is verified and old-source strings
are checked exactly before the in-memory event is altered. Native linear-scan
candidates and their original reachability/ordering still require proof.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

try:
    from tools.deadtown_lang_fallback_evidence import inspect
    from tools.deadtown_native_lang import GMX_CALL
    from tools.deadtown_native_tables import extract
    from tools.prepare_deadtown_offline import PatchError
    from tools.prepare_deadtown_poison_probe import EXPECTED
except ModuleNotFoundError:
    from deadtown_lang_fallback_evidence import inspect
    from deadtown_native_lang import GMX_CALL
    from deadtown_native_tables import extract
    from prepare_deadtown_offline import PatchError
    from prepare_deadtown_poison_probe import EXPECTED

CALL_LINE = re.compile(r'(?m)^[ \t]*lang_add\("([^"\n]*)","([^"\n]*)","([^"\n]*)","([^"\n]*)"\)[ \t]*$')


def safe_literal(value):
    if not isinstance(value, str) or any(ord(c) < 32 or c in '\\"' for c in value):
        raise PatchError('unsupported language string literal')
    return '"' + value + '"'


def rewrite(body, old_rows, entries):
    """Replace only stand-alone source language calls, preserving other GML."""
    found = CALL_LINE.findall(body)
    if found != old_rows or len(GMX_CALL.findall(body)) != len(found):
        raise PatchError('unexpected old language calls or order')
    if body.count('lang_init()') != 1:
        raise PatchError('expected exactly one language initialization')
    lines = []
    for entry in entries:
        args = entry.get('arguments', [])
        if len(args) != 4 or any(a.get('type') != 'string' for a in args):
            raise PatchError('unexpected language argument layout')
        lines.append('lang_add(' + ','.join(safe_literal(a.get('value')) for a in args) + ')')
    if not lines:
        raise PatchError('no candidate language entries')
    rewritten, count = CALL_LINE.subn('// old language call removed for isolated probe', body)
    if count != len(old_rows):
        raise PatchError('language call count changed')
    rewritten = rewritten.replace('lang_init()',
        'lang_init()\n// APK literal candidates; research-only, order not runtime-verified.\n' + '\n'.join(lines), 1)
    return rewritten


def prepare(events_path, offline_project, apk, output):
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise PatchError('output already exists; refusing to overwrite')
    source = Path(offline_project) / 'objects/sys_global.object.gmx'
    if hashlib.sha256(source.read_bytes()).hexdigest() != EXPECTED['objects/sys_global.object.gmx']:
        raise PatchError('unexpected offline sys_global source')
    tree = ET.parse(source)
    old_rows = []
    for node in tree.iter('string'):
        old_rows.extend(GMX_CALL.findall(node.text or ''))
    if len(old_rows) != 362:
        raise PatchError('unexpected old language count')
    evidence = inspect(apk)
    if [x['fallback_argument'] for x in evidence['cases']] != [0, 0, 0]:
        raise PatchError('unexpected native language fallback evidence')
    native = extract(apk)
    if native['counts']['lang_add'] != {'resolved': 465, 'unresolved': 0}:
        raise PatchError('incomplete native language candidates')
    events = json.loads(Path(events_path).read_text(encoding='utf-8'))
    targets = [event for event in events if event.get('object') == 'sys_global' and
               event.get('attributes', {}).get('eventtype') == '0' and
               event.get('attributes', {}).get('enumb') == '0']
    if len(targets) != 1:
        raise PatchError('expected exactly one sys_global Create event')
    targets[0]['gml'] = rewrite(targets[0]['gml'], old_rows, native['entries']['lang_add'])
    # Exclusive open ensures another writer's existing output is not overwritten.
    with output.open('x', encoding='utf-8') as file:
        json.dump(events, file, ensure_ascii=False, indent=2)
        file.write('\n')
    return len(old_rows), len(native['entries']['lang_add'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('events', type=Path)
    parser.add_argument('offline_project', type=Path)
    parser.add_argument('apk', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    old, native = prepare(args.events, args.offline_project, args.apk, args.output)
    print(f'LANG_TABLE_PROBE: {old} source calls replaced with {native} candidates in event JSON only')
    print('LANG_TABLE_LIMIT: incomplete desktop VM research; not native execution or an IPA')


if __name__ == '__main__':
    main()
