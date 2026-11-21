#!/usr/bin/env python3
"""Recover and verify a font atlas/glyph descriptor candidate from pinned APK.

Exports to a new folder and verifies the 490 legacy glyphs first. The resulting
GMX descriptor and PNG are candidates: GameMaker may regenerate or repack the
font, the original TTF is not included, and runtime/iOS rendering is untested.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET

try:
    from tools.check_deadtown_sound_evidence import safe_asset
    from tools.deadtown_native_inventory import project_names
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_room_evidence import checked, nested_pointers
    from tools.deadtown_sprite_pixels import load_image
    from tools.recover_deadtown_audio import pointers, read_string, u32
    from tools.recover_deadtown_sprites import frame_image, open_apk
except ModuleNotFoundError:
    from check_deadtown_sound_evidence import safe_asset
    from deadtown_native_inventory import project_names
    from deadtown_native_lang import APK_SHA256
    from deadtown_room_evidence import checked, nested_pointers
    from deadtown_sprite_pixels import load_image
    from recover_deadtown_audio import pointers, read_string, u32
    from recover_deadtown_sprites import frame_image, open_apk

FIELDS = ('character', 'x', 'y', 'w', 'h', 'shift', 'offset')
NAME = 'font_24'


def collapse_ranges(codes):
    result = []
    for code in sorted(codes):
        if not 0 <= code <= 0xffff:
            raise ValueError('invalid glyph codepoint')
        if result and code == result[-1][1]:
            raise ValueError('duplicate glyph codepoint')
        if result and code == result[-1][1] + 1:
            result[-1][1] = code
        else:
            result.append([code, code])
    return result


def parse_source(path):
    root = ET.parse(path).getroot()
    expected = {'name': '나눔고딕 ExtraBold', 'size': '24', 'bold': '-1', 'italic': '0',
                'charset': '1', 'aa': '3', 'image': 'font_24.png', 'includeTTF': '0'}
    if any(root.findtext(k) != v for k, v in expected.items()):
        raise ValueError('unexpected source font settings')
    ranges = []
    for node in root.findall('./ranges/*'):
        match = re.fullmatch(r'(\d+),(\d+)', node.text or '')
        if not match:
            raise ValueError('invalid source range')
        first, last = map(int, match.groups())
        if not 0 <= first <= last <= 0xffff:
            raise ValueError('invalid source range bounds')
        ranges.extend(range(first, last + 1))
    glyphs = []
    for node in root.findall('./glyphs/glyph'):
        if set(node.attrib) != set(FIELDS):
            raise ValueError('unexpected glyph attributes')
        glyphs.append(tuple(int(node.get(k)) for k in FIELDS))
    if len(glyphs) != len({g[0] for g in glyphs}) or len(ranges) != len(set(ranges)):
        raise ValueError('duplicate glyph or source range')
    if set(ranges) != {g[0] for g in glyphs}:
        raise ValueError('source ranges and glyphs disagree')
    if root.find('kerningPairs') is None or len(root.find('kerningPairs')):
        raise ValueError('unexpected source kerning pairs')
    return root, glyphs


def collect(apk):
    data, _, regions, atlases = open_apk(apk)
    gen = regions[b'GEN8'][0]
    if data[gen + 1] != 15 or u32(data, gen + 44) != 1:
        raise ValueError('unexpected GameMaker version')
    region = regions[b'FONT']
    fonts = pointers(data, region)
    if len(fonts) != 1:
        raise ValueError('unexpected native font count')
    p = fonts[0]
    checked(data, p, 44, region)
    name = read_string(data, u32(data, p), regions[b'STRG'])
    display = read_string(data, u32(data, p + 4), regions[b'STRG'])
    size, bold, italic = struct.unpack_from('<III', data, p + 8)
    start, charset, aa, end = struct.unpack_from('<HBBI', data, p + 20)
    sx, sy = struct.unpack_from('<ff', data, p + 32)
    if (name, display, size, bold, italic, start, charset, aa, end, sx, sy) != (NAME, '나눔고딕 ExtraBold', 24, 1, 0, 32, 1, 3, 55197, 1.0, 1.0):
        raise ValueError('unexpected native font settings')
    tpag = u32(data, p + 28)
    if tpag not in set(pointers(data, regions[b'TPAG'])) or tpag + 22 > regions[b'TPAG'][1]:
        raise ValueError('invalid font texture page')
    page = struct.unpack_from('<10Hh', data, tpag)
    if not 0 <= page[-1] < len(atlases):
        raise ValueError('invalid font atlas index')
    mode, image = frame_image(atlases[page[-1]], page, page[8:10])
    if mode != 'unscaled_canvas' or image.size != (2048, 2048):
        raise ValueError('unexpected font atlas shape')
    ptrs = nested_pointers(data, p + 40, region, 16)
    glyphs = []
    for ptr in ptrs:
        glyph = struct.unpack_from('<5H2h', data, ptr)
        ch, x, y, w, h, _, _ = glyph
        if not w or not h or x + w > image.width or y + h > image.height or struct.unpack_from('<H', data, ptr + 14)[0] != 0:
            raise ValueError('unsupported glyph dimensions or kerning')
        glyphs.append(glyph)
    codes = [g[0] for g in glyphs]
    if len(glyphs) != 2499 or codes != sorted(set(codes)) or codes[0] != start or codes[-1] != end:
        raise ValueError('unexpected glyph table')
    return image, glyphs, page


def check_legacy(old_dir, native_image, native_glyphs):
    old_dir = Path(old_dir)
    _, old = parse_source(safe_asset(old_dir, Path('font_24.font.gmx')))
    image = load_image(safe_asset(old_dir, Path('font_24.png')))
    by_code = {g[0]: g for g in native_glyphs}
    if len(old) != 490 or not set(g[0] for g in old) < set(by_code):
        raise ValueError('unexpected legacy glyph set')
    for g in old:
        ch, x, y, w, h, _, _ = g
        native = by_code[ch]
        if g[3:] != native[3:] or x < 0 or y < 0 or x + w > image.width or y + h > image.height:
            raise ValueError(f'legacy glyph metrics differ: {ch}')
        _, nx, ny, _, _, _, _ = native
        if image.crop((x, y, x + w, y + h)).tobytes() != native_image.crop((nx, ny, nx + w, ny + h)).tobytes():
            raise ValueError(f'legacy glyph pixels differ: {ch}')
    return len(old)


def verify_files(descriptor, image_path, native_image, native_glyphs):
    _, glyphs = parse_source(descriptor)
    if glyphs != native_glyphs:
        raise ValueError('candidate glyph records differ from APK')
    image = load_image(image_path)
    if image.size != native_image.size or image.tobytes() != native_image.tobytes():
        raise ValueError('candidate font atlas differs from APK')


def extract(apk, old_dir, output):
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise ValueError('output exists; refusing to overwrite')
    image, glyphs, page = collect(apk)
    old_count = check_legacy(old_dir, image, glyphs)
    original = (Path(old_dir) / 'font_24.font.gmx').read_text(encoding='utf-8')
    range_text = '\n'.join(f'    <range0>{a},{b}</range0>' for a, b in collapse_ranges(g[0] for g in glyphs))
    glyph_text = '\n'.join('    <glyph ' + ' '.join(f'{k}="{v}"' for k, v in zip(FIELDS, g)) + '/>' for g in glyphs)
    for tag, content in (('ranges', range_text), ('glyphs', glyph_text)):
        original, n = re.subn(r'(?s)(  <' + tag + r'>\n).*?(\n  </' + tag + r'>)',
                              lambda m: m.group(1) + content + m.group(2), original)
        if n != 1:
            raise ValueError(f'unexpected legacy {tag} section')
    output.mkdir(parents=True)
    desc, png = output / 'font_24.font.gmx', output / 'font_24.png'
    desc.write_text(original, encoding='utf-8')
    image.save(png, format='PNG')
    verify_files(desc, png, image, glyphs)
    return {'legacy_count': old_count, 'native_count': len(glyphs), 'atlas_region': list(page)}


def verify(apk, source):
    source = Path(source)
    image, glyphs, page = collect(apk)
    project = source / 'project'
    if NAME not in project_names(project, 'fonts', 'font'):
        raise ValueError('font not declared')
    desc = safe_asset(project, Path('fonts/font_24.font.gmx'))
    png = safe_asset(source / 'assets', Path('fonts/font_24.png'))
    verify_files(desc, png, image, glyphs)
    return {'apk_sha256': APK_SHA256, 'font': NAME, 'glyph_count': len(glyphs),
            'range_count': len(collapse_ranges(g[0] for g in glyphs)),
            'atlas_rgba_sha256': hashlib.sha256(image.tobytes()).hexdigest(), 'atlas_region': list(page),
            'limitations': 'Static glyph records and atlas only; original TTF not included, '
                           'compiler regeneration, text shaping, runtime and iOS are not verified.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    ex = sub.add_parser('extract'); ex.add_argument('apk', type=Path); ex.add_argument('legacy_fonts', type=Path); ex.add_argument('output', type=Path)
    ve = sub.add_parser('verify'); ve.add_argument('apk', type=Path); ve.add_argument('source', type=Path); ve.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'extract':
        report = extract(args.apk, args.legacy_fonts, args.output)
    else:
        report = verify(args.apk, args.source)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('FONT_CANDIDATE:', json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
