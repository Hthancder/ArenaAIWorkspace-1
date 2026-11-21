#!/usr/bin/env python3
"""Compare pinned APK background atlas images with a materialized GMX project.

Checks unscaled static pixels and a few fields, not tileset-editor settings,
compiled resource IDs, renderer, room layout, gameplay, or iOS.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

try:
    from tools.check_deadtown_sound_evidence import safe_asset
    from tools.deadtown_native_inventory import project_names
    from tools.deadtown_sprite_pixels import compare_frame, load_image
    from tools.recover_deadtown_audio import SAFE_NAME, pointers, read_string
    from tools.recover_deadtown_sprites import open_apk
except ModuleNotFoundError:
    from check_deadtown_sound_evidence import safe_asset
    from deadtown_native_inventory import project_names
    from deadtown_sprite_pixels import compare_frame, load_image
    from recover_deadtown_audio import SAFE_NAME, pointers, read_string
    from recover_deadtown_sprites import open_apk


def native_backgrounds(data, regions, atlases):
    pages = set(pointers(data, regions[b'TPAG']))
    start, end = regions[b'BGND']
    result = {}
    for index, pos in enumerate(pointers(data, (start, end))):
        if pos + 20 > end:
            raise ValueError('truncated background entry')
        nameptr, transparent, smooth, preload, tpag = struct.unpack_from('<5I', data, pos)
        name = read_string(data, nameptr, regions[b'STRG'])
        if not SAFE_NAME.fullmatch(name) or name in result:
            raise ValueError('unsafe or duplicate background name')
        if tpag not in pages or tpag + 22 > regions[b'TPAG'][1]:
            raise ValueError(f'invalid texture page reference: {name}')
        page = struct.unpack_from('<10Hh', data, tpag)
        if not 0 <= page[-1] < len(atlases):
            raise ValueError(f'invalid atlas index: {name}')
        result[name] = {'native_index': index, 'transparent': transparent, 'smooth': smooth,
                        'preload': preload, 'page': page}
    return result


def compare(apk, project):
    project = Path(project)
    data, _, regions, atlases = open_apk(apk)
    native = native_backgrounds(data, regions, atlases)
    declared = project_names(project, 'backgrounds', 'background')
    root = ET.parse(project / 'deadtown.project.gmx').getroot()
    section = root.find('backgrounds')
    if section is None:
        raise ValueError('missing backgrounds section')
    order = []
    for item in section.iter('background'):
        if item.text:
            name = item.text.replace('\\', '/').rsplit('/', 1)[-1]
            if not SAFE_NAME.fullmatch(name):
                raise ValueError('unsafe project background name')
            order.append(name)
    if len(order) != len(set(order)) or set(order) != declared:
        raise ValueError('duplicate or invalid project background declarations')
    counts, records = Counter(), {}
    for name in sorted(native.keys() & declared):
        descriptor = safe_asset(project, Path('background') / (name + '.background.gmx'))
        xml = ET.parse(descriptor).getroot()
        expected_path = 'images\\' + name + '.png'
        if xml.findtext('data') != expected_path:
            raise ValueError(f'unexpected background path: {name}')
        image = load_image(safe_asset(project, Path('background/images') / (name + '.png')))
        source_size = (int(xml.findtext('width')), int(xml.findtext('height')))
        if image.size != source_size:
            raise ValueError(f'background descriptor dimensions differ from PNG: {name}')
        info, page = native[name], native[name]['page']
        result = compare_frame(atlases[page[-1]], page, image)
        counts[result] += 1
        records[name] = {'native_index': info['native_index'], 'xml_index': order.index(name),
                         'native_size': list(page[8:10]), 'source_size': list(source_size),
                         'pixels': result, 'native_header': {k: info[k] for k in ('transparent', 'smooth', 'preload')},
                         'atlas_region': list(page)}
    common_order = [x for x in order if x in native]
    inversions = sum(native[a]['native_index'] > native[b]['native_index']
                     for i, a in enumerate(common_order) for b in common_order[i + 1:])
    return {'native_count': len(native), 'declared_count': len(declared), 'shared_count': len(records),
            'native_only': sorted(native.keys() - declared), 'source_only': sorted(declared - native.keys()),
            'pixel_counts': dict(sorted(counts.items())), 'xml_order_inversions': inversions,
            'backgrounds': records,
            'limitations': 'Unscaled atlas pixels compared by name; scaled targets classified but not resampled. '
                           'Native header flags and XML order are not proven compiler semantics or resource IDs. '
                           'Tile-editor slicing, runtime renderer, gameplay and iOS not tested.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.apk, args.project)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"BACKGROUND_EVIDENCE: {report['shared_count']} shared, pixels {report['pixel_counts']}; static only")


if __name__ == '__main__':
    main()
