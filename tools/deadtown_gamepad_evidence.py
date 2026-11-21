#!/usr/bin/env python3
"""Verify four first-connected-gamepad candidates against pinned Android ARM32.

Static inspection only: does not establish unsupported/no-device return values,
compiler/runtime equivalence, actual controller behavior, Android or iOS input.
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

FUNCTIONS = {
    'gp_button_check': (0x38dcd0, '39d9db281a721eebf4e280b2b7bf6db5ea4ba14a7a9aaeea7d250016b478e49b'),
    'gp_button_check_pressed': (0x38e3e4, '48bd0d4665c87ec27462d5cd9d092e95ba81264e80c9b5dd857d947fff5e259a'),
    'gp_button_check_released': (0x38eaf8, '6a10ea8ea04f4f3a47b8bebbf27c47decc4fff7813a3ef5547155b6784166bfd'),
    'gp_axis_value': (0x38f20c, '468d90c6c82d676d1ec97c80e4aca21bbcf633621f9425d99c6300f184253b23'),
}


def candidate(name):
    return (f'/// Candidate reconstructed from Android ARM32; first connected device only.\n'
            'if (gamepad_is_supported())\n{\n'
            '    var __dt_gp_count, __dt_gp_index;\n'
            '    __dt_gp_count = gamepad_get_device_count();\n'
            '    for (__dt_gp_index = 0; __dt_gp_index < __dt_gp_count; __dt_gp_index += 1)\n'
            '    {\n'
            '        if (gamepad_is_connected(__dt_gp_index))\n'
            f'            return gamepad_{name[3:]}(__dt_gp_index, argument0);\n'
            '    }\n}\n')


def verify_source(project):
    project = Path(project)
    declared = project_names(project, 'scripts', 'script')
    for name in FUNCTIONS:
        if name not in declared or (project / 'scripts' / (name + '.gml')).read_text(encoding='utf-8') != candidate(name):
            raise ValueError('missing or changed candidate: ' + name)


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
    got = {r['r_offset']: syms.get_symbol(r['r_info_sym']).name for r in rel.iter_relocations() if r['r_info_type'] == 21}
    rp, plt = elf.get_section_by_name('.rel.plt'), elf.get_section_by_name('.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name for i, r in enumerate(rp.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(a, n):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= a and a+n <= seg['p_vaddr']+seg['p_filesz']:
                off = seg['p_offset']+a-seg['p_vaddr']
                return raw[off:off+n]
        raise ValueError('address outside ELF')

    def ins(a):
        inst = list(dis.disasm(read(a, 4), a))
        if len(inst) != 1:
            raise ValueError('instruction decoding failed')
        return inst[0]

    def literal(a):
        i = ins(a)
        if i.mnemonic != 'ldr' or len(i.operands) != 2 or i.operands[1].type != ARM_OP_MEM or i.reg_name(i.operands[1].mem.base) != 'pc':
            raise ValueError('expected pc-relative literal')
        return struct.unpack('<I', read(a+8+i.operands[1].mem.disp, 4))[0]

    for name, (start, digest) in FUNCTIONS.items():
        target = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Script_'+name]
        if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, 1812):
            raise ValueError('unexpected export: ' + name)
        if hashlib.sha256(read(start, 1812)).hexdigest() != digest:
            raise ValueError('unexpected native bytes: ' + name)
        base = (start + 0x14 + 8 + literal(start+0xc)) & 0xffffffff
        for off, expected in ((0x20, 'g_FUNC_gamepad_is_supported'),
                              (0xf4, 'g_FUNC_gamepad_get_device_count'),
                              (0x2f0, 'g_FUNC_gamepad_is_connected'),
                              (0x3f4, 'g_FUNC_gamepad_'+name[3:])):
            if got.get((base + literal(start+off)) & 0xffffffff) != expected:
                raise ValueError(f'wrong relocation for {name}: {expected}')
        # Branches and argument array construction; addresses are relative to
        # each export, which has the same instruction shape.
        checks = {
            0x98: ('bl', '#0x17654c'), 0x9c: ('bl', '#0x176444'),
            0xa0: ('vmov.f64', 'd8, #5.000000e-01'),
            0xac: ('vmrs', 'apsr_nzcv, fpscr'), 0xb0: ('ble', '#' + hex(start+0x578)),
            0x130: ('bl', '#0x17654c'),
            0x308: ('vldr', 'd0, [sb]'), 0x318: ('bl', '#0x176594'),
            0x31c: ('cmp', 'r0, #0'), 0x320: ('bge', '#' + hex(start+0x578)),
            0x328: ('str', 'r7, [sp, #0x3c]'), 0x33c: ('mov', 'r3, #1'),
            0x348: ('bl', '#0x17654c'), 0x34c: ('bl', '#0x176444'),
            0x350: ('vmov', 'd0, r0, r1'), 0x354: ('vcmpe.f64', 'd0, d8'),
            0x35c: ('bgt', '#' + hex(start+0x3c8)), 0x374: ('bl', '#0x1765a0'),
            0x41c: ('str', 'r7, [sp, #0x34]'), 0x3f4: ('ldr', 'r0, [pc, #0x308]'),
            0x414: ('ldr', 'r1, [sp, #0xd0]'), 0x420: ('ldr', 'r1, [r1]'),
            0x428: ('str', 'r1, [sp, #0x38]'), 0x438: ('mov', 'r3, #2'),
            0x444: ('bl', '#0x17654c'), 0x448: ('mov', 'r4, r0'),
            0x44c: ('ldr', 'r0, [sp, #0xc]'),
            0x454: ('beq', '#' + hex(start+0x578)),
        }
        # Some offsets above cover instructions around a PIC literal; reject
        # any discrepancy rather than infer behavior on a new binary.
        for off, (op, args) in checks.items():
            i = ins(start+off)
            if (i.mnemonic, i.op_str) != (op, args):
                raise ValueError(f'instruction mismatch {name}+{off:#x}: {i.mnemonic} {i.op_str}, expected {op} {args}')
        for address, expected in ((0x17654c, 'YYGML_CallLegacyFunction'), (0x176444, 'REAL_RValue'),
                                  (0x176594, 'YYCompareVal'), (0x1765a0, 'YYRValuepp')):
            if expected not in calls.get(address, ''):
                raise ValueError('unexpected PLT call: '+expected)
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'scripts': {name: {'address': hex(a), 'size': 1812, 'sha256': h} for name, (a, h) in FUNCTIONS.items()},
            'behavior': 'when supported, cache device count, scan ascending, return requested builtin on first connected device',
            'limitations': 'Static ARM32; implicit return without a connected device, runtime/compiler, hardware and iOS are not verified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2)+'\n', encoding='utf-8')
    print('GAMEPAD_EVIDENCE: first-connected-device candidates, static Android ARM32 only')


if __name__ == '__main__':
    main()
