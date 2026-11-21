#!/usr/bin/env python3
"""Compare static GMS1 object defaults in pinned APK and editable GMX.

Not a decompiler: events, runtime assignments, mask pixels and physics behavior
are not compared. Object parent/sprite names resolve against each own resource
list rather than assuming compiler IDs match.
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
    from tools.deadtown_native_inventory import project_names, resource_names
    from tools.deadtown_room_evidence import checked, nested_pointers
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_native_inventory import project_names, resource_names
    from deadtown_room_evidence import checked, nested_pointers
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32

FIELDS = ('sprite', 'visible', 'solid', 'depth', 'persistent', 'parent', 'mask', 'physics')


def reference(names, idx, null):
    if idx in null:
        return None
    if idx < 0 or idx >= len(names):
        raise ValueError(f'object resource index outside table: {idx}')
    return names[idx]


def event_counts(data, pos, region):
    checked(data, pos, 80, region)
    vertices = u32(data, pos + 64)
    events = pos + 80 + 8 * vertices
    checked(data, events, 4, region)
    count = u32(data, events)
    if count != 12:
        raise ValueError('unexpected GMS1 event type count')
    checked(data, events + 4, 4 * count, region)
    return [len(nested_pointers(data, u32(data, events + 4 + 4 * i), region, 8)) for i in range(count)]


def native_objects(data):
    regions = chunks(data)
    gen = regions[b'GEN8'][0]
    if data[gen + 1] != 15 or u32(data, gen + 44) != 1:
        raise ValueError('expected GameMaker 1 bytecode 15')
    names = resource_names(data, b'OBJT')
    sprites = resource_names(data, b'SPRT')
    if len(set(names)) != len(names) or len(set(sprites)) != len(sprites):
        raise ValueError('duplicate object or sprite name')
    result = {}
    for p in pointers(data, regions[b'OBJT']):
        if p + 36 > regions[b'OBJT'][1]:
            raise ValueError('truncated object header')
        nameptr, sprite, visible, solid, depth, persistent, parent, mask, physics = struct.unpack_from('<I8i', data, p)
        name = read_string(data, nameptr, regions[b'STRG'])
        result[name] = dict(sprite=reference(sprites, sprite, {-1}), visible=bool(visible), solid=bool(solid),
                            depth=depth, persistent=bool(persistent), parent=reference(names, parent, {-100, -1}),
                            mask=reference(sprites, mask, {-1}), physics=bool(physics),
                            event_counts=event_counts(data, p, regions[b'OBJT']))
    return result


def source_object(path):
    root = ET.parse(path).getroot()
    def text(key):
        value = root.findtext(key)
        if value is None:
            raise ValueError(f'missing object field {key}: {path}')
        return value
    def name(key):
        value = text(key)
        return None if value in ('', '<undefined>') else value
    return dict(sprite=name('spriteName'), visible=bool(int(text('visible'))), solid=bool(int(text('solid'))),
                depth=int(text('depth')), persistent=bool(int(text('persistent'))), parent=name('parentName'),
                mask=name('maskName'), physics=bool(int(text('PhysicsObject'))))


def compare(apk, project):
    project = Path(project)
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
    native = native_objects(data)
    names = project_names(project, 'objects', 'object')
    source = {name: source_object(project / 'objects' / (name + '.object.gmx')) for name in names}
    common = native.keys() & source.keys()
    differences = {}
    counts = Counter()
    for name in sorted(common):
        delta = {field: {'apk': native[name][field], 'gmx': source[name][field]}
                 for field in FIELDS if native[name][field] != source[name][field]}
        if delta:
            differences[name] = delta
            counts.update(delta.keys())
    return {'apk_count': len(native), 'gmx_declared_count': len(source), 'common_count': len(common),
            'matching_defaults_count': len(common) - len(differences),
            'differing_defaults_count': len(differences), 'field_mismatch_counts': dict(sorted(counts.items())),
            'apk_only': sorted(native.keys() - source.keys()), 'gmx_only': sorted(source.keys() - native.keys()),
            'differences': differences,
            'limitations': 'Only selected initial object defaults, using names not assumed resource IDs. '
                           'Events, dynamic assignments, mask pixels, physics behavior, rendering and iOS not tested.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    report = compare(a.apk, a.project)
    a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"OBJECT_EVIDENCE: {report['common_count']} shared, {report['differing_defaults_count']} differ in selected defaults; static only")


if __name__ == '__main__':
    main()
