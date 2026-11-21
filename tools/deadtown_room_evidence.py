#!/usr/bin/env python3
"""Compare selected static ROOM fields and placed instances against editable GMX.

Specific pinned GameMaker 1/bytecode 15 APK only. This is not a room converter:
creation code, underlying tile pixels, runtime changes and gameplay are not compared.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_native_inventory import resource_names, project_names
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_native_inventory import resource_names, project_names
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32


def checked(data, offset, size, region):
    if offset < region[0] or size < 0 or offset + size > region[1]:
        raise ValueError('room data outside ROOM chunk')
    return data[offset:offset + size]


def nested_pointers(data, offset, region, entry_size):
    checked(data, offset, 4, region)
    count = u32(data, offset)
    checked(data, offset + 4, 4 * count, region)
    result = [u32(data, offset + 4 + 4 * i) for i in range(count)]
    for ptr in result:
        checked(data, ptr, entry_size, region)
    if len(result) != len(set(result)):
        raise ValueError('duplicate room list pointer')
    return result


def item_name(names, index, nullable=False):
    if nullable and index == -1:
        return None
    if index < 0 or index >= len(names):
        raise ValueError(f'invalid resource index: {index}')
    return names[index]


def normalize_float(n):
    n = float(n)
    if not math.isfinite(n):
        raise ValueError('non-finite instance value')
    return struct.unpack('<f', struct.pack('<f', n))[0]


def native_rooms(data):
    regions = chunks(data)
    gen = regions[b'GEN8'][0]
    if data[gen + 1] != 15 or u32(data, gen + 44) != 1:
        raise ValueError('expected GameMaker 1 bytecode 15')
    objects = resource_names(data, b'OBJT')
    backgrounds = resource_names(data, b'BGND')
    region = regions[b'ROOM']
    result = {}
    for p in pointers(data, region):
        checked(data, p, 56, region)
        name = read_string(data, u32(data, p), regions[b'STRG'])
        if name in result:
            raise ValueError('duplicate room name')
        w, h, speed, persistent, color, showcolor, creation, flags = struct.unpack_from('<6IiI', data, p + 8)
        views = []
        for q in nested_pointers(data, u32(data, p + 44), region, 56):
            vals = struct.unpack_from('<14i', data, q)
            views.append((bool(vals[0]), *vals[1:13], item_name(objects, vals[13], True)))
        bgs = []
        for q in nested_pointers(data, u32(data, p + 40), region, 40):
            v = struct.unpack_from('<10i', data, q)
            bgs.append((bool(v[0]), bool(v[1]), item_name(backgrounds, v[2], True), v[3], v[4],
                        bool(v[5]), bool(v[6]), v[7], v[8], bool(v[9])))
        instances = []
        codes = 0
        for q in nested_pointers(data, u32(data, p + 48), region, 36):
            x, y, obj, inst_id, code, sx, sy, colour, rotation = struct.unpack_from('<iiiIiffIf', data, q)
            if not all(math.isfinite(x) for x in (sx, sy, rotation)):
                raise ValueError('non-finite native instance value')
            instances.append((item_name(objects, obj), x, y, sx, sy, colour, rotation))
            codes += code != -1
        tiles = []
        for q in nested_pointers(data, u32(data, p + 52), region, 48):
            x, y, bg, xo, yo, width, height, depth, tile_id, sx, sy, colour = struct.unpack_from('<iiiIIIIiIffI', data, q)
            if not all(math.isfinite(v) for v in (sx, sy)):
                raise ValueError('non-finite native tile value')
            tiles.append((item_name(backgrounds, bg), x, y, xo, yo, width, height, depth, sx, sy, colour))
        result[name] = {'fields': {'width': w, 'height': h, 'speed': speed, 'persistent': bool(persistent),
                                   'colour': color, 'showcolour': bool(showcolor), 'enable_views': bool(flags & 1)},
                        'views': views, 'backgrounds': bgs, 'instances': instances, 'tiles': tiles,
                        'creation_code_reference': creation != -1, 'instances_with_creation_code': codes}
    return result


def source_room(path):
    root = ET.parse(path).getroot()
    def number(node, key):
        value = node.findtext(key)
        if value is None:
            raise ValueError(f'missing room field {key}')
        return int(value)
    fields = {k: number(root, k) for k in ('width', 'height', 'speed', 'persistent', 'colour', 'showcolour')}
    for k in ('persistent', 'showcolour'):
        fields[k] = bool(fields[k])
    fields['enable_views'] = bool(number(root, 'enableViews'))
    def res(s):
        return None if s in ('', '<undefined>') else s
    views = []
    for e in root.findall('./views/view'):
        names = ('xview', 'yview', 'wview', 'hview', 'xport', 'yport', 'wport', 'hport', 'hborder', 'vborder', 'hspeed', 'vspeed')
        views.append((bool(int(e.attrib['visible'])), *(int(e.attrib[n]) for n in names), res(e.attrib['objName'])))
    bgs = []
    for e in root.findall('./backgrounds/background'):
        a = e.attrib
        bgs.append((bool(int(a['visible'])), bool(int(a['foreground'])), res(a['name']), int(a['x']), int(a['y']),
                    bool(int(a['htiled'])), bool(int(a['vtiled'])), int(a['hspeed']), int(a['vspeed']), bool(int(a['stretch']))))
    instances = []
    for e in root.findall('./instances/instance'):
        a = e.attrib
        instances.append((a['objName'], int(a['x']), int(a['y']), normalize_float(a['scaleX']),
                          normalize_float(a['scaleY']), int(a['colour']) & 0xffffffff, normalize_float(a['rotation'])))
    tiles = []
    for e in root.findall('./tiles/tile'):
        a = e.attrib
        tiles.append((a['bgName'], *(int(a[k]) for k in ('x', 'y', 'xo', 'yo', 'w', 'h', 'depth')),
                      normalize_float(a['scaleX']), normalize_float(a['scaleY']), int(a['colour']) & 0xffffffff))
    return {'fields': fields, 'views': views, 'backgrounds': bgs, 'instances': instances,
            'tiles': tiles,
            'room_code_present': bool((root.findtext('code') or '').strip()),
            'instances_with_creation_code': sum(bool(e.get('code', '').strip()) for e in root.findall('./instances/instance'))}


def instance_comparison(native, source):
    a, b = Counter(native), Counter(source)
    def entries(counter):
        return [{'object': key[0], 'x': key[1], 'y': key[2], 'scale_x': key[3], 'scale_y': key[4],
                 'colour': key[5], 'rotation': key[6], 'count': count}
                for key, count in sorted(counter.items())]
    return {'apk_count': len(native), 'gmx_count': len(source), 'matched_count': sum((a & b).values()),
            'apk_only': entries(a - b), 'gmx_only': entries(b - a)}


def tile_comparison(native, source):
    a, b = Counter(native), Counter(source)
    def entries(counter):
        keys = ('background', 'x', 'y', 'source_x', 'source_y', 'width', 'height', 'depth', 'scale_x', 'scale_y', 'colour')
        return [dict(zip(keys, key), count=count) for key, count in sorted(counter.items())]
    return {'apk_count': len(native), 'gmx_count': len(source), 'matched_count': sum((a & b).values()),
            'apk_only': entries(a - b), 'gmx_only': entries(b - a)}


def compare(apk, project):
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
    native = native_rooms(data)
    names = project_names(Path(project), 'rooms', 'room')
    rooms = {}
    for name in sorted(native.keys() & names):
        a = native[name]
        b = source_room(Path(project) / 'rooms' / (name + '.room.gmx'))
        rooms[name] = {'fields_differ': {k: {'apk': v, 'gmx': b['fields'][k]} for k, v in a['fields'].items() if v != b['fields'][k]},
                       'views_equal': a['views'] == b['views'], 'apk_views': a['views'], 'gmx_views': b['views'],
                       'backgrounds_equal': a['backgrounds'] == b['backgrounds'],
                       'apk_backgrounds': a['backgrounds'], 'gmx_backgrounds': b['backgrounds'],
                       'instances': instance_comparison(a['instances'], b['instances']),
                       'tiles': tile_comparison(a['tiles'], b['tiles']),
                       'creation_code': {'apk_room_ref': a['creation_code_reference'], 'gmx_room_text': b['room_code_present'],
                                         'apk_instance_refs': a['instances_with_creation_code'], 'gmx_instance_texts': b['instances_with_creation_code']}}
    return {'apk_rooms': sorted(native), 'gmx_declared_rooms': sorted(names),
            'apk_only': sorted(native.keys() - names), 'gmx_only': sorted(names - native.keys()), 'shared': rooms,
            'limitations': 'Static initial state only, compares selected fields and placements without instance/tile IDs or order. '
                           'Tile pixels, creation code contents, physics, runtime behavior and iOS are not compared.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    report = compare(args.apk, args.project)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f"ROOM_EVIDENCE: APK={len(report['apk_rooms'])}, GMX={len(report['gmx_declared_rooms'])}, shared={len(report['shared'])}; static only")


if __name__ == '__main__':
    main()
