#!/usr/bin/env python3
"""Extract pinned APK sprite research data into a NEW disposable directory.

This is not a GMX patch, game, or IPA. It reconstructs unscaled atlas rectangles
on transparent canvases, retains scaled rectangles without resampling, and
copies the original packed collision-mask bytes. Re-encoded PNGs are not the
original atlas files, and transparent RGB outside a trimmed region is unknown.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import zipfile

from PIL import Image

try:
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_sprite_metadata import native_sprites
    from tools.deadtown_sprite_pixels import MAX_DIM, load_image
    from tools.recover_deadtown_audio import SAFE_NAME, chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256
    from deadtown_sprite_metadata import native_sprites
    from deadtown_sprite_pixels import MAX_DIM, load_image
    from recover_deadtown_audio import SAFE_NAME, chunks, pointers, read_string, read_zip_member, u32

NOTICE = ('DISPOSABLE RESEARCH ASSETS ONLY. NOT A GAME, GMX PATCH OR IPA.\n'
          'Original rendering, collision interpretation and runtime behavior are not verified.\n')
PAGE_FIELDS = ('source_x', 'source_y', 'source_width', 'source_height', 'target_x', 'target_y',
               'target_width', 'target_height', 'bound_width', 'bound_height', 'atlas_index')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def frame_image(atlas, page, sprite_size):
    sx, sy, sw, sh, tx, ty, tw, th, bw, bh, _ = page
    if not all((sw, sh, tw, th, bw, bh)) or max(bw, bh) > MAX_DIM:
        raise ValueError('invalid texture rectangle size')
    if (bw, bh) != sprite_size:
        raise ValueError('sprite and texture bounds differ')
    if sx + sw > atlas.width or sy + sh > atlas.height or tx + tw > bw or ty + th > bh:
        raise ValueError('texture rectangle outside atlas or target')
    cropped = atlas.crop((sx, sy, sx + sw, sy + sh))
    if (sw, sh) != (tw, th):
        # Preserve the atlas pixels, not a guessed filtering/resampling mode.
        return 'atlas_region_only_scaled_target', cropped
    image = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
    image.paste(cropped, (tx, ty))
    return 'unscaled_canvas', image


def open_apk(apk):
    apk = Path(apk)
    if sha(apk.read_bytes()) != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        data = read_zip_member(archive, 'assets/game.droid')
    metadata = native_sprites(data)
    regions = chunks(data)
    end = regions[b'TXTR'][1]
    atlases = []
    for pos in pointers(data, regions[b'TXTR']):
        if pos + 8 > end:
            raise ValueError('truncated TXTR entry')
        offset = u32(data, pos + 4)
        if not regions[b'TXTR'][0] <= offset < end:
            raise ValueError('texture data outside TXTR')
        atlases.append(load_image(io.BytesIO(data[offset:end])))
    return data, metadata, regions, atlases


def iter_sprites(data, metadata, regions, atlases):
    positions = pointers(data, regions[b'SPRT'])
    if positions != sorted(set(positions)):
        raise ValueError('overlapping or unsorted sprite entries')
    for sprite_id, pos in enumerate(positions):
        bound = positions[sprite_id + 1] if sprite_id + 1 < len(positions) else regions[b'SPRT'][1]
        name = read_string(data, u32(data, pos), regions[b'STRG'])
        if not SAFE_NAME.fullmatch(name):
            raise ValueError('unsafe sprite name')
        info = metadata[name]
        width, height, nframes = info['width'], info['height'], info['frames']
        if not width or not height or max(width, height) > MAX_DIM:
            raise ValueError('invalid sprite size')
        mask_header = pos + 60 + nframes * 4
        if mask_header + 4 > bound:
            raise ValueError('truncated sprite frame table')
        count = u32(data, mask_header)
        stride, size = (width + 7) // 8, ((width + 7) // 8) * height
        if count > (bound - mask_header - 4) // size:
            raise ValueError('truncated collision masks')
        masks = [data[mask_header + 4 + size * i:mask_header + 4 + size * (i + 1)]
                 for i in range(count)]
        frames = []
        for index in range(nframes):
            ptr = u32(data, pos + 60 + index * 4)
            if ptr + 22 > regions[b'TPAG'][1]:
                raise ValueError('truncated texture page item')
            page = struct.unpack_from('<10Hh', data, ptr)
            if not 0 <= page[-1] < len(atlases):
                raise ValueError('invalid atlas index')
            mode, image = frame_image(atlases[page[-1]], page, (width, height))
            frames.append((mode, image, dict(zip(PAGE_FIELDS, page))))
        yield sprite_id, name, info, stride, masks, frames


def manifest_header():
    return {'format': 1, 'apk_sha256': APK_SHA256,
            'limitations': 'Research only, not a GMX patch or game. Unscaled canvases have unknown RGB '
                           'outside trimmed atlas rectangles; scaled rectangles are not resampled. '
                           'Masks are original packed bytes, not validated collision behavior.',
            'sprites': []}


def checked_export_path(output, rel, write):
    path = output / rel
    if not write:
        # Fixed paths are derived from the pinned APK, never from the manifest.
        # Reject symlinks at every component when validating an existing export.
        part = output
        for item in Path(rel).parts:
            part = part / item
            if part.is_symlink():
                raise ValueError('symlinked export path')
    return path


def build_record(sprite_id, name, info, stride, masks, frames, output, write):
    record = {'id': sprite_id, 'name': name, 'metadata': info, 'mask_stride_bytes': stride,
              'masks': [], 'frames': []}
    for index, mask in enumerate(masks):
        rel = f'masks/{name}/{index}.bin'
        path = checked_export_path(output, rel, write)
        if write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(mask)
        elif path.read_bytes() != mask:
            raise ValueError(f'mask does not match APK: {name}[{index}]')
        record['masks'].append({'index': index, 'file': rel, 'bytes': len(mask), 'sha256': sha(mask)})
    for index, (mode, image, page) in enumerate(frames):
        rel = f'frames/{name}/{index}.png'
        path = checked_export_path(output, rel, write)
        if write:
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path, format='PNG')
        # Read back as well as verify: never assume PNG encoding succeeded.
        restored = load_image(path)
        if restored.size != image.size or restored.tobytes() != image.tobytes():
            raise ValueError(f'frame does not match APK atlas: {name}[{index}]')
        record['frames'].append({'index': index, 'file': rel, 'mode': mode,
                                 'width': image.width, 'height': image.height,
                                 'sha256_rgba': sha(image.tobytes()), 'sha256_png': sha(path.read_bytes()),
                                 'atlas_region': page})
    return record


def extract(apk, output):
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise ValueError('output already exists; refusing to overwrite')
    data, metadata, regions, atlases = open_apk(apk)
    manifest = manifest_header()
    output.mkdir()  # claim before cleanup; never remove a pre-existing path
    try:
        (output / 'RESEARCH-ONLY.txt').write_text(NOTICE, encoding='utf-8')
        for sprite in iter_sprites(data, metadata, regions, atlases):
            manifest['sprites'].append(build_record(*sprite, output, True))
        (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    except Exception:
        shutil.rmtree(output)
        raise
    return manifest


def verify(apk, output):
    output = Path(output)
    manifest_path = output / 'manifest.json'
    if output.is_symlink() or manifest_path.is_symlink():
        raise ValueError('symlinked output or manifest')
    claimed = json.loads(manifest_path.read_text(encoding='utf-8'))
    data, metadata, regions, atlases = open_apk(apk)
    expected = manifest_header()
    for sprite in iter_sprites(data, metadata, regions, atlases):
        expected['sprites'].append(build_record(*sprite, output, False))
    if claimed != expected:
        raise ValueError('manifest does not match extracted assets and APK')
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('extract', 'verify'))
    parser.add_argument('apk', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = (extract if args.command == 'extract' else verify)(args.apk, args.output)
    frames = sum(len(sprite['frames']) for sprite in result['sprites'])
    masks = sum(len(sprite['masks']) for sprite in result['sprites'])
    scaled = sum(frame['mode'] != 'unscaled_canvas' for sprite in result['sprites'] for frame in sprite['frames'])
    print(f"{args.command}: {len(result['sprites'])} sprites, {frames} frames, {masks} masks; {scaled} scaled atlas regions not reconstructed")
    print('Research only: not a game or IPA, not validated rendering/collisions.')


if __name__ == '__main__':
    main()
