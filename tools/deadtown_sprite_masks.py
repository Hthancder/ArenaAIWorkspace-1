#!/usr/bin/env python3
"""Summarize pinned APK's raw collision-mask bits; does not emulate collisions.

Uses the bit order of pinned gmrunner (MSB first). That interpretation has not
been independently validated against the Android runner. Metadata bounds are
reported as raw numbers; transformed runtime collision behavior is out of scope.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import zipfile

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_sprite_metadata import native_sprites
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_sprite_metadata import native_sprites
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32


def summarize_mask(raw, width, height):
    if not (0 < width <= 4096 and 0 < height <= 4096):
        raise ValueError('invalid mask dimensions')
    stride = (width + 7) // 8
    if len(raw) != stride * height:
        raise ValueError('invalid mask byte length')
    count = 0
    min_x, min_y, max_x, max_y = width, height, -1, -1
    padding_bits = 0
    for y in range(height):
        for byte_index in range(stride):
            value = raw[y * stride + byte_index]
            for bit in range(8):
                x = byte_index * 8 + bit
                if value & (0x80 >> bit):
                    if x >= width:
                        padding_bits += 1
                    else:
                        count += 1
                        min_x, max_x = min(min_x, x), max(max_x, x)
                        min_y, max_y = min(min_y, y), max(max_y, y)
    if not count:
        bounds, shape = None, 'empty'
    else:
        bounds = [min_x, max_x, min_y, max_y]
        if count == width * height:
            shape = 'full_canvas'
        elif count == (max_x - min_x + 1) * (max_y - min_y + 1):
            shape = 'rectangular'
        else:
            shape = 'irregular'
    return {'set_pixels': count, 'bounds': bounds, 'shape': shape,
            'row_padding_set_bits': padding_bits, 'sha256': hashlib.sha256(raw).hexdigest()}


def inspect(apk):
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
    metadata = native_sprites(data)
    regions = chunks(data)
    entries = pointers(data, regions[b'SPRT'])
    if entries != sorted(set(entries)):
        raise ValueError('overlapping or unsorted sprite entries')
    sprites, shapes, bounds_counts = [], Counter(), Counter()
    for sprite_id, pos in enumerate(entries):
        end = entries[sprite_id + 1] if sprite_id + 1 < len(entries) else regions[b'SPRT'][1]
        name = read_string(data, u32(data, pos), regions[b'STRG'])
        info = metadata[name]
        width, height, frames = info['width'], info['height'], info['frames']
        if not (0 < width <= 4096 and 0 < height <= 4096):
            raise ValueError('invalid sprite size')
        header = pos + 60 + frames * 4
        if header + 4 > end:
            raise ValueError('truncated sprite frame table')
        mask_count = u32(data, header)
        size = ((width + 7) // 8) * height
        if mask_count > (end - header - 4) // size:
            raise ValueError('truncated collision masks')
        bbox = [info['bbox_left'], info['bbox_right'], info['bbox_top'], info['bbox_bottom']]
        masks = []
        for index in range(mask_count):
            start = header + 4 + index * size
            value = summarize_mask(data[start:start + size], width, height)
            value['index'] = index
            value['matches_sprite_bbox'] = value['bounds'] == bbox if value['bounds'] is not None else None
            shapes[value['shape']] += 1
            bounds_counts['empty' if value['bounds'] is None else
                          'matches' if value['matches_sprite_bbox'] else 'differs'] += 1
            masks.append(value)
        sprites.append({'id': sprite_id, 'name': name, 'width': width, 'height': height,
                        'raw_bbox': bbox, 'separate_masks': info['separate_masks'], 'masks': masks})
    return {'apk_sha256': APK_SHA256, 'sprite_count': len(sprites),
            'mask_count': sum(len(s['masks']) for s in sprites), 'shape_counts': dict(sorted(shapes.items())),
            'bbox_counts': dict(sorted(bounds_counts.items())), 'sprites': sprites,
            'limitations': 'MSB-first interpretation matches pinned gmrunner, not verified against Android. '
                           'Raw pixel masks/bounds only; no positions, animation, transforms or runtime collision.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.apk)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f"Mask bitmaps: {report['mask_count']} across {report['sprite_count']} sprites; {report['shape_counts']}")
    print('Static interpretation only, not validated Android collision behavior.')


if __name__ == '__main__':
    main()
