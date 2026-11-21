#!/usr/bin/env python3
"""Static evidence for the pinned Android YYC generate_basic_string candidate.

This is not native execution or proof of string encoding, allocation, compiler,
or iOS behavior. The candidate represents the ordinary successful path only.
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


def verify_source(project):
    project = Path(project)
    if 'generate_basic_string' not in project_names(project, 'scripts', 'script'):
        raise ValueError('candidate not declared')
    if (project / 'scripts/generate_basic_string.gml').read_text(encoding='utf-8') != '/// Candidate restored from Android ARM32.\nreturn "AAAAAAAAAAAAAAAAAAAA";\n':
        raise ValueError('unexpected candidate')


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
    start, size = 0x382bb4, 852
    target = [s for s in elf.get_section_by_name('.dynsym').iter_symbols()
              if exported_name(s.name) == 'gml_Script_generate_basic_string']
    if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, size):
        raise ValueError('unexpected export')
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
        found = list(dis.disasm(read(address, 4), address))
        if len(found) != 1:
            raise ValueError('instruction decoding failed')
        return found[0]

    def literal(address):
        ins = instruction(address)
        if ins.mnemonic != 'ldr' or len(ins.operands) != 2 or ins.operands[1].type != ARM_OP_MEM or ins.reg_name(ins.operands[1].mem.base) != 'pc':
            raise ValueError('expected PC relative load')
        return struct.unpack('<I', read(address + 8 + ins.operands[1].mem.disp, 4))[0]

    def text_symbol(base_load, add, offset_load, expected):
        addr = (add + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        symbol = got.get(addr)
        if symbol is None or symbol.name != expected:
            raise ValueError('unexpected string relocation')
        section = elf.get_section(symbol['st_shndx'])
        offset = symbol['st_value'] - section['sh_addr']
        length = symbol['st_size']
        if offset < 0 or offset + length > section['sh_size']:
            raise ValueError('string outside section')
        return bytes(length) if section['sh_type'] == 'SHT_NOBITS' else section.data()[offset:offset + length]

    digest = hashlib.sha256(read(start, size)).hexdigest()
    if digest != 'f8a025c4651c4a8e7cde1ac7c9a09441d7dfaac57d6eca734f7c387b4736040a':
        raise ValueError('function bytes mismatch')
    if text_symbol(0x382bbc, 0x382bc8, 0x382bcc, 'g_pString11053_169') != b'\0':
        raise ValueError('unexpected initial string')
    if text_symbol(0x382c68, 0x382c70, 0x382c6c, 'g_pString11055_169') != b'A\0':
        raise ValueError('unexpected appended string')
    for addr, op, args in (
        (0x382be4, 'movw', 'r2, #0'), (0x382bec, 'movt', 'r2, #0x4034'),
        (0x382c08, 'str', 'r0, [sp, #0x24]'), (0x382c0c, 'str', 'r2, [sp, #0x1c]'),
        (0x382c14, 'str', 'r0, [sp, #0x18]'), (0x382c24, 'bl', '#0x1765d0'),
        (0x382c30, 'add', 'r0, sp, #0x18'), (0x382c34, 'bl', '#0x176444'),
        (0x382c3c, 'vcvt.s32.f64', 's0, d0'), (0x382c40, 'vmov', 'r7, s0'),
        (0x382c44, 'cmp', 'r7, #1'), (0x382c48, 'blt', '#0x382ce8'),
        (0x382c70, 'add', 'r0, pc, r0'), (0x382c74, 'ldr', 'fp, [r1, r0]'),
        (0x382c98, 'sub', 'r7, r7, #1'), (0x382c9c, 'cmp', 'r7, #0'),
        (0x382ca0, 'bgt', '#0x382c78'), (0x382cb0, 'ldr', 'r1, [sp, #8]'),
        (0x382cc0, 'mov', 'r1, fp'), (0x382cc4, 'bl', '#0x1765c4'),
        (0x382cd4, 'bl', '#0x1765d0'), (0x382ce0, 'b', '#0x382c98'),
        (0x382d20, 'ldr', 'r0, [sp, #0x14]'), (0x382d24, 'str', 'r0, [r4, #0xc]'),
    ):
        ins = instruction(addr)
        if (ins.mnemonic, ins.op_str) != (op, args):
            raise ValueError(f'instruction mismatch: {addr:#x}')
    for addr, name in ((0x1765d0, 'YYCreateString'), (0x176444, 'REAL_RValue'), (0x1765c4, 'YYGML_AddString')):
        if name not in calls.get(addr, ''):
            raise ValueError('unexpected call relocation')
    return {'apk_sha256': APK_SHA256, 'script': 'generate_basic_string', 'address': hex(start),
            'function_bytes_sha256': digest, 'initial_string': '', 'appended_string': 'A', 'iterations': 20,
            'result_normal_path': 'A' * 20,
            'limitations': 'Static Android ARM32 only, normal allocation path; native execution, compiler, string internals and iOS unverified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2) + '\n', encoding='utf-8')
    print('BASIC_STRING_EVIDENCE: static ARM32 normal path only')


if __name__ == '__main__':
    main()
