#!/usr/bin/env python3
"""Archive static data of eight missing rooms for research, not runnable GMX.

Specific pinned GMS1 APK. Preserves room-list order, instance/tile IDs and code
indices in addition to parsed fields. Code contents and object behavior are not
recovered; numeric IDs are native values, not portable compiled resource IDs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_room_evidence import native_rooms, nested_pointers
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_room_evidence import native_rooms, nested_pointers
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32

NAMES = frozenset(('rom_multi_lobby', 'rom_multi_login', 'rom_multi_room',
                   'rom_play_defence', 'rom_play_sewer', 'rom_setting_display',
                   'rom_setting_effect', 'rom_setting_save'))
NOTICE = ('RESEARCH ONLY: static APK room records, not runnable GMX rooms.\n'
          'Missing object events and creation code are not recovered. Native IDs are not portable.\n')


def collect_data(data):
    regions = chunks(data)
    parsed = native_rooms(data)  # validates GMS version, lists, resource indices and finite floats
    region = regions[b'ROOM']
    records = []
    for index, p in enumerate(pointers(data, region)):
        name = read_string(data, u32(data, p), regions[b'STRG'])
        if name not in NAMES:
            continue
        room = parsed[name]
        instance_ptrs = nested_pointers(data, u32(data, p + 48), region, 36)
        tile_ptrs = nested_pointers(data, u32(data, p + 52), region, 48)
        instances = []
        for values, q in zip(room['instances'], instance_ptrs):
            obj, x, y, sx, sy, colour, rotation = values
            inst_id, code = struct.unpack_from('<Ii', data, q + 12)
            instances.append(dict(object=obj, x=x, y=y, id=inst_id, creation_code_index=code,
                                  scale_x=sx, scale_y=sy, colour=colour, rotation=rotation))
        tiles = []
        for values, q in zip(room['tiles'], tile_ptrs):
            bg, x, y, xo, yo, width, height, depth, sx, sy, colour = values
            tiles.append(dict(background=bg, x=x, y=y, source_x=xo, source_y=yo,
                              width=width, height=height, depth=depth, id=u32(data, q + 32),
                              scale_x=sx, scale_y=sy, colour=colour))
        records.append(dict(name=name, native_room_index=index,
                            caption=read_string(data, u32(data, p + 4), regions[b'STRG']),
                            fields=room['fields'], room_creation_code_index=struct.unpack_from('<i', data, p + 32)[0],
                            views=room['views'], backgrounds=room['backgrounds'],
                            instances=instances, tiles=tiles))
    if {r['name'] for r in records} != NAMES or len(records) != len(NAMES):
        raise ValueError('expected exactly the eight missing native rooms')
    return {'format': 1, 'apk_sha256': APK_SHA256,
            'limitations': 'Static records only; no event/creation code or gameplay. Native IDs are not portable.',
            'view_columns': ['visible', 'xview', 'yview', 'wview', 'hview', 'xport', 'yport', 'wport', 'hport',
                             'hborder', 'vborder', 'hspeed', 'vspeed', 'follow_object'],
            'background_columns': ['visible', 'foreground', 'background', 'x', 'y', 'htiled', 'vtiled',
                                   'hspeed', 'vspeed', 'stretch'], 'rooms': records}


def collect(apk):
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        return collect_data(read_zip_member(z, 'assets/game.droid'))


def run(apk, folder, write=False):
    folder = Path(folder)
    expected = collect(apk)
    # Normalize tuples to lists as in the serialized representation.
    expected = json.loads(json.dumps(expected, allow_nan=False))
    if write:
        folder.mkdir(parents=True, exist_ok=False)
        (folder / 'RESEARCH-ONLY.txt').write_text(NOTICE, encoding='utf-8')
        (folder / 'rooms.json').write_text(json.dumps(expected, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    else:
        if folder.is_symlink() or not folder.is_dir():
            raise ValueError('not a real folder')
        for name in ('RESEARCH-ONLY.txt', 'rooms.json'):
            if (folder / name).is_symlink() or not (folder / name).is_file():
                raise ValueError('invalid research file')
        if (folder / 'RESEARCH-ONLY.txt').read_text(encoding='utf-8') != NOTICE:
            raise ValueError('missing research notice')
        if json.loads((folder / 'rooms.json').read_text(encoding='utf-8')) != expected:
            raise ValueError('room archive mismatch')
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('extract', 'verify'))
    parser.add_argument('apk', type=Path)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    records = run(args.apk, args.folder, args.command == 'extract')['rooms']
    print(f"UNRESOLVED_ROOMS_{args.command.upper()}: {len(records)} rooms, "
          f"{sum(len(r['instances']) for r in records)} instances, "
          f"{sum(len(r['tiles']) for r in records)} tiles; research only")


if __name__ == '__main__':
    main()
