#!/usr/bin/env python3
"""Pin ARM evidence for the original APK's item_drop routine, without execution.

Reads only the SHA-pinned APK/library. This is targeted static analysis, NOT a
GML decompiler, game patch, dynamic trace, or proof of iOS equivalence.
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
    matches = [sym for sym in symbols.iter_symbols() if sym.name.startswith('_Z20gml_Script_item_drop')]
    if len(matches) != 1 or (matches[0]['st_value'], matches[0]['st_size']) != (0x1a31e0, 2100):
        raise ValueError('unexpected item_drop export')
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

    def relocation(base_load, add_address, offset_load, expected):
        address = (add_address + 8 + literal(base_load) + literal(offset_load)) & 0xffffffff
        symbol = got.get(address)
        if symbol is None or symbol.name != expected:
            raise ValueError(f'unexpected GOT relocation at 0x{address:x}')
        return symbol

    def call(address, expected):
        decoded = list(dis.disasm(read(address, 4), address))
        if len(decoded) != 1 or decoded[0].mnemonic != 'bl' or expected not in calls.get(int(decoded[0].op_str[1:], 16), ''):
            raise ValueError(f'unexpected helper call at 0x{address:x}')

    # Four g_pGlobal values are captured before the selector jump table. A
    # separate instance slot is assigned one of them; names are NOT inferred.
    for base, add in ((0x1a31ec, 0x1a3200), (0x1a325c, 0x1a3260),
                      (0x1a3280, 0x1a3284), (0x1a32a4, 0x1a32a8)):
        relocation(base, add, 0x1a31f4, 'g_pGlobal')
    for address, op, operand in (
        (0x1a31e4, 'sub', 'sp, sp, #0x9c'), (0x1a31f0, 'mov', 'fp, r2'),
        (0x1a3250, 'mov', 'r1, #0'), (0x1a3254, 'blx', 'r2'), (0x1a3258, 'mov', 'sl, r0'),
        (0x1a3274, 'mov', 'r1, #1'), (0x1a3278, 'blx', 'r2'), (0x1a327c, 'mov', 'r8, r0'),
        (0x1a3298, 'mov', 'r1, #2'), (0x1a329c, 'blx', 'r2'), (0x1a32a0, 'mov', 'r5, r0'),
        (0x1a32bc, 'mov', 'r1, #3'), (0x1a32c0, 'blx', 'r2'), (0x1a32c4, 'mov', 'r4, r0'),
        (0x1a32cc, 'ldr', 'r7, [sp, #0xc0]'),
        (0x1a32f0, 'ldr', 'r1, [r7]'), (0x1a32f4, 'add', 'r0, sp, #0x80'),
        (0x1a3304, 'ldr', 'r1, [r7, #4]'), (0x1a3308, 'add', 'r0, sp, #0x70'),
        (0x1a3318, 'add', 'r0, sp, #0x80'), (0x1a3324, 'vcvt.s32.f64', 's0, d0'),
        (0x1a332c, 'sub', 'r0, r0, #1'), (0x1a3330, 'cmp', 'r0, #3'),
        (0x1a3334, 'bhi', '#0x1a3408'), (0x1a3338, 'add', 'r1, pc, #8'),
        (0x1a333c, 'lsl', 'r0, r0, #2'), (0x1a3340, 'ldr', 'r0, [r0, r1]'),
        (0x1a3344, 'add', 'pc, r0, r1'),
        (0x1a3368, 'mov', 'r0, r6'), (0x1a336c, 'mov', 'r1, #7'), (0x1a3370, 'blx', 'r2'), (0x1a3374, 'mov', 'r1, sl'),
        (0x1a3394, 'mov', 'r0, r6'), (0x1a3398, 'mov', 'r1, #7'), (0x1a339c, 'blx', 'r2'), (0x1a33a0, 'mov', 'r1, r8'),
        (0x1a33c0, 'mov', 'r0, r6'), (0x1a33c4, 'mov', 'r1, #7'), (0x1a33c8, 'blx', 'r2'), (0x1a33cc, 'mov', 'r1, r5'),
        (0x1a33ec, 'mov', 'r0, r6'), (0x1a33f0, 'mov', 'r1, #7'), (0x1a33f4, 'blx', 'r2'), (0x1a33f8, 'mov', 'r1, r4'),
        # First read of target slot and argument1; pass result to is_undefined.
        (0x1a3418, 'mov', 'r0, r6'), (0x1a341c, 'mov', 'r1, #7'), (0x1a3420, 'blx', 'r2'),
        (0x1a342c, 'add', 'r1, pc, r1'), (0x1a3430, 'str', 'r0, [sp, #0x48]'),
        (0x1a3434, 'add', 'r0, sp, #0x70'), (0x1a3438, 'str', 'r0, [sp, #0x4c]'),
        (0x1a343c, 'ldr', 'r1, [r8, r1]'), (0x1a3440, 'ldr', 'r0, [r1, #4]'),
        (0x1a3444, 'add', 'r1, sp, #0x48'), (0x1a3448, 'add', 'r2, sp, #0x60'),
        (0x1a344c, 'stm', 'sp, {r0, r1}'), (0x1a3458, 'mov', 'r3, #2'),
        (0x1a3468, 'add', 'r1, pc, r1'), (0x1a3470, 'str', 'r0, [sp, #0x44]'),
        (0x1a3474, 'ldr', 'r2, [r2, r1]'), (0x1a3478, 'ldr', 'r0, [r2, #4]'),
        (0x1a3480, 'add', 'r1, sp, #0x44'), (0x1a3484, 'mov', 'r3, #1'),
        (0x1a3488, 'stm', 'sp, {r0, r1}'), (0x1a349c, 'vmov.f64', 'd1, #5.000000e-01'),
        (0x1a34a4, 'vcmpe.f64', 'd0, d1'), (0x1a34a8, 'vmrs', 'apsr_nzcv, fpscr'),
        (0x1a34ac, 'ble', '#0x1a3564'),
        # Missing path writes numeric zero to the caller's return value.
        (0x1a3550, 'mov', 'r0, #0'), (0x1a3554, 'str', 'r0, [fp, #0xc]'),
        (0x1a3558, 'str', 'r0, [fp, #4]'), (0x1a355c, 'str', 'r0, [fp]'),
        (0x1a3560, 'b', '#0x1a3808'),
        # Re-read, subtract integer 1, and pass target/key/value to map-set.
        (0x1a3578, 'mov', 'r1, #7'), (0x1a357c, 'blx', 'r2'), (0x1a3580, 'mov', 'r7, r0'),
        (0x1a3588, 'add', 'r1, sp, #0x70'), (0x1a358c, 'str', 'r7, [sp, #0x3c]'),
        (0x1a3590, 'add', 'r0, pc, r0'), (0x1a3594, 'str', 'r1, [sp, #0x40]'),
        (0x1a3598, 'ldr', 'r0, [r8, r0]'), (0x1a35b4, 'mov', 'r3, #2'),
        (0x1a35bc, 'mov', 'r1, r0'), (0x1a35c0, 'add', 'r4, sp, #0x28'),
        (0x1a35c4, 'mov', 'r2, #1'), (0x1a35c8, 'mov', 'r0, r4'),
        (0x1a35dc, 'add', 'r2, sp, #0x70'), (0x1a35e0, 'add', 'r0, pc, r0'),
        (0x1a35e4, 'str', 'r7, [sp, #0x1c]'), (0x1a35e8, 'str', 'r2, [sp, #0x20]'),
        (0x1a35ec, 'ldr', 'r1, [r1, r0]'), (0x1a35f0, 'str', 'r4, [sp, #0x24]'),
        (0x1a35fc, 'add', 'r0, sp, #0x1c'), (0x1a3600, 'str', 'r1, [sp]'),
        (0x1a3604, 'str', 'r0, [sp, #4]'), (0x1a3610, 'mov', 'r3, #3'),
        # Read after set, compare against runtime epsilon, then optionally delete.
        (0x1a3698, 'add', 'r1, sp, #0x70'), (0x1a369c, 'add', 'r0, pc, r0'),
        (0x1a36a8, 'ldr', 'r0, [sl, r0]'), (0x1a36ac, 'str', 'r7, [sp, #0x14]'),
        (0x1a36b8, 'str', 'r1, [sp, #0x18]'), (0x1a36c8, 'mov', 'r0, r6'),
        (0x1a36cc, 'mov', 'r3, #2'), (0x1a36e8, 'add', 'r0, pc, r0'),
        (0x1a36ec, 'ldr', 'r0, [r1, r0]'), (0x1a36f0, 'vldr', 'd1, [r0]'),
        (0x1a36f4, 'vcmpe.f64', 'd0, d1'), (0x1a36f8, 'vmrs', 'apsr_nzcv, fpscr'),
        (0x1a36fc, 'bhi', '#0x1a37b8'),
        (0x1a3740, 'mov', 'r0, r6'), (0x1a3744, 'mov', 'r1, #7'), (0x1a3748, 'blx', 'r2'),
        (0x1a3754, 'add', 'r1, pc, r1'), (0x1a3758, 'str', 'r0, [sp, #0xc]'),
        (0x1a375c, 'add', 'r0, sp, #0x70'), (0x1a3760, 'str', 'r0, [sp, #0x10]'),
        (0x1a3764, 'ldr', 'r1, [r2, r1]'), (0x1a377c, 'mov', 'r3, #2'),
        (0x1a37dc, 'movw', 'r1, #0'), (0x1a37e0, 'mov', 'r0, #0'),
        (0x1a37e4, 'movt', 'r1, #0x3ff0'), (0x1a37e8, 'str', 'r0, [fp, #0xc]'),
        (0x1a37ec, 'stm', 'fp, {r0, r1}'),
    ):
        inst(address, op, operand)
    for address in (0x1a32f8, 0x1a330c, 0x1a3378, 0x1a33a4, 0x1a33d0, 0x1a33fc):
        call(address, 'YYRValueaSERKS_')
    for address in (0x1a331c, 0x1a3498, 0x1a36d8):
        call(address, 'REAL_RValue')
    call(0x1a35cc, '_ZmiRK8YYRValuei')
    for address in (0x1a345c, 0x1a3494, 0x1a35b8, 0x1a3618, 0x1a36d4, 0x1a3784):
        call(address, 'YYGML_CallLegacyFunction')
    for base, add, offset, name in (
        (0x1a3424, 0x1a342c, 0x1a3428, 'g_FUNC_ds_map_find_value'),
        (0x1a3460, 0x1a3468, 0x1a3464, 'g_FUNC_is_undefined'),
        (0x1a3584, 0x1a3590, 0x1a3428, 'g_FUNC_ds_map_find_value'),
        (0x1a35d0, 0x1a35e0, 0x1a35d8, 'g_FUNC_ds_map_set'),
        (0x1a368c, 0x1a369c, 0x1a3428, 'g_FUNC_ds_map_find_value'),
        (0x1a374c, 0x1a3754, 0x1a3750, 'g_FUNC_ds_map_delete'),
    ):
        relocation(base, add, offset, name)
    epsilon = relocation(0x1a36e0, 0x1a36e8, 0x1a36e4, 'g_GMLMathEpsilon')
    if epsilon['st_size'] != 8 or struct.unpack('<d', read(epsilon['st_value'], 8))[0] != 1e-10:
        raise ValueError('unexpected epsilon initializer')
    base = 0x1a3348
    targets = [(base + value) & 0xffffffff for value in struct.unpack('<IIII', read(base, 16))]
    if targets != [0x1a3358, 0x1a3384, 0x1a33b0, 0x1a33dc]:
        raise ValueError('unexpected selector jump table')
    return {
        'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
        'function': 'gml_Script_item_drop', 'address': '0x1a31e0', 'size': 2100,
        'selector_argument': 0, 'key_argument': 1,
        'selector_cases': [{'selector': i + 1, 'global_index': i, 'instance_slot': 7,
                            'target': f'0x{target:x}'} for i, target in enumerate(targets)],
        'missing_path': {'read_call': '0x1a345c', 'undefined_call': '0x1a3494',
                         'return_value': 0, 'nonmissing_branch': '0x1a3564'},
        'present_path': {'read_call': '0x1a35b8', 'subtract_integer': 1,
                         'set_symbol': 'g_FUNC_ds_map_set', 'set_call': '0x1a3618',
                         'reread_call': '0x1a36d4', 'delete_call': '0x1a3784', 'return_value': 1},
        'delete_comparison': {'rhs_symbol': 'g_GMLMathEpsilon', 'initial_value': 1e-10,
                              'branch_above_or_unordered_to_skip': '0x1a37b8'},
        'limitations': 'Static instruction/dataflow evidence only; no native execution, global-name or instance-slot registration, '
                       'invalid selector behavior, native DS-map internals, all numeric types, iOS or gameplay equivalence.'
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('ITEM_DROP_EVIDENCE: selector, map reads, undefined check, decrement, set, conditional delete, returns')
    print('ITEM_DROP_LIMIT: targeted static analysis only; not Android/iOS execution')


if __name__ == '__main__':
    main()
