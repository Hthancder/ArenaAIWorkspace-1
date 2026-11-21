#!/usr/bin/env python3
"""Pin the Android ARM32 random-string candidate; static evidence only.

No equivalence of RNG, character encoding, error handling, compiler, or iOS
execution is implied. The script's random state consumption is significant.
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

CANDIDATE = '''/// Candidate restored from Android ARM32. Random behavior is not verified on iOS.
var result = "";
var upper, lower, digit;
repeat (20)
{
    upper = irandom_range(65, 90);
    lower = irandom_range(97, 122);
    digit = irandom_range(48, 57);
    result += chr(choose(upper, lower, digit));
}
return result;
'''


def verify_source(project):
    project = Path(project)
    if 'generate_random_string' not in project_names(project, 'scripts', 'script'):
        raise ValueError('candidate not declared')
    if (project / 'scripts/generate_random_string.gml').read_text(encoding='utf-8') != CANDIDATE:
        raise ValueError('unexpected candidate script')


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
    start, size = 0x382674, 1344
    target = [s for s in elf.get_section_by_name('.dynsym').iter_symbols()
              if exported_name(s.name) == 'gml_Script_generate_random_string']
    if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, size):
        raise ValueError('unexpected script export')
    rel = elf.get_section_by_name('.rel.dyn')
    syms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: syms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations() if r['r_info_type'] == 21}
    rp, plt = elf.get_section_by_name('.rel.plt'), elf.get_section_by_name('.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name for i, r in enumerate(rp.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(address, length):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and address + length <= seg['p_vaddr'] + seg['p_filesz']:
                offset = seg['p_offset'] + address - seg['p_vaddr']
                return raw[offset:offset + length]
        raise ValueError('address outside ELF')

    def instruction(address):
        result = list(dis.disasm(read(address, 4), address))
        if len(result) != 1:
            raise ValueError('invalid instruction')
        return result[0]

    def literal(address):
        ins = instruction(address)
        if ins.mnemonic != 'ldr' or len(ins.operands) != 2 or ins.operands[1].type != ARM_OP_MEM or ins.reg_name(ins.operands[1].mem.base) != 'pc':
            raise ValueError('expected PC-relative load')
        return struct.unpack('<I', read(address + 8 + ins.operands[1].mem.disp, 4))[0]

    def relocation(base_load, add, offset_load, expected):
        addr = (add + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        sym = got.get(addr)
        if sym is None or sym.name != expected:
            raise ValueError(f'relocation mismatch: {expected}')
        return sym

    digest = hashlib.sha256(read(start, size)).hexdigest()
    if digest != '77bdc8f736ca4a15819060780993a7d3cdf4588062dc57fa15ae1bfc3e4afd6b':
        raise ValueError('unexpected script bytes')
    empty = relocation(0x382684, 0x38268c, 0x382694, 'g_pString11045_168')
    section = elf.get_section(empty['st_shndx'])
    if section['sh_type'] != 'SHT_NOBITS' or empty['st_size'] != 1 or not 0 <= empty['st_value'] - section['sh_addr'] < section['sh_size']:
        raise ValueError('unexpected empty string storage')
    relocation(0x382724, 0x382734, 0x38272c, 'g_FUNC_chr')
    for addr, op, args in (
        (0x3826ac, 'movw', 'r2, #0'), (0x3826b4, 'movt', 'r2, #0x4034'),
        (0x3826dc, 'str', 'r2, [sp, #0x8c]'), (0x3826e8, 'str', 'r0, [sp, #0x88]'),
        (0x3826f8, 'bl', '#0x1765d0'), (0x382704, 'add', 'r0, sp, #0x88'),
        (0x382708, 'bl', '#0x176444'), (0x382714, 'vcvt.s32.f64', 's0, d0'),
        (0x382718, 'vmov', 'sl, s0'), (0x38271c, 'cmp', 'sl, #1'),
        (0x382720, 'blt', '#0x3828d0'), (0x382734, 'add', 'r0, pc, r0'),
        (0x382744, 'ldr', 'r1, [r1, r0]'), (0x382748, 'str', 'r1, [sp, #0x14]'),
        (0x382780, 'mov', 'r0, #0x41'), (0x382784, 'mov', 'r1, #0x5a'),
        (0x382788, 'bl', '#0x176714'), (0x382798, 'vstr', 'd0, [sp, #0x58]'),
        (0x38279c, 'mov', 'r0, #0x61'), (0x3827a0, 'mov', 'r1, #0x7a'),
        (0x3827a4, 'bl', '#0x176714'), (0x3827b4, 'vstr', 'd0, [sp, #0x48]'),
        (0x3827b8, 'mov', 'r0, #0x30'), (0x3827bc, 'mov', 'r1, #0x39'),
        (0x3827c0, 'bl', '#0x176714'), (0x3827c8, 'add', 'r0, sp, #0x58'),
        (0x3827cc, 'str', 'r0, [sp, #0x2c]'), (0x3827d0, 'add', 'r0, sp, #0x48'),
        (0x3827d8, 'str', 'r0, [sp, #0x30]'), (0x3827dc, 'add', 'r0, sp, #0x38'),
        (0x3827e4, 'str', 'r0, [sp, #0x34]'), (0x3827e8, 'vstr', 'd0, [sp, #0x38]'),
        (0x3827f0, 'add', 'r2, sp, #0x2c'), (0x3827f4, 'mov', 'r1, #3'),
        (0x3827f8, 'bl', '#0x176954'), (0x3827fc, 'str', 'r0, [sp, #0x28]'),
        (0x382800, 'ldr', 'r0, [sp, #0x14]'), (0x382804, 'ldr', 'r0, [r0, #4]'),
        (0x38280c, 'add', 'r0, sp, #0x28'), (0x382810, 'str', 'r0, [sp, #4]'),
        (0x38281c, 'mov', 'r3, #1'), (0x382824, 'bl', '#0x17654c'),
        (0x382828, 'mov', 'r1, r0'), (0x38282c, 'add', 'r0, sp, #0x78'),
        (0x382830, 'bl', '#0x1765b8'), (0x3828c4, 'sub', 'sl, sl, #1'),
        (0x3828c8, 'cmp', 'sl, #0'), (0x3828cc, 'bgt', '#0x38277c'),
    ):
        ins = instruction(addr)
        if (ins.mnemonic, ins.op_str) != (op, args):
            raise ValueError(f'instruction mismatch at {addr:#x}')
    for addr, name in ((0x176714, 'YYGML_irandom_range'), (0x176954, 'YYGML_choose'),
                       (0x17654c, 'YYGML_CallLegacyFunction'), (0x1765b8, 'YYRValuepLE'),
                       (0x1765d0, 'YYCreateString'), (0x176444, 'REAL_RValue')):
        if name not in calls.get(addr, ''):
            raise ValueError('unexpected call relocation')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'address': hex(start), 'script': 'generate_random_string', 'function_bytes_sha256': digest,
            'iterations': 20, 'initial_string': '', 'random_ranges_in_order': [[65, 90], [97, 122], [48, 57]],
            'body': 'append chr(choose(upper, lower, digit))',
            'limitations': 'Static ARM32 normal path only; RNG/choose/chr algorithms, errors, compiler and iOS unverified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2) + '\n', encoding='utf-8')
    print('RANDOM_STRING_EVIDENCE: static ARM32 normal path only')


if __name__ == '__main__':
    main()
