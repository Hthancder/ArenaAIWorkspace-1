#!/usr/bin/env python3
"""Verify materialized sound payloads and selected metadata against the pinned APK.

Native bit meanings and GMX audio options are only candidate mappings. This
checks bytes and selected fields, not codec decoding, compiler output or iOS.
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
    from tools.deadtown_native_inventory import project_names
    from tools.deadtown_native_lang import APK_SHA256
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, recover
except ModuleNotFoundError:
    from deadtown_native_inventory import project_names
    from deadtown_native_lang import APK_SHA256
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, recover


def safe_asset(root, relative):
    if root.is_symlink():
        raise ValueError('symlinked asset root')
    path = root
    for part in relative.parts:
        if part in ('', '.', '..'):
            raise ValueError('unsafe asset path')
        path = path / part
        if path.is_symlink():
            raise ValueError('symlinked asset path')
    if not path.is_file():
        raise ValueError(f'missing asset: {relative}')
    return path


def native_metadata(data):
    regions = chunks(data)
    gen = regions[b'GEN8'][0]
    if data[gen + 1] != 15 or struct.unpack_from('<I', data, gen + 44)[0] != 1:
        raise ValueError('unexpected GameMaker format')
    result = {}
    start, end = regions[b'SOND']
    for ptr in pointers(data, (start, end)):
        if ptr + 36 > end:
            raise ValueError('truncated sound entry')
        name_ptr, flags, _, _, effects, volume, pitch, group, index = struct.unpack_from('<IIIIIffII', data, ptr)
        name = read_string(data, name_ptr, regions[b'STRG'])
        if name in result or not all(math.isfinite(x) for x in (volume, pitch)):
            raise ValueError('duplicate name or invalid float')
        result[name] = dict(flags=flags, effects=effects, volume=volume, pitch=pitch, group=group, audio_index=index)
    return result


def verify(apk, project):
    apk, project = Path(apk), Path(project)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        meta = native_metadata(read_zip_member(z, 'assets/game.droid'))
    records = recover(apk)
    declared = project_names(project, 'sounds', 'sound')
    if len(records) != 90 or len(meta) != 90 or declared != set(meta):
        raise ValueError('sound names/count do not match pinned APK')
    report = {}
    for name, _, _, group, index, ext, payload in records:
        if name not in declared or group != meta[name]['group'] or index != meta[name]['audio_index']:
            raise ValueError(f'bad native audio link: {name}')
        descriptor = safe_asset(project, Path('sound') / f'{name}.sound.gmx')
        root = ET.parse(descriptor).getroot()
        filename = name + ext
        if root.findtext('extension') != ext or root.findtext('data') != filename or root.findtext('origname') != 'sound\\audio\\' + filename:
            raise ValueError(f'bad source sound reference: {name}')
        content = safe_asset(project, Path('sound/audio') / filename).read_bytes()
        if content != payload:
            raise ValueError(f'audio payload differs: {name}')
        values = meta[name]
        if (int(root.findtext('audioGroup')) != group or int(root.findtext('effects')) != values['effects']
                or float(root.findtext('volume/volume')) != values['volume']):
            raise ValueError(f'selected metadata differs: {name}')
        # Candidate mapping only: observed flag 103 / Ogg uses compressed, 101 / WAV uncompressed.
        expected = {103: ('1', '0', '1', '.ogg'), 101: ('0', '0', '0', '.wav')}.get(values['flags'])
        actual = (root.findtext('compressed'), root.findtext('streamed'), root.findtext('uncompressOnLoad'), ext)
        if expected is None or actual != expected:
            raise ValueError(f'unexpected candidate audio options: {name}')
        report[name] = dict(values, extension=ext, bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
    if len(report) != 90:
        raise ValueError('duplicate recovered sound')
    return {'apk_sha256': APK_SHA256, 'sound_count': len(report), 'sound_groups': dict(sorted(Counter(str(r['group']) for r in report.values()).items())),
            'native_flags': dict(sorted(Counter(str(r['flags']) for r in report.values()).items())), 'sounds': report,
            'limitations': 'Embedded payload bytes and selected metadata only. Flag-to-GMX mappings are candidates; '
                           'not codec decode, compiler configuration, runtime behavior, sound IDs or iOS proof.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.apk, args.project)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f"SOUND_EVIDENCE: {result['sound_count']} payloads match pinned APK; static only")


if __name__ == '__main__':
    main()
