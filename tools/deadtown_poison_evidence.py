#!/usr/bin/env python3
"""Inspect a specific missing consumable-effect path in the pinned Android YYC.

This is targeted static evidence, not a complete decompilation or a patch.
It checks exact instruction/relocation patterns and fails on another APK or a
changed pattern. The inferred variable-table mapping still needs runtime proof.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_inventory import resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member


def inspect(apk_path):
    from elftools.elf.elffile import ELFFile
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM

    apk = Path(apk_path)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        lib = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
        game = read_zip_member(archive, 'assets/game.droid')
    if hashlib.sha256(lib).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(lib))
    segments = list(elf.iter_segments())
    symbols = elf.get_section_by_name('.dynsym')
    by_name = {sym.name: sym for sym in symbols.iter_symbols()}
    rel = elf.get_section_by_name('.rel.dyn')
    relsyms = elf.get_section(rel['sh_link'])
    reloc = {entry['r_offset']: relsyms.get_symbol(entry['r_info_sym'])
             for entry in rel.iter_relocations() if entry['r_info_type'] == 21}
    plt, relplt = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    pltsyms = elf.get_section(relplt['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: pltsyms.get_symbol(r['r_info_sym']).name
             for i, r in enumerate(relplt.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(address, size):
        for segment in segments:
            if (segment['p_type'] == 'PT_LOAD' and segment['p_vaddr'] <= address and
                    address + size <= segment['p_vaddr'] + segment['p_filesz']):
                pos = segment['p_offset'] + address - segment['p_vaddr']
                return lib[pos:pos + size]
        raise ValueError(f'address outside loadable file bytes: {address:x}')

    def instruction(address, mnemonic, operands):
        found = list(dis.disasm(read(address, 4), address))
        if len(found) != 1 or found[0].mnemonic != mnemonic or found[0].op_str != operands:
            raise ValueError(f'unexpected instruction at 0x{address:x}')
        return found[0]

    # item_use constructs db_info_get(..., 9): resolve its third argument's
    # GOT slot from ARM PC-relative literals, and confirm the stack ABI.
    ldr_base = instruction(0x1a56f0, 'ldr', 'r0, [pc, #0x830]')
    ldr_off = instruction(0x1a56f4, 'ldr', 'r1, [pc, #0x830]')
    instruction(0x1a56f8, 'add', 'r0, pc, r0')
    def literal(ins):
        if ins.operands[1].type != ARM_OP_MEM:
            raise ValueError('expected PC-relative literal')
        return struct.unpack('<I', read(ins.address + 8 + ins.operands[1].mem.disp, 4))[0]
    got = (0x1a56f8 + 8 + literal(ldr_base) + literal(ldr_off)) & 0xffffffff
    sym = reloc.get(got)
    if sym is None or sym.name != 'gs_constArg5_7' or sym['st_size'] != 16:
        raise ValueError('unexpected db_info_get argument relocation')
    number, flags, kind = struct.unpack('<dII', read(sym['st_value'], 16))
    if (number, flags, kind) != (9.0, 0, 0):
        raise ValueError('unexpected original field number')
    for addr, op, operands in (
        (0x1a56fc, 'str', 'r8, [sp, #0x7c]'),
        (0x1a5700, 'str', 'sl, [sp, #0x80]'),
        (0x1a5704, 'ldr', 'r0, [r1, r0]'),
        (0x1a5710, 'str', 'r0, [sp, #0x84]'),
        (0x1a5714, 'add', 'r0, sp, #0x7c'),
        (0x1a5718, 'str', 'r0, [sp]'),
        (0x1a5728, 'mov', 'r3, #3'),
        (0x1a5738, 'mov', 'r2, #0x1e'),
        (0x1a5748, 'mov', 'r2, #0x3c'),
        (0x1a57cc, 'mov', 'r1, #0x20'),
        (0x6022b4, 'mov', 'r0, #0x8e'),
        (0x6022b8, 'mov', 'r1, #0x20'),
        (0x6022d4, 'mov', 'r0, #0x8e'),
        (0x6022d8, 'mov', 'r1, #0x20'),
    ):
        instruction(addr, op, operands)
    expected_calls = {0x1a572c: 'gml_Script_db_info_get',
                      0x1a573c: 'YYRValue', 0x1a574c: 'YYRValue',
                      0x1a57d4: 'YYGML_Variable_SetValue',
                      0x6022c0: 'YYGML_Variable_GetValue',
                      0x6022cc: 'YYRValue',
                      0x6022e0: 'YYGML_Variable_SetValue'}
    for addr, expected in expected_calls.items():
        op = list(dis.disasm(read(addr, 4), addr))[0]
        if op.mnemonic != 'bl' or expected not in calls.get(int(op.op_str[1:], 16), ''):
            raise ValueError(f'unexpected helper call at 0x{addr:x}')
    names = resource_names(game, b'OBJT')
    if names[0x8e] != 'obj_player':
        raise ValueError('unexpected target object ID')
    expected_names = ['g_VAR_hungry', 'g_VAR_hp', 'g_VAR_buff_speed',
                      'g_VAR_buff_relax', 'g_VAR_buff_painkiller', 'g_VAR_buff_poison_protect']
    addresses = [by_name[name]['st_value'] for name in expected_names]
    if addresses != list(range(addresses[0], addresses[0] + len(addresses) * 8, 8)):
        raise ValueError('unexpected variable symbol layout')
    return {
        'apk_sha256': APK_SHA256, 'library_sha256': LIB_SHA256,
        'db_info_get_call': '0x1a572c', 'field': number,
        'field_symbol': sym.name, 'field_got_address': f'0x{got:x}',
        'field_value_multiplied_by': [30, 60], 'setter_call': '0x1a57d4',
        'variable_index': 32, 'adjacent_variable_symbols': expected_names,
        'variable_symbol_addresses': [f'0x{x:x}' for x in addresses],
        'player_object_id': 142, 'player_object_name': names[0x8e],
        'buff_step_get_call': '0x6022c0', 'buff_step_add_call': '0x6022cc',
        'buff_step_set_call': '0x6022e0',
        'interpretation': 'Strong static evidence that item_use reads use_db column 9, multiplies by 30*60, '
                          'and writes variable index 32; buff Step adds index 32 to obj_player. '
                          'The contiguous g_VAR symbol ordering suggests this is buff_poison_protect, '
                          'but the variable index registration and runtime behavior remain unverified.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(result['interpretation'])
    print('Report:', args.output)


if __name__ == '__main__':
    main()
