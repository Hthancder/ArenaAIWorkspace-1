#!/usr/bin/env python3
"""Prepare four disposable old-source inventory scripts for VM diagnostics.

This is a narrow workaround for a compiler defect, NOT a reconstruction of the
APK or a release patch. It does not alter a project, build, or user saves.
"""
import argparse
import hashlib
from pathlib import Path
import re
import shutil

try:
    from tools.prepare_deadtown_offline import PatchError
except ModuleNotFoundError:
    from prepare_deadtown_offline import PatchError

EXPECTED = {
    'item_get': ('d4455735ffda30b3869931e281085d5149cd963d2799ddedc2475af3a0983a17', 1, 0),
    'item_drop': ('646b2b00434161e77c954af8024a9fd80847b83822c383c716ceaee2db8be20a', 1, 2),
    'item_equip': ('ed65c6a5943e330dfb58616bfa55b1ac7d2474319d3d4276cd5f8575835c5296', 1, 1),
    'item_make': ('64217152cee32af73be6a3117bc6b603b2bb8fd2894057601a82d22db5a884f1', 3, 9),
}
# These expressions have only plain variables and are pinned to exact inputs;
# this is deliberately not a general GML accessor translator.
ACCESS = re.compile(r'\b(target_inven[123]?)\[\? (pointer|craft_index[123])\]')
ASSIGN = re.compile(r'\b(target_inven[123]?)\[\? (pointer|craft_index[123])\] ([+-])= (1|item_number|craft_number[123])(?=;|\n)')


def rewrite(text, name):
    if name not in EXPECTED:
        raise PatchError('unknown inventory script')
    def assignment(match):
        target, key, operation, amount = match.groups()
        return f'ds_map_replace({target},{key},ds_map_find_value({target},{key}) {operation} {amount})'
    text, writes = ASSIGN.subn(assignment, text)
    text, reads = ACCESS.subn(lambda m: f'ds_map_find_value({m[1]},{m[2]})', text)
    if (writes, reads) != EXPECTED[name][1:] or '[?' in text:
        raise PatchError('unexpected accessor layout')
    return text


def prepare(source, output):
    source, output = Path(source), Path(output)
    if output.exists() or output.is_symlink():
        raise PatchError('output already exists')
    if source.resolve() in output.resolve().parents or output.resolve() in source.resolve().parents:
        raise PatchError('source and output must not contain one another')
    changed = {}
    for name, (digest, _, _) in EXPECTED.items():
        data = (source / 'scripts' / (name + '.gml')).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise PatchError('unexpected source: ' + name)
        changed[name] = rewrite(data.decode('utf-8'), name)
    output.mkdir()
    try:
        for name, text in changed.items():
            (output / (name + '.gml')).write_text(text, encoding='utf-8')
        (output / 'RESEARCH-ONLY.txt').write_text('Disposable VM compiler probe only. NOT a game, IPA or native behavior.\n')
    except Exception:
        shutil.rmtree(output)
        raise
    return len(changed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('offline_source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(f'INVENTORY_PROBE: prepared {prepare(args.offline_source, args.output)} disposable source scripts')
    print('INVENTORY_PROBE_LIMIT: old-source semantics candidate in incomplete VM only; NOT APK or IPA')


if __name__ == '__main__':
    main()
