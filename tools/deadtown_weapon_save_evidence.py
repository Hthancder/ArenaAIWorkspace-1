#!/usr/bin/env python3
"""Pin native normal-save/load weapon and weaponlevel dataflow.

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
    for name, address, size in (('_Z28gml_Script_game_save_protectP', 0x1d97f8, 265392),
                                ('_Z28gml_Script_game_load_protectP', 0x21a4a8, 208304),
                                ('_Z30gml_Object_sys_global_Create_0P', 0x3b7330, 517488)):
        matches = [s for s in syms.iter_symbols() if s.name.startswith(name)]
        if len(matches) != 1 or (matches[0]['st_value'], matches[0]['st_size']) != (address, size):
            raise ValueError('unexpected native export: ' + name)
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

    def string(base, add, offset, expected):
        address = (add + 8 + lit(base) + lit(offset)) & 0xffffffff
        symbol = got.get(address)
        if (symbol is None or not symbol.name.startswith('g_pString') or
                symbol['st_size'] != len(expected) + 1 or
                read(symbol['st_value'], symbol['st_size']) != expected.encode() + b'\0'):
            raise ValueError(f'unexpected INI key literal at 0x{address:x}')

    # Native saved global getter pointers; separate load getters are used for
    # assignment. Names are corroborated by INI keys, not registration.
    for base,add,offset in ((0x1d9960,0x1d9964,0x1d9820), (0x1d9984,0x1d9988,0x1d9820),
                            (0x21a604,0x21a608,0x21a4d0), (0x21a628,0x21a62c,0x21a4d0),
                            (0x21a64c,0x21a650,0x21a4d0), (0x3b75ec,0x3b75f0,0x3b7350)):
        reloc(base,add,offset,'g_pGlobal')
    for base,add,section,key,expected in (
        (0x1db034,0x1db040,0x1db038,0x1db03c,'weapon'),
        (0x1db070,0x1db07c,0x1db074,0x1db078,'weaponlevel'),
        (0x21ec74,0x21ec88,0x21ec80,0x21ec7c,'weapon'),
        (0x21ecf4,0x21ed08,0x21ed04,0x21ecfc,'weaponlevel'),
    ):
        string(base,add,section,'equip')
        string(base,add,key,expected)
    epsilon = reloc(0x21ed78,0x21ed88,0x21ed8c,'g_GMLMathEpsilon')
    if epsilon['st_size'] != 8 or struct.unpack('<d', read(epsilon['st_value'],8))[0] != 1e-10:
        raise ValueError('unexpected epsilon initializer')
    default_addr = pc_literal(0x21e320,'vldr')
    if struct.unpack('<d',read(default_addr,8))[0] != 0.0:
        raise ValueError('unexpected zero default literal')
    for address, op, operands in (
        # Global 5/6, save: getter pointers and ini_write_real inputs.
        (0x1d9964,'add','r0, pc, r0'),(0x1d9968,'ldr','r0, [r4, r0]'),(0x1d996c,'ldr','r0, [r0]'),
        (0x1d9970,'ldr','r1, [r0]'),(0x1d9974,'ldr','r2, [r1, #8]'),(0x1d9978,'mov','r1, #5'),
        (0x1d997c,'blx','r2'),(0x1d9980,'str','r0, [sp, #0x194]'),
        (0x1d9988,'add','r0, pc, r0'),(0x1d998c,'ldr','r0, [r4, r0]'),(0x1d9990,'ldr','r0, [r0]'),
        (0x1d9994,'ldr','r1, [r0]'),(0x1d9998,'ldr','r2, [r1, #8]'),(0x1d999c,'mov','r1, #6'),
        (0x1d99a0,'blx','r2'),(0x1d99a4,'str','r0, [sp, #0x190]'),
        (0x1db028,'ldr','r0, [sp, #0x194]'),(0x1db030,'vmov','d0, r0, r1'),
        (0x1db040,'add','r6, pc, r0'),(0x1db044,'vmov','r2, r3, d0'),
        (0x1db048,'ldr','r0, [r1, r6]'),(0x1db04c,'ldr','r1, [r7, r6]'),
        (0x1db064,'ldr','r0, [sp, #0x190]'),(0x1db06c,'vmov','d0, r0, r1'),
        (0x1db07c,'add','r6, pc, r0'),(0x1db080,'vmov','r2, r3, d0'),
        (0x1db084,'ldr','r0, [r1, r6]'),(0x1db088,'ldr','r1, [r7, r6]'),
        # Load global 5/6 and cap global 24 getter pointers.
        (0x21a608,'add','r0, pc, r0'),(0x21a60c,'ldr','r0, [r4, r0]'),(0x21a610,'ldr','r0, [r0]'),
        (0x21a614,'ldr','r1, [r0]'),(0x21a618,'ldr','r2, [r1, #8]'),(0x21a61c,'mov','r1, #5'),
        (0x21a620,'blx','r2'),(0x21a624,'str','r0, [sp, #0x14c]'),
        (0x21a62c,'add','r0, pc, r0'),(0x21a630,'ldr','r0, [r4, r0]'),(0x21a634,'ldr','r0, [r0]'),
        (0x21a638,'ldr','r1, [r0]'),(0x21a63c,'ldr','r2, [r1, #8]'),(0x21a640,'mov','r1, #6'),
        (0x21a644,'blx','r2'),(0x21a648,'str','r0, [sp, #0x138]'),
        (0x21a650,'add','r0, pc, r0'),(0x21a654,'ldr','r0, [r4, r0]'),(0x21a658,'ldr','r0, [r0]'),
        (0x21a65c,'ldr','r1, [r0]'),(0x21a660,'ldr','r2, [r1, #8]'),(0x21a664,'mov','r1, #0x18'),
        (0x21a668,'blx','r2'),(0x21a66c,'str','r0, [sp, #0x140]'),
        # Defaults stored as doubles -1 and 0 for later ini_read_real calls.
        (0x21c3a8,'vmov.f64','d0, #-1.000000e+00'),(0x21c3c8,'vmov','r2, r3, d0'),
        (0x21c3dc,'str','r2, [sp, #0x130]'),(0x21c3e0,'str','r3, [sp, #0x134]'),
        (0x21e330,'vmov','r2, r5, d0'),(0x21e368,'str','r2, [sp, #0x104]'),
        (0x21e36c,'str','r5, [sp, #0x108]'),
        # Read weapon with -1 default; write returned double to global 5.
        (0x21ec88,'add','r3, pc, r0'),(0x21ec90,'ldr','r0, [r2, r3]'),(0x21ec98,'ldr','r1, [r1, r3]'),
        (0x21ecb0,'ldr','r2, [sp, #0x130]'),(0x21ecb4,'ldr','r3, [sp, #0x134]'),
        (0x21ecbc,'mov','r4, r0'),(0x21ecc0,'mov','r5, r1'),(0x21ecec,'ldr','r7, [sp, #0x14c]'),
        (0x21ecf0,'vmov','d0, r4, r5'),(0x21ed0c,'str','r3, [r7, #0xc]'),
        (0x21ed10,'vstr','d0, [r8, #0xd8]'),(0x21ed14,'ldrd','r4, r5, [r8, #0xd8]'),
        (0x21ed20,'stm','r7, {r4, r5}'),
        # Read weaponlevel with 0 default; write returned double to global 6.
        (0x21ed08,'add','r2, pc, r2'),(0x21ed18,'ldr','r0, [r0, r2]'),(0x21ed1c,'ldr','r1, [r1, r2]'),
        (0x21ed34,'ldr','r2, [sp, #0x104]'),(0x21ed38,'ldr','r3, [sp, #0x108]'),
        (0x21ed40,'mov','r4, r0'),(0x21ed44,'mov','r5, r1'),(0x21ed70,'ldr','r7, [sp, #0x138]'),
        (0x21ed74,'mov','r1, #0'),(0x21ed7c,'vmov','d0, r4, r5'),(0x21ed84,'str','r1, [r7, #0xc]'),
        (0x21ed90,'vstr','d0, [r6, #0xd0]'),(0x21ed94,'ldrd','r2, r3, [r6, #0xd0]'),(0x21eda0,'stm','r7, {r2, r3}'),
        # Compare cap against level with runtime epsilon; copy cap to level
        # only if YYCompareVal returns a negative result.
        (0x21ed88,'add','r0, pc, r0'),(0x21ed98,'ldr','r0, [r1, r0]'),(0x21eda8,'vldr','d0, [r0]'),
        (0x21edb0,'vmov','r2, r3, d0'),(0x21edb4,'ldr','r0, [sp, #0x140]'),
        (0x21edb8,'mov','r1, r7'),(0x21edbc,'mov','sl, r7'),(0x21edc4,'cmp','r0, #0'),
        (0x21edc8,'bge','#0x21ede8'),(0x21eddc,'ldr','r1, [sp, #0x140]'),(0x21ede0,'mov','r0, sl'),
        # Static sys_global Create assignment of global 24 to real 20.0.
        (0x3b75f0,'add','r0, pc, r0'),(0x3b75f4,'ldr','r0, [r5, r0]'),(0x3b75f8,'ldr','r0, [r0]'),
        (0x3b75fc,'ldr','r1, [r0]'),(0x3b7600,'ldr','r2, [r1, #8]'),(0x3b7604,'mov','r1, #0x18'),
        (0x3b7608,'blx','r2'),(0x3b760c,'str','r0, [sp, #0xc0]'),
        (0x3f4e10,'movw','r4, #0'),(0x3f4e14,'mov','fp, #0'),(0x3f4e18,'movt','r4, #0x4034'),
        (0x3f4e48,'bne','#0x3f4e54'),(0x3f4e4c,'ldr','r0, [sp, #0xc0]'),
        (0x3f4e54,'ldr','r0, [sp, #0xc0]'),(0x3f4e64,'str','fp, [r0, #0xc]'),
        (0x3f4e68,'str','r4, [r0, #4]'),(0x3f4e6c,'str','fp, [r0]'),
    ):
        inst(address,op,operands)
    for address in (0x1db02c,0x1db068):
        call(address,'REAL_RValue')
    for address in (0x1db050,0x1db08c):
        call(address,'YYGML_ini_write_real')
    for address in (0x21ecb8,0x21ed3c):
        call(address,'YYGML_ini_read_real')
    call(0x21edc0,'YYCompareVal')
    call(0x21ede4,'YYRValueaSERKS_')
    call(0x3f4e50,'FREE_RValue')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'save_function':'gml_Script_game_save_protect','load_function':'gml_Script_game_load_protect',
            'keys':[{'global_index':5,'section':'equip','key':'weapon','save_call':'0x1db050',
                     'load_call':'0x21ecb8','default':-1.0},
                    {'global_index':6,'section':'equip','key':'weaponlevel','save_call':'0x1db08c',
                     'load_call':'0x21ed3c','default':0.0}],
            'level_cap':{'global_index':24,'static_create_value':20.0,'assignment':'0x3f4e54',
                         'compare_call':'0x21edc0','conditional_copy':'0x21ede4',
                         'comparison_rhs':'g_GMLMathEpsilon'},
            'limitations':'Static normal save/load path only; no native or iOS execution, global registration, '
                          'complete CFG or original save-format compatibility; defaults, cap and epsilon may change at runtime.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    report=inspect(args.apk)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('WEAPON_SAVE_EVIDENCE: equip weapon/weaponlevel save, load and cap pinned')
    print('WEAPON_SAVE_LIMIT: static only; no native execution or save compatibility')


if __name__ == '__main__':
    main()
