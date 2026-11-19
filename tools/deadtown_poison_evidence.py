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
    # The following Step indices are corroborated below against save/load keys;
    # the index-registration mechanism itself is still not established.
    for addr, op, operands in (
        (0x5cea74, 'vldr', 'd8, [pc, #0x26c]'),
        (0x5d0448, 'mov', 'r1, #0x20'),
        (0x5d044c, 'blx', 'r2'),
        (0x5d0458, 'bl', '#0x176444'),
        (0x5d0468, 'vsub.f64', 'd0, d8, d0'),
        (0x5d0474, 'vneg.f64', 'd1, d1'),
        (0x5d0478, 'vcmpe.f64', 'd0, d1'),
        (0x5d0480, 'bpl', '#0x5d04d8'),
        (0x5d0498, 'mov', 'r1, #0x20'),
        (0x5d049c, 'blx', 'r2'),
        (0x5d04a0, 'mov', 'r5, r0'),
        (0x5d04a8, 'mov', 'r0, #0'),
        (0x5d04ac, 'movt', 'r1, #0x3ff0'),
        (0x5d04b4, 'str', 'r1, [sp, #0x154]'),
        (0x5d04b8, 'str', 'r0, [sp, #0x150]'),
        (0x5d04ec, 'mov', 'r1, #0x20'),
        (0x5d04f0, 'blx', 'r2'),
        (0x5d04f4, 'mov', 'r5, r0'),
        (0x5d0564, 'add', 'r0, sp, #0x150'),
        (0x5d0568, 'bl', '#0x176444'),
        (0x5d0584, 'vsub.f64', 'd0, d1, d0'),
        (0x5d0594, 'stm', 'r5, {r0, r1}'),
        (0x5d0598, 'b', '#0x5d05f4'),
        (0x5d0624, 'mov', 'r1, #0xab'),
        (0x5d0628, 'blx', 'r2'),
        (0x5d062c, 'mov', 'r5, r0'),
        (0x5d064c, 'mov', 'r0, #0'),
        (0x5d0650, 'str', 'r0, [r5, #0xc]'),
        (0x5d0654, 'str', 'r0, [r5, #4]'),
        (0x5d0658, 'str', 'r0, [r5]'),
        (0x5d0670, 'movw', 'r1, #0x38f'),
        (0x5d0690, 'bl', '#0x176594'),
        (0x5d0698, 'bge', '#0x5d06d8'),
        (0x5d06b0, 'movw', 'r1, #0x38f'),
        (0x5d06c8, 'mov', 'r1, #0x20'),
        (0x5d06d4, 'bl', '#0x176558'),
    ):
        instruction(addr, op, operands)
    if struct.unpack('<d', read(0x5cece8, 8))[0] != 0.0:
        raise ValueError('unexpected player Step comparison constant')
    # Resolve the exact strings used as section/key by the native save and load
    # code. An index-to-key association is independent of g_VAR symbol order.
    def string_relocation(base_address, base_load, offset_load, expected):
        address = (base_address + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        symbol = reloc.get(address)
        if symbol is None or symbol['st_size'] < 1:
            raise ValueError(f'no string relocation at 0x{address:x}')
        value = read(symbol['st_value'], symbol['st_size'])
        if value != expected.encode('ascii') + b'\0':
            raise ValueError(f'unexpected save/load string at 0x{address:x}')
        return {'text': expected, 'symbol': symbol.name, 'got': f'0x{address:x}'}

    string_specs = [
        # section and key at each native ini_write_real / ini_read_real call
        (0x1dc404, 0x1dc3f8, 0x1dc3fc, 'r0, [pc, #0xf2c]', 'r1, [pc, #0xf2c]', 'player'),
        (0x1dc404, 0x1dc3f8, 0x1dc400, 'r0, [pc, #0xf2c]', 'r7, [pc, #0xf2c]', 'buffpoison'),
        (0x1dc464, 0x1dc458, 0x1dc45c, 'r0, [pc, #0xed8]', 'r1, [pc, #0xed8]', 'player'),
        (0x1dc464, 0x1dc458, 0x1dc460, 'r0, [pc, #0xed8]', 'r7, [pc, #0xed8]', 'buffpoisonprotect'),
        (0x220fec, 0x220fdc, 0x220fe8, 'r2, [pc, #0x578]', 'r0, [pc, #0x574]', 'player'),
        (0x220fec, 0x220fdc, 0x220fe4, 'r2, [pc, #0x578]', 'r1, [pc, #0x574]', 'buffpoison'),
        (0x221074, 0x221064, 0x221070, 'r2, [pc, #0x4fc]', 'r0, [pc, #0x4f8]', 'player'),
        (0x221074, 0x221064, 0x22106c, 'r2, [pc, #0x4fc]', 'r1, [pc, #0x4f8]', 'buffpoisonprotect'),
    ]
    save_load_strings = [string_relocation(base, instruction(b, 'ldr', bops),
                                           instruction(o, 'ldr', oops), text)
                         for base, b, o, bops, oops, text in string_specs]
    hp_section = string_relocation(0x1dc174, instruction(0x1dc168, 'ldr', 'r0, [pc, #0xa80]'),
                                   instruction(0x1dc16c, 'ldr', 'r1, [pc, #0xa80]'), 'player')
    hp_key = string_relocation(0x1dc174, instruction(0x1dc168, 'ldr', 'r0, [pc, #0xa80]'),
                               instruction(0x1dc170, 'ldr', 'r7, [pc, #0xa80]'), 'hp')
    hp_max_section = string_relocation(0x1dc1d4, instruction(0x1dc1c8, 'ldr', 'r0, [pc, #0xa2c]'),
                                       instruction(0x1dc1cc, 'ldr', 'r1, [pc, #0xa2c]'), 'player')
    hp_max_key = string_relocation(0x1dc1d4, instruction(0x1dc1c8, 'ldr', 'r0, [pc, #0xa2c]'),
                                   instruction(0x1dc1d0, 'ldr', 'r7, [pc, #0xa2c]'), 'hp_max')
    skill_base = instruction(0x5cea94, 'ldr', 'r0, [pc, #0xfb8]')
    skill_offset = instruction(0x5cea98, 'ldr', 'r1, [pc, #0xfb8]')
    instruction(0x5cea9c, 'add', 'r0, pc, r0')
    skill_got = (0x5cea9c + 8 + literal(skill_base) + literal(skill_offset)) & 0xffffffff
    skill_symbol = reloc.get(skill_got)
    if skill_symbol is None or skill_symbol['st_size'] != 16 or struct.unpack(
            '<dII', read(skill_symbol['st_value'], 16)) != (20.0, 0, 0):
        raise ValueError('unexpected poison skill argument')
    for addr, op, operands in (
        (0x1dc144, 'mov', 'r0, #0x8e'), (0x1dc14c, 'mov', 'r1, #0x1c'),
        (0x1dc150, 'mov', 'r2, #0x80000000'), (0x1dc160, 'bl', '#0x176444'),
        (0x1dc174, 'add', 'r6, pc, r0'), (0x1dc178, 'vmov', 'r2, r3, d0'),
        (0x1dc17c, 'ldr', 'r0, [r1, r6]'), (0x1dc180, 'ldr', 'r1, [r7, r6]'),
        (0x1dc1a4, 'mov', 'r0, #0x8e'), (0x1dc1ac, 'mov', 'r1, #0xa9'),
        (0x1dc1b0, 'mov', 'r2, #0x80000000'), (0x1dc1c0, 'bl', '#0x176444'),
        (0x1dc1d4, 'add', 'r6, pc, r0'), (0x1dc1d8, 'vmov', 'r2, r3, d0'),
        (0x1dc1dc, 'ldr', 'r0, [r1, r6]'), (0x1dc1e0, 'ldr', 'r1, [r7, r6]'),
        (0x5cea50, 'mov', 'r1, #0xab'), (0x5cea54, 'blx', 'r2'),
        (0x5cea7c, 'vsub.f64', 'd0, d8, d0'), (0x5cea90, 'bpl', '#0x5ced30'),
        (0x5ceaa0, 'ldr', 'r0, [r1, r0]'), (0x5ceaac, 'str', 'r0, [sp, #0x2b4]'),
        (0x5ceab8, 'add', 'r2, sp, #0x2b4'), (0x5ceabc, 'str', 'r2, [sp]'),
        (0x5ceac4, 'mov', 'r3, #1'), (0x5cead0, 'vmov.f64', 'd1, #5.000000e-01'),
        (0x5cead8, 'vcmpe.f64', 'd0, d1'), (0x5ceae0, 'ble', '#0x5ceb78'),
        (0x5ceb28, 'mov', 'r1, #0x1c'), (0x5ceb40, 'movw', 'r1, #0x392'),
        (0x5ceb4c, 'vmov.f64', 'd0, #2.000000e+00'),
        (0x5ceb8c, 'mov', 'r1, #0x1c'), (0x5ceba4, 'movw', 'r1, #0x392'),
        (0x5cec5c, 'vsub.f64', 'd0, d1, d0'), (0x5cec6c, 'stm', 'r4, {r0, r1}'),
        (0x5cecd0, 'vsub.f64', 'd0, d1, d0'), (0x5cece0, 'stm', 'r4, {r0, r1}'),
        (0x5a6774, 'movw', 'sb, #0'), (0x5a677c, 'movt', 'sb, #0x4059'),
        (0x5a688c, 'mov', 'r1, #0xa9'), (0x5a6890, 'blx', 'r2'),
        (0x5a6894, 'mov', 'r6, r0'), (0x5a68b4, 'mov', 'r0, #0'),
        (0x5a68b8, 'str', 'r0, [r6, #0xc]'), (0x5a68bc, 'str', 'sb, [r6, #4]'),
        (0x5a68c0, 'str', 'r0, [r6]'), (0x5a6e10, 'movw', 'r1, #0x392'),
        (0x5a6e14, 'blx', 'r2'), (0x5a6e1c, 'vldr', 'd0, [pc, #0x14]'),
        (0x5a6e28, 'mov', 'r1, r6'), (0x5a6e44, 'mov', 'r0, r5'),
    ):
        instruction(addr, op, operands)
    if struct.unpack('<d', read(0x5a6e38, 8))[0] != 4500.0:
        raise ValueError('unexpected candidate poison damage divisor')
    for addr, expected in {0x1dc154: 'YYGML_Variable_GetValue', 0x1dc184: 'YYGML_ini_write_real',
                           0x1dc1b4: 'YYGML_Variable_GetValue', 0x1dc1e4: 'YYGML_ini_write_real',
                           0x5ceac8: 'gml_Script_rpg_skill_get_level', 0x5ceb58: '_ZdvRK8YYRValued',
                           0x5a6e2c: '_ZdvRK8YYRValued', 0x5a6e48: '_ZN8YYRValueaSERKS_'}.items():
        op = list(dis.disasm(read(addr, 4), addr))[0]
        if op.mnemonic != 'bl' or expected not in calls.get(int(op.op_str[1:], 16), ''):
            raise ValueError(f'unexpected damage helper call at 0x{addr:x}')
    for addr, op, operands in (
        (0x1dc3dc, 'mov', 'r0, #0x8e'), (0x1dc3e0, 'mov', 'r1, #0xab'),
        (0x1dc3e4, 'mov', 'r2, #0x80000000'), (0x1dc3ec, 'add', 'r0, sp, #0x3680'),
        (0x1dc404, 'add', 'r6, pc, r0'), (0x1dc408, 'vmov', 'r2, r3, d0'),
        (0x1dc40c, 'ldr', 'r0, [r1, r6]'), (0x1dc410, 'ldr', 'r1, [r7, r6]'),
        (0x1dc434, 'mov', 'r0, #0x8e'), (0x1dc43c, 'mov', 'r1, #0x20'),
        (0x1dc440, 'mov', 'r2, #0x80000000'), (0x1dc450, 'bl', '#0x176444'),
        (0x1dc464, 'add', 'r6, pc, r0'), (0x1dc468, 'vmov', 'r2, r3, d0'),
        (0x1dc46c, 'ldr', 'r0, [r1, r6]'), (0x1dc470, 'ldr', 'r1, [r7, r6]'),
        (0x220fec, 'add', 'r2, pc, r2'), (0x220ff8, 'ldr', 'r1, [r1, r2]'),
        (0x220ffc, 'ldr', 'r0, [r0, r2]'), (0x22103c, 'vmov', 'd0, r4, r5'),
        (0x221048, 'vstr', 'd0, [r6, #0x40]'), (0x221050, 'mov', 'r0, #0x8e'),
        (0x221058, 'mov', 'r1, #0xab'), (0x22105c, 'mov', 'r2, #0x80000000'),
        (0x221074, 'add', 'r2, pc, r2'), (0x221080, 'ldr', 'r1, [r1, r2]'),
        (0x221084, 'ldr', 'r0, [r0, r2]'), (0x2210c8, 'vmov', 'd0, r4, r5'),
        (0x2210dc, 'vstr', 'd0, [r1, #0x30]'), (0x2210e4, 'mov', 'r0, #0x8e'),
        (0x2210e8, 'mov', 'r1, #0x20'), (0x2210ec, 'mov', 'r2, #0x80000000'),
        # Initial zero, and the bound's IEEE-754 high and low words.
        (0x5a6ae8, 'movw', 'r7, #0x9400'), (0x5a6af0, 'movt', 'r7, #0x40d1'),
        (0x5a6cdc, 'mov', 'r1, #0x20'), (0x5a6ce0, 'blx', 'r2'),
        (0x5a6d04, 'mov', 'r0, #0'), (0x5a6d08, 'str', 'r0, [r5, #0xc]'),
        (0x5a6d0c, 'str', 'r0, [r5, #4]'), (0x5a6d10, 'str', 'r0, [r5]'),
        (0x5a6d28, 'movw', 'r1, #0x38f'), (0x5a6d2c, 'blx', 'r2'),
        (0x5a6d50, 'mov', 'r0, #0'), (0x5a6d54, 'str', 'r0, [r5, #0xc]'),
        (0x5a6d58, 'str', 'r7, [r5, #4]'), (0x5a6d5c, 'str', 'r0, [r5]'),
        # This is just the native zombie5 poison assignment block, not the
        # entire combat hit condition or evidence that every hit poisons.
        (0x68ee84, 'mov', 'r0, #0x8e'), (0x68ee88, 'mov', 'r1, #0xab'),
        (0x68ee8c, 'mov', 'r2, #0x80000000'), (0x68ee98, 'bl', '#0x176444'),
        (0x68eea4, 'vldr', 'd1, [pc, #-0x25c]'), (0x68eeac, 'vadd.f64', 'd0, d0, d1'),
        (0x68eebc, 'vcmpe.f64', 'd0, d1'), (0x68eec4, 'bpl', '#0x68ef14'),
        (0x68eec8, 'movw', 'r1, #0x2000'), (0x68eed4, 'mov', 'r0, #0'),
        (0x68eed8, 'movt', 'r1, #0x408c'), (0x68eee0, 'strd', 'r0, r1, [sl, #0x98]'),
        (0x68eee8, 'mov', 'r0, #0x8e'), (0x68eeec, 'mov', 'r1, #0xab'),
        (0x68eef0, 'mov', 'r2, #0x80000000'),
    ):
        instruction(addr, op, operands)
    for addr, expected in {0x1dc3e8: 'YYGML_Variable_GetValue', 0x1dc3f0: 'REAL_RValue',
                           0x1dc414: 'YYGML_ini_write_real', 0x1dc444: 'YYGML_Variable_GetValue',
                           0x1dc474: 'YYGML_ini_write_real', 0x221010: 'YYGML_ini_read_real',
                           0x221060: 'YYGML_Variable_SetValue', 0x221098: 'YYGML_ini_read_real',
                           0x2210f0: 'YYGML_Variable_SetValue', 0x68ee90: 'YYGML_Variable_GetValue',
                           0x68eef4: 'YYGML_Variable_SetValue'}.items():
        op = list(dis.disasm(read(addr, 4), addr))[0]
        if op.mnemonic != 'bl' or expected not in calls.get(int(op.op_str[1:], 16), ''):
            raise ValueError(f'unexpected save/load or zombie helper call at 0x{addr:x}')
    if struct.unpack('<d', read(0x68ec50, 8))[0] != -900.0:
        raise ValueError('unexpected zombie comparison constant')
    max_value = struct.unpack('<d', struct.pack('<II', 0, 0x40d19400))[0]
    zombie_value = struct.unpack('<d', struct.pack('<II', 0, 0x408c2000))[0]

    # The compiler's exported g_Vars pointer array contains global, instance,
    # and potentially other scope entries. It is not a flat instance-index
    # lookup: e.g. index 32 there is pointer, not buff_poison_protect.
    var_array = by_name['g_Vars']
    array_slot = var_array['st_value'] + 32 * 4
    # g_Vars slots use R_ARM_ABS32, while the GOT lookups above use GLOB_DAT.
    abs32 = {entry['r_offset']: relsyms.get_symbol(entry['r_info_sym'])
             for entry in rel.iter_relocations() if entry['r_info_type'] == 2}
    array_symbol = abs32.get(array_slot)
    if (var_array['st_size'] <= 32 * 4 or array_symbol is None or
            array_symbol.name != 'g_VAR_pointer'):
        raise ValueError('unexpected g_Vars pointer array layout')

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
        'player_step_evidence': {
            'function': 'gml_Object_obj_player_Step_0',
            'comparison_zero_literal': '0x5cece8',
            'variable_index': 32,
            'conditional_branch': '0x5d0480',
            'subtract_one_real_path': '0x5d0564-0x5d0594',
            'comparison_fallthrough_zeroes_variable_index': 171,
            'branch_target_zeroes_variable_index': 32,
            'candidate_upper_bound_index': 911,
            'clamp_assignment': '0x5d06a4-0x5d06d4',
            'limitations': 'The comparison uses a runtime-loaded tolerance; exact branching, types and '
                           'runtime behavior are not fully validated. Index 911 is a candidate bound, '
                           'not an independently registered name.',
        },
        'save_load_evidence': {
            'function_pair': ['gml_Script_game_save_protect', 'gml_Script_game_load_protect'],
            'section': 'player',
            'keys_to_player_indices': {'buffpoison': 171, 'buffpoisonprotect': 32},
            'save_get_calls': ['0x1dc3e8', '0x1dc444'],
            'save_write_calls': ['0x1dc414', '0x1dc474'],
            'load_read_calls': ['0x221010', '0x221098'],
            'load_set_calls': ['0x221060', '0x2210f0'],
            'resolved_string_relocations': save_load_strings,
            'limitations': 'The key associations are static; actual registration, other save modes, '
                           'path reachability and persistence are not runtime verified.',
        },
        'player_create_evidence': {'index': 32, 'initial_value': 0,
                                   'candidate_bound_index': 911, 'candidate_bound_initial_value': max_value},
        'poison_damage_evidence': {
            'poison_index': 171, 'health_candidate_index': 28,
            'health_save_section': hp_section, 'health_save_key': hp_key,
            'damage_candidate_index': 914, 'skill_id': 20, 'skill_arg_symbol': skill_symbol.name,
            'skill_got': f'0x{skill_got:x}', 'skill_call': '0x5ceac8',
            'skill_result_above_half_divisor': 2, 'create_numerator_candidate_index': 169,
            'numerator_save_section': hp_max_section, 'numerator_save_key': hp_max_key,
            'numerator_create_initial_value': 100, 'create_divisor': 4500,
            'create_divide_call': '0x5a6e2c',
            'limitations': 'Static real-number arithmetic paths only; name registration, reachability, '
                           'other writers to damage and health, and observed frame-rate behavior are unverified.',
        },
        'zombie5_step_evidence': {'target_index': 171, 'comparison_offset': -900.0,
                                  'fallthrough_set_value': zombie_value,
                                  'limitations': 'The surrounding combat condition and runtime reachability '
                                                 'are not established; the comparison uses runtime tolerance.'},
        'g_vars_index_32': {'symbol': array_symbol.name, 'slot': f'0x{array_slot:x}',
                            'warning': 'g_Vars is not a verified instance-variable-index mapping'},
        'interpretation': 'Strong static evidence that item_use reads use_db column 9, multiplies by 30*60, '
                          'and writes variable index 32; buff Step adds index 32 to obj_player. '
                          'Independent save/load instructions associate player indices 32 and 171 with '
                          'keys buffpoisonprotect and buffpoison respectively; registration and runtime '
                          'behavior remain unverified.',
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
