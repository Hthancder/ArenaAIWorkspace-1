#!/usr/bin/env python3
"""Trace four inventory global indices to normal-save keys in pinned ARM.

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
        (0x1daad0, 'add', 'r1, r6, #0x328'), (0x1daae8, 'mov', 'r3, #1'),
        (0x1daaec, 'add', 'r1, r4, #0x84'), (0x1dab14, 'add', 'r3, r4, #0x328'),
        (0x1dab30, 'mov', 'r3, #3'), (0x1dab34, 'add', 'r1, r4, #0x78'),
        (0x1dabd4, 'ldr', 'r1, [r0, r1]'), (0x1dabf4, 'add', 'r4, r5, #0x68'),
        (0x1dac14, 'ldr', 'r1, [r1, r0]'), (0x1dac10, 'add', 'r5, r6, #0x58'),
        (0x1dac38, 'add', 'r1, r6, #0x328'), (0x1dac50, 'mov', 'r3, #1'),
        (0x1dac54, 'add', 'r1, r4, #0x54'), (0x1dac7c, 'add', 'r3, r4, #0x328'),
        (0x1dac98, 'mov', 'r3, #3'), (0x1dac9c, 'add', 'r1, r4, #0x48'),
        (0x1dad3c, 'ldr', 'r1, [r0, r1]'), (0x1dad5c, 'add', 'r4, r5, #0x38'),
        (0x1dad7c, 'ldr', 'r1, [r1, r0]'), (0x1dad78, 'add', 'r5, r6, #0x28'),
        (0x1dada0, 'add', 'r1, r6, #0x328'), (0x1dadb8, 'mov', 'r3, #1'),
        (0x1dadbc, 'add', 'r1, r4, #0x24'), (0x1dade4, 'add', 'r3, r4, #0x328'),
        (0x1dae00, 'mov', 'r3, #3'), (0x1dae04, 'add', 'r1, r4, #0x18'),
        (0x1daea4, 'ldr', 'r1, [r0, r1]'), (0x1daec4, 'add', 'r4, r5, #8'),
        (0x1daee4, 'ldr', 'r1, [r1, r0]'), (0x1daee0, 'add', 'r5, r6, #0x3f8'),
        (0x1daf08, 'add', 'r1, r6, #0x328'), (0x1daf20, 'mov', 'r3, #1'),
        (0x1daf24, 'add', 'r1, r4, #0x3f4'), (0x1daf4c, 'add', 'r3, r4, #0x328'),
        (0x1daf68, 'mov', 'r3, #3'), (0x1daf6c, 'add', 'r1, r4, #0x3e8'),
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
    return {'apk_sha256': APK_SHA256, 'function': 'gml_Script_game_save_protect',
            'address': '0x1d97f8', 'mapping': result,
            'limitations': 'Static normal-save and item_drop dataflow only. Key names corroborate use, not global registration, '
                           'runtime reachability, native save compatibility, other modes, or iOS.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('INVENTORY_SAVE_EVIDENCE: four native item_drop global indices matched to inventory save keys')
    print('INVENTORY_SAVE_LIMIT: static only; no native execution or save-format equivalence')


if __name__ == '__main__':
    main()
