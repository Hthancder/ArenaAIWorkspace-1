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
    zombie = ET.parse(project / 'objects/obj_zombie3.object.gmx')
    events = zombie.findall('./events/event[@eventtype="2"][@enumb="6"]')
    if len(events) != 1:
        raise ValueError('expected one zombie3 Alarm 6')
    text = '\n'.join(x.text or '' for x in events[0].findall('./action/arguments/argument/string'))
    for quantity, indent in (('1', '            '), ('item_number[ran]', '        ')):
        snippet = (f'ins.item_number = {quantity}\n{indent}// Partial native candidate: this zombie drop is timed.\n'
                   f'{indent}ins.__dt_item_timed = 1\n{indent}\n{indent}ins.dir = random(360)')
        if text.count(snippet) != 1:
            raise ValueError('missing zombie3 candidate assignment: ' + quantity)
    if text.count('ins.__dt_item_timed = 1') != 2:
        raise ValueError('unexpected zombie3 timed assignments')


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
    ):
        i = instruction(address)
        if (i.mnemonic, i.op_str) != (op, operands):
            raise ValueError(f'instruction mismatch at {address:#x}')
    for addr, expected in ((0x176444, 'REAL_RValue'), (0x176c30, 'YYGML_action_set_alarm'),
                           (0x176408, 'YYGML_instance_destroy'), (0x17645c, 'YYGML_instance_create'),
                           (0x176474, 'INT32_RValue'), (0x176480, 'YYGML_Variable_SetValue'),
                           (0x1765f4, 'YYRValueix'), (0x1766a8, 'YYGML_random')):
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
