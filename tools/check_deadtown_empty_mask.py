#!/usr/bin/env python3
"""Check the special fully transparent, scaled mask_noone candidate.

Static input bytes and metadata only, not GameMaker collision/packing or iOS.
The ordinary pixel comparator deliberately leaves scaled frames unclassified.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image

try:
    from tools.check_deadtown_restored_frames import safe_asset
    from tools.deadtown_rect_sprite_candidates import collect
    from tools.deadtown_sprite_metadata import FIELDS, source_sprites
except ModuleNotFoundError:
    from check_deadtown_restored_frames import safe_asset
    from deadtown_rect_sprite_candidates import collect
    from deadtown_sprite_metadata import FIELDS, source_sprites


def require_zero_image(image):
    if image.mode != 'RGBA' or image.size != (32, 32) or any(image.tobytes()):
        raise ValueError('expected zero RGBA image 32x32')


def verify(apk, source):
    source = Path(source)
    native = collect(apk)
    _, info, masks, frames = native['mask_noone']
    if len(masks) != 1 or len(masks[0]) != 128 or any(masks[0]) or len(frames) != 1:
        raise ValueError('native empty mask assumptions failed')
    mode, image, page = frames[0]
    if mode != 'atlas_region_only_scaled_target' or (page['source_width'], page['source_height'], page['target_width'],
             page['target_height'], page['target_x'], page['target_y'], page['bound_width'], page['bound_height']) != (32, 32, 1, 1, 0, 0, 32, 32):
        raise ValueError('unexpected native scaled frame geometry')
    require_zero_image(image)
    project = source / 'project'
    metadata = source_sprites(project)['mask_noone']
    if any(metadata[f] != info[f] for f in FIELDS):
        raise ValueError('candidate metadata differs')
    root = ET.parse(project / 'sprites/mask_noone.sprite.gmx').getroot()
    if root.findtext('colkind') != '0' or root.findtext('coltolerance') != '0':
        raise ValueError('unexpected candidate collision settings')
    entries = root.findall('./frames/frame')
    if len(entries) != 1 or entries[0].get('index') != '0' or entries[0].text != 'images\\mask_noone_0.png':
        raise ValueError('unexpected candidate frame reference')
    path = safe_asset(source / 'assets', Path('sprites/images/mask_noone_0.png'))
    with Image.open(path) as frame:
        if frame.format != 'PNG':
            raise ValueError('expected PNG')
        require_zero_image(frame.convert('RGBA'))
    return {'name': 'mask_noone', 'native_atlas_rgba_all_zero': True, 'native_mask_all_zero': True,
            'source_candidate_rgba_all_zero': True, 'native_source_size': [32, 32], 'native_target_size': [1, 1],
            'limitations': 'Specific zero-valued scaled atlas region; no actual resampling/compositor, '
                           'GameMaker-generated mask, runtime collision, or iPhone validation.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('source', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    result = verify(a.apk, a.source)
    a.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('EMPTY_MASK_CANDIDATE_PASS: zero atlas and mask bytes; not runtime proof')


if __name__ == '__main__':
    main()
