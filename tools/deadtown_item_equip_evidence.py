#!/usr/bin/env python3
"""Pin native item_equip key splitting and pet-related map-consumption guard.

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
    for name, address, size in (('_Z21gml_Script_item_equipP', 0x1a0d8c, 6668),
                                ('_Z25gml_Script_item_check_petP', 0x1ba9c4, 732),
                                ('_Z30gml_Object_sys_global_Create_0P', 0x3b7330, 517488)):
        matches = [s for s in syms.iter_symbols() if s.name.startswith(name)]
        if len(matches) != 1 or (matches[0]['st_value'], matches[0]['st_size']) != (address, size):
            raise ValueError('unexpected native script export: ' + name)
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

    # Global 18 supplies both arithmetic operands; 0/1 provide target maps;
    # global 19 supplies the array used for the field-4 check. Registration
    # names and runtime values are intentionally not guessed from g_Vars.
    for base, add in ((0x1a0d9c,0x1a0dac), (0x1a0e0c,0x1a0e10),
                      (0x1a0e30,0x1a0e34), (0x1a0e54,0x1a0e58),
                      (0x1a0e78,0x1a0e7c), (0x1a0e9c,0x1a0ea0)):
        reloc(base, add, 0x1a0da4, 'g_pGlobal')
    reloc(0x3b75a4,0x3b75a8,0x3b7350,'g_pGlobal')
    one = reloc(0x1a1720,0x1a1728,0x1a1724,'gs_constArg0_4')
    if one['st_size'] != 16 or read(one['st_value'],16) != struct.pack('<dII', 1.0, 0, 0):
        raise ValueError('unexpected item_get literal argument')
    for base, add, offset, name in (
        (0x1a1044,0x1a104c,0x1a1048,'g_FUNC_floor'),
        (0x1a1268,0x1a1270,0x1a1260,'g_GMLMathEpsilon'),
        (0x1a12e0,0x1a12e8,0x1a1260,'g_GMLMathEpsilon'),
        (0x1a13f4,0x1a13fc,0x1a1260,'g_GMLMathEpsilon'),
        (0x1a143c,0x1a1448,0x1a1444,'g_FUNC_ds_map_find_value'),
        (0x1a148c,0x1a149c,0x1a1494,'g_FUNC_ds_map_set'),
        (0x1a1518,0x1a1528,0x1a1444,'g_FUNC_ds_map_find_value'),
        (0x1a156c,0x1a1574,0x1a1260,'g_GMLMathEpsilon'),
        (0x1a15d8,0x1a15e0,0x1a15dc,'g_FUNC_ds_map_delete'),
        (0x1a1678,0x1a1680,0x1a1260,'g_GMLMathEpsilon'),
        (0x1a16b8,0x1a16bc,0x1a1260,'g_GMLMathEpsilon'),
        (0x1bab18,0x1bab1c,0x1bab10,'g_GMLMathEpsilon'),
        (0x1bab48,0x1bab4c,0x1bab10,'g_GMLMathEpsilon'),
    ):
        symbol = reloc(base,add,offset,name)
        if name == 'g_GMLMathEpsilon' and (symbol['st_size'] != 8 or
                struct.unpack('<d', read(symbol['st_value'], 8))[0] != 1e-10):
            raise ValueError('unexpected epsilon initializer')
    for address, op, operands in (
        # Argument vector copies and the four global getters.
        (0x1a0df8,'ldr','r1, [r0]'),(0x1a0dfc,'ldr','r2, [r1, #8]'),
        (0x1a0e00,'mov','r1, #0x12'),(0x1a0e04,'blx','r2'),(0x1a0e08,'str','r0, [sp, #0x30]'),
        (0x1a0e10,'add','r0, pc, r0'),(0x1a0e14,'ldr','r0, [r4, r0]'),(0x1a0e18,'ldr','r0, [r0]'),
        (0x1a0e1c,'ldr','r1, [r0]'),(0x1a0e20,'ldr','r2, [r1, #8]'),(0x1a0e24,'mov','r1, #0'),
        (0x1a0e28,'blx','r2'),(0x1a0e2c,'mov','fp, r0'),
        (0x1a0e34,'add','r0, pc, r0'),(0x1a0e38,'ldr','r0, [r4, r0]'),(0x1a0e3c,'ldr','r0, [r0]'),
        (0x1a0e40,'ldr','r1, [r0]'),(0x1a0e44,'ldr','r2, [r1, #8]'),(0x1a0e48,'mov','r1, #1'),
        (0x1a0e4c,'blx','r2'),(0x1a0e50,'mov','r6, r0'),
        (0x1a0e58,'add','r0, pc, r0'),(0x1a0e5c,'ldr','r0, [r4, r0]'),(0x1a0e60,'ldr','r0, [r0]'),
        (0x1a0e64,'ldr','r1, [r0]'),(0x1a0e68,'ldr','r2, [r1, #8]'),(0x1a0e6c,'mov','r1, #0x13'),
        (0x1a0e70,'blx','r2'),(0x1a0e74,'str','r0, [sp, #0x28]'),
        (0x1a0e7c,'add','r0, pc, r0'),(0x1a0e80,'ldr','r0, [r4, r0]'),(0x1a0e84,'ldr','r0, [r0]'),
        (0x1a0e88,'ldr','r1, [r0]'),(0x1a0e8c,'ldr','r2, [r1, #8]'),(0x1a0e90,'mov','r1, #5'),
        (0x1a0e94,'blx','r2'),(0x1a0e98,'str','r0, [sp, #0x2c]'),
        (0x1a0ea0,'add','r0, pc, r0'),(0x1a0ea4,'ldr','r0, [r4, r0]'),(0x1a0ea8,'ldr','r0, [r0]'),
        (0x1a0eac,'ldr','r1, [r0]'),(0x1a0eb0,'ldr','r2, [r1, #8]'),(0x1a0eb4,'mov','r1, #6'),
        (0x1a0eb8,'blx','r2'),(0x1a0ebc,'str','r0, [sp, #0x20]'),
        (0x1a0f90,'mov','sb, r6'),(0x1a0fb0,'ldr','r4, [sp, #0x200]'),(0x1a0fbc,'mov','r6, fp'),
        (0x1a0ff0,'ldr','r1, [r4]'),(0x1a0ff4,'add','r0, sp, #0x1a8'),
        (0x1a1004,'ldr','r1, [r4, #4]'),(0x1a1008,'add','r0, sp, #0x198'),
        # Slot 5 = floor(argument1/global18), slot 6 = fmod(argument1,global18).
        (0x1a1018,'ldr','r0, [r8]'),(0x1a101c,'ldr','r2, [r0, #8]'),(0x1a1020,'mov','r0, r8'),
        (0x1a1024,'mov','r1, #5'),(0x1a1028,'blx','r2'),(0x1a102c,'mov','r4, r0'),
        (0x1a1030,'add','r5, sp, #0xf8'),(0x1a1034,'ldr','r2, [sp, #0x30]'),
        (0x1a1038,'add','r1, sp, #0x198'),(0x1a103c,'mov','r0, r5'),
        (0x1a104c,'add','r0, pc, r0'),(0x1a1058,'ldr','r1, [r1, r0]'),
        (0x1a105c,'str','r5, [sp, #0xf4]'),(0x1a1064,'ldr','r1, [r1, #4]'),
        (0x1a1068,'str','r1, [sp]'),(0x1a106c,'add','r0, sp, #0xf4'),
        (0x1a1074,'mov','r3, #1'),(0x1a1078,'str','r0, [sp, #4]'),
        (0x1a1084,'mov','r1, r0'),(0x1a1088,'mov','r0, r4'),
        (0x1a10f8,'ldr','r0, [r8]'),(0x1a10fc,'ldr','r2, [r0, #8]'),
        (0x1a1100,'mov','r0, r8'),(0x1a1104,'mov','r1, #6'),(0x1a1108,'blx','r2'),(0x1a110c,'mov','r7, r0'),
        (0x1a1110,'add','r0, sp, #0x198'),(0x1a1118,'mov','r5, r0'),(0x1a111c,'mov','r4, r1'),
        (0x1a1120,'ldr','r0, [sp, #0x30]'),(0x1a1128,'vmov','d1, r0, r1'),(0x1a112c,'vmov','d0, r5, r4'),
        (0x1a1130,'vmov','r2, r3, d1'),(0x1a1134,'vmov','r0, r1, d0'),
        (0x1a1160,'vmov','d0, r5, fp'),(0x1a1164,'mov','r0, #0'),(0x1a1168,'str','r0, [r7, #0xc]'),
        (0x1a116c,'vstr','d0, [sp, #0x48]'),(0x1a1170,'ldr','r0, [sp, #0x48]'),
        (0x1a1174,'ldr','r1, [sp, #0x4c]'),(0x1a1178,'stm','r7, {r0, r1}'),
        # Selector assigns slot 7 to the global 0/1 target map.
        (0x1a1184,'add','r0, sp, #0x1a8'),(0x1a1190,'vcvt.s32.f64','s0, d0'),(0x1a1198,'cmp','r0, #2'),
        (0x1a119c,'bne','#0x1a11cc'),(0x1a11b4,'mov','r1, #7'),(0x1a11b8,'blx','r2'),(0x1a11bc,'mov','r1, sb'),
        (0x1a11cc,'cmp','r0, #1'),(0x1a11d0,'bne','#0x1a1200'),
        (0x1a11e8,'mov','r1, #7'),(0x1a11ec,'blx','r2'),(0x1a11f0,'mov','r1, r6'),
        # Initialize flag slot 8 to 0. Type approximately 2 and field 4
        # approximately 4 are necessary to invoke the pet helper.
        (0x1a1214,'mov','r1, #8'),(0x1a1218,'blx','r2'),(0x1a121c,'mov','r7, r0'),
        (0x1a123c,'mov','r0, #0'),(0x1a1240,'str','r0, [r7, #0xc]'),
        (0x1a1244,'str','r0, [r7, #4]'),(0x1a1248,'str','r0, [r7]'),
        (0x1a1254,'add','r0, sp, #0x1a8'),(0x1a125c,'vmov.f64','d9, #-2.000000e+00'),
        (0x1a126c,'vadd.f64','d0, d0, d9'),(0x1a1270,'add','r0, pc, r0'),(0x1a1274,'ldr','r0, [sb, r0]'),
        (0x1a1278,'vcmpe.f64','d0, #0'),(0x1a1280,'vldr','d1, [r0]'),
        (0x1a1284,'vnegmi.f64','d0, d0'),(0x1a1288,'vcmpe.f64','d0, d1'),(0x1a1290,'bhi','#0x1a13e0'),
        (0x1a12a8,'mov','r1, #6'),(0x1a12ac,'blx','r2'),(0x1a12b8,'mov','r1, #0x7d00'),
        (0x1a12bc,'vcvt.s32.f64','s0, d0'),(0x1a12c4,'mul','r0, r0, r1'),(0x1a12c8,'orr','r1, r0, #4'),
        (0x1a12cc,'ldr','r0, [sp, #0x28]'),(0x1a12d8,'vmov.f64','d1, #-4.000000e+00'),
        (0x1a12e4,'vadd.f64','d0, d0, d1'),(0x1a12e8,'add','r0, pc, r0'),(0x1a12ec,'ldr','r0, [sb, r0]'),
        (0x1a12f0,'vcmpe.f64','d0, #0'),(0x1a12f8,'vldr','d1, [r0]'),(0x1a12fc,'vnegmi.f64','d0, d0'),
        (0x1a1300,'vcmpe.f64','d0, d1'),(0x1a1308,'bhi','#0x1a13e0'),
        (0x1a131c,'mov','r0, r8'),(0x1a1320,'mov','r1, #6'),(0x1a1324,'blx','r2'),
        (0x1a1328,'str','r0, [sp, #0xf0]'),(0x1a132c,'ldr','r1, [sp, #0x34]'),
        (0x1a1330,'add','r0, sp, #0xf0'),(0x1a1334,'add','r2, sp, #0x118'),
        (0x1a1338,'str','r0, [sp]'),(0x1a133c,'mov','r0, r8'),(0x1a1340,'mov','r3, #1'),
        (0x1a134c,'vmov.f64','d1, #5.000000e-01'),(0x1a1350,'vmov','d0, r0, r1'),
        (0x1a1354,'vcmpe.f64','d0, d1'),(0x1a135c,'ble','#0x1a13e0'),
        (0x1a139c,'ldr','r2, [r0, #8]'),(0x1a13a0,'mov','r0, r8'),(0x1a13a4,'mov','r1, #8'),
        (0x1a13a8,'blx','r2'),(0x1a13ac,'mov','r5, r0'),(0x1a13cc,'movw','r1, #0'),
        (0x1a13d0,'mov','r0, #0'),(0x1a13d4,'movt','r1, #0x3ff0'),
        (0x1a13d8,'str','r0, [r5, #0xc]'),(0x1a13dc,'stm','r5, {r0, r1}'),
        # A positive flag skips the following map update; if flag is zero,
        # read(target, original argument1)-1, set, reread and maybe delete.
        (0x1a13e8,'mov','r0, r7'),(0x1a13f8,'vcmpe.f64','d0, #0'),(0x1a1408,'vldr','d1, [r0]'),
        (0x1a140c,'vnegmi.f64','d0, d0'),(0x1a1410,'vcmpe.f64','d0, d1'),(0x1a1418,'bhi','#0x1a1660'),
        (0x1a1430,'mov','r1, #7'),(0x1a1434,'blx','r2'),(0x1a1438,'mov','r7, r0'),
        (0x1a1440,'add','r1, sp, #0x198'),(0x1a1448,'add','r0, pc, r0'),
        (0x1a144c,'str','r7, [sp, #0xe8]'),(0x1a1450,'str','r1, [sp, #0xec]'),
        (0x1a1454,'ldr','r0, [fp, r0]'),(0x1a1458,'ldr','r0, [r0, #4]'),
        (0x1a145c,'add','r1, sp, #0xe8'),(0x1a1464,'stm','sp, {r0, r1}'),(0x1a146c,'mov','r3, #2'),
        (0x1a1478,'mov','r1, r0'),(0x1a147c,'add','r5, sp, #0xd8'),(0x1a1480,'mov','r2, #1'),(0x1a1484,'mov','r0, r5'),
        (0x1a1498,'add','r2, sp, #0x198'),(0x1a149c,'add','r0, pc, r0'),
        (0x1a14a0,'str','r7, [sp, #0xcc]'),(0x1a14a4,'str','r2, [sp, #0xd0]'),
        (0x1a14a8,'ldr','r0, [r1, r0]'),(0x1a14ac,'str','r5, [sp, #0xd4]'),
        (0x1a14b0,'ldr','r0, [r0, #4]'),(0x1a14b4,'add','r1, sp, #0xcc'),
        (0x1a14bc,'stm','sp, {r0, r1}'),(0x1a14c4,'mov','r3, #3'),
        (0x1a1524,'add','r1, sp, #0x198'),(0x1a1528,'add','r0, pc, r0'),
        (0x1a1534,'ldr','r0, [fp, r0]'),(0x1a1538,'str','r7, [sp, #0xc4]'),
        (0x1a1540,'ldr','r0, [r0, #4]'),(0x1a1544,'str','r1, [sp, #0xc8]'),
        (0x1a1548,'add','r1, sp, #0xc4'),(0x1a1550,'stm','sp, {r0, r1}'),(0x1a1558,'mov','r3, #2'),
        (0x1a1574,'add','r0, pc, r0'),(0x1a1578,'ldr','r0, [sb, r0]'),
        (0x1a157c,'vldr','d1, [r0]'),(0x1a1580,'vcmpe.f64','d0, d1'),(0x1a1588,'bhi','#0x1a1644'),
        (0x1a15d0,'mov','r1, #7'),(0x1a15d4,'blx','r2'),(0x1a15e0,'add','r1, pc, r1'),
        (0x1a15e4,'str','r0, [sp, #0xbc]'),(0x1a15e8,'add','r0, sp, #0x198'),(0x1a15ec,'str','r0, [sp, #0xc0]'),
        (0x1a15f0,'ldr','r1, [r2, r1]'),(0x1a15f4,'ldr','r0, [r1, #4]'),
        (0x1a15f8,'add','r1, sp, #0xbc'),(0x1a1600,'stm','sp, {r0, r1}'),(0x1a1608,'mov','r3, #2'),
        # Weapon branch: conditionally return global5 + global6*global18 as
        # item_get(1, packed key, 1), then assign new remainder and quotient.
        (0x1a1668,'add','r0, sp, #0x1a8'),(0x1a1670,'vmov.f64','d8, #-1.000000e+00'),
        (0x1a167c,'vadd.f64','d0, d0, d8'),(0x1a1688,'vcmpe.f64','d0, #0'),
        (0x1a1690,'vldr','d1, [r0]'),(0x1a1694,'vnegmi.f64','d0, d0'),
        (0x1a1698,'vcmpe.f64','d0, d1'),(0x1a16a0,'bhi','#0x1a1914'),
        (0x1a16ac,'ldr','r0, [sp, #0x2c]'),(0x1a16c4,'vldr','d1, [r0]'),
        (0x1a16c8,'vneg.f64','d1, d1'),(0x1a16cc,'vcmpe.f64','d0, d1'),(0x1a16d4,'blt','#0x1a17a0'),
        (0x1a16e0,'ldr','r1, [sp, #0x20]'),(0x1a16e4,'add','r0, sp, #0x98'),(0x1a16e8,'ldr','r2, [sp, #0x30]'),
        (0x1a16f0,'add','r4, sp, #0xa8'),(0x1a16f4,'ldr','r1, [sp, #0x2c]'),(0x1a16f8,'add','r2, sp, #0x98'),
        (0x1a16fc,'mov','r0, r4'),(0x1a1728,'add','r0, pc, r0'),(0x1a172c,'ldr','r0, [r1, r0]'),
        (0x1a1730,'str','r0, [sp, #0x8c]'),(0x1a1734,'str','r4, [sp, #0x90]'),
        (0x1a1738,'str','r0, [sp, #0x94]'),(0x1a1740,'add','r0, sp, #0x8c'),
        (0x1a1748,'str','r0, [sp]'),(0x1a1750,'mov','r3, #3'),
        (0x1a17a8,'ldr','r0, [r8]'),(0x1a17ac,'ldr','r2, [r0, #8]'),(0x1a17b0,'mov','r0, r8'),
        (0x1a17b4,'mov','r1, #6'),(0x1a17b8,'blx','r2'),(0x1a17bc,'mov','r1, r0'),(0x1a17c0,'ldr','r0, [sp, #0x2c]'),
        (0x1a17d0,'ldr','r0, [r8]'),(0x1a17d4,'ldr','r2, [r0, #8]'),(0x1a17d8,'mov','r0, r8'),
        (0x1a17dc,'mov','r1, #5'),(0x1a17e0,'blx','r2'),(0x1a17e4,'mov','r1, r0'),(0x1a17e8,'ldr','r0, [sp, #0x20]'),
        # In sys_global Create, global 18's getter pointer is retained on stack
        # and is assigned IEEE754 100000.0 via the two RValue data words.
        (0x3b75a8,'add','r0, pc, r0'),(0x3b75ac,'ldr','r0, [r5, r0]'),(0x3b75b0,'ldr','r0, [r0]'),
        (0x3b75b4,'ldr','r1, [r0]'),(0x3b75b8,'ldr','r2, [r1, #8]'),(0x3b75bc,'mov','r1, #0x12'),
        (0x3b75c0,'blx','r2'),(0x3b75c4,'str','r0, [sp, #0x40]'),(0x3f4c20,'ldr','r5, [sp, #0x40]'),
        (0x3f4d80,'mov','fp, #0'),(0x3f4dac,'ldr','r0, [r5, #0xc]'),
        (0x3f4db8,'bne','#0x3f4dc4'),(0x3f4dbc,'mov','r0, r5'),
        (0x3f4dc4,'movw','r0, #0x6a00'),(0x3f4dc8,'str','fp, [r5, #0xc]'),
        (0x3f4dcc,'movt','r0, #0x40f8'),(0x3f4dd4,'str','r0, [r5, #4]'),(0x3f4ddc,'str','fp, [r5]'),
        # item_check_pet: numeric argument is compared to 17 and 22 using
        # epsilon; return RValue is set to 0 or 1.
        (0x1ba9d0,'mov','r4, r2'),(0x1ba9e0,'ldr','r3, [sp, #0x38]'),
        (0x1baa14,'add','r0, sp, #8'),(0x1baa18,'ldr','r1, [r3]'),
        (0x1baa34,'ldr','r2, [r1, #0xc]'),(0x1baa38,'bfc','r2, #0x18, #8'),
        (0x1baa3c,'cmp','r2, #0xe'),(0x1baa40,'bhi','#0x1baafc'),
        (0x1baa44,'add','r3, pc, #8'),(0x1baa48,'lsl','r2, r2, #2'),
        (0x1baa4c,'ldr','r2, [r2, r3]'),(0x1baa50,'add','pc, r2, r3'),
        (0x1baa98,'ldm','r1, {r0, r1}'),(0x1baa9c,'stm','sp, {r0, r1}'),
        (0x1baaa0,'vldr','d0, [sp]'),(0x1baaa4,'vstr','d0, [sp, #8]'),
        (0x1bab04,'add','r0, sp, #8'),(0x1bab0c,'vmov.f64','d1, #1.700000e+01'),
        (0x1bab14,'vmov','d0, r0, r1'),(0x1bab1c,'add','r0, pc, r0'),(0x1bab20,'vsub.f64','d0, d1, d0'),
        (0x1bab24,'ldr','r0, [r6, r0]'),(0x1bab28,'vldr','d1, [r0]'),(0x1bab2c,'vcmpe.f64','d0, d1'),
        (0x1bab34,'bhi','#0x1bab68'),(0x1bab38,'add','r0, sp, #8'),
        (0x1bab40,'vmov.f64','d1, #-2.200000e+01'),(0x1bab44,'vmov','d0, r0, r1'),
        (0x1bab4c,'add','r0, pc, r0'),(0x1bab50,'vadd.f64','d0, d0, d1'),
        (0x1bab54,'ldr','r0, [r6, r0]'),(0x1bab58,'vldr','d1, [r0]'),
        (0x1bab5c,'vcmpe.f64','d0, d1'),(0x1bab64,'bls','#0x1baba4'),
        (0x1bab94,'mov','r0, #0'),(0x1bab98,'str','r0, [r4, #0xc]'),
        (0x1bab9c,'str','r0, [r4, #4]'),(0x1baba0,'b','#0x1babe4'),
        (0x1babd0,'movw','r1, #0'),(0x1babd4,'mov','r0, #0'),(0x1babd8,'movt','r1, #0x3ff0'),
        (0x1babdc,'str','r0, [r4, #0xc]'),(0x1babe0,'str','r1, [r4, #4]'),(0x1babe4,'str','r0, [r4]'),
    ):
        inst(address,op,operands)
    for address in (0x1a0ff8,0x1a100c,0x1a108c,0x1a11c0,0x1a11f4,0x1a17c4,0x1a17ec):
        call(address,'YYRValueaSERKS_')
    for address in (0x1a1188,0x1a1114,0x1a1124,0x1a1258,0x1a12b0,0x1a12d4,
                    0x1a1348,0x1a13ec,0x1a1564,0x1a166c,0x1a16b0,0x1bab08,0x1bab3c):
        call(address,'REAL_RValue')
    for address in (0x1a1080,0x1a1474,0x1a14cc,0x1a1560,0x1a1610):
        call(address,'YYGML_CallLegacyFunction')
    for address, name in ((0x1a1040,'_ZdvRK8YYRValueS1_'),(0x1a1138,'fmod'),
                          (0x1a12d0,'YYRValueixEi'),(0x1a1344,'gml_Script_item_check_pet'),
                          (0x1a1488,'_ZmiRK8YYRValuei'), (0x1a16ec,'_ZmlRK8YYRValueS1_'),
                          (0x1a1700,'_ZplRK8YYRValueS1_'), (0x1a1754,'gml_Script_item_get'),
                          (0x3f4dc0,'FREE_RValue')):
        call(address,name)
    targets = [(0x1baa54 + n) & 0xffffffff for n in struct.unpack('<15I', read(0x1baa54,60))]
    if targets[0] != 0x1baa98:
        raise ValueError('unexpected numeric RValue path in pet helper')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'function': 'gml_Script_item_equip', 'address': '0x1a0d8c', 'size': 6668,
            'key_argument': 1, 'divisor_global_index': 18,
            'divisor_create_assignment': {'function': 'gml_Object_sys_global_Create_0',
                                          'address': '0x3f4dc4', 'value': 100000.0},
            'weapon_return': {'item_get_call': '0x1a1754', 'selector': 1, 'amount': 1,
                              'base_global_index': 5, 'quotient_global_index': 6},
            'quotient_instance_slot': 5, 'remainder_instance_slot': 6,
            'target_map_instance_slot': 7, 'skip_consumption_instance_slot': 8,
            'field_array_global_index': 19, 'field_array_column': 4,
            'pet_helper': {'address': '0x1ba9c4', 'size': 732,
                           'finite_integer_range': [17,22], 'initial_epsilon': 1e-10},
            'consumption': {'read': '0x1a1474', 'set': '0x1a14cc',
                            'reread': '0x1a1560', 'delete': '0x1a1610',
                            'skip_target': '0x1a1660'},
            'limitations': 'Static selected path only; global/instance registration, divisor runtime value, '
                           'pet helper runtime, complete equip effects, abnormal values, native DS implementation '
                           'and Android/iOS execution remain unverified.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.apk)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('ITEM_EQUIP_EVIDENCE: key split, pet range and consumption guard pinned')
    print('ITEM_EQUIP_LIMIT: static only; no native execution or complete equip reconstruction')


if __name__ == '__main__':
    main()
