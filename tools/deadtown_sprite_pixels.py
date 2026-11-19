#!/usr/bin/env python3
"""Compare original APK sprite atlas frames to GMX PNG frames, for research only.

Requires Pillow. Reconstructs only unscaled GMS 1.4 atlas regions; excludes
extra frames, scaled entries, masks and all runtime rendering behavior. Never
writes images into a game project, modifies assets or creates a game build.
"""
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

from PIL import Image

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_sprite_metadata import native_sprites, source_sprites
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_sprite_metadata import native_sprites, source_sprites
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32

MAX_DIM = 4096


def load_image(fp):
    with Image.open(fp) as img:
        if img.format != 'PNG' or not (0 < img.width <= MAX_DIM and 0 < img.height <= MAX_DIM):
            raise ValueError('unsupported image format or dimensions')
        return img.convert('RGBA')


def strip_transparent_rgb(image):
    # Fully transparent RGB can be changed by texture packing without changing
    # visible RGBA pixels. Preserve RGB and alpha at every nonzero-alpha pixel.
    result = image.copy()
    transparent = image.getchannel('A').point(lambda alpha: 255 if alpha == 0 else 0)
    result.paste((0, 0, 0, 0), (0, 0), transparent)
    return result


def compare_frame(atlas, region, source):
    sx, sy, sw, sh, tx, ty, tw, th, bw, bh, _ = region
    if not (sw and sh and tw and th and bw and bh):
        raise ValueError('empty texture page region')
    if sx + sw > atlas.width or sy + sh > atlas.height or tx + tw > bw or ty + th > bh:
        raise ValueError('texture region outside page or frame')
    if source.size != (bw, bh):
        return 'dimension_mismatch'
    if (sw, sh) != (tw, th):
        return 'scaled_not_compared'
    reconstructed = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
    reconstructed.paste(atlas.crop((sx, sy, sx + sw, sy + sh)), (tx, ty))
    if reconstructed.tobytes() == source.tobytes():
        return 'exact_rgba'
    if strip_transparent_rgb(reconstructed).tobytes() == strip_transparent_rgb(source).tobytes():
        return 'transparent_rgb_only'
    return 'visible_rgba_differs'


def compare(apk, project):
    apk, project = Path(apk), Path(project)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
    # Metadata parser verifies bytecode version, bounds and every TPAG pointer.
    native = native_sprites(data)
    source = source_sprites(project)
    regions = chunks(data)
    end = regions[b'TXTR'][1]
    atlases = []
    for pos in pointers(data, regions[b'TXTR']):
        if pos + 8 > end:
            raise ValueError('truncated texture header')
        offset = u32(data, pos + 4)
        if not regions[b'TXTR'][0] <= offset < end:
            raise ValueError('texture data outside TXTR')
        atlases.append(load_image(io.BytesIO(data[offset:end])))
    native_positions = {}
    for pos in pointers(data, regions[b'SPRT']):
        name = read_string(data, u32(data, pos), regions[b'STRG'])
        native_positions[name] = pos
    counts, per_sprite = Counter(), {}
    for name in sorted(source.keys() & native.keys()):
        xml = ET.parse(project / 'sprites' / (name + '.sprite.gmx')).getroot()
        entries = sorted(xml.findall('./frames/frame'), key=lambda item: int(item.get('index')))
        pos = native_positions[name]
        frame_count = min(len(entries), native[name]['frames'])
        rows = []
        for index in range(frame_count):
            text = entries[index].text or ''
            rel = Path(text.replace('\\', '/'))
            sprite_dir = (project / 'sprites').resolve()
            path = (sprite_dir / rel).resolve()
            if path == sprite_dir or sprite_dir not in path.parents:
                raise ValueError('source frame outside sprite directory')
            frame = load_image(path)
            page_ptr = u32(data, pos + 60 + 4 * index)
            if page_ptr + 22 > regions[b'TPAG'][1]:
                raise ValueError('truncated texture page item')
            page = struct.unpack_from('<10Hh', data, page_ptr)
            tex = page[-1]
            if not 0 <= tex < len(atlases):
                raise ValueError('invalid texture index')
            if page[8:10] != (native[name]['width'], native[name]['height']):
                raise ValueError('unexpected sprite and frame bounds')
            status = compare_frame(atlases[tex], page, frame)
            counts[status] += 1
            rows.append(status)
        per_sprite[name] = {'frames_compared_or_classified': frame_count,
                            'apk_extra_frames': max(0, native[name]['frames'] - len(entries)),
                            'gmx_extra_frames': max(0, len(entries) - native[name]['frames']),
                            'frames': rows}
    return {'apk_sha256': APK_SHA256, 'atlas_count': len(atlases), 'shared_sprites': len(per_sprite),
            'frame_counts': dict(sorted(counts.items())),
            'apk_extra_frames': sum(x['apk_extra_frames'] for x in per_sprite.values()),
            'gmx_extra_frames': sum(x['gmx_extra_frames'] for x in per_sprite.values()),
            'sprites': per_sprite,
            'limitations': 'Frame-index comparison for shared sprite names only. Unscaled PNG atlas regions; '
                           'fully transparent RGB ignored only in transparent_rgb_only. No masks, frame timings, '
                           'UI behavior, filtering or runtime equivalence. No APK-only sprites reconstructed.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.apk, args.project)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('Sprite-frame categories:', report['frame_counts'])
    print('Metadata/pixels only; not runtime UI equivalence. Report:', args.output)


if __name__ == '__main__':
    main()
