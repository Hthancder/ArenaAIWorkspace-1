#!/usr/bin/env python3
"""Compare sprite metadata against the pinned Android APK, not rendered pixels.

Reads only the GameMaker 1 / bytecode 15 layout in this specific APK. This is
research reporting, not a game patch or a proof of UI equivalence.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_native_inventory import project_names
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_native_inventory import project_names
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32


FIELDS = ('width', 'height', 'origin_x', 'origin_y', 'bbox_left', 'bbox_right',
          'bbox_top', 'bbox_bottom', 'bbox_mode', 'separate_masks', 'frames')


def native_sprites(data):
    regions = chunks(data)
    gen = regions[b'GEN8']
    if gen[1] - gen[0] < 2 or data[gen[0] + 1] != 15:
        raise ValueError('unsupported GameMaker bytecode version')
    spr = regions[b'SPRT']
    pages = set(pointers(data, regions[b'TPAG']))
    result = {}
    for pos in pointers(data, spr):
        if pos + 60 > spr[1]:
            raise ValueError('truncated sprite header')
        (name_ptr, width, height, left, right, bottom, top, _transparent,
         _smooth, _preload, bbox_mode, separate_masks, origin_x, origin_y,
         frame_count) = struct.unpack_from('<IIIiiiiIIIIIiiI', data, pos)
        name = read_string(data, name_ptr, regions[b'STRG'])
        if not name or name in result:
            raise ValueError('empty or duplicate sprite name')
        # GMS 2 sentinel is not supported. Bound the array before reading.
        if frame_count > (spr[1] - (pos + 60)) // 4:
            raise ValueError('invalid sprite frame count')
        frame_ptrs = [u32(data, pos + 60 + i * 4) for i in range(frame_count)]
        if any(ptr not in pages for ptr in frame_ptrs):
            raise ValueError('sprite frame points outside TPAG')
        if separate_masks not in (0, 1):
            raise ValueError('unexpected separate-masks flag')
        result[name] = dict(width=width, height=height, origin_x=origin_x, origin_y=origin_y,
                            bbox_left=left, bbox_right=right, bbox_top=top, bbox_bottom=bottom,
                            bbox_mode=bbox_mode, separate_masks=separate_masks, frames=frame_count)
    return result


def source_sprites(project):
    project = Path(project)
    result = {}
    for name in sorted(project_names(project, 'sprites', 'sprite')):
        root = ET.parse(project / 'sprites' / (name + '.sprite.gmx')).getroot()
        def number(field):
            text = root.findtext(field)
            if text is None:
                raise ValueError(f'missing {field} in {name}')
            return int(text)
        frames = root.findall('./frames/frame')
        indexes = sorted(int(f.get('index', '-1')) for f in frames)
        if indexes != list(range(len(frames))):
            raise ValueError(f'noncontiguous sprite frames in {name}')
        result[name] = dict(width=number('width'), height=number('height'),
                            origin_x=number('xorig'), origin_y=number('yorigin'),
                            bbox_left=number('bbox_left'), bbox_right=number('bbox_right'),
                            bbox_top=number('bbox_top'), bbox_bottom=number('bbox_bottom'),
                            bbox_mode=number('bboxmode'), separate_masks=int(number('sepmasks') != 0),
                            frames=len(frames))
    return result


def compare(apk, project):
    apk = Path(apk)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
    native, source = native_sprites(data), source_sprites(project)
    common = sorted(native.keys() & source.keys())
    differences, counts = {}, Counter()
    for name in common:
        diffs = {field: {'apk': native[name][field], 'gmx': source[name][field]}
                 for field in FIELDS if native[name][field] != source[name][field]}
        if diffs:
            differences[name] = diffs
            counts.update(diffs.keys())
    return {'apk_sha256': APK_SHA256, 'apk_sprites': len(native), 'gmx_sprites': len(source),
            'matched_names': len(common), 'matching_metadata': len(common) - len(differences),
            'differing_metadata': len(differences), 'field_mismatch_counts': dict(sorted(counts.items())),
            'apk_only': sorted(native.keys() - source.keys()),
            'gmx_only': sorted(source.keys() - native.keys()), 'differences': differences,
            'limitations': 'Metadata only; not decoded image pixels, masks, animation timing, '
                           'runtime rendering, UI behavior or equivalence. GMX names are project-declared.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.apk, args.project)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f"Sprite metadata: {report['apk_sprites']} APK, {report['gmx_sprites']} GMX, "
          f"{report['matched_names']} shared, {report['differing_metadata']} differing")
    print('Not a pixel or UI comparison. Report:', args.output)


if __name__ == '__main__':
    main()
