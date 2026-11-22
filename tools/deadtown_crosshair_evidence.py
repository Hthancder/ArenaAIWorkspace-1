#!/usr/bin/env python3
"""Verify the partial draw_line_crosshair candidate against pinned Android ARM32.

Static evidence and source checks only; no native or iOS execution is implied.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name, project_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.deadtown_sprite_metadata import native_sprites
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, project_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from deadtown_sprite_metadata import native_sprites
    from recover_deadtown_audio import read_zip_member

START = 0x1cff00
SIZE = 2252
EXPORT_SHA256 = '4845fe11a4aa1fa9730b419f8a43cbc6a221987da12a768ea390aae39cd770b4'
GAME_SHA256 = '0900da067462bd48040da6e217a86e2d5411397b05f07d55d13c58440b82a7b8'
SOURCE = '''/// Candidate restored from Android ARM32; numeric locals are invented names.
var __dt_angle, __dt_distance, __dt_frame;
__dt_angle = point_direction(argument0, argument1, argument2, argument3);
__dt_distance = point_distance(argument0, argument1, argument2, argument3);
__dt_frame = 0;
if (__dt_distance > 100)
{
    __dt_frame = 1;
}
draw_sprite_ext(spr_crosshair, __dt_frame, argument0, argument1, __dt_distance / 100, 1, __dt_angle, draw_get_colour(), draw_get_alpha());
'''


def verify_source(project):
    p = Path(project)
    if 'draw_line_crosshair' not in project_names(p, 'scripts', 'script') or 'spr_crosshair' not in project_names(p, 'sprites', 'sprite'):
        raise ValueError('candidate resources not declared')
    if (p/'scripts/draw_line_crosshair.gml').read_text(encoding='utf-8') != SOURCE:
        raise ValueError('candidate script mismatch')
    sprite = ET.parse(p/'sprites/spr_crosshair.sprite.gmx').getroot()
    frames = sprite.findall('./frames/frame')
    if [f.get('index') for f in frames] != ['0', '1']:
        raise ValueError('expected two crosshair frames')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        raw = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
        game = read_zip_member(z, 'assets/game.droid')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256 or hashlib.sha256(game).hexdigest() != GAME_SHA256:
        raise ValueError('unexpected native/game bytes')
    sprite_names = list(native_sprites(game))
    if len(sprite_names) != 402 or sprite_names[181] != 'spr_crosshair' or native_sprites(game)['spr_crosshair']['frames'] != 2:
        raise ValueError('unexpected native crosshair sprite')
    elf = ELFFile(io.BytesIO(raw))
    matches = [s for s in elf.get_section_by_name('.dynsym').iter_symbols() if exported_name(s.name) == 'gml_Script_draw_line_crosshair']
    if len(matches) != 1 or (matches[0]['st_value'], matches[0]['st_size']) != (START, SIZE):
        raise ValueError('unexpected export')
    rel = elf.get_section_by_name('.rel.dyn')
    sy = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: sy.get_symbol(r['r_info_sym']) for r in rel.iter_relocations() if r['r_info_type'] == 21}
    plt, rp = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr']+20+i*12: ps.get_symbol(r['r_info_sym']).name for i,r in enumerate(rp.iter_relocations())}
    d = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    d.detail = True

    def read(addr, size):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= addr and addr+size <= seg['p_vaddr']+seg['p_filesz']:
                off = seg['p_offset']+addr-seg['p_vaddr']
                return raw[off:off+size]
        raise ValueError('address outside ELF')

    def ins(addr):
        out = list(d.disasm(read(addr, 4), addr))
        if len(out) != 1:
            raise ValueError('invalid instruction')
        return out[0]

    def check(addr, op, operands):
        i = ins(addr)
        if (i.mnemonic, i.op_str) != (op, operands):
            raise ValueError(f'instruction mismatch at {addr:#x}')

    def literal(addr):
        i = ins(addr)
        if i.mnemonic != 'ldr' or len(i.operands) != 2 or i.operands[1].type != ARM_OP_MEM or i.reg_name(i.operands[1].mem.base) != 'pc':
            raise ValueError('expected pc literal')
        return struct.unpack('<I', read(addr+8+i.operands[1].mem.disp, 4))[0]

    def symbol(base, add, off, expected):
        address = (add+8+literal(base)+literal(off)) & 0xffffffff
        result = got.get(address)
        if result is None or result.name != expected:
            raise ValueError('unexpected GOT relocation: '+expected)

    if hashlib.sha256(read(START, SIZE)).hexdigest() != EXPORT_SHA256:
        raise ValueError('function bytes mismatch')
    for base,add,off,name in (
        (0x1d0090,0x1d0098,0x1d0088,'g_FUNC_point_distance'),
        (0x1d01ec,0x1d01f0,0x1d01e8,'g_FUNC_draw_get_colour'),
        (0x1d0228,0x1d022c,0x1d0224,'g_FUNC_draw_get_alpha'),
        (0x1d0394,0x1d0398,0x1d0390,'g_FUNC_draw_get_colour'),
        (0x1d03d0,0x1d03d4,0x1d03cc,'g_FUNC_draw_get_alpha'),
    ):
        symbol(base,add,off,name)
    for addr,name in ((0x17672c,'YYGML_point_direction'), (0x17654c,'YYGML_CallLegacyFunction'),
                      (0x176438,'_ZdvRK8YYRValued'), (0x176738,'YYGML_draw_sprite_ext')):
        if name not in calls.get(addr, ''):
            raise ValueError('unexpected function relocation')
    checks = {
        0x1cff44: ('ldr','r4, [sp, #0x120]'), 0x1cff9c: ('ldr','r1, [r4]'),
        0x1cffb0: ('ldr','r1, [r4, #4]'), 0x1cffc4: ('ldr','r1, [r4, #8]'),
        0x1cffd8: ('ldr','r1, [r4, #0xc]'), 0x1d005c: ('bl','#0x17672c'),
        0x1d00b4: ('add','r2, sp, #0xd0'), 0x1d00c0: ('add','r2, sp, #0xc0'),
        0x1d00c8: ('str','sl, [sp, #0x58]'), 0x1d00d0: ('str','r5, [sp, #0x5c]'),
        0x1d00e4: ('mov','r3, #4'), 0x1d00f0: ('bl','#0x17654c'),
        0x1d00f8: ('add','r0, sp, #0x80'), 0x1d0158: ('add','r0, sp, #0x80'),
        0x1d0170: ('vldr','d8, [pc, #0x1b8]'), 0x1d0178: ('vsub.f64','d0, d8, d0'),
        0x1d0180: ('vneg.f64','d1, d1'), 0x1d0184: ('vcmpe.f64','d0, d1'),
        0x1d0188: ('vmrs','apsr_nzcv, fpscr'), 0x1d018c: ('bpl','#0x1d0338'),
        0x1d01b8: ('vmov','r2, r3, d8'), 0x1d01c0: ('add','r1, sp, #0x80'),
        0x1d01c4: ('bl','#0x176438'), 0x1d0214: ('bl','#0x17654c'),
        0x1d0250: ('bl','#0x17654c'), 0x1d02a8: ('mov','r1, #0xb5'),
        0x1d02b0: ('mov','r2, #1'), 0x1d02ac: ('str','r0, [sp, #8]'),
        0x1d02c4: ('bl','#0x176738'), 0x1d0360: ('vmov','r2, r3, d8'),
        0x1d0368: ('add','r1, sp, #0x80'), 0x1d036c: ('bl','#0x176438'),
        0x1d03bc: ('bl','#0x17654c'), 0x1d03f8: ('bl','#0x17654c'),
        0x1d0450: ('mov','r1, #0xb5'), 0x1d0458: ('mov','r2, #0'),
        0x1d0454: ('str','r0, [sp, #8]'), 0x1d046c: ('bl','#0x176738'),
    }
    for address,(op,operands) in checks.items():
        check(address,op,operands)
    if struct.unpack('<d',read(0x1d0330,8))[0] != 100.0:
        raise ValueError('unexpected threshold and divisor')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'address': hex(START), 'size': SIZE, 'sha256': EXPORT_SHA256,
            'sprite': 'spr_crosshair', 'sprite_index_native': 181,
            'threshold_and_divisor': 100, 'frame_below': 0, 'frame_above': 1,
            'limitations': 'Static ARM32 and partial source candidate only; numerical epsilon, rendering, caller event, native execution and iOS unverified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    verify_source(a.project)
    a.output.write_text(json.dumps(inspect(a.apk), indent=2)+'\n', encoding='utf-8')
    print('CROSSHAIR_EVIDENCE: static candidate only')


if __name__ == '__main__':
    main()
