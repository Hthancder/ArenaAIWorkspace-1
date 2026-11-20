#!/usr/bin/env python3
"""Compare pinned modified iOS IPA and Android APK assets; no execution or patching.

The supplied IPA has injected third-party code. Only its embedded GameMaker
container and fixed audio members are inspected. Checksums pin the exact input;
identical names/assets are not proof of equivalent native code or gameplay.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_inventory import resource_names
    from tools.deadtown_sprite_metadata import native_sprites
    from tools.deadtown_sprite_pixels import compare_frame, load_image
    from tools.recover_deadtown_sprites import frame_image
    from tools.recover_deadtown_audio import chunks, pointers, read_string, u32, read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import resource_names
    from deadtown_sprite_metadata import native_sprites
    from deadtown_sprite_pixels import compare_frame, load_image
    from recover_deadtown_sprites import frame_image
    from recover_deadtown_audio import chunks, pointers, read_string, u32, read_zip_member

IPA_SHA = '0212db7196f54894476d902bf8832e2e1db9f6de2121757c2740ec46283b0c09'
APK_SHA = 'bc8fa1990cb2cdde8d184f2a942fe4010820f0592d88a36e1cbee0a6aac081fb'
MAIN_SHA = '8cff86ba15945ef074771e66ef2b1c1882f5c3dbd67f84ba2e63c1f58b0c3cec'
BACKUP_SHA = '80c8f830cd9e44fec660f5f232c4d5b86c360c3c5544973eb7cf74e1a9fdfec5'
IOS_FORM_SHA = 'd377806aff85cb9d082d531c4ae6eeb4b15d61db311f43d62bbc55a58bba8a33'
RESOURCE_TYPES = (b'SOND', b'SPRT', b'BGND', b'SCPT', b'FONT', b'OBJT', b'ROOM')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ogg_without_serial_and_crc(data):
    """Zero stream serial and page CRC only; preserve other Ogg page bytes.

    Structurally validates each page and its lacing bounds, but does not validate
    CRC or claim audio playback equivalence. Multiplexed stream serial identities
    are deliberately ignored, so equality is a narrowly defined byte comparison.
    """
    out = bytearray(data)
    pos = 0
    if not data:
        raise ValueError('empty Ogg')
    while pos < len(data):
        if pos + 27 > len(data) or data[pos:pos + 5] != b'OggS\0':
            raise ValueError('invalid Ogg page')
        count = data[pos + 26]
        header_end = pos + 27 + count
        if header_end > len(data):
            raise ValueError('truncated Ogg lacing table')
        end = header_end + sum(data[pos + 27:header_end])
        if end > len(data):
            raise ValueError('truncated Ogg page body')
        out[pos + 14:pos + 18] = b'\0' * 4
        out[pos + 22:pos + 26] = b'\0' * 4
        pos = end
    return bytes(out)


def embedded_form(binary, expected_sha=BACKUP_SHA):
    # Exact pinned inputs, not a generic scanner or an assertion of authenticity.
    if sha(binary) != expected_sha:
        raise ValueError('unexpected iOS executable SHA-256')
    start = 0x896600
    if binary[start:start + 4] != b'FORM':
        raise ValueError('missing embedded FORM at pinned offset')
    end = start + 8 + u32(binary, start + 4)
    if end > len(binary):
        raise ValueError('embedded FORM extends past executable')
    data = binary[start:end]
    if sha(data) != IOS_FORM_SHA:
        raise ValueError('unexpected iOS FORM SHA-256')
    chunks(data)
    return data


def sound_payloads(data, groups):
    regions = chunks(data)
    streams = {0: data, **groups}
    audio = {k: (v, chunks(v)[b'AUDO']) for k, v in streams.items()}
    positions = {k: pointers(v, region) for k, (v, region) in audio.items()}
    output = {}
    for pos in pointers(data, regions[b'SOND']):
        if pos + 36 > regions[b'SOND'][1]:
            raise ValueError('truncated sound descriptor')
        name_ptr, flags, _, _, _, _, _, group, index = struct.unpack_from('<9I', data, pos)
        name = read_string(data, name_ptr, regions[b'STRG'])
        if not name or name in output or flags & 0x64 != 0x64 or group not in audio or index >= len(positions[group]):
            raise ValueError('unsupported sound descriptor')
        blob, region = audio[group]
        start = positions[group][index]
        size = u32(blob, start)
        if size > region[1] - start - 4:
            raise ValueError('truncated sound payload')
        payload = blob[start + 4:start + 4 + size]
        if payload.startswith(b'OggS\0'):
            normalized = ogg_without_serial_and_crc(payload)
            kind = 'ogg'
        elif payload.startswith(b'RIFF') and payload[8:12] == b'WAVE':
            normalized, kind = payload, 'wav'
        else:
            raise ValueError('unsupported audio payload')
        output[name] = {'sha256': sha(payload), 'normalized_sha256': sha(normalized),
                        'size': size, 'format': kind}
    return output


def png_payloads(data):
    regions = chunks(data)
    start, end = regions[b'TXTR']
    result = []
    for entry in pointers(data, regions[b'TXTR']):
        if entry + 8 > end:
            raise ValueError('truncated texture entry')
        offset = u32(data, entry + 4)
        if offset < start or offset + 8 > end or data[offset:offset + 8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError('invalid texture PNG header')
        pos = offset + 8
        while True:
            if pos + 12 > end:
                raise ValueError('truncated PNG chunk')
            length = struct.unpack_from('>I', data, pos)[0]
            tag = data[pos + 4:pos + 8]
            if length > end - pos - 12:
                raise ValueError('PNG chunk outside texture')
            pos += 12 + length
            if tag == b'IEND':
                if length != 0:
                    raise ValueError('invalid IEND')
                break
        result.append(sha(data[offset:pos]))
    return result


def sprite_layout(data):
    """Return packed mask bytes and TPAG entries by sprite name and index."""
    metadata = native_sprites(data)  # checks version and frame pointers
    regions = chunks(data)
    positions = pointers(data, regions[b'SPRT'])
    if positions != sorted(set(positions)):
        raise ValueError('unexpected sprite positions')
    result = {}
    for index, pos in enumerate(positions):
        end = positions[index + 1] if index + 1 < len(positions) else regions[b'SPRT'][1]
        name = read_string(data, u32(data, pos), regions[b'STRG'])
        info = metadata[name]
        width, height, count = info['width'], info['height'], info['frames']
        size = ((width + 7) // 8) * height
        header = pos + 60 + 4 * count
        if size <= 0 or header + 4 > end:
            raise ValueError('invalid mask size')
        masks = u32(data, header)
        if masks > (end - header - 4) // size:
            raise ValueError('truncated masks')
        mask_hash = sha(data[header + 4:header + 4 + masks * size])
        frames = []
        for j in range(count):
            ptr = u32(data, pos + 60 + j * 4)
            if ptr + 22 > regions[b'TPAG'][1]:
                raise ValueError('truncated texture-page entry')
            frames.append(struct.unpack_from('<10Hh', data, ptr))
        result[name] = {'metadata': info, 'mask_count': masks, 'masks_sha256': mask_hash, 'frames': frames}
    return result


def sprite_pixels(android, ios, android_layout, ios_layout):
    """Compare reconstructed frames only; scaled Android frames are skipped."""
    def atlases(data):
        regions = chunks(data)
        end = regions[b'TXTR'][1]
        output = []
        for entry in pointers(data, regions[b'TXTR']):
            if entry + 8 > end:
                raise ValueError('truncated texture entry')
            offset = u32(data, entry + 4)
            if not regions[b'TXTR'][0] <= offset < end:
                raise ValueError('atlas outside TXTR')
            output.append(load_image(io.BytesIO(data[offset:end])))
        return output

    a, b = atlases(android), atlases(ios)
    counts, exceptional = {}, []
    for name in sorted(android_layout.keys() & ios_layout.keys()):
        one, two = android_layout[name], ios_layout[name]
        if len(one['frames']) != len(two['frames']):
            raise ValueError('different sprite frame counts')
        dimensions = (one['metadata']['width'], one['metadata']['height'])
        for index, (left, right) in enumerate(zip(one['frames'], two['frames'])):
            if not 0 <= left[-1] < len(a) or not 0 <= right[-1] < len(b):
                raise ValueError('invalid texture page index')
            mode, frame = frame_image(a[left[-1]], left, dimensions)
            if mode != 'unscaled_canvas':
                status = 'android_scaled_not_compared'
            else:
                status = compare_frame(b[right[-1]], right, frame)
            counts[status] = counts.get(status, 0) + 1
            if status not in ('exact_rgba', 'transparent_rgb_only'):
                exceptional.append({'sprite': name, 'frame': index, 'status': status})
    return {'frame_counts': dict(sorted(counts.items())), 'exceptional_frames': exceptional}


def compare(ipa, apk):
    ipa, apk = Path(ipa), Path(apk)
    if sha(ipa.read_bytes()) != IPA_SHA or sha(apk.read_bytes()) != APK_SHA:
        raise ValueError('unexpected IPA or APK SHA-256')
    with zipfile.ZipFile(ipa) as archive:
        executable = read_zip_member(archive, 'Payload/deadtown.app/deadtown.troll-fools.bak')
        ios = embedded_form(executable)
        main_executable = read_zip_member(archive, 'Payload/deadtown.app/deadtown')
        if embedded_form(main_executable, MAIN_SHA) != ios:
            raise ValueError('main and backup embedded FORM disagree')
        ios_groups = {j: read_zip_member(archive, f'Payload/deadtown.app/games/audiogroup{j}.dat') for j in (1, 2)}
    with zipfile.ZipFile(apk) as archive:
        android = read_zip_member(archive, 'assets/game.droid')
        android_groups = {j: read_zip_member(archive, f'assets/audiogroup{j}.dat') for j in (1, 2)}
    resources = {}
    for kind in RESOURCE_TYPES:
        a, b = resource_names(android, kind), resource_names(ios, kind)
        resources[kind.decode()] = {'android_count': len(a), 'ios_count': len(b),
                                    'same_ordered_names': a == b,
                                    'android_only': sorted(set(a) - set(b)), 'ios_only': sorted(set(b) - set(a))}
    asprites, isprites = sprite_layout(android), sprite_layout(ios)
    common = asprites.keys() & isprites.keys()
    sprite = {'shared': len(common),
              'metadata_differ': sorted(n for n in common if asprites[n]['metadata'] != isprites[n]['metadata']),
              'packed_masks_differ': sorted(n for n in common if (asprites[n]['mask_count'], asprites[n]['masks_sha256']) !=
                                             (isprites[n]['mask_count'], isprites[n]['masks_sha256'])),
              'page_entries_differ': sorted(n for n in common if asprites[n]['frames'] != isprites[n]['frames'])}
    apng, ipng = png_payloads(android), png_payloads(ios)
    asounds, isounds = sound_payloads(android, android_groups), sound_payloads(ios, ios_groups)
    sound_common = asounds.keys() & isounds.keys()
    sounds = {'shared': len(sound_common),
              'byte_identical': sum(asounds[n]['sha256'] == isounds[n]['sha256'] for n in sound_common),
              'equal_after_ogg_serial_crc_zeroed': sum(asounds[n]['normalized_sha256'] == isounds[n]['normalized_sha256'] for n in sound_common),
              'different_after_normalization': sorted(n for n in sound_common if asounds[n]['normalized_sha256'] != isounds[n]['normalized_sha256']),
              'format_counts': {kind: sum(x['format'] == kind for x in asounds.values()) for kind in ('ogg', 'wav')}}
    return {'ipa_sha256': IPA_SHA, 'apk_sha256': APK_SHA, 'main_executable_sha256': MAIN_SHA,
            'backup_executable_sha256': BACKUP_SHA, 'main_and_backup_form_identical': True,
            'ios_form_offset': '0x896600', 'ios_form_sha256': sha(ios), 'android_form_sha256': sha(android),
            'resources': resources, 'sprites': sprite,
            'texture_png': {'android_count': len(apng), 'ios_count': len(ipng),
                            'byte_identical_same_index': [j for j in range(min(len(apng), len(ipng))) if apng[j] == ipng[j]],
                            'different_same_index': [j for j in range(min(len(apng), len(ipng))) if apng[j] != ipng[j]]},
            'sprite_pixels': sprite_pixels(android, ios, asprites, isprites),
            'sounds': sounds,
            'limitations': 'Modified iOS executable backup; static assets only. Name/order and byte comparisons '
                           'do not prove native code, gameplay or cross-platform equivalence. Ogg normalization '
                           'ignores serial and CRC and does not validate CRC or audio playback; PNG hashes are '
                           'encoded bytes. Frame comparison excludes scaled frames and masks/runtime behavior; '
                           'transparent pixels outside trimmed regions are reconstructed. No iOS execution or installation.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = compare(args.ipa, args.apk)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('iOS/Android static asset comparison:', args.output)
    print('Not native runtime equivalence or a game build.')


if __name__ == '__main__':
    main()
