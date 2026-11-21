#!/usr/bin/env python3
"""Pin a partial timed-item/parcel candidate against Android ARM32.

The original variable names are unknown: __dt_item_timed is a source-only alias
for one native slot in this subset. Other setters and Alarm 1 are not restored.
Static inspection does not prove instance lifecycle or GameMaker/iOS behavior.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name, resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.deadtown_object_evidence import native_objects
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from deadtown_object_evidence import native_objects
    from recover_deadtown_audio import read_zip_member

FUNCTIONS = {
    'gml_Object_obj_item_Create_0': (0x6242f0, 1140, '0c10fa52f80d8134b69c3e307e8567ab351b502c26c19f3cc87e23dfbe49a86c'),
    'gml_Object_obj_item_Alarm_0': (0x625454, 196, 'b6f8d30bbc6079b82d2a24824280eb374173186c9bf18079c85958df69f3e448'),
    'gml_Object_obj_parcel_Step_0': (0x62eb58, 4104, '149ecb7c36ca228e6441746d11faf4d19705d1ebeaed21af70ac16f40a141182'),
    'gml_Object_obj_zombie3_Alarm_6': (0x668a38, 6936, 'f758909f83cc6499d0c57ee11307573e4322428823586af099589e2d8ad2a757'),
    'gml_Object_obj_zombie2_Step_0': (0x658910, 40784, '9a7cb64db9fe3a7c94ac56f0b69c095899cf32f1b0f37c6077d512f5f1e5f1f5'),
    'gml_Object_obj_zombie4_Step_0': (0x679698, 37992, 'ada019456226f637c40f2282afa0405870bd09217a6a5c22dd405cf2cb06cb78'),
    'gml_Object_obj_zombie5_Step_0': (0x687fc8, 34880, '9f5f3373755778960b45ec66a04ca27771deefe88443ccbcb2ff0db9cd500b0d'),
    'gml_Object_obj_zombie_Step_0': (0x647a08, 44536, '422271b0202040eb4b4e79c905e54428183f744b40a5943a8c119a1e5c89dd05'),
}


def verify_source(project):
    project = Path(project)
    item = ET.parse(project / 'objects/obj_item.object.gmx')
    create = item.findall('./events/event[@eventtype="0"][@enumb="0"]')
    alarm = item.findall('./events/event[@eventtype="2"][@enumb="0"]')
    if len(create) != 1 or len(alarm) != 1:
        raise ValueError('expected one item Create and one Alarm 0')
    create_text = '\n'.join(x.text or '' for x in create[0].findall('./action/arguments/argument/string'))
    expected_init = ('// Partial native candidate: neutral alias for an unidentified item flag.\n'
                     '__dt_item_timed = 0\nalarm[0] = 900\n')
    if create_text.count(expected_init) != 1:
        raise ValueError('missing item candidate initialization')
    action_text = [x.text or '' for x in alarm[0].findall('./action/arguments/argument/string')]
    expected_alarm = ('/// Partial candidate: native slot 1096, original name unknown.\n'
                      'if __dt_item_timed\n{\n    instance_destroy()\n}\n')
    if action_text != [expected_alarm]:
        raise ValueError('unexpected item Alarm 0 candidate')
    parcel = ET.parse(project / 'objects/obj_parcel.object.gmx')
    step = parcel.findall('./events/event[@eventtype="3"][@enumb="0"]')
    if len(step) != 1:
        raise ValueError('missing parcel Step')
    texts = '\n'.join(x.text or '' for x in step[0].findall('./action/arguments/argument/string'))
    snippet = ('ins.item_number = item_number[i]\n'
               '            // Partial native candidate: parcel marks the dropped item as timed.\n'
               '            ins.__dt_item_timed = 1\n')
    if texts.count(snippet) != 1:
        raise ValueError('missing parcel candidate assignment')
    for obj, typ, sub, indents in (('obj_zombie3', '2', '6', (12, 8)),
                                     ('obj_zombie2', '3', '0', (16, 12)),
                                     ('obj_zombie4', '3', '0', (16, 12)),
                                     ('obj_zombie5', '3', '0', (16, 12))):
        zombie = ET.parse(project / 'objects' / (obj + '.object.gmx'))
        events = zombie.findall(f'./events/event[@eventtype="{typ}"][@enumb="{sub}"]')
        if len(events) != 1:
            raise ValueError('expected one event: ' + obj)
        text = '\n'.join(x.text or '' for x in events[0].findall('./action/arguments/argument/string'))
        for quantity, spaces in zip(('1', 'item_number[ran]'), indents):
            indent = ' ' * spaces
            snippet = (f'ins.item_number = {quantity}\n{indent}// Partial native candidate: this zombie drop is timed.\n'
                       f'{indent}ins.__dt_item_timed = 1\n{indent}\n{indent}ins.dir = random(360)')
            if text.count(snippet) != 1:
                raise ValueError(f'missing {obj} candidate assignment: {quantity}')
        if text.count('ins.__dt_item_timed = 1') != 2:
            raise ValueError(f'unexpected {obj} timed assignments')
    zombie = ET.parse(project / 'objects/obj_zombie.object.gmx')
    events = zombie.findall('./events/event[@eventtype="3"][@enumb="0"]')
    if len(events) != 1:
        raise ValueError('expected one zombie Step')
    text = '\n'.join(x.text or '' for x in events[0].findall('./action/arguments/argument/string'))
    for quantity, spaces, count in (('1', 16, 2), ('item_number[ran]', 12, 1),
                                    ('irandom_range(db_spawn_info_get(ran,3),db_spawn_info_get(ran,4))', 12, 1)):
        indent = ' ' * spaces
        snippet = (f'ins.item_number = {quantity}\n{indent}// Partial native candidate: this zombie drop is timed.\n'
                   f'{indent}ins.__dt_item_timed = 1\n{indent}\n{indent}ins.dir = random(360)')
        if text.count(snippet) != count:
            raise ValueError('missing zombie candidate assignments: ' + quantity)
    if text.count('ins.__dt_item_timed = 1') != 4:
        raise ValueError('unexpected zombie timed assignments')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        raw = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
        data = read_zip_member(z, 'assets/game.droid')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    names = resource_names(data, b'OBJT')
    if len(names) != 240 or names[161] != 'obj_item':
        raise ValueError('unexpected object table')
    objects = native_objects(data)
    if objects['obj_item']['event_counts'][0] != 1 or objects['obj_item']['event_counts'][2] != 2 or objects['obj_parcel']['event_counts'][3] != 1:
        raise ValueError('unexpected native event inventory')
    elf = ELFFile(io.BytesIO(raw))
    sym = elf.get_section_by_name('.dynsym')
    rp, plt = elf.get_section_by_name('.rel.plt'), elf.get_section_by_name('.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name for i, r in enumerate(rp.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(address, length):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and address + length <= seg['p_vaddr'] + seg['p_filesz']:
                offset = seg['p_offset'] + address - seg['p_vaddr']
                return raw[offset:offset + length]
        raise ValueError('address outside ELF')

    def instruction(address):
        i = list(dis.disasm(read(address, 4), address))
        if len(i) != 1:
            raise ValueError('invalid instruction')
        return i[0]

    for name, (address, size, digest) in FUNCTIONS.items():
        found = [s for s in sym.iter_symbols() if exported_name(s.name) == name]
        if len(found) != 1 or (found[0]['st_value'], found[0]['st_size']) != (address, size):
            raise ValueError(f'unexpected export {name}')
        if hashlib.sha256(read(address, size)).hexdigest() != digest:
            raise ValueError(f'unexpected function bytes {name}')

    for address, op, operands in (
        # Create writes zero to the flag, then 900 to another slot and arms
        # alarm 0 using that RValue; it also arms the still-missing Alarm 1.
        (0x6245dc, 'ldr', 'r0, [r4]'), (0x6245e0, 'ldr', 'r2, [r0, #8]'),
        (0x6245e4, 'mov', 'r0, r4'), (0x6245e8, 'movw', 'r1, #0x448'),
        (0x6245ec, 'blx', 'r2'), (0x6245f0, 'mov', 'r5, r0'),
        (0x624610, 'mov', 'r0, #0'), (0x624614, 'str', 'r0, [r5, #0xc]'),
        (0x624618, 'str', 'r0, [r5, #4]'), (0x62461c, 'str', 'r0, [r5]'),
        (0x624628, 'ldr', 'r0, [r4]'), (0x62462c, 'ldr', 'r2, [r0, #8]'),
        (0x624630, 'mov', 'r0, r4'), (0x624634, 'movw', 'r1, #0x449'),
        (0x624638, 'blx', 'r2'), (0x62463c, 'mov', 'r5, r0'),
        (0x62465c, 'movw', 'r1, #0x2000'), (0x624660, 'mov', 'r0, #0'),
        (0x624664, 'movt', 'r1, #0x408c'), (0x624668, 'str', 'r0, [r5, #0xc]'),
        (0x62466c, 'stm', 'r5, {r0, r1}'), (0x624678, 'mov', 'r0, r5'),
        (0x62467c, 'bl', '#0x176444'), (0x624680, 'vmov', 'd0, r0, r1'),
        (0x624684, 'vcvt.s32.f64', 's0, d0'), (0x624688, 'vmov', 'r1, s0'),
        (0x62468c, 'mov', 'r0, r4'), (0x624690, 'mov', 'r2, #0'),
        (0x624694, 'bl', '#0x176c30'), (0x6246a0, 'mov', 'r0, r4'),
        (0x6246a4, 'mov', 'r1, #1'), (0x6246a8, 'mov', 'r2, #1'),
        (0x6246ac, 'bl', '#0x176c30'),
        # Alarm 0 reads the same self slot and destroys self when > 0.5.
        (0x62545c, 'mov', 'r4, r0'), (0x625494, 'ldr', 'r0, [r4]'),
        (0x625498, 'ldr', 'r2, [r0, #8]'), (0x62549c, 'mov', 'r0, r4'),
        (0x6254a0, 'movw', 'r1, #0x448'), (0x6254a4, 'blx', 'r2'),
        (0x6254a8, 'bl', '#0x176444'), (0x6254ac, 'vmov.f64', 'd1, #5.000000e-01'),
        (0x6254b0, 'vmov', 'd0, r0, r1'), (0x6254b4, 'vcmpe.f64', 'd0, d1'),
        (0x6254b8, 'vmrs', 'apsr_nzcv, fpscr'), (0x6254bc, 'ble', '#0x6254d0'),
        (0x6254c8, 'mov', 'r0, r4'), (0x6254cc, 'bl', '#0x176408'),
        # Parcel creates native obj_item and keeps the returned instance ID in
        # an RValue at sb; it writes real 1 to slot 1096 of that instance.
        (0x62f260, 'mov', 'r2, #0xa1'), (0x62f264, 'bl', '#0x17645c'),
        (0x62f268, 'mov', 'r5, r0'), (0x62f290, 'vmov', 's0, r5'),
        (0x62f294, 'str', 'fp, [sb, #0xc]'), (0x62f298, 'vcvt.f64.s32', 'd0, s0'),
        (0x62f29c, 'vstr', 'd0, [sp, #0x28]'), (0x62f2a0, 'ldr', 'r0, [sp, #0x28]'),
        (0x62f2a4, 'ldr', 'r1, [sp, #0x2c]'), (0x62f2a8, 'stm', 'sb, {r0, r1}'),
        (0x62f458, 'movw', 'r1, #0'), (0x62f45c, 'mov', 'r0, #0'),
        (0x62f460, 'movt', 'r1, #0x3ff0'), (0x62f468, 'str', 'r0, [sp, #0x104]'),
        (0x62f46c, 'str', 'r1, [sp, #0xfc]'), (0x62f470, 'str', 'r0, [sp, #0xf8]'),
        (0x62f474, 'mov', 'r0, sb'), (0x62f478, 'bl', '#0x176474'),
        (0x62f47c, 'add', 'r3, sp, #0xf8'), (0x62f480, 'movw', 'r1, #0x448'),
        (0x62f484, 'mov', 'r2, #0x80000000'), (0x62f488, 'bl', '#0x176480'),
        # Zombie3 Alarm 6 has two paths: below-one quantity with random gate,
        # and the other quantity branch. Both create object 161 and set the
        # same 1096 slot on the instance handle stored in the RValue at r6.
        (0x668f54, 'mov', 'r1, #0xc2'), (0x668f78, 'bl', '#0x1765f4'),
        (0x668f88, 'vmov.f64', 'd1, #-1.000000e+00'),
        (0x668fa8, 'bpl', '#0x66940c'), (0x668fe4, 'vmov.f64', 'd0, #1.000000e+00'),
        (0x668fec, 'bl', '#0x1766a8'), (0x669088, 'bpl', '#0x669730'),
        (0x6690a0, 'mov', 'r1, #0'), (0x6690a4, 'blx', 'r2'),
        (0x6690a8, 'mov', 'r6, r0'),
        (0x669124, 'mov', 'r2, #0xa1'), (0x669128, 'bl', '#0x17645c'),
        (0x66912c, 'mov', 'r5, r0'), (0x66914c, 'vmov', 's0, r5'),
        (0x669154, 'str', 'r0, [r6, #0xc]'), (0x66915c, 'vcvt.f64.s32', 'd0, s0'),
        (0x669160, 'vstr', 'd0, [r0]'), (0x669164, 'ldr', 'r0, [sp, #0x10]'),
        (0x669168, 'ldr', 'r1, [sp, #0x14]'), (0x66916c, 'stm', 'r6, {r0, r1}'),
        (0x66926c, 'movw', 'r5, #0'), (0x669270, 'mov', 'r0, #0'),
        (0x669274, 'movt', 'r5, #0x3ff0'), (0x6692c0, 'mov', 'r0, #0'),
        (0x6692c4, 'str', 'r0, [sp, #0x1e4]'), (0x6692c8, 'str', 'r5, [sp, #0x1dc]'),
        (0x6692cc, 'str', 'r0, [sp, #0x1d8]'), (0x6692d0, 'mov', 'r0, r6'),
        (0x6692d4, 'bl', '#0x176474'), (0x6692d8, 'add', 'r3, sp, #0x1d8'),
        (0x6692dc, 'movw', 'r1, #0x448'), (0x6692e0, 'mov', 'r2, #0x80000000'),
        (0x6692e4, 'bl', '#0x176480'), (0x66939c, 'b', '#0x669730'),
        (0x669420, 'mov', 'r1, #0'), (0x669424, 'blx', 'r2'),
        (0x669428, 'mov', 'r6, r0'), (0x6694a4, 'mov', 'r2, #0xa1'),
        (0x6694a8, 'bl', '#0x17645c'), (0x6694ac, 'mov', 'r5, r0'),
        (0x6694cc, 'vmov', 's0, r5'), (0x6694d4, 'str', 'r0, [r6, #0xc]'),
        (0x6694dc, 'vcvt.f64.s32', 'd0, s0'), (0x6694e0, 'vstr', 'd0, [r0, #8]'),
        (0x6694e4, 'ldr', 'r0, [sp, #0x18]'), (0x6694e8, 'ldr', 'r1, [sp, #0x1c]'),
        (0x6694ec, 'stm', 'r6, {r0, r1}'),
        (0x66964c, 'movw', 'r1, #0'), (0x669650, 'mov', 'r0, #0'),
        (0x669654, 'movt', 'r1, #0x3ff0'), (0x669658, 'str', 'r0, [sp, #0x184]'),
        (0x66965c, 'str', 'r1, [sp, #0x17c]'), (0x669660, 'str', 'r0, [sp, #0x178]'),
        (0x669664, 'mov', 'r0, r6'), (0x669668, 'bl', '#0x176474'),
        (0x66966c, 'add', 'r3, sp, #0x178'), (0x669670, 'movw', 'r1, #0x448'),
        (0x669674, 'mov', 'r2, #0x80000000'), (0x669678, 'bl', '#0x176480'),
        # Zombie2 Step has the same two quantity branches. Its instance handle
        # is kept in the RValue addressed by r5.
        (0x65bfa4, 'mov', 'r1, #0xc2'), (0x65bfcc, 'bl', '#0x1765f4'),
        (0x65bffc, 'bpl', '#0x65c4cc'), (0x65c040, 'bl', '#0x1766a8'),
        (0x65c0e8, 'bpl', '#0x65c818'),
        (0x65c100, 'mov', 'r1, #0'), (0x65c108, 'blx', 'r2'),
        (0x65c10c, 'mov', 'r5, r0'), (0x65c188, 'mov', 'r2, #0xa1'),
        (0x65c18c, 'bl', '#0x17645c'), (0x65c190, 'mov', 'r4, r0'),
        (0x65c1b8, 'vmov', 's0, r4'), (0x65c1c0, 'str', 'r0, [r5, #0xc]'),
        (0x65c1c4, 'vcvt.f64.s32', 'd0, s0'), (0x65c1c8, 'vstr', 'd0, [sb, #0x58]'),
        (0x65c1cc, 'ldrd', 'r0, r1, [sb, #0x58]'), (0x65c1d0, 'stm', 'r5, {r0, r1}'),
        (0x65c2e0, 'movw', 'r4, #0'), (0x65c2e4, 'mov', 'r0, #0'),
        (0x65c2e8, 'movt', 'r4, #0x3ff0'), (0x65c33c, 'mov', 'r0, #0'),
        (0x65c340, 'str', 'r0, [sp, #0xb5c]'), (0x65c344, 'str', 'r4, [sp, #0xb54]'),
        (0x65c348, 'str', 'r0, [sp, #0xb50]'), (0x65c34c, 'mov', 'r0, r5'),
        (0x65c350, 'bl', '#0x176474'), (0x65c354, 'add', 'r3, sp, #0xb50'),
        (0x65c358, 'movw', 'r1, #0x448'), (0x65c35c, 'mov', 'r2, #0x80000000'),
        (0x65c360, 'bl', '#0x176480'),
        (0x65c4e0, 'mov', 'r1, #0'), (0x65c4e8, 'blx', 'r2'),
        (0x65c4ec, 'mov', 'r5, r0'), (0x65c568, 'mov', 'r2, #0xa1'),
        (0x65c56c, 'bl', '#0x17645c'), (0x65c570, 'mov', 'r4, r0'),
        (0x65c598, 'vmov', 's0, r4'), (0x65c5a0, 'str', 'r0, [r5, #0xc]'),
        (0x65c5a4, 'vcvt.f64.s32', 'd0, s0'), (0x65c5a8, 'vstr', 'd0, [sb, #0x60]'),
        (0x65c5ac, 'ldrd', 'r0, r1, [sb, #0x60]'), (0x65c5b0, 'stm', 'r5, {r0, r1}'),
        (0x65c720, 'movw', 'r1, #0'), (0x65c724, 'mov', 'r0, #0'),
        (0x65c728, 'movt', 'r1, #0x3ff0'), (0x65c72c, 'str', 'r0, [sp, #0xafc]'),
        (0x65c730, 'str', 'r1, [sp, #0xaf4]'), (0x65c734, 'str', 'r0, [sp, #0xaf0]'),
        (0x65c738, 'mov', 'r0, r5'), (0x65c73c, 'bl', '#0x176474'),
        (0x65c740, 'add', 'r3, sp, #0xaf0'), (0x65c744, 'movw', 'r1, #0x448'),
        (0x65c748, 'mov', 'r2, #0x80000000'), (0x65c74c, 'bl', '#0x176480'),
        # Zombie4 and zombie5 Step: quantity and probability branches, and
        # access the native local handle slot before each item creation.
        (0x67d34c, 'mov', 'r1, #0xc2'), (0x67d374, 'bl', '#0x1765f4'),
        (0x67d3a4, 'bpl', '#0x67d8b8'), (0x67d3e8, 'vmov.f64', 'd0, #1.000000e+00'),
        (0x67d3f0, 'bl', '#0x1766a8'), (0x67d4a8, 'bpl', '#0x67dc4c'),
        (0x67d4c0, 'mov', 'r1, #0'), (0x67d4c8, 'blx', 'r2'), (0x67d4cc, 'mov', 'r5, r0'),
        (0x67d8cc, 'mov', 'r1, #0'), (0x67d8d4, 'blx', 'r2'), (0x67d8d8, 'mov', 'r5, r0'),
        (0x68afa4, 'mov', 'r1, #0xc2'), (0x68afcc, 'bl', '#0x1765f4'),
        (0x68affc, 'bpl', '#0x68b528'), (0x68b040, 'vmov.f64', 'd0, #1.000000e+00'),
        (0x68b048, 'bl', '#0x1766a8'), (0x68b0f0, 'bpl', '#0x68b8c0'),
        (0x68b108, 'mov', 'r1, #0'), (0x68b110, 'blx', 'r2'), (0x68b114, 'mov', 'r4, r0'),
        (0x68b53c, 'mov', 'r1, #0'), (0x68b544, 'blx', 'r2'), (0x68b548, 'mov', 'r4, r0'),
        # Each low-quantity path reuses the real 1 placed in r4/r5 for
        # item_number. Each whole-quantity path constructs its own real 1.
        (0x67d6cc, 'movw', 'r4, #0'), (0x67d6d0, 'mov', 'r0, #0'),
        (0x67d6d4, 'movt', 'r4, #0x3ff0'), (0x67d730, 'mov', 'r0, #0'),
        (0x67d734, 'str', 'r0, [sp, #0x9f4]'), (0x67d738, 'str', 'r4, [sp, #0x9ec]'),
        (0x67d73c, 'str', 'r0, [sp, #0x9e8]'), (0x67d740, 'mov', 'r0, r5'),
        (0x67d744, 'bl', '#0x176474'), (0x67d748, 'add', 'r4, sp, #0x800'),
        (0x67d74c, 'movw', 'r1, #0x448'), (0x67d750, 'add', 'r3, r4, #0x1e8'),
        (0x67d754, 'mov', 'r2, #0x80000000'), (0x67d758, 'bl', '#0x176480'),
        (0x67db40, 'movw', 'r1, #0'), (0x67db44, 'mov', 'r0, #0'),
        (0x67db48, 'movt', 'r1, #0x3ff0'), (0x67db4c, 'str', 'r0, [sp, #0x994]'),
        (0x67db50, 'str', 'r1, [sp, #0x98c]'), (0x67db54, 'str', 'r0, [sp, #0x988]'),
        (0x67db58, 'mov', 'r0, r5'), (0x67db5c, 'bl', '#0x176474'),
        (0x67db60, 'add', 'r4, sp, #0x800'), (0x67db64, 'movw', 'r1, #0x448'),
        (0x67db68, 'add', 'r3, r4, #0x188'), (0x67db6c, 'mov', 'r2, #0x80000000'),
        (0x67db70, 'bl', '#0x176480'),
        (0x68b314, 'movw', 'r5, #0'), (0x68b318, 'mov', 'r0, #0'),
        (0x68b31c, 'movt', 'r5, #0x3ff0'), (0x68b378, 'mov', 'r0, #0'),
        (0x68b37c, 'str', 'r0, [sp, #0x8d4]'), (0x68b380, 'str', 'r5, [sp, #0x8cc]'),
        (0x68b384, 'str', 'r0, [sp, #0x8c8]'), (0x68b388, 'mov', 'r0, r4'),
        (0x68b38c, 'bl', '#0x176474'), (0x68b390, 'add', 'r5, sp, #0x800'),
        (0x68b394, 'movw', 'r1, #0x448'), (0x68b398, 'add', 'r3, r5, #0xc8'),
        (0x68b39c, 'mov', 'r2, #0x80000000'), (0x68b3a0, 'bl', '#0x176480'),
        (0x68b7b0, 'movw', 'r1, #0'), (0x68b7b4, 'mov', 'r0, #0'),
        (0x68b7b8, 'movt', 'r1, #0x3ff0'), (0x68b7bc, 'str', 'r0, [sp, #0x874]'),
        (0x68b7c0, 'str', 'r1, [sp, #0x86c]'), (0x68b7c4, 'str', 'r0, [sp, #0x868]'),
        (0x68b7c8, 'mov', 'r0, r4'), (0x68b7cc, 'bl', '#0x176474'),
        (0x68b7d0, 'add', 'r5, sp, #0x800'), (0x68b7d4, 'movw', 'r1, #0x448'),
        (0x68b7d8, 'add', 'r3, r5, #0x68'), (0x68b7dc, 'mov', 'r2, #0x80000000'),
        (0x68b7e0, 'bl', '#0x176480'),
    ):
        i = instruction(address)
        if (i.mnemonic, i.op_str) != (op, operands):
            raise ValueError(f'instruction mismatch at {address:#x}')
    for start, handle, result, tmp, offset in (
        (0x67d55c, 'r5', 'r4', '0x120', '0x30'), (0x67d968, 'r5', 'r4', '0x120', '0x38'),
        (0x68b1a4, 'r4', 'r5', '0x118', '0x20'), (0x68b5d8, 'r4', 'r5', '0x118', '0x28'),
    ):
        for delta, op, operands in (
            (-4, 'mov', 'r2, #0xa1'), (0, 'bl', '#0x17645c'),
            (4, 'mov', f'{result}, r0'), (0x2c, 'vmov', f's0, {result}'),
            (0x30, 'mov', 'r0, #0'), (0x34, 'str', f'r0, [{handle}, #0xc]'),
            (0x38, 'add', f'r0, sp, #{tmp}'), (0x3c, 'vcvt.f64.s32', 'd0, s0'),
            (0x40, 'vstr', f'd0, [r0, #{offset}]'), (0x44, 'ldrd', f'r0, r1, [r0, #{offset}]'),
            (0x48, 'stm', f'{handle}, {{r0, r1}}'),
        ):
            i = instruction(start + delta)
            if (i.mnemonic, i.op_str) != (op, operands):
                raise ValueError(f'zombie4/5 creation mismatch at {start + delta:#x}')
    # Normal zombie: two array-backed and two database-backed paths.
    checks = (
        (0x64ba58, 'mov', 'r1, #0xc2'), (0x64ba80, 'bl', '#0x1765f4'),
        (0x64bab0, 'bpl', '#0x64bf50'), (0x64baf8, 'bl', '#0x1766a8'),
        (0x64bbac, 'bpl', '#0x64c2a0'), (0x64bbc4, 'mov', 'r1, #0'),
        (0x64bbcc, 'blx', 'r2'), (0x64bbd0, 'mov', 'r6, r0'),
        (0x64bf64, 'mov', 'r1, #0'), (0x64bf6c, 'blx', 'r2'), (0x64bf70, 'mov', 'r6, r0'),
        (0x64c2dc, 'bl', '#0x17696c'), (0x64c384, 'bl', '#0x176978'),
        (0x64c3b4, 'bpl', '#0x64c9b0'), (0x64c430, 'bl', '#0x1766a8'),
        (0x64c458, 'bl', '#0x176978'), (0x64c4dc, 'bpl', '#0x64ced4'),
        (0x64c52c, 'mov', 'r1, #0'), (0x64c534, 'blx', 'r2'), (0x64c538, 'mov', 'r5, r0'),
        (0x64c9c4, 'mov', 'r1, #0'), (0x64c9cc, 'blx', 'r2'), (0x64c9d0, 'mov', 'r5, r0'),
        (0x64bda8, 'movw', 'r4, #0'), (0x64bdac, 'mov', 'r0, #0'), (0x64bdb0, 'movt', 'r4, #0x3ff0'),
        (0x64c7d8, 'movw', 'r4, #0'), (0x64c7dc, 'mov', 'r0, #0'), (0x64c7e0, 'movt', 'r4, #0x3ff0'),
    )
    for address, op, operands in checks:
        i = instruction(address)
        if (i.mnemonic, i.op_str) != (op, operands):
            raise ValueError(f'zombie branch mismatch at {address:#x}')
    for start, handle, offset in ((0x64bc50, 'r6', '0x30'), (0x64bff0, 'r6', '0x38'),
                                  (0x64c5b8, 'r5', '0x20'), (0x64ca50, 'r5', '0x28')):
        for delta, op, operands in ((-4, 'mov', 'r2, #0xa1'), (0, 'bl', '#0x17645c'),
            (4, 'mov', 'r4, r0'), (0x2c, 'vmov', 's0, r4'), (0x30, 'mov', 'r0, #0'),
            (0x34, 'str', f'r0, [{handle}, #0xc]'), (0x38, 'vcvt.f64.s32', 'd0, s0'),
            (0x3c, 'vstr', f'd0, [sl, #{offset}]'), (0x40, 'ldrd', f'r0, r1, [sl, #{offset}]'),
            (0x44, 'stm', f'{handle}, {{r0, r1}}')):
            i = instruction(start + delta)
            if (i.mnemonic, i.op_str) != (op, operands):
                raise ValueError(f'zombie creation mismatch at {start+delta:#x}')
    for start, handle, address, const in ((0x64be04, 'r6', '0xbf0', True), (0x64c1a8, 'r6', '0xb90', False),
                                         (0x64c834, 'r5', '0xb30', True), (0x64cdcc, 'r5', '0xad0', False)):
        checks = ([('mov', 'r0, #0'), ('str', f'r0, [sp, #{hex(int(address, 16)+12)}]'),
                   ('str', f'r4, [sp, #{hex(int(address, 16)+4)}]'), ('str', f'r0, [sp, #{address}]')]
                  if const else [('movw', 'r1, #0'), ('mov', 'r0, #0'), ('movt', 'r1, #0x3ff0'),
                    ('str', f'r0, [sp, #{hex(int(address, 16)+12)}]'),
                    ('str', f'r1, [sp, #{hex(int(address, 16)+4)}]'), ('str', f'r0, [sp, #{address}]')])
        checks += [('mov', f'r0, {handle}'), ('bl', '#0x176474'), ('add', f'r3, sp, #{address}'),
                   ('movw', 'r1, #0x448'), ('mov', 'r2, #0x80000000'), ('bl', '#0x176480')]
        for index, (op, operands) in enumerate(checks):
            i = instruction(start + 4*index)
            if (i.mnemonic, i.op_str) != (op, operands):
                raise ValueError(f'zombie setter mismatch at {start+4*index:#x}')
    for addr, expected in ((0x176444, 'REAL_RValue'), (0x176c30, 'YYGML_action_set_alarm'),
                           (0x176408, 'YYGML_instance_destroy'), (0x17645c, 'YYGML_instance_create'),
                           (0x176474, 'INT32_RValue'), (0x176480, 'YYGML_Variable_SetValue'),
                           (0x1765f4, 'YYRValueix'), (0x1766a8, 'YYGML_random'),
                           (0x17696c, 'gml_Script_db_spawn_random'), (0x176978, 'gml_Script_db_spawn_info_get')):
        if expected not in calls.get(addr, ''):
            raise ValueError('unexpected function call relocation')
    trace = list(dis.disasm(read(0x62f2ac, 0x62f474 - 0x62f2ac), 0x62f2ac))
    if len(trace) != (0x62f474 - 0x62f2ac) // 4:
        raise ValueError('incomplete parcel register trace')
    for i in trace:
        if any(i.reg_name(reg) in ('sb', 'r9') for reg in i.regs_access()[1]):
            raise ValueError('parcel instance pointer register unexpectedly overwritten')
    for begin, end in ((0x669170, 0x6692d0), (0x6694f0, 0x669664)):
        trace = list(dis.disasm(read(begin, end - begin), begin))
        if len(trace) != (end - begin) // 4:
            raise ValueError('incomplete zombie instance register trace')
        for i in trace:
            if any(i.reg_name(reg) == 'r6' for reg in i.regs_access()[1]):
                raise ValueError('zombie instance pointer register unexpectedly overwritten')
    for begin, end in ((0x65c1d4, 0x65c34c), (0x65c5b4, 0x65c738)):
        trace = list(dis.disasm(read(begin, end - begin), begin))
        if len(trace) != (end - begin) // 4 or any(
                i.reg_name(reg) == 'r5' for i in trace for reg in i.regs_access()[1]):
            raise ValueError('zombie2 instance pointer register unexpectedly overwritten')
    for begin, end, register in ((0x64bbd4, 0x64be14, 'r6'), (0x64bf74, 0x64c1c0, 'r6'),
                                 (0x64c53c, 0x64c844, 'r5'), (0x64c9d4, 0x64cde4, 'r5'),
                                 (0x64bdb4, 0x64be0c, 'r4'), (0x64c7e4, 0x64c83c, 'r4'),
                                 (0x67d4d0, 0x67d740, 'r5'), (0x67d8dc, 0x67db58, 'r5'),
                                 (0x68b118, 0x68b388, 'r4'), (0x68b54c, 0x68b7c8, 'r4'),
                                 (0x67d6d8, 0x67d738, 'r4'), (0x68b320, 0x68b380, 'r5')):
        trace = list(dis.disasm(read(begin, end - begin), begin))
        if len(trace) != (end - begin) // 4 or any(
                i.reg_name(reg) == register for i in trace for reg in i.regs_access()[1]):
            raise ValueError(f'zombie register trace mismatch: {begin:#x} {register}')
    trace = list(dis.disasm(read(0x65c2ec, 0x65c344 - 0x65c2ec), 0x65c2ec))
    if len(trace) != (0x65c344 - 0x65c2ec) // 4 or any(
            i.reg_name(reg) == 'r4' for i in trace for reg in i.regs_access()[1]):
        raise ValueError('zombie2 constant register unexpectedly overwritten')
    trace = list(dis.disasm(read(0x669278, 0x6692c8 - 0x669278), 0x669278))
    if len(trace) != (0x6692c8 - 0x669278) // 4 or any(
            i.reg_name(reg) == 'r5' for i in trace for reg in i.regs_access()[1]):
        raise ValueError('zombie constant register unexpectedly overwritten')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'native_item_object_index': 161, 'native_flag_slot': 1096, 'native_delay_slot': 1097,
            'create': 'flag 0, delay 900, alarm 0 set to delay, alarm 1 set to 1',
            'alarm_0': 'destroy self when real flag > 0.5',
            'parcel_representative_path': 'create obj_item and set its flag to 1',
            'zombie3_alarm_6': 'two drop paths create obj_item and set its flag to 1',
            'zombie2_step_0': 'two drop paths create obj_item and set its flag to 1',
            'zombie4_step_0': 'two drop paths create obj_item and set its flag to 1',
            'zombie5_step_0': 'two drop paths create obj_item and set its flag to 1',
            'zombie_step_0': 'four array/database-backed drop paths create obj_item and set its flag to 1',
            'source_only_alias': '__dt_item_timed',
            'limitations': 'Partial candidate only; original variable names unknown, other setters and Alarm 1 are missing. '
                           'Static ARM32, no native/iOS execution, no proof of scheduling or all parcel paths.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2) + '\n', encoding='utf-8')
    print('ITEM_LIFETIME_EVIDENCE: partial candidate; original flag name unknown')


if __name__ == '__main__':
    main()
