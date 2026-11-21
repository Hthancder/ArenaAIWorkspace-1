#!/usr/bin/env python3
"""Compare APK sprite IDs to GMX declaration positions, not compiled IDs.

Static inventory only. The GameMaker compiler's ordering and behavior are not
established by XML declaration order; no game data or resource IDs are changed.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_sprite_metadata import native_sprites
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_sprite_metadata import native_sprites
    from recover_deadtown_audio import read_zip_member


def declared_sprites(project):
    root = ET.parse(Path(project) / 'deadtown.project.gmx').getroot()
    group = root.find('sprites')
    if group is None:
        raise ValueError('project sprites section missing')
    result = []
    for item in group.iter('sprite'):
        if not item.text or not item.text.strip():
            raise ValueError('empty sprite declaration')
        p = PurePosixPath(item.text.strip().replace('\\', '/'))
        if p.is_absolute() or '..' in p.parts or len(p.parts) != 2 or p.parts[0] != 'sprites':
            raise ValueError('unexpected sprite declaration path')
        result.append(p.name)
    if not result or len(set(result)) != len(result):
        raise ValueError('empty or duplicate sprite declarations')
    return result


def analyze_order(native, declared):
    if not native or not declared or len(set(native)) != len(native) or len(set(declared)) != len(declared):
        raise ValueError('empty or duplicate sprite names')
    native_ids = {name: i for i, name in enumerate(native)}
    declared_ids = {name: i for i, name in enumerate(declared)}
    in_native = set(native)
    in_declared = set(declared)
    declared_common = [n for n in declared if n in in_native]
    native_common = [n for n in native if n in in_declared]
    native_rank = {n: i for i, n in enumerate(native_common)}
    declared_rank = {n: i for i, n in enumerate(declared_common)}
    inversions = sum(native_rank[a] > native_rank[b]
                     for i, a in enumerate(declared_common) for b in declared_common[i + 1:])
    rows = [{'name': name, 'apk_sprite_id': native_ids[name], 'gmx_declared_ordinal': declared_ids[name],
             'apk_common_rank': native_rank[name], 'gmx_common_rank': declared_rank[name]}
            for name in declared_common]
    return {'native_sprites': len(native), 'gmx_declared_sprites': len(declared),
            'shared_sprites': len(rows),
            'missing_from_gmx': [name for name in native if name not in in_declared],
            'only_in_gmx': [name for name in declared if name not in in_native],
            'same_numeric_ordinal': sum(row['apk_sprite_id'] == row['gmx_declared_ordinal'] for row in rows),
            'different_common_rank': sum(row['apk_common_rank'] != row['gmx_common_rank'] for row in rows),
            'relative_order_inversions': inversions, 'shared': rows,
            'limitations': 'APK ID is SPRT table position; GMX ordinal is XML declaration order, '
                           'not an observed compiled GameMaker sprite ID. No inference about actual '
                           'runtime references, offsets, gameplay, iOS, or a safe reorder.'}


def compare(apk, project):
    apk = Path(apk)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        game = read_zip_member(archive, 'assets/game.droid')
    # native_sprites preserves the SPRT table order and validates every name.
    native = list(native_sprites(game))
    return {'apk_sha256': APK_SHA256, **analyze_order(native, declared_sprites(project))}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    result = compare(args.apk, args.project)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('SPRITE_ORDER_EVIDENCE:', json.dumps({k: result[k] for k in
          ('native_sprites', 'gmx_declared_sprites', 'shared_sprites', 'same_numeric_ordinal',
           'different_common_rank', 'relative_order_inversions')}, separators=(',', ':')))
    print('GMX XML ordinals are not proven compiler IDs; no runtime equivalence is claimed.')


if __name__ == '__main__':
    main()
