#!/usr/bin/env python3
"""Compare the old RE-test3 IPA graphics data to the pinned Android APK.

Static asset comparison only. This does not render, execute on iOS, diagnose
motion trails, or reproduce the reported on-device failure.
"""
import argparse
import json
from pathlib import Path
import zipfile

try:
    from tools.deadtown_ios_compare import APK_SHA, png_payloads, sha, sprite_layout
    from tools.deadtown_native_inventory import resource_names
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_ios_compare import APK_SHA, png_payloads, sha, sprite_layout
    from deadtown_native_inventory import resource_names
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32

IPA_SHA = '7e0f10c8761fe1160baa855a4e825aa31974f02cb2b2205a27b0df9d5aefe781'
TEST_DATA_SHA = '313da9db0f0f74b1e9eea100b8f0de0e7d315e3f21697d638a44a9e2014608b0'


def room_background_defaults(data):
    regions = chunks(data)
    start, end = regions[b'GEN8']
    if end - start < 2 or data[start + 1] != 15:
        raise ValueError('unexpected GameMaker bytecode version')
    result = {}
    for pos in pointers(data, regions[b'ROOM']):
        if pos + 32 > regions[b'ROOM'][1]:
            raise ValueError('truncated room header')
        name = read_string(data, u32(data, pos), regions[b'STRG'])
        if not name or name in result:
            raise ValueError('invalid or duplicate room name')
        show = u32(data, pos + 28)
        if show not in (0, 1):
            raise ValueError('unexpected room background flag')
        result[name] = {'color': u32(data, pos + 24), 'show_color': bool(show)}
    return result


def compare(ipa_path, apk_path):
    ipa_path, apk_path = Path(ipa_path), Path(apk_path)
    if sha(ipa_path.read_bytes()) != IPA_SHA or sha(apk_path.read_bytes()) != APK_SHA:
        raise ValueError('unexpected IPA or APK SHA-256')
    with zipfile.ZipFile(ipa_path) as z:
        test = read_zip_member(z, 'Payload/gmRunner.app/BundledGame/data.win')
    if sha(test) != TEST_DATA_SHA:
        raise ValueError('unexpected test data SHA-256')
    with zipfile.ZipFile(apk_path) as z:
        android = read_zip_member(z, 'assets/game.droid')
    resource = {}
    for kind in (b'SPRT', b'OBJT', b'ROOM'):
        a, b = resource_names(android, kind), resource_names(test, kind)
        resource[kind.decode()] = {'apk_count': len(a), 'test_count': len(b), 'names_same_order': a == b}
    one, two = sprite_layout(android), sprite_layout(test)
    shared = one.keys() & two.keys()
    textures_a, textures_b = png_payloads(android), png_payloads(test)
    return {'ipa_sha256': IPA_SHA, 'apk_sha256': APK_SHA, 'test_game_data_sha256': TEST_DATA_SHA,
            'resource_names': resource,
            'sprite': {'shared': len(shared),
                       'metadata_differ': sorted(n for n in shared if one[n]['metadata'] != two[n]['metadata']),
                       'texture_page_entries_differ': sorted(n for n in shared if one[n]['frames'] != two[n]['frames']),
                       'mask_differ': sorted(n for n in shared if (one[n]['mask_count'], one[n]['masks_sha256']) !=
                                             (two[n]['mask_count'], two[n]['masks_sha256']))},
            'texture_png': {'apk_count': len(textures_a), 'test_count': len(textures_b),
                            'all_identical_in_order': textures_a == textures_b},
            'apk_room_background_defaults': room_background_defaults(android),
            'test_room_background_defaults': room_background_defaults(test),
            'limitations': 'Static original-resource and room defaults only; runtime code may alter drawing state. '
                           'Not a render, on-device reproduction, an iOS/native equivalence claim, or a diagnosis. '
                           'The user reported these symptoms on test builds 1, 2 and 3.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('ipa', type=Path)
    p.add_argument('apk', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    report = compare(args.ipa, args.apk)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Old test3 graphics data compared; not an on-device diagnosis:', args.output)


if __name__ == '__main__':
    main()
