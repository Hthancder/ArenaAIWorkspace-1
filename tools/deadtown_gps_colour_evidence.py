#!/usr/bin/env python3
"""Verify the pinned Android ARM32 random HSV colour script candidate.

Static analysis only. Random algorithm, legacy HSV implementation, compiler,
resource IDs, native execution and iOS behavior are not verified.
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
    if 'gps_colour_random' not in project_names(project, 'scripts', 'script'):
        raise ValueError('gps_colour_random not declared')
    expected = ('/// Candidate restored from Android ARM32; random colour in HSV space.\n'
                'return make_colour_hsv(irandom(255), 180, 120);\n')
    if (project / 'scripts/gps_colour_random.gml').read_text(encoding='utf-8') != expected:
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
    target = [s for s in elf.get_section_by_name('.dynsym').iter_symbols()
              if exported_name(s.name) == 'gml_Script_gps_colour_random']
    start, size = 0x1d86c4, 648
    if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, size):
        raise ValueError('unexpected GPS colour export')
    rel = elf.get_section_by_name('.rel.dyn')
    relsyms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: relsyms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations()
           if r['r_info_type'] == 21}
    plt, rp = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name
             for i, r in enumerate(rp.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(address, length):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and address + length <= seg['p_vaddr'] + seg['p_filesz']:
                pos = seg['p_offset'] + address - seg['p_vaddr']
                return raw[pos:pos + length]
        raise ValueError('address outside ELF')

    def ins(address):
        items = list(dis.disasm(read(address, 4), address))
        if len(items) != 1:
            raise ValueError('instruction decoding failed')
        return items[0]

    def require(address, op, args):
        i = ins(address)
        if (i.mnemonic, i.op_str) != (op, args):
            raise ValueError(f'instruction mismatch: {address:#x}')

    def literal(address):
        i = ins(address)
        if i.mnemonic != 'ldr' or len(i.operands) != 2 or i.operands[1].type != ARM_OP_MEM or i.reg_name(i.operands[1].mem.base) != 'pc':
            raise ValueError('expected literal load')
        return struct.unpack('<I', read(address + 8 + i.operands[1].mem.disp, 4))[0]

    if hashlib.sha256(read(start, size)).hexdigest() != '27eb5d2d10f76b522a390af173595cf52c3c816bc46be66f7ae0e85f1b51a202':
        raise ValueError('function bytes mismatch')
    base = (0x1d8720 + 8 + literal(0x1d8718)) & 0xffffffff
    def relocation(address, expected):
        symbol = got.get((base + literal(address)) & 0xffffffff)
        if symbol is None or symbol.name != expected:
            raise ValueError(f'relocation mismatch: {expected}')
        return symbol
    relocation(0x1d871c, 'g_FUNC_make_colour_hsv')
    values = []
    for address, name in ((0x1d8728, 'gs_constArg0_79'), (0x1d8730, 'gs_constArg1_79')):
        symbol = relocation(address, name)
        if symbol['st_size'] != 16:
            raise ValueError('unexpected constant RValue size')
        data = read(symbol['st_value'], 16)
        if data[8:] != bytes(8):
            raise ValueError('constant is not expected real RValue')
        values.append(struct.unpack('<d', data[:8])[0])
    if values != [180.0, 120.0]:
        raise ValueError('unexpected constant values')
    relocation(0x1d8748, 'gs_ret79')
    for address, op, args in (
        (0x1d870c, 'mov', 'r0, #0xff'), (0x1d8710, 'bl', '#0x176804'),
        (0x1d8714, 'vmov', 's0, r0'), (0x1d8720, 'add', 'r1, pc, r1'),
        (0x1d8724, 'vcvt.f64.s32', 'd0, s0'), (0x1d872c, 'ldr', 'r2, [r2, r1]'),
        (0x1d8734, 'ldr', 'r0, [r0, r1]'), (0x1d8738, 'str', 'r7, [sp, #0x34]'),
        (0x1d873c, 'add', 'r7, sp, #0x28'), (0x1d8740, 'str', 'r7, [sp, #0x1c]'),
        (0x1d8744, 'str', 'r0, [sp, #0x20]'), (0x1d874c, 'ldr', 'r0, [r2, #4]'),
        (0x1d8750, 'ldr', 'r3, [r3, r1]'), (0x1d8754, 'vstr', 'd0, [sp, #0x28]'),
        (0x1d8758, 'str', 'r3, [sp, #0x24]'), (0x1d875c, 'ldr', 'r2, [r5, r1]'),
        (0x1d8760, 'add', 'r1, sp, #0x1c'), (0x1d8764, 'mov', 'r3, #3'),
        (0x1d8768, 'stm', 'sp, {r0, r1}'), (0x1d8774, 'bl', '#0x17654c'),
        (0x1d8778, 'mov', 'r5, r0'),
    ):
        require(address, op, args)
    if 'YYGML_irandom' not in calls.get(0x176804, '') or 'YYGML_CallLegacyFunction' not in calls.get(0x17654c, ''):
        raise ValueError('unexpected call relocation')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'script': 'gps_colour_random', 'address': hex(start), 'size': size,
            'function_bytes_sha256': '27eb5d2d10f76b522a390af173595cf52c3c816bc46be66f7ae0e85f1b51a202',
            'static_call': 'make_colour_hsv(irandom(255), 180, 120)',
            'limitations': 'Static ARM32 only; native HSV and RNG implementations, compiler, resource IDs, iOS and gameplay not tested.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2) + '\n', encoding='utf-8')
    print('GPS_COLOUR_EVIDENCE: static Android ARM32 candidate only')


if __name__ == '__main__':
    main()
