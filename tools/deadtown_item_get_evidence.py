#!/usr/bin/env python3
"""Pin the special branches and ordinary item_get loop in the original ARM APK.

Not a decompiler, patch, Android/iOS execution, or global-variable name resolver.
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
    syms = elf.get_section_by_name('.dynsym')
    matches = [s for s in syms.iter_symbols() if s.name.startswith('_Z19gml_Script_item_getP')]
    if len(matches) != 1 or (matches[0]['st_value'], matches[0]['st_size']) != (0x19f528, 4952):
        raise ValueError('unexpected item_get export')
    rel = elf.get_section_by_name('.rel.dyn')
    rsyms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: rsyms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations()
           if r['r_info_type'] == 21}
    plt, relplt = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    psyms = elf.get_section(relplt['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: psyms.get_symbol(r['r_info_sym']).name
             for i, r in enumerate(relplt.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(address, size):
        for seg in segments:
            if (seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and
                    address + size <= seg['p_vaddr'] + seg['p_filesz']):
                offset = seg['p_offset'] + address - seg['p_vaddr']
                return raw[offset:offset + size]
        raise ValueError(f'address outside ELF file bytes: 0x{address:x}')

    def inst(address, mnemonic, operands):
        ins = list(dis.disasm(read(address, 4), address))
        if len(ins) != 1 or (ins[0].mnemonic, ins[0].op_str) != (mnemonic, operands):
            raise ValueError(f'unexpected instruction at 0x{address:x}')
        return ins[0]

    def pc_literal(address, mnemonic):
        ins = list(dis.disasm(read(address, 4), address))
        if (len(ins) != 1 or ins[0].mnemonic != mnemonic or len(ins[0].operands) != 2 or
                ins[0].operands[1].type != ARM_OP_MEM or
                ins[0].reg_name(ins[0].operands[1].mem.base) != 'pc'):
            raise ValueError(f'expected PC-relative literal at 0x{address:x}')
        return address + 8 + ins[0].operands[1].mem.disp

    def lit(address):
        return struct.unpack('<I', read(pc_literal(address, 'ldr'), 4))[0]

    def reloc(base, add, offset, expected):
        address = (add + 8 + lit(base) + lit(offset)) & 0xffffffff
        symbol = got.get(address)
        if symbol is None or symbol.name != expected:
            raise ValueError(f'unexpected GOT relocation at 0x{address:x}')
        return symbol

    def call(address, name):
        ins = list(dis.disasm(read(address, 4), address))
        if (len(ins) != 1 or ins[0].mnemonic != 'bl' or
                name not in calls.get(int(ins[0].op_str[1:], 16), '')):
            raise ValueError(f'unexpected call at 0x{address:x}')

    # Getter pointers 0..3 are selector inputs; 12..16 are targets of
    # the five special branches. No names are inferred from g_Vars.
    getters = [(0x19f534,0x19f544,0,0x19f5a0,'sl'),
               (0x19f5ac,0x19f5b4,1,0x19f5cc,'r8'),
               (0x19f5d8,0x19f5dc,2,0x19f5f0,'r4'),
               (0x19f5fc,0x19f600,3,0x19f614,'[sp, #0x28]'),
               (0x19f620,0x19f624,12,0x19f638,'[sp, #0x24]'),
               (0x19f644,0x19f648,13,0x19f65c,'[sp, #0x20]'),
               (0x19f668,0x19f66c,14,0x19f680,'[sp, #0x1c]'),
               (0x19f68c,0x19f690,15,0x19f6a4,'[sp, #0x18]'),
               (0x19f6b0,0x19f6b4,16,0x19f6c8,'[sp, #0x14]')]
    for base, add, index, at, destination in getters:
        reloc(base, add, 0x19f540, 'g_pGlobal')
        if index:
            inst(add, 'add', 'r0, pc, r0')
            inst(at - 16, 'ldr', 'r0, [r5, r0]')
            inst(at - 12, 'ldr', 'r0, [r0]')
        inst(at - 8, 'ldr', 'r1, [r0]')
        inst(at - 4, 'ldr', 'r2, [r1, #8]')
        inst(at, 'mov', f'r1, #0x{index:x}' if index >= 10 else f'r1, #{index}')
        inst(at + 4, 'blx', 'r2')
        if destination.startswith('['):
            inst(at + 8, 'str', f'r0, {destination}')
        else:
            inst(at + 8, 'mov', f'{destination}, r0')
    # Three arguments copied to RValues, followed by selector jump table.
    for address, op, operand in (
        (0x19f6d8,'ldr','r7, [sp, #0x150]'),
        (0x19f710,'ldr','r1, [r7]'),(0x19f714,'add','r0, sp, #0x110'),
        (0x19f724,'ldr','r1, [r7, #4]'),(0x19f728,'add','r5, sp, #0x100'),(0x19f72c,'mov','r0, r5'),
        (0x19f73c,'ldr','r1, [r7, #8]'),(0x19f740,'add','r0, sp, #0xf0'),
        (0x19f750,'add','r0, sp, #0x110'),(0x19f75c,'vcvt.s32.f64','s0, d0'),
        (0x19f764,'sub','r0, r0, #1'),(0x19f768,'cmp','r0, #3'),(0x19f76c,'bhi','#0x19f7f4'),
        (0x19f770,'add','r1, pc, #8'),(0x19f774,'lsl','r0, r0, #2'),
        (0x19f778,'ldr','r0, [r0, r1]'),(0x19f77c,'add','pc, r0, r1'),
        (0x19f798,'add','r0, sp, #0xe0'),(0x19f79c,'mov','r1, sl'),
        (0x19f7b0,'add','r0, sp, #0xe0'),(0x19f7b4,'mov','r1, r8'),
        (0x19f7c8,'add','r0, sp, #0xe0'),(0x19f7cc,'mov','r1, r4'),
        (0x19f7e4,'ldr','r1, [sp, #0x28]'),(0x19f7e8,'add','r0, sp, #0xe0'),
        (0x19fbc8,'add','r0, pc, r0'),(0x19fbd4,'ldr','r0, [r5, r0]'),
        (0x19fbe0,'vldr','d0, [r0]'),(0x19fbe8,'vmov','r2, r3, d0'),(0x19fbec,'ldr','r1, [sp, #0x28]'),
        (0x19fbf0,'add','r0, sp, #0xe0'),(0x19fbf8,'cmp','r0, #0'),
        (0x19fbfc,'bne','#0x19fd54'),
        (0x1a04d4,'ldr','r1, [sp, #0x2c]'),(0x1a04d8,'mov','r0, #0'),
        (0x1a04dc,'str','r0, [r1, #0xc]'),(0x1a04e0,'str','r0, [r1, #4]'),(0x1a04e4,'str','r0, [r1]'),
    ):
        inst(address, op, operand)
    for address in (0x19f718,0x19f730,0x19f744,0x19f7a0,0x19f7b8,0x19f7d0,0x19f7ec):
        call(address, 'YYRValueaSERKS_')
    call(0x19f754, 'REAL_RValue')
    call(0x19fb00, 'gml_Script_ui_message_type')
    call(0x19fbf4, 'YYCompareVal')
    table = [(0x19f780 + n) & 0xffffffff for n in struct.unpack('<IIII', read(0x19f780, 16))]
    if table != [0x19f790,0x19f7a8,0x19f7c0,0x19f7dc]:
        raise ValueError('unexpected selector jump table')
    epsilon = reloc(0x19fbb8,0x19fbc8,0x19fbc0,'g_GMLMathEpsilon')
    if epsilon['st_size'] != 8 or struct.unpack('<d', read(epsilon['st_value'], 8))[0] != 1e-10:
        raise ValueError('unexpected epsilon initializer')

    cases = []
    for number, start, target, slot in (
        (44,0x19fc08,0x1a036c,0x24),(45,0x19fc4c,0x1a03b0,0x20),
        (46,0x19fc90,0x1a03f4,0x1c),(47,0x19fcd4,0x1a0438,0x18),
        (48,0x19fd18,0x1a0494,0x14)):
        # REAL(argument1), plus the negative integer literal, absolute value,
        # and compare with mutable epsilon. Exact finite integers match.
        inst(start,'add','r0, sp, #0x100')
        call(start + 4,'REAL_RValue')
        inst(start + 8,'vmov','d0, r0, r1')
        lit_addr = pc_literal(start + 12, 'vldr')
        if struct.unpack('<d', read(lit_addr, 8))[0] != -float(number):
            raise ValueError('unexpected item index literal')
        reloc(start + 16, start + 24, 0x19fbc0, 'g_GMLMathEpsilon')
        for delta, op, operands in (
            (20,'vadd.f64','d0, d0, d1'),(24,'add','r0, pc, r0'),
            (28,'ldr','r0, [r5, r0]'),(32,'vcmpe.f64','d0, #0'),
            (36,'vmrs','apsr_nzcv, fpscr'),(40,'vldr','d1, [r0]'),
            (44,'vnegmi.f64','d0, d0'),(48,'vcmpe.f64','d0, d1'),
            (52,'vmrs','apsr_nzcv, fpscr'),(56,'bls',f'#0x{target:x}'),
            (target-start+8,'ldr',f'r0, [sp, #0x{slot:x}]'),
            (target-start+12,'add','r1, sp, #0xf0'),
        ):
            inst(start + delta,op,operands)
        call(target + 16, 'YYRValuepLERKS_')
        inst(target + 52, 'bne', '#0x1a04d4')
        if number != 48:
            inst(target + 64, 'b', '#0x1a04d4')
        cases.append({'item_index': number, 'global_index': number - 32,
                      'compare_branch': f'0x{start+56:x}', 'add_call': f'0x{target+16:x}',
                      'return_value': 0})
    # Trace the ordinary path after the special checks: target map and key
    # live at sp+0xe0 and sp+0x100; amount at sp+0xf0. Instance slots 2, 3,
    # and 4 hold size, found flag and loop index respectively. Their names are
    # deliberately not inferred from the dynamic variable-registration table.
    for base, add, offset, name in (
        (0x19fd74,0x19fd80,0x19fd7c,'g_FUNC_ds_map_size'),
        (0x19fe00,0x19fe10,0x19fe08,'g_FUNC_ds_map_find_first'),
        (0x19ff98,0x19ff9c,0x19ff70,'g_FUNC_ds_map_find_next'),
        (0x1a014c,0x1a015c,0x1a0154,'g_FUNC_ds_map_find_value'),
        (0x1a01b8,0x1a01c4,0x1a01c0,'g_FUNC_ds_map_set'),
        (0x1a02e0,0x1a02e8,0x1a02e4,'g_FUNC_ds_map_add'),
        (0x19ff68,0x19ff74,0x19fbc0,'g_GMLMathEpsilon'),
        (0x19ff84,0x19ff8c,0x19fbc0,'g_GMLMathEpsilon'),
        (0x1a02b4,0x1a02c0,0x1a02bc,'g_GMLMathEpsilon'),
    ):
        reloc(base, add, offset, name)
    for address, op, operand in (
        # size(target) copied into slot 2; find_first(target) into local key.
        (0x19fd5c,'ldr','r0, [r6]'),(0x19fd60,'ldr','r2, [r0, #8]'),
        (0x19fd64,'mov','r0, r6'),(0x19fd68,'mov','r1, #2'),(0x19fd6c,'blx','r2'),(0x19fd70,'mov','r4, r0'),
        (0x19fd78,'add','r2, sp, #0xe0'),(0x19fd80,'add','r0, pc, r0'),(0x19fd84,'str','r2, [sp, #0x88]'),
        (0x19fd8c,'ldr','r1, [r1, r0]'),(0x19fd94,'ldr','r1, [r1, #4]'),(0x19fd98,'str','r1, [sp]'),
        (0x19fd9c,'add','r0, sp, #0x88'),(0x19fda4,'mov','r3, #1'),(0x19fda8,'str','r0, [sp, #4]'),
        (0x19fdb4,'mov','r1, r0'),(0x19fdb8,'mov','r0, r4'),
        (0x19fe10,'add','r0, pc, r0'),(0x19fe18,'ldr','r0, [r1, r0]'),(0x19fe30,'ldr','r0, [r0, #4]'),
        (0x19fe38,'add','r1, sp, #0xe0'),(0x19fe3c,'str','r1, [sp, #0x84]'),
        (0x19fe40,'add','r1, sp, #0x84'),(0x19fe44,'mov','r3, #1'),(0x19fe48,'stm','sp, {r0, r1}'),
        (0x19fe58,'mov','r1, r0'),(0x19fe5c,'add','r0, sp, #0xd0'),(0x19fe60,'mov','r8, r0'),
        # Initial found=0 (slot 3), loop index=0 (slot 4).
        (0x19fed4,'ldr','r0, [r6]'),(0x19fed8,'ldr','r2, [r0, #8]'),(0x19fedc,'mov','r0, r6'),
        (0x19fee0,'mov','r1, #3'),(0x19fee4,'blx','r2'),(0x19fee8,'mov','r4, r0'),
        (0x19ff10,'mov','r0, #0'),(0x19ff14,'str','r4, [sp, #0x28]'),
        (0x19ff18,'str','r0, [r4, #0xc]'),(0x19ff1c,'str','r0, [r4, #4]'),(0x19ff20,'str','r0, [r4]'),
        (0x19ff2c,'ldr','r0, [r6]'),(0x19ff30,'ldr','r2, [r0, #8]'),(0x19ff34,'mov','r0, r6'),
        (0x19ff38,'mov','r1, #4'),(0x19ff3c,'blx','r2'),(0x19ff40,'mov','r4, r0'),
        (0x19ff6c,'mov','fp, #0'),(0x19ff78,'str','fp, [r4, #0xc]'),(0x19ff7c,'str','fp, [r4, #4]'),(0x19ff88,'str','fp, [r4]'),
        # The loop compares index vs size, then current key vs requested key.
        (0x19ff74,'add','r0, pc, r0'),(0x19ff80,'ldr','sb, [r5, r0]'),
        (0x19ff8c,'add','r0, pc, r0'),(0x19ff90,'ldr','sl, [r5, r0]'),
        (0x19ff9c,'add','r0, pc, r0'),(0x19ffa0,'ldr','r7, [r1, r0]'),
        (0x19ffa4,'ldr','r0, [r6]'),(0x19ffa8,'ldr','r2, [r0, #8]'),(0x19ffac,'mov','r0, r6'),
        (0x19ffb0,'mov','r1, #4'),(0x19ffb4,'blx','r2'),(0x19ffb8,'mov','r4, r0'),
        (0x19ffbc,'ldr','r0, [r6]'),(0x19ffc0,'ldr','r2, [r0, #8]'),(0x19ffc4,'mov','r0, r6'),
        (0x19ffc8,'mov','r1, #2'),(0x19ffcc,'blx','r2'),(0x19ffd0,'mov','r1, r0'),
        (0x19ffd4,'vldr','d0, [sb]'),(0x19ffd8,'vmov','r2, r3, d0'),(0x19ffdc,'mov','r0, r4'),
        (0x19ffe4,'cmp','r0, #0'),(0x19ffe8,'bge','#0x1a02a0'),
        (0x19ffec,'vldr','d0, [sl]'),(0x19fff8,'vmov','r2, r3, d0'),
        (0x19fffc,'add','r1, sp, #0x100'),(0x1a0000,'mov','r0, r8'),
        (0x1a0008,'cmp','r0, #0'),(0x1a000c,'beq','#0x1a0108'),
        # Nonmatch: find_next(target,current), update local key and increment slot 4.
        (0x1a0018,'add','r0, sp, #0xe0'),(0x1a001c,'str','r0, [sp, #0x68]'),
        (0x1a0020,'ldr','r0, [r7, #4]'),(0x1a0024,'str','r8, [sp, #0x6c]'),
        (0x1a0030,'str','r0, [sp]'),(0x1a0034,'add','r0, sp, #0x68'),
        (0x1a0038,'str','r0, [sp, #4]'),(0x1a0040,'mov','r3, #2'),
        (0x1a0048,'mov','r1, r0'),(0x1a004c,'mov','r0, r8'),
        (0x1a0090,'ldr','r0, [r6]'),(0x1a0094,'ldr','r2, [r0, #8]'),(0x1a0098,'mov','r0, r6'),
        (0x1a009c,'mov','r1, #4'),(0x1a00a0,'blx','r2'),(0x1a00a4,'mov','r1, r0'),
        (0x1a00a8,'mov','r0, r5'),(0x1a00ac,'mov','r2, #0'),
        (0x1a00cc,'bne','#0x19ffa4'),(0x1a00d8,'b','#0x19ffa4'),
        # Match: flag slot 3=1; find_value(target,current) + amount,
        # then set(target,current,sum).
        (0x1a0110,'ldr','r0, [r6]'),(0x1a0114,'ldr','r2, [r0, #8]'),(0x1a0118,'mov','r0, r6'),
        (0x1a011c,'mov','r1, #3'),(0x1a0120,'blx','r2'),(0x1a0124,'mov','r5, r0'),
        (0x1a0150,'movw','r3, #0'),(0x1a0158,'mov','r2, #0'),(0x1a0160,'movt','r3, #0x3ff0'),
        (0x1a0164,'str','r2, [r5, #0xc]'),(0x1a0170,'stm','r5, {r2, r3}'),
        (0x1a015c,'add','r1, pc, r1'),(0x1a0168,'ldr','r0, [r0, r1]'),(0x1a0174,'ldr','r0, [r0, #4]'),
        (0x1a017c,'add','r1, sp, #0xe0'),(0x1a0180,'str','r1, [sp, #0x60]'),
        (0x1a0184,'str','r8, [sp, #0x64]'),(0x1a0188,'add','r1, sp, #0x60'),
        (0x1a0190,'stm','sp, {r0, r1}'),(0x1a0198,'mov','r3, #2'),
        (0x1a01a4,'mov','r1, r0'),(0x1a01a8,'add','r4, sp, #0x50'),
        (0x1a01ac,'add','r2, sp, #0xf0'),(0x1a01b0,'mov','r0, r4'),
        (0x1a01bc,'add','r2, sp, #0xe0'),(0x1a01c4,'add','r0, pc, r0'),(0x1a01cc,'str','r2, [sp, #0x44]'),
        (0x1a01d0,'ldr','r1, [r1, r0]'),(0x1a01d4,'str','r8, [sp, #0x48]'),(0x1a01d8,'str','r4, [sp, #0x4c]'),
        (0x1a01dc,'ldr','r1, [r1, #4]'),(0x1a01e4,'str','r1, [sp]'),(0x1a01e8,'add','r0, sp, #0x44'),
        (0x1a01f4,'str','r0, [sp, #4]'),(0x1a01fc,'mov','r3, #3'),
        # After exit/found, near-zero flag causes add(target,requested,amount).
        (0x1a02a8,'ldr','r0, [sp, #0x28]'),(0x1a02b0,'vmov','d0, r0, r1'),
        (0x1a02b8,'vcmpe.f64','d0, #0'),(0x1a02c0,'add','r0, pc, r0'),(0x1a02c4,'ldr','r0, [r1, r0]'),
        (0x1a02c8,'vmrs','apsr_nzcv, fpscr'),(0x1a02cc,'vldr','d1, [r0]'),(0x1a02d0,'vnegmi.f64','d0, d0'),
        (0x1a02d4,'vcmpe.f64','d0, d1'),(0x1a02d8,'vmrs','apsr_nzcv, fpscr'),(0x1a02dc,'bhi','#0x1a04e8'),
        (0x1a02e8,'add','r0, pc, r0'),(0x1a02ec,'ldr','r0, [r1, r0]'),
        (0x1a02f8,'add','r1, sp, #0xe0'),(0x1a02fc,'str','r1, [sp, #0x38]'),
        (0x1a0300,'add','r1, sp, #0x100'),(0x1a0304,'ldr','r0, [r0, #4]'),
        (0x1a0308,'str','r1, [sp, #0x3c]'),(0x1a030c,'add','r1, sp, #0xf0'),(0x1a0310,'str','r1, [sp, #0x40]'),
        (0x1a0314,'add','r1, sp, #0x38'),(0x1a031c,'stm','sp, {r0, r1}'),(0x1a0324,'mov','r3, #3'),
    ):
        inst(address, op, operand)
    for address in (0x19fdb0,0x19fe54,0x1a0044,0x1a01a0,0x1a0204,0x1a032c):
        call(address, 'YYGML_CallLegacyFunction')
    for address in (0x19fdbc,0x19fe64,0x1a0050):
        call(address, 'YYRValueaSERKS_')
    for address in (0x19ffe0,0x1a0004):
        call(address, 'YYCompareVal')
    call(0x1a00b0, 'YYRValueppEi')
    call(0x1a01b4, '_ZplRK8YYRValueS1_')
    call(0x1a02ac, 'REAL_RValue')
    ordinary = {'size_call':'0x19fdb0', 'find_first_call':'0x19fe54',
                'find_next_call':'0x1a0044', 'find_value_call':'0x1a01a0',
                'set_call':'0x1a0204', 'add_call':'0x1a032c',
                'size_instance_slot':2, 'found_instance_slot':3, 'loop_instance_slot':4}
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'function': 'gml_Script_item_get', 'address': '0x19f528', 'size': 4952,
            'selector_argument': 0, 'item_index_argument': 1, 'amount_argument': 2,
            'selector_global_indices': [0,1,2,3], 'map_equality_global_index': 3,
            'message_call': '0x19fb00', 'epsilon_initial': 1e-10, 'special_cases': cases,
            'ordinary_map_path': ordinary,
            'limitations': 'Static instruction/dataflow only; mutable runtime epsilon, exact branch entry, '
                           'nonfinite values, global name registration, native DS map behavior and Android/iOS execution are unproven.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.apk)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('ITEM_GET_EVIDENCE: selector, five special cases and ordinary map loop pinned')
    print('ITEM_GET_LIMIT: static only; no native execution or global name registration')


if __name__ == '__main__':
    main()
