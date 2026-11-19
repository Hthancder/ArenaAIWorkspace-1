#!/usr/bin/env python3
"""Compare the original APK's exported YYC symbols with a GMX source project.

This is an inventory, not a decompiler. Matching names do not prove that the
native function and source code have the same implementation. It never runs
or modifies the Android binary and does not convert the original audio.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:  # invocation as python tools/deadtown_native_inventory.py
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32

EVENT_TYPES = ('Create', 'Destroy', 'Alarm', 'Step', 'Collision', 'Keyboard', 'Mouse',
               'Other', 'Draw', 'KeyPress', 'KeyRelease', 'Trigger', 'CleanUp', 'Gesture', 'PreCreate')
EVENT_RE = re.compile(r'^gml_Object_(.+)_(' + '|'.join(EVENT_TYPES) + r')_(\d+)$')


def exported_name(mangled):
    """Read the simple Itanium C++ name prefix without guessing suffix lengths."""
    match = re.match(r'^_Z([0-9]+)', mangled)
    if not match:
        return None
    count = int(match.group(1))
    start = match.end()
    name = mangled[start:start + count]
    if len(name) != count or not (name.startswith('gml_Object_') or name.startswith('gml_Script_')):
        return None
    return name


def parse_nm(output):
    scripts = {}
    events = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        name = exported_name(parts[0])
        if not name:
            continue
        record = {'address': int(parts[2], 16), 'size': int(parts[3], 16)}
        if name.startswith('gml_Script_'):
            scripts[name[len('gml_Script_'):]] = record
        else:
            match = EVENT_RE.fullmatch(name)
            if not match:
                raise ValueError(f'unrecognized native event {name}')
            key = (match.group(1), match.group(2), int(match.group(3)))
            if key in events:
                raise ValueError(f'duplicate native event {key}')
            events[key] = record
    if not scripts or not events:
        raise ValueError('no exported GML script or event symbols found')
    return scripts, events


def resource_names(data, chunk_name):
    info = chunks(data)
    return [read_string(data, u32(data, address), info[b'STRG'])
            for address in pointers(data, info[chunk_name])]


def project_names(project, section, element):
    tree = ET.parse(project / 'deadtown.project.gmx')
    node = tree.find(section)
    if node is None:
        raise ValueError(f'project missing {section}')
    names = set()
    for item in node.iter(element):
        if item.text:
            name = item.text.replace('\\', '/').rsplit('/', 1)[-1]
            names.add(name.removesuffix('.gml') if element == 'script' else name)
    return names


def source_events(project, objects, object_ids):
    events = set()
    unresolved = []
    for name in sorted(objects):
        file = project / 'objects' / f'{name}.object.gmx'
        if not file.is_file():
            raise ValueError(f'missing object file {file}')
        for event in ET.parse(file).findall('./events/event'):
            type_id = int(event.get('eventtype', '-1'))
            if not 0 <= type_id < len(EVENT_TYPES):
                raise ValueError(f'unsupported event type {type_id} in {name}')
            if type_id == 4:
                other = event.get('ename')
                if other not in object_ids:
                    unresolved.append(f'{name}:Collision:{other}')
                    continue
                subtype = object_ids[other]
            else:
                subtype = int(event.get('enumb', '-1'))
                if subtype < 0:
                    raise ValueError(f'missing event subtype in {name}')
            events.add((name, EVENT_TYPES[type_id], subtype))
    return events, unresolved


def event_strings(events):
    return [f'{obj}:{kind}:{subtype}' for obj, kind, subtype in sorted(events)]


def compare(apk_path, project):
    with zipfile.ZipFile(apk_path) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
        native = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    names = {key: resource_names(data, key) for key in (b'OBJT', b'SCPT', b'ROOM')}
    if len(set(names[b'OBJT'])) != len(names[b'OBJT']):
        raise ValueError('duplicate object names')
    with tempfile.TemporaryDirectory() as temp:
        lib = Path(temp) / 'libyoyo.so'
        lib.write_bytes(native)
        result = subprocess.run(['nm', '-D', '-S', '--defined-only', '--format=posix', str(lib)],
                                check=True, text=True, capture_output=True)
    native_scripts, native_events = parse_nm(result.stdout)
    all_scripts = {path.stem for path in (project / 'scripts').glob('*.gml')}
    all_objects = {path.name.removesuffix('.object.gmx') for path in (project / 'objects').glob('*.object.gmx')}
    declared_scripts = project_names(project, 'scripts', 'script')
    declared_objects = project_names(project, 'objects', 'object')
    declared_rooms = project_names(project, 'rooms', 'room')
    object_ids = {name: i for i, name in enumerate(names[b'OBJT'])}
    all_events, unresolved_all = source_events(project, all_objects, object_ids)
    declared_events, unresolved_declared = source_events(project, declared_objects, object_ids)
    script_set, event_set = set(native_scripts), set(native_events)
    source_info = {}
    for label, scripts, objects, events, unresolved in (
        ('all_files', all_scripts, all_objects, all_events, unresolved_all),
        ('project_declared', declared_scripts, declared_objects, declared_events, unresolved_declared),
    ):
        source_info[label] = {
            'script_files': len(scripts), 'object_files': len(objects), 'event_keys': len(events),
            'native_scripts_matching_names': len(scripts & script_set),
            'native_scripts_missing_in_source': sorted(script_set - scripts),
            'source_scripts_absent_in_native': sorted(scripts - script_set),
            'native_objects_missing_in_source': sorted(set(names[b'OBJT']) - objects),
            'source_objects_absent_in_apk': sorted(objects - set(names[b'OBJT'])),
            'native_event_keys_matching_source': len(events & event_set),
            'native_event_keys_missing_in_source': event_strings(event_set - events),
            'source_event_keys_absent_in_native': event_strings(events - event_set),
            'unresolved_collision_targets': unresolved,
        }
    return {
        'apk_sha256': hashlib.sha256(Path(apk_path).read_bytes()).hexdigest(),
        'game_droid_sha256': hashlib.sha256(data).hexdigest(),
        'native_arm_library_sha256': hashlib.sha256(native).hexdigest(),
        'apk_resource_counts': {key.decode(): len(value) for key, value in names.items()},
        'apk_room_names': names[b'ROOM'],
        'project_room_names': sorted(declared_rooms),
        'native_exported_script_count': len(native_scripts),
        'native_exported_event_count': len(native_events),
        'native_event_types': dict(sorted(Counter(key[1] for key in native_events).items())),
        'native_symbols': {'scripts': native_scripts,
                           'events': {f'{k[0]}:{k[1]}:{k[2]}': v for k, v in sorted(native_events.items())}},
        'comparison': source_info,
        'limitations': 'Name/event-key equality does not establish equivalent code or behavior. '
                       'Only exported symbols are inventoried; no native code is decompiled or executed.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path, help='directory containing deadtown.project.gmx')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = compare(args.apk, args.project)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    for label, counts in report['comparison'].items():
        print(f"{label}: native scripts matched {counts['native_scripts_matching_names']}/{report['native_exported_script_count']}; "
              f"native event keys matched {counts['native_event_keys_matching_source']}/{report['native_exported_event_count']}")
    print('Report:', args.output)


if __name__ == '__main__':
    main()
