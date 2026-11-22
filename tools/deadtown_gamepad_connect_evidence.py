#!/usr/bin/env python3
"""Verify a partial gamepad-settings/connect candidate against pinned ARM32.

Slot 88 is identified by its INI section/key, not by an original GML name.
Static Android evidence only. No controller, platform-enum or iOS verification.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name, project_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, project_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

EXPORTS = {
    'gp_connect_check': (0x38d470, 2144, '0049e77f4c24a987b9df43d3454b78e918ee5339a7eb79ca177e31366efdf84d'),
    'setting_load': (0x2ec430, 7344, '6dd19e3c8f09a8db1413aa916bfceeedd1a463ca7b22640812929a6eccf48a36'),
    'setting_save': (0x2ee0e0, 2232, '5bf074aad1be0f4566ac777b183062604481ca23f797c6d5287d4e3bef00f7f5'),
}
CANDIDATE = '''/// Partial Android ARM32 candidate; slot 88 has a neutral, invented alias.
var __dt_gp_result, __dt_gp_count, __dt_gp_index;
__dt_gp_result = 0;
// Native compares os_type to numeric 4 and converts slot 88 to int before > 0.
if (os_type == 4 && global.__dt_setting_gamepad >= 1 && gamepad_is_supported())
{
    __dt_gp_count = gamepad_get_device_count();
    for (__dt_gp_index = 0; __dt_gp_index < __dt_gp_count; __dt_gp_index += 1)
    {
        if (gamepad_is_connected(__dt_gp_index))
        {
            gamepad_set_axis_deadzone(__dt_gp_index, 0.2);
            __dt_gp_result = 1;
        }
    }
}
return __dt_gp_result;
'''


def verify_source(project):
    project = Path(project)
    if 'gp_connect_check' not in project_names(project, 'scripts', 'script'):
        raise ValueError('candidate not declared')
    if (project / 'scripts/gp_connect_check.gml').read_text(encoding='utf-8') != CANDIDATE:
        raise ValueError('changed connect candidate')
    load = (project / 'scripts/setting_load.gml').read_text(encoding='utf-8')
    save = (project / 'scripts/setting_save.gml').read_text(encoding='utf-8')
    expected_load = 'global.__dt_setting_gamepad = ini_read_real("control","gamepad",0)'
    expected_new = 'global.__dt_setting_gamepad = 0'
    expected_save = 'ini_write_real("control","gamepad",global.__dt_setting_gamepad)'
    if (load.count(expected_load) != 1 or load.count(expected_new) != 1 or
            save.count(expected_save) != 1 or
            not load.index(expected_load) < load.index('else // new') < load.index(expected_new)):
        raise ValueError('changed setting candidate')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile

    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        raw = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    dyn = elf.get_section_by_name('.dynsym')
    rel = elf.get_section_by_name('.rel.dyn')
    syms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: syms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations() if r['r_info_type'] == 21}
    rp, plt = elf.get_section_by_name('.rel.plt'), elf.get_section_by_name('.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name for i, r in enumerate(rp.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(a, n):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= a and a+n <= seg['p_vaddr']+seg['p_filesz']:
                off = seg['p_offset'] + a - seg['p_vaddr']
                return raw[off:off+n]
        raise ValueError('address outside ELF')

    def ins(a):
        result = list(dis.disasm(read(a, 4), a))
        if len(result) != 1:
            raise ValueError('instruction decoding failed')
        return result[0]

    def literal(a):
        i = ins(a)
        if i.mnemonic != 'ldr' or len(i.operands) != 2 or i.operands[1].type != ARM_OP_MEM or i.reg_name(i.operands[1].mem.base) != 'pc':
            raise ValueError('expected pc-relative literal')
        return struct.unpack('<I', read(a+8+i.operands[1].mem.disp, 4))[0]

    def sym(base_load, add, offset_load, expected):
        address = (add + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        symbol = got.get(address)
        if not symbol or symbol.name != expected:
            raise ValueError(f'wrong relocation: {expected}')
        return symbol

    def payload(symbol):
        section = elf.get_section(symbol['st_shndx'])
        offset, length = symbol['st_value']-section['sh_addr'], symbol['st_size']
        if offset < 0 or offset + length > section['sh_size'] or section['sh_type'] == 'SHT_NOBITS':
            raise ValueError('invalid symbol data')
        return section.data()[offset:offset+length]

    for name, (start, size, digest) in EXPORTS.items():
        exports = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Script_' + name]
        if len(exports) != 1 or (exports[0]['st_value'], exports[0]['st_size']) != (start, size):
            raise ValueError('unexpected export: '+name)
        if hashlib.sha256(read(start, size)).hexdigest() != digest:
            raise ValueError('unexpected bytes: '+name)
    for base, add, off, name in (
        (0x38d480, 0x38d490, 0x38d48c, 'g_pGlobal'),
        (0x2ec444, 0x2ec450, 0x2ec448, 'g_pGlobal'),
        (0x2ee0f4, 0x2ee0fc, 0x2ee0ec, 'g_pGlobal'),
        (0x38d544, 0x38d54c, 0x38d548, 'g_VAR_os_type'),
        (0x38d594, 0x38d59c, 0x38d58c, 'g_GMLMathEpsilon'),
        (0x38d5dc, 0x38d5e4, 0x38d5e0, 'g_FUNC_gamepad_is_supported'),
        (0x38d648, 0x38d654, 0x38d650, 'g_FUNC_gamepad_get_device_count'),
        (0x38d7e8, 0x38d7f8, 0x38d7f0, 'g_FUNC_gamepad_is_connected'),
        (0x38d820, 0x38d828, 0x38d7fc, 'g_FUNC_gamepad_set_axis_deadzone'),
    ):
        sym(base, add, off, name)
    const = sym(0x38d820, 0x38d828, 0x38d824, 'gs_constArg0_185')
    if struct.unpack('<dII', payload(const)) != (0.2, 0, 0):
        raise ValueError('unexpected deadzone value')
    for base, add, off, name, value in (
        (0x2ece1c, 0x2ece30, 0x2ece2c, 'g_pString8559_130', b'control\0'),
        (0x2ece1c, 0x2ece30, 0x2ece24, 'g_pString8560_130', b'gamepad\0'),
        (0x2ee6f4, 0x2ee700, 0x2ee6f8, 'g_pString8614_131', b'control\0'),
        (0x2ee6f4, 0x2ee700, 0x2ee6fc, 'g_pString8615_131', b'gamepad\0'),
    ):
        if payload(sym(base, add, off, name)) != value:
            raise ValueError('unexpected INI key')
    checks = {
        0x38d4dc: ('ldr', 'r1, [r0]'), 0x38d4e0: ('ldr', 'r2, [r1, #8]'),
        0x38d4e4: ('mov', 'r1, #0x58'), 0x38d4e8: ('blx', 'r2'),
        0x38d558: ('str', 'r1, [sp, #0xa4]'), 0x38d560: ('str', 'r1, [sp, #0x98]'),
        0x38d588: ('vmov.f64', 'd1, #-4.000000e+00'), 0x38d5bc: ('bhi', '#0x38d9b4'),
        0x38d5c0: ('mov', 'r0, r8'), 0x38d5cc: ('vcvt.s32.f64', 's0, d0'),
        0x38d5d4: ('cmp', 'r0, #0'), 0x38d5d8: ('ble', '#0x38d9b4'),
        0x38d610: ('bl', '#0x17654c'), 0x38d628: ('ble', '#0x38d9b4'),
        0x38d68c: ('bl', '#0x17654c'), 0x38d7b4: ('mov', 'sl, #0'),
        0x38d844: ('add', 'r1, sp, #0x78'), 0x38d848: ('mov', 'r0, r5'),
        0x38d84c: ('bl', '#0x176594'), 0x38d854: ('bge', '#0x38d9b4'),
        0x38d85c: ('str', 'r5, [sp, #0x34]'), 0x38d880: ('mov', 'r3, #1'),
        0x38d884: ('bl', '#0x17654c'), 0x38d898: ('ble', '#0x38d95c'),
        0x38d8cc: ('str', 'r5, [sp, #0x2c]'), 0x38d8d0: ('str', 'r0, [sp, #0x30]'),
        0x38d8f8: ('mov', 'r3, #2'), 0x38d8fc: ('bl', '#0x17654c'),
        0x38d948: ('movw', 'r0, #0'), 0x38d950: ('movt', 'r0, #0x3ff0'),
        0x38d954: ('str', 'r0, [sp, #0x9c]'), 0x38d958: ('str', 'sl, [sp, #0x98]'),
        0x38d970: ('bl', '#0x1765a0'), 0x38d980: ('bne', '#0x38d83c'),
        0x2ec6ac: ('mov', 'r1, #0x58'), 0x2ec6b4: ('str', 'r0, [sp, #0x34]'),
        0x2ec740: ('str', 'r2, [sp, #0x14]'), 0x2ec744: ('str', 'r3, [sp, #0x18]'),
        0x2ece5c: ('ldr', 'r2, [sp, #0x14]'), 0x2ece60: ('ldr', 'r3, [sp, #0x18]'),
        0x2ece64: ('bl', '#0x176828'), 0x2ecea8: ('ldr', 'r6, [sp, #0x34]'),
        0x2ecec8: ('stm', 'r6, {r3, r7}'), 0x2ed490: ('ldr', 'r2, [sp, #0x34]'),
        0x2ed49c: ('str', 'r4, [r2, #0xc]'), 0x2ed4a0: ('str', 'r4, [r2, #4]'),
        0x2ed4a4: ('str', 'r4, [r2]'),
        0x2ee354: ('mov', 'r1, #0x58'), 0x2ee35c: ('str', 'r0, [sp, #0x1c]'),
        0x2ee6e8: ('ldr', 'r0, [sp, #0x1c]'), 0x2ee6ec: ('bl', '#0x176444'),
        0x2ee710: ('bl', '#0x17681c'),
    }
    for address, expected in checks.items():
        i = ins(address)
        if (i.mnemonic, i.op_str) != expected:
            raise ValueError(f'instruction mismatch {address:#x}: {i.mnemonic} {i.op_str}')
    if struct.unpack('<d', read(0x2ec750, 8))[0] != 0:
        raise ValueError('unexpected default INI value')
    for address, name in ((0x17654c, 'YYGML_CallLegacyFunction'), (0x176594, 'YYCompareVal'),
                          (0x1765a0, 'YYRValuepp'), (0x176828, 'YYGML_ini_read_real'),
                          (0x17681c, 'YYGML_ini_write_real')):
        if name not in calls.get(address, ''):
            raise ValueError('unexpected call: '+name)
    return {'apk_sha256': APK_SHA256, 'library_sha256': LIB_SHA256,
            'exports': {k: {'address': hex(v[0]), 'size': v[1], 'sha256': v[2]} for k, v in EXPORTS.items()},
            'global_slot': 88, 'settings_key': ['control', 'gamepad'], 'default': 0,
            'platform_numeric': 4, 'deadzone': 0.2,
            'limitations': 'Static Android ARM32 only. Alias is invented; os enum portability, unusual numeric values, compiler, input hardware, gameplay and iOS are not verified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    verify_source(a.project)
    a.output.write_text(json.dumps(inspect(a.apk), indent=2)+'\n', encoding='utf-8')
    print('GAMEPAD_CONNECT_EVIDENCE: partial static ARM32 candidate only')


if __name__ == '__main__':
    main()
