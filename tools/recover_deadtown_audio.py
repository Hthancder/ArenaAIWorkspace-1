#!/usr/bin/env python3
"""Recover embedded audio from this GameMaker 1 APK, without transcoding.

This is a deliberately narrow reader for the version/layout of the supplied
Dead Town APK, not a general GameMaker container parser.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile

MAX_FILE = 64 * 1024 * 1024
SAFE_NAME = re.compile(r'^[A-Za-z0-9_]+$')


def u32(data, offset):
    if offset < 0 or offset + 4 > len(data):
        raise ValueError('integer outside container')
    return struct.unpack_from('<I', data, offset)[0]


def chunks(data):
    if len(data) < 8 or data[:4] != b'FORM' or u32(data, 4) != len(data) - 8:
        raise ValueError('invalid FORM header or size')
    result, pos = {}, 8
    while pos < len(data):
        if pos + 8 > len(data):
            raise ValueError('truncated chunk header')
        name, length = data[pos:pos + 4], u32(data, pos + 4)
        end = pos + 8 + length
        if end > len(data) or name in result:
            raise ValueError('invalid or duplicate chunk')
        result[name] = (pos + 8, end)
        pos = end
    return result


def pointers(data, region):
    start, end = region
    count = u32(data, start)
    if count > (end - start - 4) // 4:
        raise ValueError('invalid resource count')
    result = [u32(data, start + 4 + i * 4) for i in range(count)]
    if any(not start + 4 + count * 4 <= ptr < end for ptr in result):
        raise ValueError('resource pointer outside chunk')
    return result


def read_string(data, ptr, region):
    start, end = region
    if ptr < start + 4 or ptr > end:
        raise ValueError('string pointer outside STRG')
    length = u32(data, ptr - 4)
    if ptr + length >= end or data[ptr + length] != 0:
        raise ValueError('invalid string length')
    return data[ptr:ptr + length].decode('utf-8')


def read_zip_member(archive, name):
    info = archive.getinfo(name)
    if info.file_size > MAX_FILE:
        raise ValueError(f'{name} too large')
    return archive.read(info)


def recover(apk):
    with zipfile.ZipFile(apk) as archive:
        game = read_zip_member(archive, 'assets/game.droid')
        files = {0: game}
        for group in (1, 2):
            files[group] = read_zip_member(archive, f'assets/audiogroup{group}.dat')
    info = chunks(game)
    # Bytecode version 15 and the layout checked against UndertaleModLib.
    if game[info[b'GEN8'][0] + 1] != 15:
        raise ValueError('unsupported GameMaker bytecode version')
    sounds = pointers(game, info[b'SOND'])
    groups = {group: (data, chunks(data)[b'AUDO']) for group, data in files.items()}
    tables = {group: pointers(data, region) for group, (data, region) in groups.items()}
    recovered = []
    seen = set()
    for pos in sounds:
        if pos + 36 > info[b'SOND'][1]:
            raise ValueError('truncated sound entry')
        name_ptr, flags, type_ptr, file_ptr, _, _, _, group, index = struct.unpack_from('<9I', game, pos)
        name = read_string(game, name_ptr, info[b'STRG'])
        original = read_string(game, file_ptr, info[b'STRG'])
        source_type = read_string(game, type_ptr, info[b'STRG'])
        if not SAFE_NAME.fullmatch(name) or name in seen:
            raise ValueError(f'unsafe or duplicate sound name: {name!r}')
        seen.add(name)
        if (flags & 0x64) != 0x64 or group not in groups or index >= len(tables[group]):
            raise ValueError(f'unsupported sound reference: {name}')
        data, region = groups[group]
        offset = tables[group][index]
        size = u32(data, offset)
        if size > region[1] - offset - 4:
            raise ValueError(f'truncated embedded sound: {name}')
        payload = data[offset + 4:offset + 4 + size]
        if payload.startswith(b'OggS\x00'):
            extension = '.ogg'
        elif payload.startswith(b'RIFF') and payload[8:12] == b'WAVE':
            extension = '.wav'
        else:
            raise ValueError(f'unknown audio format: {name}')
        recovered.append((name, original, source_type, group, index, extension, payload))
    return recovered


def extract(apk, output):
    output = Path(output)
    if output.exists():
        raise ValueError('output already exists; refusing to overwrite')
    records = recover(apk)
    output.mkdir(parents=True)
    manifest = []
    for name, original, source_type, group, index, extension, payload in records:
        filename = name + extension
        (output / filename).write_bytes(payload)
        manifest.append({'name': name, 'file': filename, 'original_name': original,
                         'source_type': source_type, 'group': group, 'index': index,
                         'size': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()})
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


def apply(project, audio_dir):
    """Update a staging copy only. Never use on the original upstream checkout."""
    project, audio_dir = Path(project), Path(audio_dir)
    records = json.loads((audio_dir / 'manifest.json').read_text(encoding='utf-8'))
    by_name = {r['name']: r for r in records}
    root = ET.parse(project / 'deadtown.project.gmx').getroot()
    changes = []
    for item in root.iter('sound'):
        if not item.text or not item.text.strip():
            continue
        path = item.text.strip().replace('\\', '/')
        descriptor = project / (path + '.sound.gmx')
        name = Path(path).name
        record = by_name.get(name)
        if not record:
            raise ValueError(f'APK does not contain sound {name}')
        filename = record['file']
        if filename not in (name + '.ogg', name + '.wav'):
            raise ValueError(f'invalid recovered filename: {filename}')
        content = (audio_dir / filename).read_bytes()
        if hashlib.sha256(content).hexdigest() != record['sha256']:
            raise ValueError(f'audio checksum mismatch: {filename}')
        tree = ET.parse(descriptor)
        for tag, value in [('extension', Path(filename).suffix), ('origname', 'sound\\audio\\' + filename), ('data', filename)]:
            node = tree.find(tag)
            if node is None:
                raise ValueError(f'missing {tag} in {descriptor}')
            node.text = value
        changes.append((descriptor, tree, filename, content))
    out = project / 'sound' / 'audio'
    out.mkdir(parents=True, exist_ok=True)
    for descriptor, tree, filename, content in changes:
        (out / filename).write_bytes(content)
        tree.write(descriptor, encoding='utf-8', xml_declaration=True)
    return len(changes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    a = sub.add_parser('extract')
    a.add_argument('apk')
    a.add_argument('output')
    b = sub.add_parser('apply')
    b.add_argument('project', help='staged project copy (not the upstream checkout)')
    b.add_argument('audio_dir')
    args = parser.parse_args()
    try:
        if args.command == 'extract':
            manifest = extract(args.apk, args.output)
            print(f'Extracted {len(manifest)} embedded audio files without transcoding to {args.output}')
        else:
            print(f'Updated {apply(args.project, args.audio_dir)} staged sound descriptors without transcoding')
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile, ET.ParseError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
