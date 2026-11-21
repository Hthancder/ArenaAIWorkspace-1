#!/usr/bin/env python3
"""Preserve four unscaled atlas sprites and native masks without guessing GMX masks.

Research-only files do not get declared in the project. Native packed masks and
RGBA PNGs are verified against the pinned APK, not against a compiler or device.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops

try:
    from tools.check_deadtown_restored_frames import safe_asset
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_rect_sprite_candidates import collect
    from tools.deadtown_sprite_masks import summarize_mask
except ModuleNotFoundError:
    from check_deadtown_restored_frames import safe_asset
    from deadtown_native_lang import APK_SHA256
    from deadtown_rect_sprite_candidates import collect
    from deadtown_sprite_masks import summarize_mask

NAMES = ('spr_map_info', 'ih_slingshot', 'spr_multi_slot_kind', 'spr_player_kind')
NOTICE = ('RESEARCH-ONLY unresolved sprites. These are NOT included in the GMX project.\n'
          'Native masks are preserved, not reconstructed by a GameMaker compiler.\n')


def best_union_alpha_error(info, mask, frames):
    if not frames or any(mode != 'unscaled_canvas' for mode, _, _ in frames):
        raise ValueError('expected unscaled frames')
    alpha = frames[0][1].getchannel('A')
    for _, image, _ in frames[1:]:
        alpha = ImageChops.lighter(alpha, image.getchannel('A'))
    width, height = alpha.size
    if (width, height) != (info['width'], info['height']):
        raise ValueError('inconsistent bounds')
    pixels = alpha.tobytes()
    stride = (width + 7) // 8
    if len(mask) != stride * height:
        raise ValueError('invalid mask length')
    set_hist, clear_hist = [0] * 256, [0] * 256
    for y in range(height):
        for x in range(width):
            target = set_hist if mask[y * stride + x // 8] & (0x80 >> (x % 8)) else clear_hist
            target[pixels[y * width + x]] += 1
    false_negatives, false_positives = 0, sum(clear_hist)
    losses = []
    for threshold in range(256):
        false_negatives += set_hist[threshold]
        false_positives -= clear_hist[threshold]
        losses.append(false_negatives + false_positives)
    return min(losses)


def record(name, info, masks, frames, folder, write):
    if len(masks) != 1 or any(mode != 'unscaled_canvas' for mode, _, _ in frames):
        raise ValueError(f'unexpected native sprite shape: {name}')
    mask = masks[0]
    shape = summarize_mask(mask, info['width'], info['height'])
    error = best_union_alpha_error(info, mask, frames)
    if shape['shape'] != 'irregular' or shape['row_padding_set_bits'] or error == 0:
        raise ValueError(f'unresolved-mask assumption failed: {name}')
    out = {'name': name, 'metadata': info, 'native_mask': {'file': f'{name}/mask.bin',
           'sha256': hashlib.sha256(mask).hexdigest(), 'shape': shape['shape'],
           'best_union_alpha_threshold_bit_difference': error}, 'frames': []}
    mask_path = folder / name / 'mask.bin'
    if write:
        mask_path.parent.mkdir(parents=True, exist_ok=True)
        mask_path.write_bytes(mask)
    elif safe_asset(folder, Path(name) / 'mask.bin').read_bytes() != mask:
        raise ValueError(f'native mask changed: {name}')
    for index, (_, image, page) in enumerate(frames):
        rel = Path(name) / f'{index}.png'
        path = folder / rel
        if write:
            image.save(path, format='PNG')
        else:
            path = safe_asset(folder, rel)
        with Image.open(path) as decoded:
            if decoded.format != 'PNG':
                raise ValueError(f'not PNG: {rel}')
            actual = decoded.convert('RGBA')
            if actual.size != image.size or actual.tobytes() != image.tobytes():
                raise ValueError(f'atlas frame changed: {rel}')
        out['frames'].append({'file': rel.as_posix(), 'sha256_rgba': hashlib.sha256(image.tobytes()).hexdigest(),
                              'atlas_region': page})
    return out


def run(apk, folder, write=False):
    folder = Path(folder)
    if write:
        if folder.exists() or folder.is_symlink():
            raise ValueError('output exists; refusing to overwrite')
    elif folder.is_symlink() or not folder.is_dir():
        raise ValueError('not a real folder')
    native = collect(apk)
    if write:
        folder.mkdir(parents=True)
        (folder / 'RESEARCH-ONLY.txt').write_text(NOTICE, encoding='utf-8')
    else:
        notice = safe_asset(folder, Path('RESEARCH-ONLY.txt')).read_text(encoding='utf-8')
        if notice != NOTICE:
            raise ValueError('missing research notice')
    expected = {'format': 1, 'apk_sha256': APK_SHA256, 'sprites': []}
    for name in NAMES:
        _, info, masks, frames = native[name]
        expected['sprites'].append(record(name, info, masks, frames, folder, write))
    manifest = folder / 'manifest.json'
    if write:
        manifest.write_text(json.dumps(expected, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    elif json.loads(safe_asset(folder, Path('manifest.json')).read_text(encoding='utf-8')) != expected:
        raise ValueError('research manifest mismatch')
    return expected


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=('extract', 'verify'))
    p.add_argument('apk', type=Path)
    p.add_argument('folder', type=Path)
    a = p.parse_args()
    r = run(a.apk, a.folder, write=a.command == 'extract')
    print(f"UNRESOLVED_SPRITES_{a.command.upper()}: {len(r['sprites'])} sprites, "
          f"{sum(len(x['frames']) for x in r['sprites'])} frames; no GMX mask or runtime verification")


if __name__ == '__main__':
    main()
