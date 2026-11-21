#!/usr/bin/env python3
"""Check static bbox and single-frame mask candidates against native metadata and frames.

Requires a materialized workspace project (including its PNGs). This compares
alpha planes and bounds only, not the compiler-generated masks or gameplay.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops
try:
    from tools.check_deadtown_restored_frames import safe_asset
    from tools.deadtown_rect_sprite_candidates import collect
    from tools.deadtown_sprite_masks import summarize_mask
    from tools.deadtown_sprite_metadata import FIELDS, source_sprites
except ModuleNotFoundError:
    from check_deadtown_restored_frames import safe_asset
    from deadtown_rect_sprite_candidates import collect
    from deadtown_sprite_masks import summarize_mask
    from deadtown_sprite_metadata import FIELDS, source_sprites

NAMES = ('ih_dagger', 'spr_item_use', 'spr_item_use_small', 'spr_parcel',
         'spr_save_button', 'spr_skills', 'spr_ui_buff', 'spr_ui_health')
SINGLE_FRAME_MASKS = ('mask_200_100', 'mask_40_40', 'mask_arrow', 'mask_player')


def alpha_bounds(images):
    if not images:
        raise ValueError('no frames')
    result = images[0].getchannel('A')
    for image in images[1:]:
        if image.size != result.size:
            raise ValueError('frame size mismatch')
        result = ImageChops.lighter(result, image.getchannel('A'))
    bounds = result.getbbox()
    return None if bounds is None else [bounds[0], bounds[2] - 1, bounds[1], bounds[3] - 1]


def verify(apk, project):
    project = Path(project)
    native, source = collect(apk), source_sprites(project)
    report = {}
    for name in NAMES + SINGLE_FRAME_MASKS:
        _, info, masks, frames = native[name]
        if any(info[k] != source[name][k] for k in FIELDS):
            raise ValueError(f'metadata mismatch: {name}')
        root = ET.parse(project / 'sprites' / (name + '.sprite.gmx')).getroot()
        # Preserve each old colkind/tolerance. Numeric metadata agreement
        # does not establish the collision mask emitted by the compiler.
        expected_kind = '0' if name == 'mask_arrow' else '1'
        if root.findtext('colkind') != expected_kind or root.findtext('coltolerance') != '0':
            raise ValueError(f'unexpected collision settings: {name}')
        entries = root.findall('./frames/frame')
        if len(entries) != len(frames) or len(masks) != 1:
            raise ValueError(f'unexpected frame or mask count: {name}')
        images = []
        for index, (entry, (mode, expected, _)) in enumerate(zip(entries, frames)):
            filename = f'{name}_{index}.png'
            if entry.get('index') != str(index) or entry.text != 'images\\' + filename or mode != 'unscaled_canvas':
                raise ValueError(f'unexpected frame reference or scale: {name}[{index}]')
            path = safe_asset(project, Path('sprites/images') / filename)
            with Image.open(path) as opened:
                image = opened.convert('RGBA')
            if image.size != expected.size or image.getchannel('A').tobytes() != expected.getchannel('A').tobytes():
                raise ValueError(f'frame alpha differs: {name}[{index}]')
            images.append(image)
        bbox = [info[k] for k in ('bbox_left', 'bbox_right', 'bbox_top', 'bbox_bottom')]
        if alpha_bounds(images) != bbox:
            raise ValueError(f'alpha union bounds mismatch: {name}')
        mask = summarize_mask(masks[0], info['width'], info['height'])
        if name in SINGLE_FRAME_MASKS and (len(frames) != 1 or images[0].getchannel('A').getextrema() != (255, 255)
                                           or mask['shape'] != 'full_canvas' or mask['row_padding_set_bits']):
            raise ValueError(f'single-frame full mask assumption failed: {name}')
        report[name] = {'frames_checked': len(frames), 'bbox': bbox, 'native_mask': mask}
    return {'sprites': report, 'limitations': 'Static alpha and selected metadata only. Native bit interpretation is MSB-first; '
            'no assertion that GameMaker generates the native collision masks, IDs, texture packing or runtime behavior.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.apk, args.project)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f"BBOX_CANDIDATES_PASS: {len(result['sprites'])} sprites, "
          f"{sum(x['frames_checked'] for x in result['sprites'].values())} alpha frames; static only")


if __name__ == '__main__':
    main()
