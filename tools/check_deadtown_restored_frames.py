#!/usr/bin/env python3
"""Verify editable-frame candidates against the pinned Android atlas.

Static pixels and a limited metadata subset only; no proof of masks, renderer,
frame timing, gameplay or iOS. Intended project is explicitly incomplete.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

from PIL import Image
try:
    from tools.recover_deadtown_sprites import open_apk
    from tools.recover_deadtown_audio import chunks, pointers, read_string, u32
    from tools.deadtown_sprite_pixels import compare_frame
    from tools.deadtown_sprite_metadata import FIELDS, source_sprites
except ModuleNotFoundError:
    from recover_deadtown_sprites import open_apk
    from recover_deadtown_audio import chunks, pointers, read_string, u32
    from deadtown_sprite_pixels import compare_frame
    from deadtown_sprite_metadata import FIELDS, source_sprites

# First verified replacement/added frame and total frames in the pinned APK.
# spr_ui_day starts at 0: the existing first image differed visibly and is
# intentionally replaced in the overlay; frames 1 and 2 are new.
RESTORED = {'spr_action_button': (10, 11), 'spr_item_equip': (26, 27),
            'spr_item_equip_small': (26, 27), 'spr_item_etc': (49, 65),
            'spr_item_etc_small': (49, 65), 'spr_item_weapon': (30, 35),
            'spr_item_weapon_small': (30, 35), 'spr_zombie_foot_left': (1, 2),
            'spr_zombie_foot_right': (1, 2), 'spr_item_use': (20, 22),
            'spr_item_use_small': (20, 22), 'spr_parcel': (1, 4),
            'spr_save_button': (2, 4), 'spr_skills': (21, 23),
            'spr_ui_buff': (6, 7), 'spr_ui_health': (4, 6), 'spr_ui_day': (0, 3)}

# These pre-existing bbox values are deliberately not changed. Each pair is
# (native, GMX); numeric equality/differences do not prove collision semantics.
BBOX_DIFFERENCES = {
    'spr_item_use': {'bbox_top': (2, 5), 'bbox_bottom': (118, 115)},
    'spr_item_use_small': {'bbox_top': (4, 5)},
    'spr_parcel': {'bbox_top': (4, 5)},
    'spr_save_button': {'bbox_top': (9, 10)},
    'spr_skills': {'bbox_left': (8, 10), 'bbox_right': (64, 63), 'bbox_top': (9, 10)},
    'spr_ui_buff': {'bbox_top': (1, 5), 'bbox_bottom': (68, 64)},
    'spr_ui_health': {'bbox_top': (4, 5)},
}


def safe_asset(root, relative):
    path = root
    if root.is_symlink():
        raise ValueError('symlinked asset root')
    for part in relative.parts:
        if part in ('', '.', '..'):
            raise ValueError('unsafe asset path')
        path = path / part
        if path.is_symlink():
            raise ValueError('symlinked asset path')
    if not path.is_file():
        raise ValueError(f'missing asset: {relative}')
    return path


def verify(apk, source):
    source = Path(source)
    project, assets = source / 'project', source / 'assets'
    data, native, regions, atlases = open_apk(apk)
    gmx = source_sprites(project)
    positions = {read_string(data, u32(data, pos), regions[b'STRG']): pos
                 for pos in pointers(data, regions[b'SPRT'])}
    report = {}
    for name, (first, count) in RESTORED.items():
        if name not in native or name not in gmx or name not in positions:
            raise ValueError(f'missing sprite: {name}')
        differences = {f: (native[name][f], gmx[name][f]) for f in FIELDS
                       if native[name][f] != gmx[name][f]}
        if native[name]['frames'] != count or differences != BBOX_DIFFERENCES.get(name, {}):
            raise ValueError(f'metadata mismatch: {name}')
        root = ET.parse(project / 'sprites' / (name + '.sprite.gmx')).getroot()
        frames = root.findall('./frames/frame')
        if sorted(int(f.get('index', '-1')) for f in frames) != list(range(count)):
            raise ValueError(f'noncontiguous frame table: {name}')
        by_index = {int(f.get('index')): f.text for f in frames}
        entries = []
        for i in range(first, count):
            filename = f'{name}_{i}.png'
            if by_index[i] != 'images\\' + filename:
                raise ValueError(f'unexpected frame reference: {name}[{i}]')
            path = safe_asset(assets, Path('sprites/images') / filename)
            png = path.read_bytes()
            with Image.open(path) as image:
                if image.format != 'PNG':
                    raise ValueError(f'not PNG: {name}[{i}]')
                image = image.convert('RGBA')
            ptr = u32(data, positions[name] + 60 + 4 * i)
            if not regions[b'TPAG'][0] <= ptr or ptr + 22 > regions[b'TPAG'][1]:
                raise ValueError(f'bad TPAG pointer: {name}[{i}]')
            page = struct.unpack_from('<10Hh', data, ptr)
            if not 0 <= page[-1] < len(atlases):
                raise ValueError(f'bad atlas index: {name}[{i}]')
            if (page[2], page[3]) != (page[6], page[7]):
                raise ValueError(f'scaled frame not supported: {name}[{i}]')
            if (page[8], page[9]) != (native[name]['width'], native[name]['height']):
                raise ValueError(f'inconsistent frame bounds: {name}[{i}]')
            if compare_frame(atlases[page[-1]], page, image) != 'exact_rgba':
                raise ValueError(f'frame differs from atlas reconstruction: {name}[{i}]')
            entries.append({'index': i, 'atlas': page[-1], 'atlas_rect': list(page[:4]),
                            'target_rect': list(page[4:8]), 'sha256_png': hashlib.sha256(png).hexdigest(),
                            'sha256_rgba': hashlib.sha256(image.tobytes()).hexdigest()})
        report[name] = {'restored': entries,
                        'metadata_matches_fields': [f for f in FIELDS if f not in differences],
                        'known_metadata_differences': {f: {'apk': a, 'gmx': b} for f, (a, b) in differences.items()}}
    return {'sprites': report, 'sprite_count': len(report),
            'frame_count': sum(len(x['restored']) for x in report.values()),
            'limitations': 'Static unscaled atlas reconstruction; outside trimmed rectangles transparent RGB '
                           'is unknown, PNGs re-encoded. Collision masks, animation rate, behavior, GPU rendering '
                           'and iOS have not been validated. The overall game remains incomplete.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('source', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    result = verify(args.apk, args.source)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f"FRAME_CANDIDATES_PASS: {result['sprite_count']} sprites; {result['frame_count']} restored frames; not iOS or gameplay proof")


if __name__ == '__main__':
    main()
