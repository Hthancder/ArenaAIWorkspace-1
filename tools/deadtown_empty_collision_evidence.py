#!/usr/bin/env python3
"""Verify four no-op collisions using pinned APK OBJT and ARM32 bytes.

This checks explicit native events and comment-only GMX actions. It
is not a collision-dispatch, inherited behavior, GameMaker compiler or iOS test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_event_probe import translate_actions
    from tools.deadtown_native_inventory import exported_name, resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.deadtown_room_evidence import checked, nested_pointers
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_event_probe import translate_actions
    from deadtown_native_inventory import exported_name, resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from deadtown_room_evidence import checked, nested_pointers
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32


def elf_file_bytes(raw, addr, size):
    if len(raw) < 52 or raw[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H', raw, 18)[0] != 40:
        raise ValueError('expected ARM little-endian ELF32')
    phoff = u32(raw, 28)
    entry_size, count = struct.unpack_from('<HH', raw, 42)
    if entry_size < 32 or phoff + entry_size * count > len(raw):
        raise ValueError('invalid ELF program headers')
    for i in range(count):
        ptype, offset, vaddr, _, file_size = struct.unpack_from('<5I', raw, phoff + i * entry_size)
        if ptype == 1 and vaddr <= addr and addr + size <= vaddr + file_size:
            start = offset + addr - vaddr
            if start + size > len(raw):
                raise ValueError('truncated ELF segment')
            return raw[start:start + size]
    raise ValueError('function not backed by ELF file bytes')


def verify(apk, project):
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        data = read_zip_member(z, 'assets/game.droid')
        lib = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(lib).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    regions = chunks(data)
    if data[regions[b'GEN8'][0] + 1] != 15 or u32(data, regions[b'GEN8'][0] + 44) != 1:
        raise ValueError('unexpected GameMaker format')
    objects = resource_names(data, b'OBJT')
    targets = (("obj_player", "par_action", 184, 0x5d1670),
               ("obj_zombie4", "obj_player_body", 144, 0x682b00),
               ("obj_zombie5", "par_action_door", 187, 0x690808),
               ("obj_zombie5", "par_action", 184, 0x69080c))
    if len(objects) != 240 or any(objects[index] != target for _, target, index, _ in targets):
        raise ValueError('unexpected collision object index')
    region = regions[b'OBJT']
    object_positions = {}
    for p in pointers(data, region):
        name = read_string(data, u32(data, p), regions[b'STRG'])
        if name in object_positions:
            raise ValueError('duplicate native object name')
        object_positions[name] = p
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'libyoyo.so'
        path.write_bytes(lib)
        output = subprocess.run(['nm', '-D', '-S', '--defined-only', '--format=posix', str(path)],
                                check=True, capture_output=True, text=True).stdout
    symbols = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 4:
            name = exported_name(parts[0])
            if name:
                symbols.setdefault(name, []).append((int(parts[2], 16), int(parts[3], 16)))
    results = []
    for obj, target, index, address in targets:
        p = object_positions.get(obj)
        if p is None:
            raise ValueError('native object missing: '+obj)
        checked(data, p, 80, region)
        ev = p + 80 + 8 * u32(data, p + 64)
        checked(data, ev, 4 + 12 * 4, region)
        if u32(data, ev) != 12:
            raise ValueError('unexpected event type count')
        collisions = nested_pointers(data, u32(data, ev + 4 + 4 * 4), region, 8)
        matches = [ptr for ptr in collisions if u32(data, ptr) == index]
        if len(matches) != 1:
            raise ValueError('native collision event missing or duplicated: '+obj)
        event = matches[0]
        if u32(data, event + 4) != 1:
            raise ValueError('unexpected native action count')
        checked(data, event + 8, 4, region)
        action = u32(data, event + 8)
        checked(data, action, 36, region)
        if (u32(data, action), u32(data, action + 4), u32(data, action + 8)) != (1, 603, 7):
            raise ValueError('unexpected native action kind')
        symbol = f'gml_Object_{obj}_Collision_{index}'
        if symbols.get(symbol) != [(address, 4)] or elf_file_bytes(lib, address, 4) != b'\x1e\xff\x2f\xe1':
            raise ValueError('native event is not a single ARM bx lr: '+symbol)
        root = ET.parse(Path(project) / 'objects' / (obj+'.object.gmx')).getroot()
        events = [e for e in root.findall('./events/event') if e.get('eventtype') == '4' and e.get('ename') == target]
        if len(events) != 1:
            raise ValueError('source collision event missing or duplicated: '+symbol)
        actions = events[0].findall('action')
        if (len(actions) != 1 or actions[0].findtext('./arguments/argument/string') != '/// not inherited\n'
                or translate_actions(actions) != '{\n/// not inherited\n\n}\n'):
            raise ValueError('source event is not the expected comment-only action: '+symbol)
        results.append({'object': obj, 'collision_target': target, 'native_target_index': index,
                        'native_export_address': hex(address), 'native_arm_bytes': '1eff2fe1',
                        'native_action_count': 1, 'source_action': 'comment-only'})
    return {'events': results,
            'limitations': 'Static OBJT and ARM bytes only; no collision dispatch, inheritance, compile or device proof.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.apk, args.project)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('EMPTY_COLLISION_EVIDENCE: four events; static only')


if __name__ == '__main__':
    main()
