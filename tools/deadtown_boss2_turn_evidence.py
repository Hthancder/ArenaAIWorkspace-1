#!/usr/bin/env python3
"""Verify a partial boss tentacle turn-reversal candidate against pinned ARM32.

The alias is invented; other Create and Step behavior is old source and remains
unverified. This static analysis does not prove in-game timing or iOS behavior.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
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

INIT = '''// Partial native candidate: slot 1201 temporarily reverses the turn.
__dt_reverse_turn = 0
if (choose(1,0,0) > 0.5)
{
    __dt_reverse_turn = 1
    alarm[0] = 20
}
'''
SPEED_INITIAL = '''// Partial native candidate: slot 180 is the tentacle move speed.
move_speed = 8
'''
DAMAGE_INITIAL = '''// Partial native candidate: slot 1200 controls the tentacle's damage.
blood_speed = 0.4
'''
SPEED_CHOICE = '''// Partial native candidate: independent rare faster tentacle.
if (choose(1,0,0,0,0) > 0.5)
{
    move_speed = 9
}
'''
TURN = '''// Partial native candidate: the temporary flag reverses the turn.
            if (__dt_reverse_turn > 0.5)
            {
                go_dir *= -1
            }
'''
ALARM = '''/// Partial native candidate: slot 1201; original name unknown.
__dt_reverse_turn = 0
'''
FUNCTIONS = {
    'Create_0': (0x714ef4, 3092, '5e3c1b95cf4bef5649a0a9918ba8498f996e3a9743581a823d6b62b0af2c7b55'),
    'Step_0': (0x715bd8, 21620, '7cbd9b72a9e392fff2fadab03234c79e8d5620a6adaf5f3d1d116aade1d9caf3'),
    'Alarm_0': (0x715b08, 204, '03d9b62c5f9bb060fc67b18e4cd0fc342dc6a4bfb10fe103a036211d360a263b'),
}


def fragments(project):
    root = ET.parse(Path(project)/'objects/obj_boss2_ten.object.gmx').getroot()
    def action(typ, sub):
        events = root.findall(f'./events/event[@eventtype="{typ}"][@enumb="{sub}"]')
        if len(events) != 1:
            raise ValueError('expected one boss event')
        texts = events[0].findall('./action/arguments/argument/string')
        expected = 2 if typ == '3' else 1
        if len(texts) != expected:
            raise ValueError('unexpected boss event actions')
        return '\n'.join(x.text or '' for x in texts)
    create, step, alarm = action('0','0'), action('3','0'), action('2','0')
    if (create.count(INIT) != 1 or create.count('__dt_reverse_turn') != 2 or
            create.count(SPEED_INITIAL) != 1 or create.count(SPEED_CHOICE) != 1 or
            create.count('move_speed =') != 2 or create.count(DAMAGE_INITIAL) != 1 or
            create.count('blood_speed =') != 1 or not create.index(SPEED_INITIAL) < create.index(DAMAGE_INITIAL) < create.index(INIT) < create.index(SPEED_CHOICE)):
        raise ValueError('unexpected boss Create candidate')
    before = '{go_dir = point_direction(x,y,obj_player.x,obj_player.y)-bangle}\n\n            '
    after = '            \n            body_x[0] += lengthdir_x(body_length,bangle+go_dir)'
    damage = 'if type == 0\n        {\n            obj_player.hp -= blood_speed/2\n        }'
    if (step.count(before + TURN + after) != 1 or step.count('__dt_reverse_turn') != 1 or
            step.count(damage) != 1):
        raise ValueError('unexpected boss Step candidate')
    if alarm != ALARM:
        raise ValueError('unexpected boss Alarm candidate')
    return INIT, TURN, ALARM


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        data = read_zip_member(z, 'assets/game.droid')
        raw = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected native library SHA-256')
    if resource_names(data, b'OBJT')[142] != 'obj_player':
        raise ValueError('unexpected damage target object')
    obj = native_objects(data)['obj_boss2_ten']
    if any(obj['event_counts'][i] != 1 for i in (0, 2, 3)):
        raise ValueError('unexpected boss event inventory')
    elf = ELFFile(io.BytesIO(raw))
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True
    dyn = elf.get_section_by_name('.dynsym')
    rel = elf.get_section_by_name('.rel.dyn')
    syms = elf.get_section(rel['sh_link'])
    relocations = {r['r_offset']: (r['r_info_type'], syms.get_symbol(r['r_info_sym'])) for r in rel.iter_relocations()}
    def read(a, n):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= a and a+n <= seg['p_vaddr']+seg['p_filesz']:
                off = seg['p_offset']+a-seg['p_vaddr']
                return raw[off:off+n]
        raise ValueError('address outside ELF')
    def check(a, op, operands):
        i = list(dis.disasm(read(a, 4), a))
        if len(i) != 1 or (i[0].mnemonic, i[0].op_str) != (op, operands):
            raise ValueError(f'instruction mismatch at {a:#x}')
    def literal(a):
        i = list(dis.disasm(read(a, 4), a))
        if len(i) != 1 or i[0].mnemonic != 'ldr' or i[0].operands[1].type != ARM_OP_MEM or i[0].reg_name(i[0].operands[1].mem.base) != 'pc':
            raise ValueError('expected literal load')
        return struct.unpack('<I', read(a+8+i[0].operands[1].mem.disp, 4))[0]
    def relocation(a, typ, name):
        r = relocations.get(a)
        if r is None or r[0] != typ or r[1].name != name:
            raise ValueError(f'unexpected relocation {a:#x}')
        return r[1]
    for name, (address, size, digest) in FUNCTIONS.items():
        found = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Object_obj_boss2_ten_'+name]
        if len(found) != 1 or (found[0]['st_value'], found[0]['st_size']) != (address, size) or hashlib.sha256(read(address, size)).hexdigest() != digest:
            raise ValueError('unexpected boss export '+name)
    for a, op, operands in (
        # Source move_position starts at zero, is increased by slot 180,
        # and is subsequently compared to the slot initialized to length 35.
        (0x714f64,'mov','r1, #0xb4'), (0x714f68,'blx','r2'), (0x714f6c,'mov','r5, r0'),
        (0x714f94,'movw','r1, #0'), (0x714f98,'mov','r0, #0'),
        (0x714f9c,'movt','r1, #0x4020'), (0x714fa4,'stm','r5, {r0, r1}'),
        (0x7150ac,'movw','r1, #0x427'), (0x7150b4,'mov','r5, r0'),
        (0x7150d4,'mov','r0, #0'), (0x7150d8,'str','r0, [r5, #0xc]'),
        (0x7150dc,'str','r0, [r5, #4]'), (0x7150e0,'str','r0, [r5]'),
        # Slot 1200 starts as the binary64 0.4 (low word r7 retained from
        # the earlier alpha-speed initialization).
        (0x7155a4,'movw','r7, #0x999a'), (0x7155b4,'movt','r7, #0x9999'),
        (0x715620,'movw','r1, #0x4ad'), (0x715624,'blx','r2'), (0x715628,'mov','r5, r0'),
        (0x715648,'mov','r0, #0'), (0x71564c,'str','r0, [r5, #0xc]'),
        (0x715650,'str','r0, [r5, #4]'), (0x715654,'str','r0, [r5]'),
        (0x7156bc,'mov','r1, #0x4b0'), (0x7156c0,'blx','r2'), (0x7156c4,'mov','r5, r0'),
        (0x7156ec,'movw','r0, #0x9999'), (0x7156f0,'movt','r0, #0x3fd9'),
        (0x7156f4,'str','r0, [r5, #4]'), (0x7156fc,'str','r7, [r5]'),
        (0x71683c,'movw','r1, #0x427'), (0x716840,'blx','r2'), (0x716844,'mov','r4, r0'),
        (0x716854,'mov','r1, #0xb4'), (0x716858,'blx','r2'),
        (0x71685c,'mov','r1, r0'), (0x716860,'mov','r0, r4'), (0x716864,'bl','#0x1765b8'),
        (0x71687c,'movw','r1, #0x4a9'), (0x71689c,'mov','r1, r4'), (0x7168a0,'bl','#0x176594'),
        # Type 0 path reads slot 1200 / 2, subtracts from slot 28 on
        # native object 142, then writes it back to that object and slot.
        (0x7170b8,'movw','r1, #0x4ad'), (0x7170bc,'blx','r2'), (0x7170c0,'mov','r4, r0'),
        (0x7170c8,'bl','#0x176444'), (0x7170d4,'vcmpe.f64','d0, #0'),
        (0x7170ec,'vnegmi.f64','d0, d0'), (0x7170f0,'vcmpe.f64','d0, d1'),
        (0x7170f8,'bhi','#0x717344'), (0x717120,'mov','r1, #0x4b0'),
        (0x717124,'blx','r2'), (0x717128,'mov','r5, r0'),
        (0x717130,'mov','r0, #0x8e'), (0x717134,'mov','r1, #0x1c'),
        (0x717138,'mov','r2, #0x80000000'), (0x71713c,'bl','#0x176654'),
        (0x717140,'vmov.f64','d0, #2.000000e+00'), (0x71714c,'mov','r1, r5'),
        (0x717150,'bl','#0x176438'), (0x7172a4,'add','r0, sp, #0x2a0'),
        (0x7172a8,'bl','#0x176444'), (0x7172b8,'vsub.f64','d0, d1, d0'),
        (0x717310,'mov','r0, #0x8e'), (0x717314,'mov','r1, #0x1c'),
        (0x717318,'mov','r2, #0x80000000'), (0x71731c,'bl','#0x176480'),
        (0x715710,'movw','r1, #0x4b1'), (0x715714,'blx','r2'), (0x715718,'mov','r5, r0'),
        (0x715748,'str','r2, [r5, #0xc]'), (0x71574c,'str','r2, [r5, #4]'), (0x715750,'str','r2, [r5]'),
        (0x715744,'add','r1, pc, r1'), (0x715760,'ldr','r2, [r0, r1]!'),
        (0x715764,'ldmib','r0, {r3, r7}'), (0x715770,'stm','r1, {r2, r3, r7}'),
        (0x715778,'mov','r1, #3'), (0x71577c,'bl','#0x176954'), (0x715780,'bl','#0x176444'),
        (0x715784,'vmov.f64','d8, #5.000000e-01'), (0x71578c,'vcmpe.f64','d0, d8'),
        (0x715794,'ble','#0x71588c'), (0x7157fc,'movw','r1, #0x4b1'),
        (0x715800,'blx','r2'), (0x715804,'mov','r5, r0'), (0x71582c,'str','r6, [r5, #0xc]'),
        (0x715830,'str','r8, [r5, #4]'), (0x715834,'str','r6, [r5]'),
        (0x715550,'movw','r8, #0'), (0x715558,'movt','r8, #0x3ff0'),
        (0x715868,'movw','r1, #0'), (0x71586c,'movt','r1, #0x4034'),
        (0x715870,'str','r1, [sp, #0x5c]'), (0x715878,'str','r6, [sp, #0x58]'),
        (0x715880,'mov','r0, r4'), (0x715884,'mov','r2, #0'), (0x715888,'bl','#0x1768dc'),
        (0x71589c,'add','r0, pc, r0'), (0x7158a4,'ldr','r2, [r1, r0]!'),
        (0x7158ac,'ldmib','r1, {r3, r7}'), (0x7158b0,'ldr','r6, [r1, #0xc]'),
        (0x7158b4,'ldr','r1, [r1, #0x10]'), (0x7158b8,'str','r1, [sp, #0x28]'),
        (0x7158bc,'str','r6, [sp, #0x24]'), (0x7158c0,'stm','r5, {r2, r3, r7}'),
        (0x7158c8,'mov','r1, #5'), (0x7158cc,'bl','#0x176954'), (0x7158d0,'bl','#0x176444'),
        (0x7158d8,'vcmpe.f64','d0, d8'), (0x7158e0,'ble','#0x715984'),
        (0x715948,'mov','r1, #0xb4'), (0x71594c,'blx','r2'), (0x715950,'mov','r4, r0'),
        (0x715970,'movw','r1, #0'), (0x715974,'mov','r0, #0'),
        (0x715978,'movt','r1, #0x4022'), (0x71597c,'str','r0, [r4, #0xc]'),
        (0x715980,'stm','r4, {r0, r1}'),
        # Source's body_angle_max is 18 at create; in Step it is assigned to
        # the turn delta, which is zeroed before the angle comparisons.
        (0x71505c,'movw','r1, #0x4aa'), (0x715084,'movw','r1, #0'),
        (0x71508c,'movt','r1, #0x4032'), (0x715094,'stm','r5, {r0, r1}'),
        (0x7187c4,'mov','r1, #0x440'), (0x7187c8,'blx','r2'),
        (0x7187cc,'mov','r6, r0'), (0x7187fc,'str','r1, [r6, #0xc]'),
        (0x718800,'str','r1, [r6, #4]'), (0x718808,'str','r1, [r6]'),
        (0x7189b0,'movw','r1, #0x4aa'), (0x7189c8,'mov','r1, #0x440'),
        (0x7189d0,'mov','r1, r4'), (0x7189d4,'bl','#0x176558'),
        (0x718f74,'movw','r1, #0x4b1'), (0x718f78,'blx','r2'),
        (0x718f7c,'bl','#0x176444'), (0x718f80,'vmov.f64','d1, #5.000000e-01'),
        (0x718f88,'vcmpe.f64','d0, d1'), (0x718f90,'ble','#0x7190b4'),
        (0x718fa8,'mov','r1, #0x440'), (0x718fac,'blx','r2'),
        (0x718fb4,'movw','r1, #0'), (0x718fb8,'mov','r0, #0'),
        (0x718fbc,'movt','r1, #0xbff0'), (0x71905c,'vmul.f64','d0, d0, d1'),
        (0x71906c,'stm','r4, {r0, r1}'),
        (0x715b4c,'movw','r1, #0x4b1'), (0x715b50,'blx','r2'),
        (0x715b54,'mov','r4, r0'), (0x715b80,'mov','r1, #0'),
        (0x715b84,'str','r1, [r4, #0xc]'), (0x715b8c,'str','r1, [r4, #4]'),
        (0x715b90,'str','r1, [r4]')):
        check(a, op, operands)
    for a in range(0x7155b8, 0x7156fc, 4):
        for inst in dis.disasm(read(a, 4), a):
            _, writes = inst.regs_access()
            if any(inst.reg_name(reg) == 'r7' for reg in writes):
                raise ValueError('damage initializer low word overwritten')
    # choose's relocated pointer array refers to real RValues [1,0,0].
    table = (0x715744+8+literal(0x715738)+literal(0x715740)) & 0xffffffff
    if table != 0xb7bd28:
        raise ValueError('unexpected choose table address')
    one = relocation(table, 2, 'gs_constArg0_963')
    zero1 = relocation(table+4, 2, 'gs_constArg1_963')
    zero2 = relocation(table+8, 2, 'gs_constArg1_963')
    if one['st_size'] != 16 or read(one['st_value'], 16) != struct.pack('<dII', 1.0, 0, 0):
        raise ValueError('unexpected choose one')
    if zero1['st_value'] != zero2['st_value'] or zero1['st_size'] != 16 or elf.get_section(zero1['st_shndx'])['sh_type'] != 'SHT_NOBITS':
        raise ValueError('unexpected choose zeros')
    speed_table = (0x71589c+8+literal(0x71588c)+literal(0x715894)) & 0xffffffff
    if speed_table != 0xb7bd34:
        raise ValueError('unexpected speed choose table address')
    for i in range(5):
        relocation(speed_table+4*i, 2, 'gs_constArg0_963' if i == 0 else 'gs_constArg1_963')
    alarm = (0x71585c+8+literal(0x715854)+literal(0x715858)) & 0xffffffff
    relocation(alarm, 21, 'g_VAR_alarm')
    rp, plt = elf.get_section_by_name('.rel.plt'), elf.get_section_by_name('.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr']+20+i*12: ps.get_symbol(r['r_info_sym']).name for i,r in enumerate(rp.iter_relocations())}
    for addr, name in ((0x176954, 'YYGML_choose'), (0x1768dc, 'Variable_SetValue_Direct'),
                       (0x176444, 'REAL_RValue'), (0x1765b8, 'YYRValuepLERKS_'),
                       (0x176438, '_ZdvRK8YYRValued'), (0x176654, 'YYGML_Variable_GetValue'),
                       (0x176480, 'YYGML_Variable_SetValue')):
        if name not in calls.get(addr, ''):
            raise ValueError('unexpected native call')
    return {'object': 'obj_boss2_ten', 'flag_slot': 1201, 'turn_slot': 1088,
            'choose_values': [1, 0, 0], 'alarm': 0, 'alarm_steps': 20,
            'speed_slot': 180, 'speed_initial': 8, 'speed_choose_values': [1, 0, 0, 0, 0], 'speed_if_chosen': 9,
            'damage_slot': 1200, 'damage_initial': 0.4, 'target_object': 'obj_player', 'target_slot': 28,
            'functions': {name: {'address': hex(row[0]), 'size': row[1], 'sha256': row[2]} for name, row in FUNCTIONS.items()},
            'limitations': 'Partial static ARM evidence and source matching only; variable names inferred, remaining Create/Step behavior, RNG, scheduler, gameplay and iOS unverified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    fragments(a.project)
    a.output.write_text(json.dumps(inspect(a.apk), indent=2)+'\n', encoding='utf-8')
    print('BOSS2_TURN_EVIDENCE: partial static ARM candidate only')


if __name__ == '__main__':
    main()
