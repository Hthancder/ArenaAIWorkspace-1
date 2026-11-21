#!/usr/bin/env python3
"""Build/verify static rectangular-mask sprite candidates from the pinned APK.

Extraction goes into a new disposable folder; it does not edit the project.
Verification compares assets to the pinned APK and the recorded candidate list.
A GMX descriptor is a hypothesis: compiler IDs, texture packing, collision
masks, runtime behavior, and iOS are not established by these checks.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops

try:
    from tools.deadtown_sprite_masks import summarize_mask
    from tools.deadtown_sprite_metadata import FIELDS, source_sprites
    from tools.deadtown_sprite_order_evidence import declared_sprites
    from tools.recover_deadtown_audio import SAFE_NAME
    from tools.recover_deadtown_sprites import iter_sprites, open_apk
    from tools.check_deadtown_restored_frames import safe_asset
except ModuleNotFoundError:
    from deadtown_sprite_masks import summarize_mask
    from deadtown_sprite_metadata import FIELDS, source_sprites
    from deadtown_sprite_order_evidence import declared_sprites
    from recover_deadtown_audio import SAFE_NAME
    from recover_deadtown_sprites import iter_sprites, open_apk
    from check_deadtown_restored_frames import safe_asset

CATALOGUE = 'rect-sprite-candidates.json'


def qualifies(info, masks, frames):
    if not frames or len(masks) != 1 or any(mode != 'unscaled_canvas' for mode, _, _ in frames):
        return False
    if info['separate_masks'] and len(frames) != 1:
        return False  # union model would not establish per-frame masks
    detail = summarize_mask(masks[0], info['width'], info['height'])
    bbox = [info['bbox_left'], info['bbox_right'], info['bbox_top'], info['bbox_bottom']]
    if detail['shape'] not in ('rectangular', 'full_canvas') or detail['bounds'] != bbox or detail['row_padding_set_bits']:
        return False
    alpha = frames[0][1].getchannel('A')
    for _, image, _ in frames[1:]:
        alpha = ImageChops.lighter(alpha, image.getchannel('A'))
    bounds = alpha.getbbox()  # nonzero alpha; returned right/bottom are exclusive
    return bounds == (bbox[0], bbox[2], bbox[1] + 1, bbox[3] + 1)


def descriptor(name, info):
    root = ET.Element('sprite')
    values = [('type', 0), ('xorig', info['origin_x']), ('yorigin', info['origin_y']),
              ('colkind', 1), ('coltolerance', 0), ('sepmasks', -int(info['separate_masks'])),
              ('bboxmode', info['bbox_mode']), ('bbox_left', info['bbox_left']), ('bbox_right', info['bbox_right']),
              ('bbox_top', info['bbox_top']), ('bbox_bottom', info['bbox_bottom']), ('HTile', 0), ('VTile', 0)]
    for key, value in values:
        ET.SubElement(root, key).text = str(value)
    group = ET.SubElement(root, 'TextureGroups')
    ET.SubElement(group, 'TextureGroup0').text = '0'
    for key, value in [('For3D', 0), ('width', info['width']), ('height', info['height'])]:
        ET.SubElement(root, key).text = str(value)
    frame_root = ET.SubElement(root, 'frames')
    for index in range(info['frames']):
        ET.SubElement(frame_root, 'frame', index=str(index)).text = f'images\\{name}_{index}.png'
    ET.indent(root, space='  ')
    return ET.tostring(root, encoding='unicode') + '\n'


def collect(apk):
    data, meta, regions, atlases = open_apk(apk)
    return {name: (sprite_id, info, masks, frames)
            for sprite_id, name, info, _, masks, frames in iter_sprites(data, meta, regions, atlases)}


def extract(apk, project, output):
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise ValueError('output exists; refuse to overwrite')
    declared = set(declared_sprites(project))
    native = collect(apk)
    selected = [(name, info, frames) for name, (_, info, masks, frames) in native.items()
                if name not in declared and qualifies(info, masks, frames)]
    output.mkdir()
    (output / 'INCOMPLETE.txt').write_text('STATIC CANDIDATES ONLY: no game, compiler or iOS validation.\n')
    (output / 'project/sprites').mkdir(parents=True)
    (output / 'assets/sprites/images').mkdir(parents=True)
    for name, info, frames in selected:
        if not SAFE_NAME.fullmatch(name):
            raise ValueError('unsafe sprite name')
        (output / 'project/sprites' / (name + '.sprite.gmx')).write_text(descriptor(name, info), encoding='utf-8')
        for index, (_, image, _) in enumerate(frames):
            image.save(output / 'assets/sprites/images' / f'{name}_{index}.png', format='PNG')
    (output / CATALOGUE).write_text(json.dumps({'format': 1, 'names': [x[0] for x in selected]}, indent=2) + '\n')
    return len(selected), sum(len(x[2]) for x in selected)


def verify(apk, source):
    source = Path(source)
    catalogue = json.loads((source / CATALOGUE).read_text(encoding='utf-8'))
    if not isinstance(catalogue, dict) or set(catalogue) != {'format', 'names'} or catalogue['format'] != 1 or not isinstance(catalogue['names'], list):
        raise ValueError('invalid candidate catalogue')
    names = catalogue['names']
    if not names or any(not isinstance(n, str) or not SAFE_NAME.fullmatch(n) for n in names) or len(names) != len(set(names)):
        raise ValueError('invalid or duplicate candidate names')
    native = collect(apk)
    project, assets = source / 'project', source / 'assets'
    declared = declared_sprites(project)
    source_metadata = source_sprites(project)
    frames_checked = 0
    for name in names:
        if name not in native or name not in source_metadata or declared.count(name) != 1:
            raise ValueError(f'missing candidate: {name}')
        _, info, masks, frames = native[name]
        if not qualifies(info, masks, frames):
            raise ValueError(f'candidate no longer qualifies: {name}')
        if any(info[f] != source_metadata[name][f] for f in FIELDS):
            raise ValueError(f'metadata differs: {name}')
        xml = ET.parse(project / 'sprites' / (name + '.sprite.gmx')).getroot()
        if xml.findtext('colkind') != '1' or xml.findtext('coltolerance') != '0':
            raise ValueError(f'candidate collision settings differ: {name}')
        rows = xml.findall('./frames/frame')
        if len(rows) != len(frames):
            raise ValueError(f'frame count differs: {name}')
        for index, (_, expected, _) in enumerate(frames):
            row = rows[index]
            filename = f'{name}_{index}.png'
            if row.get('index') != str(index) or row.text != 'images\\' + filename:
                raise ValueError(f'frame reference differs: {name}[{index}]')
            path = safe_asset(assets, Path('sprites/images') / filename)
            with Image.open(path) as image:
                if image.format != 'PNG':
                    raise ValueError(f'not a PNG: {filename}')
                actual = image.convert('RGBA')
                if actual.size != expected.size or actual.tobytes() != expected.tobytes():
                    raise ValueError(f'frame differs from atlas: {name}[{index}]')
            frames_checked += 1
    return {'sprite_count': len(names), 'frame_count': frames_checked,
            'limitations': 'Unscaled atlas reconstruction and candidate rectangle mask model only; '
                           'no proof of GameMaker ID/packing/mask or runtime/iOS behavior.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    ex = sub.add_parser('extract')
    ex.add_argument('apk', type=Path); ex.add_argument('project', type=Path); ex.add_argument('output', type=Path)
    ve = sub.add_parser('verify')
    ve.add_argument('apk', type=Path); ve.add_argument('source', type=Path); ve.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if a.command == 'extract':
        sprites, frames = extract(a.apk, a.project, a.output)
        print(f'EXTRACTED_CANDIDATES: {sprites} sprites, {frames} frames; not gameplay or iOS proof')
    else:
        report = verify(a.apk, a.source)
        a.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(f"RECT_CANDIDATES_PASS: {report['sprite_count']} sprites, {report['frame_count']} frames; static only")


if __name__ == '__main__':
    main()
