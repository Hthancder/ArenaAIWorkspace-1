#!/usr/bin/env python3
"""Inspect Android YYC deactivate_all_auto without guessing its global name.

The object IDs and variable slot are native-only. This report does not add a
GML script, prove active/inactive semantics, or execute Android or iOS code.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name, resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        raw = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
        data = read_zip_member(z, 'assets/game.droid')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    objects = resource_names(data, b'OBJT')
    if len(objects) != 240 or objects[38] != 'sys_global' or objects[74] != 'sys_multi':
        raise ValueError('unexpected native object table')
    elf = ELFFile(io.BytesIO(raw))
    start, size = 0x1cfc40, 704
    target = [s for s in elf.get_section_by_name('.dynsym').iter_symbols()
              if exported_name(s.name) == 'gml_Script_deactivate_all_auto']
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

    def ins(address):
        items = list(dis.disasm(read(address, 4), address))
        if len(items) != 1:
            raise ValueError('invalid instruction')
        return items[0]

    def literal(address):
        instruction = ins(address)
        if instruction.mnemonic != 'ldr' or len(instruction.operands) != 2 or instruction.operands[1].type != ARM_OP_MEM or instruction.reg_name(instruction.operands[1].mem.base) != 'pc':
            raise ValueError('expected PC-relative load')
        return struct.unpack('<I', read(address + 8 + instruction.operands[1].mem.disp, 4))[0]

    def relocation(base_load, add, offset_load, expected):
        addr = (add + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        symbol = got.get(addr)
        if symbol is None or symbol.name != expected:
            raise ValueError(f'relocation mismatch: {expected}')
        return symbol

    digest = hashlib.sha256(read(start, size)).hexdigest()
    if digest != 'afded62bd69c87f35ca7b74523d6b2f4e1ff130f06277d93cf4454a3058ed09b':
        raise ValueError('unexpected function bytes')
    relocation(0x1cfc4c, 0x1cfc60, 0x1cfc54, 'g_pGlobal')
    relocation(0x1cfcc0, 0x1cfccc, 0x1cfcc8, 'g_FUNC_instance_deactivate_all')
    relocation(0x1cfd44, 0x1cfd50, 0x1cfd4c, 'g_FUNC_instance_activate_object')
    for base, add, offset, name, expected in (
        (0x1cfcc0, 0x1cfccc, 0x1cfcd0, 'gs_constArg0_65', 1.0),
        (0x1cfd44, 0x1cfd50, 0x1cfd54, 'gs_constArg1_65', 38.0),
        (0x1cfdcc, 0x1cfdd8, 0x1cfdd4, 'gs_constArg2_65', 74.0),
    ):
        symbol = relocation(base, add, offset, name)
        value = read(symbol['st_value'], 16)
        if symbol['st_size'] != 16 or value[8:] != bytes(8) or struct.unpack('<d', value[:8])[0] != expected:
            raise ValueError(f'unexpected real argument: {name}')
    for address, op, operands in (
        (0x1cfc60, 'add', 'r0, pc, r0'), (0x1cfc74, 'ldr', 'r0, [r1, r0]'),
        (0x1cfc80, 'ldr', 'r0, [r0]'), (0x1cfc94, 'ldr', 'r1, [r0]'),
        (0x1cfc98, 'ldr', 'r2, [r1, #8]'), (0x1cfc9c, 'mov', 'r1, #0x30'),
        (0x1cfca0, 'blx', 'r2'), (0x1cfca8, 'bl', '#0x176444'),
        (0x1cfcac, 'vmov.f64', 'd1, #5.000000e-01'), (0x1cfcb0, 'vmov', 'd0, r0, r1'),
        (0x1cfcb4, 'vcmpe.f64', 'd0, d1'), (0x1cfcb8, 'vmrs', 'apsr_nzcv, fpscr'),
        (0x1cfcbc, 'ble', '#0x1cfe70'),
        (0x1cfccc, 'add', 'r0, pc, r0'), (0x1cfcd8, 'ldr', 'r1, [r1, r0]'),
        (0x1cfcdc, 'ldr', 'r2, [r2, r0]'), (0x1cfce0, 'str', 'r2, [sp, #0x14]'),
        (0x1cfce4, 'ldr', 'r1, [r1, #4]'), (0x1cfcf0, 'add', 'r0, sp, #0x14'),
        (0x1cfcf4, 'str', 'r1, [sp]'), (0x1cfcf8, 'str', 'r0, [sp, #4]'),
        (0x1cfd04, 'mov', 'r3, #1'), (0x1cfd08, 'bl', '#0x17654c'),
        (0x1cfd50, 'add', 'r0, pc, r0'), (0x1cfd58, 'ldr', 'r3, [fp, r0]'),
        (0x1cfd60, 'ldr', 'r0, [r1, r0]'), (0x1cfd64, 'str', 'r0, [sp, #0x10]'),
        (0x1cfd68, 'ldr', 'r0, [r3, #4]'), (0x1cfd84, 'add', 'r1, sp, #0x10'),
        (0x1cfd88, 'mov', 'r3, #1'), (0x1cfd8c, 'stm', 'sp, {r0, r1}'),
        (0x1cfd98, 'bl', '#0x17654c'), (0x1cfdd8, 'add', 'r0, pc, r0'),
        (0x1cfddc, 'ldr', 'r3, [fp, r0]'), (0x1cfde4, 'ldr', 'r0, [r1, r0]'),
        (0x1cfde8, 'str', 'r0, [sp, #0xc]'), (0x1cfdec, 'ldr', 'r0, [r3, #4]'),
        (0x1cfe08, 'add', 'r1, sp, #0xc'), (0x1cfe0c, 'mov', 'r3, #1'),
        (0x1cfe10, 'stm', 'sp, {r0, r1}'), (0x1cfe1c, 'bl', '#0x17654c'),
    ):
        instruction = ins(address)
        if (instruction.mnemonic, instruction.op_str) != (op, operands):
            raise ValueError(f'instruction mismatch at {address:#x}')
    if 'REAL_RValue' not in calls.get(0x176444, '') or 'YYGML_CallLegacyFunction' not in calls.get(0x17654c, ''):
        raise ValueError('unexpected call relocation')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'script': 'deactivate_all_auto', 'address': hex(start), 'function_bytes_sha256': digest,
            'native_global_slot': 48, 'condition_for_finite_value': 'global slot > 0.5',
            'true_branch_calls_in_order': ['instance_deactivate_all(1)', 'instance_activate_object(sys_global)', 'instance_activate_object(sys_multi)'],
            'object_native_ids': {'sys_global': 38, 'sys_multi': 74},
            'limitations': 'Static ARM32 only. Global slot name not identified; IDs are not portable; sys_multi is missing in source. '
                           'No GML added, no native/iOS execution or instance activation behavior verified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    args.output.write_text(json.dumps(inspect(args.apk), indent=2) + '\n', encoding='utf-8')
    print('DEACTIVATE_AUTO_EVIDENCE: unidentified global slot; no script added')


if __name__ == '__main__':
    main()
