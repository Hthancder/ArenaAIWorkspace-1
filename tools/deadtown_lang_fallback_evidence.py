#!/usr/bin/env python3
"""Pin static ARM evidence for missing-key language fallback in the original APK.

This checks one specific function and GOT/PLT layout, not Android execution or a
complete translation decompilation. It does not patch game data or create an IPA.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile

    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        raw = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    segments = list(elf.iter_segments())
    symbols = elf.get_section_by_name('.dynsym')
    candidates = [s for s in symbols.iter_symbols() if s.name.startswith('_Z19gml_Script_lang_get')]
    if len(candidates) != 1 or (candidates[0]['st_value'], candidates[0]['st_size']) != (0x2df86c, 1416):
        raise ValueError('unexpected lang_get export')
    rel = elf.get_section_by_name('.rel.dyn')
    relsyms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: relsyms.get_symbol(r['r_info_sym']).name for r in rel.iter_relocations()
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
        op = list(dis.disasm(read(address, 4), address))[0]
        if op.mnemonic != 'ldr' or len(op.operands) != 2 or op.operands[1].type != ARM_OP_MEM or op.reg_name(op.operands[1].mem.base) != 'pc':
            raise ValueError(f'expected PC-relative literal at 0x{address:x}')
        return struct.unpack('<I', read(address + 8 + op.operands[1].mem.disp, 4))[0]

    def relocation(base_load, add_address, offset_load, expected):
        address = (add_address + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        if got.get(address) != expected:
            raise ValueError(f'unexpected GOT relocation at 0x{address:x}')
        return {'got': f'0x{address:x}', 'symbol': expected}

    def call(address, expected):
        op = list(dis.disasm(read(address, 4), address))[0]
        if op.mnemonic != 'bl' or expected not in calls.get(int(op.op_str[1:], 16), ''):
            raise ValueError(f'unexpected call at 0x{address:x}')

    # Four global values are read through the same g_pGlobal object. These
    # indices are observed, but their registration/names are not inferred from
    # g_Vars here. Their roles follow their use in this particular function.
    relocation(0x2df878, 0x2df888, 0x2df87c, 'g_pGlobal')
    for address, operand in ((0x2df8c8, 'r1, #0x3e'), (0x2df8ec, 'r1, #0x3f'),
                             (0x2df910, 'r1, #0x40'), (0x2df934, 'r1, #0x41')):
        inst(address, 'mov', operand)
        inst(address + 4, 'blx', 'r2')
    for address, mnemonic, operand in (
        (0x2df8d0, 'mov', 'r4, r0'), (0x2df8f4, 'mov', 'r7, r0'),
        (0x2df918, 'mov', 'r5, r0'), (0x2df93c, 'mov', 'r6, r0'),
        (0x2df954, 'mov', 'r0, r4'), (0x2df960, 'vcvt.s32.f64', 's0, d0'),
        (0x2df964, 'vmov', 'r0, s0'), (0x2df968, 'cmp', 'r0, #3'),
        (0x2df96c, 'bhi', '#0x2dfcfc'), (0x2df970, 'add', 'r1, pc, #0xc'),
        (0x2df978, 'ldr', 'r4, [sp, #0x78]'), (0x2df97c, 'ldr', 'r0, [r0, r1]'),
        (0x2df980, 'add', 'pc, r0, r1'), (0x2df99c, 'ldr', 'r1, [r4]'),
        (0x2df9a0, 'mov', 'r0, sl')):
        inst(address, mnemonic, operand)
    call(0x2df958, 'REAL_RValue')
    call(0x2df9a4, 'YYRValueaSERKS_')
    offsets = struct.unpack('<4I', read(0x2df984, 16))
    targets = [0x2df984 + x for x in offsets]
    if targets != [0x2df994, 0x2df9ac, 0x2dfab0, 0x2dfbb4]:
        raise ValueError('unexpected switch targets')

    cases = []
    for case, reg, exists_base, exists_add, exists_offset, find_base, find_add, find_offset, \
        exists_store, argument_load, argument_store, argc, exists_call, real_call, half, compare, branch, \
        find_store, find_arg, find_arg_store, find_argc, find_call, find_return, fallback in (
        (1, 'r7', 0x2df9ac, 0x2df9b8, 0x2df9b4, 0x2dfa44, 0x2dfa50, 0x2dfa4c,
         0x2df9c8, 0x2df9cc, 0x2df9d4, 0x2df9e0, 0x2df9f0, 0x2df9f4, 0x2df9f8, 0x2dfa00, 0x2dfa08,
         0x2dfa54, 0x2dfa78, 0x2dfa80, 0x2dfa98, 0x2dfa9c, 0x2dfaa8, 0x2dfcb8),
        (2, 'r5', 0x2dfab0, 0x2dfabc, 0x2dfab8, 0x2dfb48, 0x2dfb54, 0x2dfb50,
         0x2dfacc, 0x2dfad0, 0x2dfad8, 0x2dfae4, 0x2dfaf4, 0x2dfaf8, 0x2dfafc, 0x2dfb04, 0x2dfb0c,
         0x2dfb58, 0x2dfb7c, 0x2dfb84, 0x2dfb9c, 0x2dfba0, 0x2dfbac, 0x2dfcd0),
        (3, 'r6', 0x2dfbb4, 0x2dfbc0, 0x2dfbbc, 0x2dfc4c, 0x2dfc58, 0x2dfc54,
         0x2dfbd0, 0x2dfbd4, 0x2dfbdc, 0x2dfbe8, 0x2dfbf8, 0x2dfbfc, 0x2dfc00, 0x2dfc08, 0x2dfc10,
         0x2dfc5c, 0x2dfc80, 0x2dfc88, 0x2dfca0, 0x2dfca4, 0x2dfcb0, 0x2dfce8),
    ):
        inst(exists_add, 'add', 'r1, pc, r1')
        inst(find_add, 'add', 'r0, pc, r0')
        exists = relocation(exists_base, exists_add, exists_offset, 'g_FUNC_ds_map_exists')
        find = relocation(find_base, find_add, find_offset, 'g_FUNC_ds_map_find_value')
        # Pin argument setup as well as the dynamic call target/branch.
        slots = {1: ('#0x30', '#0x34', '#0x28', '#0x2c'),
                 2: ('#0x20', '#0x24', '#0x18', '#0x1c'),
                 3: ('#0x10', '#0x14', '#8', '#0xc')}[case]
        inst(exists_store, 'str', f'{reg}, [sp, {slots[0]}]')
        inst(argument_load, 'ldr', 'r2, [r4]')
        inst(argument_store, 'str', f'r2, [sp, {slots[1]}]')
        inst(argc, 'mov', 'r3, #2')
        call(exists_call, 'YYGML_CallLegacyFunction')
        call(real_call, 'REAL_RValue')
        inst(half, 'vmov.f64', 'd1, #5.000000e-01')
        inst(compare, 'vcmpe.f64', 'd0, d1')
        inst(branch - 4, 'vmrs', 'apsr_nzcv, fpscr')
        inst(branch, 'ble', f'#{hex(fallback)}')
        inst(find_store, 'str', f'{reg}, [sp, {slots[2]}]')
        inst(find_arg, 'ldr', 'r1, [r4]')
        inst(find_arg_store, 'str', f'r1, [sp, {slots[3]}]')
        inst(find_argc, 'mov', 'r3, #2')
        call(find_call, 'YYGML_CallLegacyFunction')
        inst(find_return - 8, 'mov', 'r1, r0')
        inst(find_return - 4, 'mov', 'r0, sl')
        call(find_return, 'YYRValueaSERKS_')
        inst(fallback + 8, 'ldr', 'r1, [r4]')
        inst(fallback + 12, 'mov', 'r0, sl')
        call(fallback + 16, 'YYRValueaSERKS_')
        cases.append({'selector': case, 'candidate_map_global_index': 62 + case,
                      'map_exists': exists, 'map_find_value': find,
                      'exists_call': f'0x{exists_call:x}', 'find_call': f'0x{find_call:x}',
                      'missing_branch_target': f'0x{fallback:x}', 'fallback_argument': 0})
    return {'apk_sha256': APK_SHA256, 'function': 'gml_Script_lang_get', 'address': '0x2df86c',
            'selector_global_index': 62, 'case_zero_returns_argument': 0, 'cases': cases,
            'limitations': 'Pinned ARM patterns and branch targets only; no native execution, no full CFG, '
                           'no proof of global-index registration, map contents, out-of-range behavior or UI equivalence.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.apk)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Pinned ARM shows 3 map-existence branches with fallback to argument 0; static evidence only.')


if __name__ == '__main__':
    main()
