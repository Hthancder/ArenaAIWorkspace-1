#!/usr/bin/env python3
"""Pin one YYC room-check script's ARM32 comparison and a source candidate.

This is static analysis of the pinned APK, not a decompiler or execution test.
The constant is an Android native resource index, not a portable GMX room ID.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name, project_names, resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, project_names, resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member


def verify_source(project):
    project = Path(project)
    if 'check_room_is_multiplay_room' not in project_names(project, 'scripts', 'script'):
        raise ValueError('candidate is not declared')
    expected = ('/// Candidate for valid rooms at the default comparison tolerance.\n'
                '/// Name lookup avoids assuming a portable numeric room ID.\n'
                'return room_get_name(room) == "rom_play_defence";\n')
    if (project / 'scripts/check_room_is_multiplay_room.gml').read_text(encoding='utf-8') != expected:
        raise ValueError('unexpected room-check candidate')


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
    names = resource_names(data, b'ROOM')
    if len(names) != 15 or len(set(names)) != len(names) or names[14] != 'rom_play_defence':
        raise ValueError('unexpected native room table')
    integer_case_agreement = all((abs(index - 14) <= 1e-10) == (name == 'rom_play_defence')
                                 for index, name in enumerate(names))
    if not integer_case_agreement:
        raise ValueError('room names do not match integer comparison at default epsilon')
    elf = ELFFile(io.BytesIO(raw))
    syms = elf.get_section_by_name('.dynsym')
    target = [s for s in syms.iter_symbols() if exported_name(s.name) == 'gml_Script_check_room_is_multiplay_room']
    if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (0x2f5ec4, 476):
        raise ValueError('unexpected script export')
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

    def read(address, size):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and address + size <= seg['p_vaddr'] + seg['p_filesz']:
                offset = seg['p_offset'] + address - seg['p_vaddr']
                return raw[offset:offset + size]
        raise ValueError(f'address outside ELF bytes: {address:#x}')

    def instruction(address):
        result = list(dis.disasm(read(address, 4), address))
        if len(result) != 1:
            raise ValueError(f'invalid instruction at {address:#x}')
        return result[0]

    def require(address, op, operands):
        ins = instruction(address)
        if (ins.mnemonic, ins.op_str) != (op, operands):
            raise ValueError(f'instruction mismatch at {address:#x}')

    def literal(address):
        ins = instruction(address)
        if (ins.mnemonic != 'ldr' or len(ins.operands) != 2 or ins.operands[1].type != ARM_OP_MEM
                or ins.reg_name(ins.operands[1].mem.base) != 'pc'):
            raise ValueError(f'expected PC-relative load at {address:#x}')
        return struct.unpack('<I', read(address + 8 + ins.operands[1].mem.disp, 4))[0]

    def relocation(base_load, add, offset_load, name):
        address = (add + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        symbol = got.get(address)
        if symbol is None or symbol.name != name:
            raise ValueError(f'GOT symbol mismatch: {name}')
        return symbol

    def call(address, expected):
        ins = instruction(address)
        if ins.mnemonic != 'bl' or expected not in calls.get(int(ins.op_str[1:], 16), ''):
            raise ValueError(f'call mismatch at {address:#x}')

    relocation(0x2f5ecc, 0x2f5ed8, 0x2f5edc, 'g_VAR_room')
    epsilon = relocation(0x2f5f38, 0x2f5f44, 0x2f5f3c, 'g_GMLMathEpsilon')
    if epsilon['st_size'] != 8 or struct.unpack('<d', read(epsilon['st_value'], 8))[0] != 1e-10:
        raise ValueError('unexpected static epsilon initializer')
    call(0x2f5f24, 'Variable_GetValue_Direct')
    call(0x2f5f2c, 'REAL_RValue')
    for address, op, args in (
        (0x2f5ed0, 'mov', 'r4, r2'), (0x2f5ed8, 'add', 'r1, pc, r1'),
        (0x2f5ee8, 'ldr', 'r3, [r3, r1]'),
        (0x2f5f18, 'ldr', 'r1, [r3, #4]'), (0x2f5f20, 'mov', 'r2, #0x80000000'),
        (0x2f5f30, 'vmov.f64', 'd1, #-1.400000e+01'), (0x2f5f34, 'vmov', 'd0, r0, r1'),
        (0x2f5f40, 'vadd.f64', 'd0, d0, d1'), (0x2f5f44, 'add', 'r0, pc, r0'),
        (0x2f5f48, 'ldr', 'r0, [r1, r0]'), (0x2f5f4c, 'vcmpe.f64', 'd0, #0'),
        (0x2f5f50, 'vmrs', 'apsr_nzcv, fpscr'), (0x2f5f54, 'vldr', 'd1, [r0]'),
        (0x2f5f58, 'vnegmi.f64', 'd0, d0'), (0x2f5f5c, 'vcmpe.f64', 'd0, d1'),
        (0x2f5f60, 'vmrs', 'apsr_nzcv, fpscr'), (0x2f5f64, 'bls', '#0x2f5fa4'),
        (0x2f5f94, 'mov', 'r0, #0'), (0x2f5f98, 'str', 'r0, [r4, #0xc]'),
        (0x2f5f9c, 'str', 'r0, [r4, #4]'), (0x2f5fa0, 'b', '#0x2f5fe4'),
        (0x2f5fd0, 'movw', 'r1, #0'), (0x2f5fd4, 'mov', 'r0, #0'),
        (0x2f5fd8, 'movt', 'r1, #0x3ff0'), (0x2f5fdc, 'str', 'r0, [r4, #0xc]'),
        (0x2f5fe0, 'str', 'r1, [r4, #4]'), (0x2f5fe4, 'str', 'r0, [r4]'),
    ):
        require(address, op, args)
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'script': 'check_room_is_multiplay_room', 'function_address': '0x2f5ec4',
            'builtin_variable': 'room', 'compared_native_room_index': 14,
            'room_name_at_native_index': names[14], 'epsilon_static_initializer': 1e-10,
            'native_room_names': names, 'all_room_indices_agree_at_default_epsilon': integer_case_agreement,
            'static_rule_for_finite_values': 'return 1 when abs(room - 14) <= current epsilon, otherwise 0',
            'candidate_rule': 'room_get_name(room) == "rom_play_defence"',
            'limitations': 'Static Android ARM32 only; epsilon can change at runtime, no native or iOS execution. '
                           'Native index is not a portable GMX ID. Candidate assumes valid named rooms and default '
                           'tolerance. The defence room and multiplayer logic are missing in source.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--project', type=Path, help='also verify the declared candidate')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.project is not None:
        verify_source(args.project)
    result = inspect(args.apk)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('ROOM_CHECK_EVIDENCE: native room index 14; source name-lookup candidate, static only')


if __name__ == '__main__':
    main()
