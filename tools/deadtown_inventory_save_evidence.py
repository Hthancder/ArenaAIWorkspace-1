#!/usr/bin/env python3
"""Trace four inventory global indices to normal-save/load keys in pinned ARM.

Only static evidence from a SHA-pinned APK, not a native or iOS execution, a
save-format converter, or a release patch. Never touches game save files.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_item_drop_evidence import inspect as inspect_drop
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_item_drop_evidence import inspect as inspect_drop
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile

    drop = inspect_drop(apk)
    if [x['global_index'] for x in drop['selector_cases']] != [0, 1, 2, 3]:
        raise ValueError('unexpected item_drop globals')
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        raw = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    segments = list(elf.iter_segments())
    symbols = elf.get_section_by_name('.dynsym')
    func = [s for s in symbols.iter_symbols() if s.name.startswith('_Z28gml_Script_game_save_protect')]
    if len(func) != 1 or (func[0]['st_value'], func[0]['st_size']) != (0x1d97f8, 265392):
        raise ValueError('unexpected normal save export')
    load_func = [s for s in symbols.iter_symbols() if s.name.startswith('_Z28gml_Script_game_load_protect')]
    if len(load_func) != 1 or (load_func[0]['st_value'], load_func[0]['st_size']) != (0x21a4a8, 208304):
        raise ValueError('unexpected normal load export')
    rel = elf.get_section_by_name('.rel.dyn')
    relsyms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: relsyms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations()
           if r['r_info_type'] == 21}
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
                offset = segment['p_offset'] + address - segment['p_vaddr']
                return raw[offset:offset + size]
        raise ValueError(f'address outside ELF file bytes: 0x{address:x}')

    def inst(address, mnemonic, operands):
        decoded = list(dis.disasm(read(address, 4), address))
        if len(decoded) != 1 or (decoded[0].mnemonic, decoded[0].op_str) != (mnemonic, operands):
            raise ValueError(f'unexpected instruction at 0x{address:x}')
        return decoded[0]

    def literal(address):
        decoded = list(dis.disasm(read(address, 4), address))
        if (len(decoded) != 1 or decoded[0].mnemonic != 'ldr' or len(decoded[0].operands) != 2 or
                decoded[0].operands[1].type != ARM_OP_MEM or decoded[0].reg_name(decoded[0].operands[1].mem.base) != 'pc'):
            raise ValueError(f'expected PC-relative literal at 0x{address:x}')
        return struct.unpack('<I', read(address + 8 + decoded[0].operands[1].mem.disp, 4))[0]

    def relocation(base, add, offset):
        address = (add + 8 + literal(base) + literal(offset)) & 0xffffffff
        symbol = got.get(address)
        if symbol is None:
            raise ValueError(f'missing GOT relocation at 0x{address:x}')
        return symbol

    def require_symbol(base, add, offset, expected):
        symbol = relocation(base, add, offset)
        if symbol.name != expected:
            raise ValueError(f'unexpected GOT symbol at 0x{add:x}')
        return symbol

    def require_string(base, add, offset, expected):
        symbol = relocation(base, add, offset)
        if not symbol.name.startswith('g_pString') or not 1 <= symbol['st_size'] <= 128:
            raise ValueError('unexpected string relocation')
        if read(symbol['st_value'], symbol['st_size']) != expected.encode('utf-8') + b'\x00':
            raise ValueError('unexpected save section/key string')

    def call(address, expected):
        decoded = list(dis.disasm(read(address, 4), address))
        if len(decoded) != 1 or decoded[0].mnemonic != 'bl' or expected not in calls.get(int(decoded[0].op_str[1:], 16), ''):
            raise ValueError(f'unexpected helper call at 0x{address:x}')

    # Establish the independent global getter and stack slots captured for
    # four maps. Keep the association to save keys separate from registration.
    for base, add in ((0x1d98d0, 0x1d98d4), (0x1d98f4, 0x1d98f8),
                      (0x1d9918, 0x1d991c), (0x1d993c, 0x1d9940)):
        require_symbol(base, add, 0x1d9820, 'g_pGlobal')
    for address, mnemonic, operands in (
        (0x1d98d4, 'add', 'r0, pc, r0'), (0x1d98d8, 'ldr', 'r0, [r4, r0]'),
        (0x1d98dc, 'ldr', 'r0, [r0]'), (0x1d98e0, 'ldr', 'r1, [r0]'), (0x1d98e4, 'ldr', 'r2, [r1, #8]'),
        (0x1d98e8, 'mov', 'r1, #0'), (0x1d98ec, 'blx', 'r2'), (0x1d98f0, 'str', 'r0, [sp, #0x1b0]'),
        (0x1d98f8, 'add', 'r0, pc, r0'), (0x1d98fc, 'ldr', 'r0, [r4, r0]'),
        (0x1d9900, 'ldr', 'r0, [r0]'), (0x1d9904, 'ldr', 'r1, [r0]'), (0x1d9908, 'ldr', 'r2, [r1, #8]'),
        (0x1d990c, 'mov', 'r1, #1'), (0x1d9910, 'blx', 'r2'), (0x1d9914, 'str', 'r0, [sp, #0x1ac]'),
        (0x1d991c, 'add', 'r0, pc, r0'), (0x1d9920, 'ldr', 'r0, [r4, r0]'),
        (0x1d9924, 'ldr', 'r0, [r0]'), (0x1d9928, 'ldr', 'r1, [r0]'), (0x1d992c, 'ldr', 'r2, [r1, #8]'),
        (0x1d9930, 'mov', 'r1, #2'), (0x1d9934, 'blx', 'r2'), (0x1d9938, 'str', 'r0, [sp, #0x1a4]'),
        (0x1d9940, 'add', 'r0, pc, r0'), (0x1d9944, 'ldr', 'r0, [r4, r0]'),
        (0x1d9948, 'ldr', 'r0, [r0]'), (0x1d994c, 'ldr', 'r1, [r0]'), (0x1d9950, 'ldr', 'r2, [r1, #8]'),
        (0x1d9954, 'mov', 'r1, #3'), (0x1d9958, 'blx', 'r2'), (0x1d995c, 'str', 'r0, [sp, #0x19c]'),
    ):
        inst(address, mnemonic, operands)

    # Every tuple pins the two literal strings, the map serialization and
    # the final ini_write_string call. Instruction checks below additionally
    # verify the saved global pointer and vector locations, not just proximity.
    rows = [
        ('weapon', (0x1daa78,0x1daa80,0x1daa70), (0x1daa98,0x1daaa0,0x1daa9c),
         0x1daa94,0x1daab4,(0x1daab8,0x1daac4,0x1daac0),0x1dab04,
         (0x1dab08,0x1dab18,0x1dab10),0x1dab44,0x1daac8,0x1daad4,0x1daadc,0x1daae0,0x1dab1c,
         'r2, [sp, #0x1b0]','r4, [r1, #0x550]','r2, [r1, #0x55c]','r5, [r1, #0x554]','r0, [r3, #0x558]'),
        ('equip', (0x1dabbc,0x1dabcc,0x1dabc4), (0x1dac00,0x1dac08,0x1dac04),
         0x1dabfc,0x1dac1c,(0x1dac20,0x1dac2c,0x1dac28),0x1dac6c,
         (0x1dac70,0x1dac80,0x1dac78),0x1dacac,0x1dac30,0x1dac3c,0x1dac44,0x1dac48,0x1dac84,
         'r2, [sp, #0x1ac]','r4, [r1, #0x520]','r2, [r1, #0x52c]','r5, [r1, #0x524]','r0, [r3, #0x528]'),
        ('use', (0x1dad24,0x1dad34,0x1dad2c), (0x1dad68,0x1dad70,0x1dad6c),
         0x1dad64,0x1dad84,(0x1dad88,0x1dad94,0x1dad90),0x1dadd4,
         (0x1dadd8,0x1dade8,0x1dade0),0x1dae14,0x1dad98,0x1dada4,0x1dadac,0x1dadb0,0x1dadec,
         'r2, [sp, #0x1a4]','r4, [r1, #0x4f0]','r2, [r1, #0x4fc]','r5, [r1, #0x4f4]','r0, [r3, #0x4f8]'),
        ('etc', (0x1dae8c,0x1dae9c,0x1dae94), (0x1daed0,0x1daed8,0x1daed4),
         0x1daecc,0x1daeec,(0x1daef0,0x1daefc,0x1daef8),0x1daf3c,
         (0x1daf40,0x1daf50,0x1daf48),0x1daf7c,0x1daf00,0x1daf0c,0x1daf14,0x1daf18,0x1daf54,
         'r2, [sp, #0x19c]','r4, [r1, #0x4c0]','r2, [r1, #0x4cc]','r5, [r1, #0x4c4]','r0, [r3, #0x4c8]'),
    ]
    for address, mnemonic, operands in (
        # Confirm the string GOT loads, output RValue pointers, vector bases,
        # and argument-count/address setup around both legacy calls.
        (0x1daa8c, 'ldr', 'r1, [r0, r1]'), (0x1daa88, 'add', 'r4, r5, #0x98'),
        (0x1daaac, 'ldr', 'r1, [r1, r0]'), (0x1daaa8, 'add', 'r5, r6, #0x88'),
        (0x1daacc, 'ldr', 'r0, [r1, r0]'), (0x1daad8, 'ldr', 'r0, [r0, #4]'),
        (0x1daad0, 'add', 'r1, r6, #0x328'), (0x1daae8, 'mov', 'r3, #1'),
        (0x1daaec, 'add', 'r1, r4, #0x84'), (0x1daaf4, 'stm', 'sp, {r0, r1}'),
        (0x1dab14, 'add', 'r3, r4, #0x328'), (0x1dab20, 'ldr', 'r2, [r2, r1]'),
        (0x1dab24, 'ldr', 'r0, [r2, #4]'), (0x1dab30, 'mov', 'r3, #3'),
        (0x1dab34, 'add', 'r1, r4, #0x78'), (0x1dab38, 'stm', 'sp, {r0, r1}'),
        (0x1dabd4, 'ldr', 'r1, [r0, r1]'), (0x1dabf4, 'add', 'r4, r5, #0x68'),
        (0x1dac14, 'ldr', 'r1, [r1, r0]'), (0x1dac10, 'add', 'r5, r6, #0x58'),
        (0x1dac34, 'ldr', 'r0, [r1, r0]'), (0x1dac40, 'ldr', 'r0, [r0, #4]'),
        (0x1dac38, 'add', 'r1, r6, #0x328'), (0x1dac50, 'mov', 'r3, #1'),
        (0x1dac54, 'add', 'r1, r4, #0x54'), (0x1dac5c, 'stm', 'sp, {r0, r1}'),
        (0x1dac7c, 'add', 'r3, r4, #0x328'), (0x1dac88, 'ldr', 'r2, [r2, r1]'),
        (0x1dac8c, 'ldr', 'r0, [r2, #4]'), (0x1dac98, 'mov', 'r3, #3'),
        (0x1dac9c, 'add', 'r1, r4, #0x48'), (0x1daca0, 'stm', 'sp, {r0, r1}'),
        (0x1dad3c, 'ldr', 'r1, [r0, r1]'), (0x1dad5c, 'add', 'r4, r5, #0x38'),
        (0x1dad7c, 'ldr', 'r1, [r1, r0]'), (0x1dad78, 'add', 'r5, r6, #0x28'),
        (0x1dad9c, 'ldr', 'r0, [r1, r0]'), (0x1dada8, 'ldr', 'r0, [r0, #4]'),
        (0x1dada0, 'add', 'r1, r6, #0x328'), (0x1dadb8, 'mov', 'r3, #1'),
        (0x1dadbc, 'add', 'r1, r4, #0x24'), (0x1dadc4, 'stm', 'sp, {r0, r1}'),
        (0x1dade4, 'add', 'r3, r4, #0x328'), (0x1dadf0, 'ldr', 'r2, [r2, r1]'),
        (0x1dadf4, 'ldr', 'r0, [r2, #4]'), (0x1dae00, 'mov', 'r3, #3'),
        (0x1dae04, 'add', 'r1, r4, #0x18'), (0x1dae08, 'stm', 'sp, {r0, r1}'),
        (0x1daea4, 'ldr', 'r1, [r0, r1]'), (0x1daec4, 'add', 'r4, r5, #8'),
        (0x1daee4, 'ldr', 'r1, [r1, r0]'), (0x1daee0, 'add', 'r5, r6, #0x3f8'),
        (0x1daf04, 'ldr', 'r0, [r1, r0]'), (0x1daf10, 'ldr', 'r0, [r0, #4]'),
        (0x1daf08, 'add', 'r1, r6, #0x328'), (0x1daf20, 'mov', 'r3, #1'),
        (0x1daf24, 'add', 'r1, r4, #0x3f4'), (0x1daf2c, 'stm', 'sp, {r0, r1}'),
        (0x1daf4c, 'add', 'r3, r4, #0x328'), (0x1daf58, 'ldr', 'r2, [r2, r1]'),
        (0x1daf5c, 'ldr', 'r0, [r2, #4]'), (0x1daf68, 'mov', 'r3, #3'),
        (0x1daf6c, 'add', 'r1, r4, #0x3e8'), (0x1daf70, 'stm', 'sp, {r0, r1}'),
    ):
        inst(address, mnemonic, operands)
    result = []
    for index, (key, section, key_str, section_call, key_call, map_sym, map_call,
                ini_sym, ini_call, load, section_store, global_store, key_store, result_store,
                load_op, section_op, global_op, key_op, result_op) in enumerate(rows):
        inst(section[1], 'add', 'r1, pc, r1')
        inst(key_str[1], 'add', 'r0, pc, r0')
        require_string(*section, 'inventory')
        require_string(*key_str, key)
        require_symbol(*map_sym, 'g_FUNC_ds_map_write')
        require_symbol(*ini_sym, 'g_FUNC_ini_write_string')
        for address in (section_call, key_call):
            call(address, 'YYSetString')
        for address in (map_call, ini_call):
            call(address, 'YYGML_CallLegacyFunction')
        for address, mnemonic, operands in ((load, 'ldr', load_op), (section_store, 'str', section_op),
                                             (global_store, 'str', global_op), (key_store, 'str', key_op),
                                             (result_store, 'str', result_op)):
            inst(address, mnemonic, operands)
        # r4/r5 hold YYSetString output pointers; confirm at each call site.
        inst(section_call - 4, 'mov', 'r0, r4')
        inst(key_call - 4, 'mov', 'r0, r5')
        result.append({'selector': index + 1, 'global_index': index, 'save_section': 'inventory',
                       'save_key': key, 'map_write_call': f'0x{map_call:x}',
                       'ini_write_string_call': f'0x{ini_call:x}'})
    # Independently pin the corresponding normal-load global getters and four
    # clear calls. BSS-backed one-byte literals are initially zero but writable;
    # the exact runtime default is not observed in this static experiment.
    for base, add in ((0x21a574, 0x21a578), (0x21a598, 0x21a59c),
                      (0x21a5bc, 0x21a5c0), (0x21a5e0, 0x21a5e4)):
        require_symbol(base, add, 0x21a4d0, 'g_pGlobal')
        for delta, mnemonic, operands in (
            (0, 'add', 'r0, pc, r0'), (4, 'ldr', 'r0, [r4, r0]'),
            (8, 'ldr', 'r0, [r0]'), (12, 'ldr', 'r1, [r0]'),
            (16, 'ldr', 'r2, [r1, #8]')):
            inst(add + delta, mnemonic, operands)
    for address, mnemonic, operands in (
        (0x21a58c,'mov','r1, #0'),(0x21a590,'blx','r2'),(0x21a594,'str','r0, [sp, #0xec]'),
        (0x21a5b0,'mov','r1, #1'),(0x21a5b4,'blx','r2'),(0x21a5b8,'str','r0, [sp, #0xe8]'),
        (0x21a5d4,'mov','r1, #2'),(0x21a5d8,'blx','r2'),(0x21a5dc,'str','r0, [sp, #0xe4]'),
        (0x21a5f8,'mov','r1, #3'),(0x21a5fc,'blx','r2'),(0x21a600,'str','r0, [sp, #0xe0]'),
        (0x21e3b0,'ldr','r4, [pc, #-0x408]'),
        (0x21e3b4,'add','r0, pc, r0'),(0x21e3c8,'ldr','r1, [r4, r0]'),(0x21e3d8,'ldr','r1, [r1, #4]'),
        (0x21e3dc,'add','r5, sp, #0x2000'),(0x21e3e4,'add','r2, r5, #0x5d0'),(0x21e3f4,'add','r5, sp, #0x2800'),
        (0x21e3e8,'ldr','r3, [sp, #0xec]'),(0x21e3ec,'str','r3, [r2, #0x318]'),
        (0x21e3f8,'str','r1, [sp]'),(0x21e3fc,'add','r0, r5, #0xe8'),(0x21e400,'str','r0, [sp, #4]'),
        (0x21e408,'mov','r3, #1'),
        (0x21e454,'add','r0, pc, r0'),(0x21e45c,'ldr','r0, [r4, r0]'),(0x21e478,'ldr','r0, [r0, #4]'),
        (0x21e474,'add','r5, sp, #0x2000'),(0x21e480,'add','r1, r5, #0x5d0'),(0x21e48c,'add','r5, sp, #0x2800'),
        (0x21e484,'ldr','r3, [sp, #0xe8]'),(0x21e488,'str','r3, [r1, #0x314]'),
        (0x21e490,'mov','r3, #1'),(0x21e494,'add','r1, r5, #0xe4'),(0x21e498,'stm','sp, {r0, r1}'),
        (0x21e4e8,'add','r0, pc, r0'),(0x21e4f0,'ldr','r0, [r4, r0]'),(0x21e50c,'ldr','r0, [r0, #4]'),
        (0x21e508,'add','r5, sp, #0x2000'),(0x21e514,'add','r1, r5, #0x5d0'),(0x21e520,'add','r5, sp, #0x2000'),
        (0x21e518,'ldr','r3, [sp, #0xe4]'),(0x21e51c,'str','r3, [r1, #0x310]'),
        (0x21e524,'mov','r3, #1'),(0x21e528,'add','r1, r5, #0x8e0'),(0x21e52c,'stm','sp, {r0, r1}'),
        (0x21e578,'add','r0, pc, r0'),(0x21e580,'ldr','r0, [r4, r0]'),(0x21e5a0,'ldr','r0, [r0, #4]'),
        (0x21e59c,'add','r4, sp, #0x2000'),(0x21e5a8,'add','r1, r4, #0x5d0'),(0x21e5b4,'add','r4, sp, #0x2800'),
        (0x21e5ac,'ldr','r3, [sp, #0xe0]'),(0x21e5b0,'str','r3, [r1, #0x30c]'),
        (0x21e5b8,'mov','r3, #1'),(0x21e5bc,'add','r1, r4, #0xdc'),(0x21e5c0,'stm','sp, {r0, r1}'),
    ):
        inst(address, mnemonic, operands)
    for base, add in ((0x21e3a0,0x21e3b4),(0x21e444,0x21e454),
                      (0x21e4d8,0x21e4e8),(0x21e56c,0x21e578)):
        require_symbol(base, add, 0x21e3b0, 'g_FUNC_ds_map_clear')
    for address in (0x21e410,0x21e4a4,0x21e538,0x21e5cc):
        call(address, 'YYGML_CallLegacyFunction')
    # The local conditional branches here skip RValue cleanup calls, not one
    # of the clear/read calls. This does not establish entry to the block.
    for branch, target, free_call in (
        (0x21e430,0x21e444,0x21e440),(0x21e4c4,0x21e4d8,0x21e4d4),
        (0x21e558,0x21e56c,0x21e568),(0x21e5ec,0x21e600,0x21e5fc),
        (0x21e73c,0x21e754,0x21e750),(0x21e78c,0x21e79c,0x21e798),
        (0x21e8d0,0x21e8e8,0x21e8e4),(0x21e920,0x21e930,0x21e92c),
        (0x21ea68,0x21ea80,0x21ea7c),(0x21eab8,0x21eac8,0x21eac4),
    ):
        inst(branch, 'bne', f'#0x{target:x}')
        call(free_call, 'FREE_RValue')

    # section, key, BSS default, three string calls, ini and map call,
    # vector sites and offsets: all dataflow pinned for the four maps.
    load_rows = [
        ((0x21e600,0x21e610,0x21e608),(0x21e648,0x21e650,0x21e64c),(0x21e668,0x21e670,0x21e66c),
         (0x21e644,0x21e664,0x21e684),(0x21e688,0x21e694,0x21e690),0x21e6d4,
         (0x21e6d8,0x21e6e8,0x21e6e0),0x21e718,0x21e6a4,0x21e6ac,0x21e6b0,0x21e6ec,
         'r2, [sp, #0xec]','r2, [r1, #0x2c4]','r0, [r3, #0x2c8]'),
        ((0x21e79c,0x21e7ac,0x21e7a4),(0x21e7dc,0x21e7e4,0x21e7e0),(0x21e7fc,0x21e804,0x21e800),
         (0x21e7d8,0x21e7f8,0x21e818),(0x21e81c,0x21e828,0x21e824),0x21e868,
         (0x21e86c,0x21e87c,0x21e874),0x21e8ac,0x21e838,0x21e840,0x21e844,0x21e880,
         'r2, [sp, #0xe8]','r2, [r1, #0x27c]','r0, [r3, #0x280]'),
        ((0x21e930,0x21e940,0x21e938),(0x21e974,0x21e97c,0x21e978),(0x21e994,0x21e99c,0x21e998),
         (0x21e970,0x21e990,0x21e9b0),(0x21e9b4,0x21e9c0,0x21e9bc),0x21ea00,
         (0x21ea04,0x21ea14,0x21ea0c),0x21ea44,0x21e9d0,0x21e9d8,0x21e9dc,0x21ea18,
         'r2, [sp, #0xe4]','r2, [r1, #0x234]','r0, [r3, #0x238]'),
        ((0x21eac8,0x21ead8,0x21ead0),(0x21eb0c,0x21eb14,0x21eb10),(0x21eb2c,0x21eb34,0x21eb30),
         (0x21eb08,0x21eb28,0x21eb48),(0x21eb4c,0x21eb58,0x21eb54),0x21eb98,
         (0x21eb9c,0x21ebac,0x21eba4),0x21ebdc,0x21eb68,0x21eb70,0x21eb74,0x21ebb0,
         'r2, [sp, #0xe0]','r2, [r1, #0x1ec]','r0, [r3, #0x1f0]'),
    ]
    # Verify each vector base and call ABI: r4/r5/r6 are section/key/default;
    # the map_read vector starts one pointer before the ini argument vector,
    # with the saved map handle followed by the returned ini value.
    for address, mnemonic, operands in (
        (0x21e638,'add','r5, sp, #0x2800'),(0x21e63c,'add','r4, r5, #0xc8'),(0x21e618,'ldr','r1, [r1, r0]'),
        (0x21e654,'add','r6, sp, #0x2800'),(0x21e658,'add','r5, r6, #0xb8'),(0x21e65c,'ldr','r1, [r1, r0]'),
        (0x21e674,'add','r7, sp, #0x2800'),(0x21e678,'add','r6, r7, #0xa8'),(0x21e67c,'ldr','r1, [r1, r0]'),
        (0x21e7d0,'add','r4, sp, #0x2880'),(0x21e7b4,'ldr','r1, [r0, r1]'),
        (0x21e7e8,'add','r6, sp, #0x2000'),(0x21e7ec,'add','r5, r6, #0x870'),(0x21e7f0,'ldr','r1, [r1, r0]'),
        (0x21e808,'add','r7, sp, #0x2000'),(0x21e80c,'add','r6, r7, #0x860'),(0x21e810,'ldr','r1, [r1, r0]'),
        (0x21e964,'add','r5, sp, #0x2800'),(0x21e968,'add','r4, r5, #0x38'),(0x21e948,'ldr','r1, [r0, r1]'),
        (0x21e980,'add','r6, sp, #0x2800'),(0x21e984,'add','r5, r6, #0x28'),(0x21e988,'ldr','r1, [r1, r0]'),
        (0x21e9a0,'add','r7, sp, #0x2800'),(0x21e9a4,'add','r6, r7, #0x18'),(0x21e9a8,'ldr','r1, [r1, r0]'),
        (0x21eafc,'add','r5, sp, #0x2000'),(0x21eb00,'add','r4, r5, #0x7f0'),(0x21eae0,'ldr','r1, [r0, r1]'),
        (0x21eb18,'add','r6, sp, #0x2000'),(0x21eb1c,'add','r5, r6, #0x7e0'),(0x21eb20,'ldr','r1, [r1, r0]'),
        (0x21eb38,'add','r7, sp, #0x2000'),(0x21eb3c,'add','r6, r7, #0x7d0'),(0x21eb40,'ldr','r1, [r1, r0]'),
        (0x21e69c,'add','r1, r7, #0x5d0'),(0x21e6a0,'add','r2, r1, #0x2cc'),
        (0x21e6b4,'add','r4, sp, #0x2800'),(0x21e6b8,'mov','r3, #3'),(0x21e6bc,'add','r1, r4, #0x9c'),(0x21e6c4,'stm','sp, {r0, r1}'),
        (0x21e6dc,'add','r4, sp, #0x2000'),(0x21e6e4,'add','r3, r4, #0x5d0'),
        (0x21e6f0,'ldr','r2, [r2, r1]'),(0x21e6f4,'ldr','r0, [r2, #4]'),(0x21e700,'add','r4, sp, #0x2800'),
        (0x21e704,'mov','r3, #2'),(0x21e708,'add','r1, r4, #0x94'),(0x21e70c,'stm','sp, {r0, r1}'),
        (0x21e830,'add','r1, r7, #0x5d0'),(0x21e834,'add','r2, r1, #0x284'),
        (0x21e848,'add','r4, sp, #0x2800'),(0x21e84c,'mov','r3, #3'),(0x21e850,'add','r1, r4, #0x54'),(0x21e858,'stm','sp, {r0, r1}'),
        (0x21e870,'add','r4, sp, #0x2000'),(0x21e878,'add','r3, r4, #0x5d0'),
        (0x21e884,'ldr','r2, [r2, r1]'),(0x21e888,'ldr','r0, [r2, #4]'),(0x21e894,'add','r4, sp, #0x2800'),
        (0x21e898,'mov','r3, #2'),(0x21e89c,'add','r1, r4, #0x4c'),(0x21e8a0,'stm','sp, {r0, r1}'),
        (0x21e9c8,'add','r1, r7, #0x5d0'),(0x21e9cc,'add','r2, r1, #0x23c'),
        (0x21e9e0,'add','r4, sp, #0x2800'),(0x21e9e4,'mov','r3, #3'),(0x21e9e8,'add','r1, r4, #0xc'),(0x21e9f0,'stm','sp, {r0, r1}'),
        (0x21ea08,'add','r4, sp, #0x2000'),(0x21ea10,'add','r3, r4, #0x5d0'),
        (0x21ea1c,'ldr','r2, [r2, r1]'),(0x21ea20,'ldr','r0, [r2, #4]'),(0x21ea2c,'add','r4, sp, #0x2800'),
        (0x21ea30,'mov','r3, #2'),(0x21ea34,'add','r1, r4, #4'),(0x21ea38,'stm','sp, {r0, r1}'),
        (0x21eb60,'add','r1, r7, #0x5d0'),(0x21eb64,'add','r2, r1, #0x1f4'),
        (0x21eb78,'add','r4, sp, #0x2400'),(0x21eb7c,'mov','r3, #3'),(0x21eb80,'add','r1, r4, #0x3c4'),(0x21eb88,'stm','sp, {r0, r1}'),
        (0x21eba0,'add','r4, sp, #0x2000'),(0x21eba8,'add','r3, r4, #0x5d0'),
        (0x21ebb4,'ldr','r2, [r2, r1]'),(0x21ebb8,'ldr','r0, [r2, #4]'),(0x21ebc4,'add','r4, sp, #0x2400'),
        (0x21ebc8,'mov','r3, #2'),(0x21ebcc,'add','r1, r4, #0x3bc'),(0x21ebd0,'stm','sp, {r0, r1}'),
    ):
        inst(address, mnemonic, operands)
    for index, (section, key_str, default, string_calls, ini_sym, ini_call, map_sym, map_call,
                vector, load, target_store, result_store, load_op, target_op, result_op) in enumerate(load_rows):
        key = result[index]['save_key']
        require_string(*section, 'inventory')
        require_string(*key_str, key)
        default_sym = relocation(*default)
        section_def = elf.get_section(default_sym['st_shndx'])
        if (not default_sym.name.startswith('g_pString') or default_sym['st_size'] != 1 or
                section_def is None or section_def['sh_type'] != 'SHT_NOBITS' or
                not section_def['sh_addr'] <= default_sym['st_value'] < section_def['sh_addr'] + section_def['sh_size']):
            raise ValueError('unexpected BSS-initialized default string')
        require_symbol(*ini_sym, 'g_FUNC_ini_read_string')
        require_symbol(*map_sym, 'g_FUNC_ds_map_read')
        inst(ini_sym[1], 'add', 'r0, pc, r0')
        inst(ini_sym[1] + 4, 'ldr', 'r0, [r1, r0]')
        inst(vector + 4, 'ldr', 'r0, [r0, #4]')
        inst(map_sym[1], 'add', 'r1, pc, r1')
        for addr, reg in zip(string_calls, ('r4','r5','r6')):
            inst(addr-4, 'mov', 'r0, ' + reg)
            call(addr, 'YYSetString')
        inst(vector, 'stm', 'r2, {r4, r5, r6}')
        inst(load, 'ldr', load_op)
        inst(target_store, 'str', target_op)
        inst(result_store, 'str', result_op)
        for addr in (ini_call, map_call):
            call(addr, 'YYGML_CallLegacyFunction')
        result[index].update({'clear_call': f'0x{(0x21e410,0x21e4a4,0x21e538,0x21e5cc)[index]:x}',
                              'ini_read_string_call': f'0x{ini_call:x}', 'map_read_call': f'0x{map_call:x}',
                              'default_literal_initial': 'zero-initialized BSS byte'})
    return {'apk_sha256': APK_SHA256, 'function': 'gml_Script_game_save_protect',
            'address': '0x1d97f8', 'load_function': 'gml_Script_game_load_protect',
            'load_address': '0x21a4a8', 'mapping': result,
            'limitations': 'Static normal-save/load and item_drop dataflow only. Key names corroborate use, not global registration, '
                           'runtime reachability, writable BSS contents, native save compatibility, other modes, or iOS.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('INVENTORY_SAVE_LOAD_EVIDENCE: four native item_drop global indices matched to normal save/load keys')
    print('INVENTORY_SAVE_LOAD_LIMIT: static only; no native execution or save-format equivalence')


if __name__ == '__main__':
    main()
