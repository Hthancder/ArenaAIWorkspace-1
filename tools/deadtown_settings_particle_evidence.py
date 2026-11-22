#!/usr/bin/env python3
"""Verify partial settings persistence and particle gating from Android ARM32.

Names prefixed __dt are invented aliases. This verifies only selected native
instructions/strings and source fragments, not full scripts or gameplay.
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
    from tools.deadtown_native_inventory import exported_name, project_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, project_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

# section, key, alias, native slot, load temporary pointer, load GOT addresses,
# load call, new-setting write, save temporary pointer
SETTINGS = (
    ('feedback', 'feedback', 'feedback', 0x52, 0x50, 0x2ecaf0, 0x2ecb04, 0x2ecb08, 0x2ecaf8, 0x2ecb38, 0x2ed2f8, 0x40),
    ('effect', 'interpolate', 'interpolate', 0x53, 0x4c, 0x2ecb64, 0x2ecb78, 0x2ecb7c, 0x2ecb6c, 0x2ecbac, 0x2ed334, 0x20),
    ('effect', 'soundeffect', 'soundeffect', 0x54, 0x48, 0x2ecbd8, 0x2ecbec, 0x2ecbf0, 0x2ecbe0, 0x2ecc20, 0x2ed368, 0x24),
    ('effect', 'crosshair', 'crosshair', 0x55, 0x44, 0x2ecc4c, 0x2ecc60, 0x2ecc64, 0x2ecc54, 0x2ecc94, 0x2ed3a4, 0x28),
    ('effect', 'shadow', 'shadow', 0x56, 0x40, 0x2eccc0, 0x2eccd4, 0x2eccd8, 0x2eccc8, 0x2ecd08, 0x2ed3d8, 0x10),
    ('left', 'finger', 'finger', 0x57, 0x3c, 0x2ecd34, 0x2ecd48, 0x2ecd4c, 0x2ecd3c, 0x2ecd7c, 0x2ed414, 0x14),
    ('effect', 'particle', 'particle', 0x31, 0x38, 0x2ecda8, 0x2ecdbc, 0x2ecdb8, 0x2ecdb0, 0x2ecdf0, 0x2ed448, 0x18),
)
# address, size, SHA256, slot-get address, gate real-conversion address, false branch target, pointer register
PARTICLES = {
    'particle_burst': (0x1cc4a0, 2176, '6172ef12a6007730e5d0e85e6a903f91c9f7180197dd3f36e0cba36f70b48170', 0x1cc530, 0x1cc5bc, 0x1cc97c, 'r7'),
    'particle_burst_up': (0x1ccd20, 2176, '48c8dda474db91d6eda417c7811768a490732e93c616a53986fa0195e54ce0ae', 0x1ccdb0, 0x1cce3c, 0x1cd1fc, 'r7'),
    'particle_burst_up_size': (0x1cd5a0, 2468, '5b3e478d11de58889360fa4267d66aac8569251ac88d19e11210cf272a9aaed3', 0x1cd638, 0x1cd6dc, 0x1cdb44, 'r7'),
    'particle_burst_up_out': (0x1cdf44, 2352, '01b6ec149bb41d801871a822a38599d03d96184c0e3aa2ade05297c1927aff11', 0x1cdfd4, 0x1ce060, 0x1ce4c0, 'r4'),
}
GATE = '// Partial candidate: native global slot 49 controls particle emission.\nif (global.__dt_setting_particle > 0.5)\n{\n'
PLAYER_FEEDBACK = '''/// feedback
// Partial native candidate: slot 82 enables feedback; a connected gamepad suppresses it.
if (global.__dt_setting_feedback > 0.5)
{
    if (gp_connect_check() <= 0.5)
    {
        if 0.01<sys_view.left_distance_ratio
        {
            fx = x+lengthdir_x(sys_view.left_distance_ratio*100,sys_view.view_a+sys_view.left_direction)
            fy = y+lengthdir_y(sys_view.left_distance_ratio*100,sys_view.view_a+sys_view.left_direction)
            draw_sprite_ext(spr_player_move,0,fx,fy,0.8,0.8,sys_view.view_a+sys_view.left_direction-90,c_white,0.5)
        }
    }
}
'''
PLAYER_SHADOW = '''    // Partial native candidate: global slot 86 gates both player shadow branches.
    if (global.__dt_setting_shadow > 0.5)
    {
        if (weapon_kind == 3) and (weapon_launched == 1)
        {
            draw_sprite_ext(player_sprite,player_costume,xx,yy,global.char_aspect,global.char_aspect,player_near_angle,c_black,0.5) // shadow
        }
        else
        {
            draw_sprite_ext(player_sprite,player_costume,xx,yy,global.char_aspect,global.char_aspect,player_gun_angle,c_black,0.5) // shadow
        }
    }'''
ROOF_SHADOW = ('// Partial native candidate: global slot 86 gates this roof shadow.\n'
               'if (global.__dt_setting_shadow > 0.5)\n{\n'
               '    draw_sprite_ext(roof_sprite,0,xx,yy,image_xscale,image_yscale,image_angle,c_black,0.3*roof_alpha)\n'
               '}')
SHADOW_OBJECTS = {
    'par_solid': (0x39ec20, '680aab026db2e55a4b7f4797aa5e8c426f53f1cdb4520be58f74720d121ae76d'),
    'par_vehicle': (0x5f8894, '94f9ff7a157e20efb6fc7ff4af3ffd40872ef64d8755af25e435ddd9a7bbf9b1'),
    'obj_parcel': (0x62fb60, '0826af5c78b0bc109791e1d66b0bf6627c002d702b422701490f8205da076bef'),
}
ACTION_SHADOW_OBJECTS = {
    'par_action': (0x6b2f9c, 'fa8ee3fc857a11914993a0ecd47a0246b9a353f598ac03c7bbbda07bf25ece47'),
    'par_action_move': (0x6b41a4, 'abb8245fd4b4a6ffa095b860cc7779f3bb96aa1343ed35d791407ea6b441b2c6'),
    'par_action_door': (0x6b53ac, 'cbcbae342a5b23ca3215c024bef834a07d512c4d8700b00ea13bf71d7041ca0c'),
}
ACTION_SHADOW = ('// Partial native candidate: global slot 86 gates this shadow draw.\n'
                 'if (global.__dt_setting_shadow > 0.5)\n{\n'
                 '    draw_sprite_ext(sprite_index,image_index,xx+shake_x,yy+shake_y,image_xscale,image_yscale,image_angle,c_black,0.5)\n'
                 '}')
SHADOW = ('// Partial native candidate: global slot 86 gates this shadow draw.\n'
          'if (global.__dt_setting_shadow > 0.5)\n{\n'
          '    draw_sprite_ext(sprite_index,image_index,xx,yy,image_xscale,image_yscale,image_angle,c_black,0.5)\n'
          '}\ndraw_self()')


def shadow_source(project, name):
    root = ET.parse(Path(project) / 'objects' / (name+'.object.gmx')).getroot()
    events = root.findall('./events/event[@eventtype="8"][@enumb="0"]')
    if len(events) != 1:
        raise ValueError('expected one Draw event: '+name)
    strings = events[0].findall('./action/arguments/argument/string')
    fragment = ROOF_SHADOW if name == 'par_building' else (ACTION_SHADOW if name in ACTION_SHADOW_OBJECTS else SHADOW)
    if len(strings) != 1 or (strings[0].text or '').count(fragment) != 1:
        raise ValueError('unexpected shadow gate: '+name)
    return strings[0].text


def verify_source(project):
    p = Path(project)
    load = (p / 'scripts/setting_load.gml').read_text(encoding='utf-8')
    save = (p / 'scripts/setting_save.gml').read_text(encoding='utf-8')
    marker = load.index('else // new')
    for section, key, alias, *_ in SETTINGS:
        read = f'global.__dt_setting_{alias} = ini_read_real("{section}","{key}",1)'
        new = f'global.__dt_setting_{alias} = 1'
        write = f'ini_write_real("{section}","{key}",global.__dt_setting_{alias})'
        if load.count(read) != 1 or load.count(new) != 1 or save.count(write) != 1:
            raise ValueError('missing/changed settings candidate: '+alias)
        if not load.index(read) < marker < load.index(new):
            raise ValueError('wrong setting branch: '+alias)
    declared = project_names(p, 'scripts', 'script')
    for name in PARTICLES:
        text = (p / 'scripts' / (name+'.gml')).read_text(encoding='utf-8')
        if name not in declared or text.count(GATE) != 1:
            raise ValueError('missing particle gate: '+name)
        before, body = text.split(GATE)
        if 'part_' in before or text.count('{') != 1 or text.count('}') != 1 or not body.rstrip().endswith('}'):
            raise ValueError('unexpected particle gate structure: '+name)
        for call in ('part_emitter_region(', 'part_type_direction(', 'part_emitter_burst('):
            if body.count(call) != 1:
                raise ValueError('missing particle call: '+name)
        if body.count('part_type_size(') != int(name.endswith('_size')) or body.count('part_type_orientation(') != int(name.endswith('_out')):
            raise ValueError('unexpected particle operation: '+name)
    for name in (*SHADOW_OBJECTS, *ACTION_SHADOW_OBJECTS, 'par_building'):
        text = shadow_source(p, name)
        if name == 'par_building':
            remaining = text.split(ROOF_SHADOW)[1]
            if 'draw_sprite_ext(mask_index,0,x,y,image_xscale,image_yscale,image_angle,c_white,1)' not in remaining or 'draw_sprite_ext(roof_sprite,0,x,y,image_xscale,image_yscale,image_angle,roof_color,roof_alpha)' not in remaining:
                raise ValueError('building foreground calls missing')
    player = ET.parse(p/'objects'/'obj_player.object.gmx').getroot()
    actions = player.findall('./events/event[@eventtype="8"][@enumb="0"]/action/arguments/argument/string')
    if len(actions) != 3 or (actions[2].text or '').count(PLAYER_SHADOW) != 1 or 'draw_sprite_ext(spr_player_foot_right' not in (actions[2].text or '').split(PLAYER_SHADOW)[1]:
        raise ValueError('unexpected player shadow fragment')
    if (actions[1].text or '').strip() != PLAYER_FEEDBACK.strip():
        raise ValueError('unexpected player feedback fragment')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        raw = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    dyn = elf.get_section_by_name('.dynsym')
    rel = elf.get_section_by_name('.rel.dyn')
    syms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: syms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations() if r['r_info_type'] == 21}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(a, n):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= a and a+n <= seg['p_vaddr']+seg['p_filesz']:
                off = seg['p_offset'] + a - seg['p_vaddr']
                return raw[off:off+n]
        raise ValueError('address outside ELF')

    def check(a, op, arg):
        instructions = list(dis.disasm(read(a, 4), a))
        if len(instructions) != 1 or (instructions[0].mnemonic, instructions[0].op_str) != (op, arg):
            raise ValueError(f'instruction mismatch at {a:#x}')

    def lit(a):
        instructions = list(dis.disasm(read(a, 4), a))
        if len(instructions) != 1:
            raise ValueError('instruction decoding failed')
        i = instructions[0]
        if i.mnemonic != 'ldr' or len(i.operands) != 2 or i.operands[1].type != ARM_OP_MEM or i.reg_name(i.operands[1].mem.base) != 'pc':
            raise ValueError('expected pc-relative literal')
        return struct.unpack('<I', read(a+8+i.operands[1].mem.disp, 4))[0]

    def sym(base, add, off):
        address = (add + 8 + lit(base) + lit(off)) & 0xffffffff
        result = got.get(address)
        if result is None:
            raise ValueError(f'missing GOT symbol at {address:#x}')
        return result

    def payload(s):
        section = elf.get_section(s['st_shndx'])
        offset = s['st_value'] - section['sh_addr']
        if section['sh_type'] == 'SHT_NOBITS' or offset < 0 or offset+s['st_size'] > section['sh_size']:
            raise ValueError('invalid symbol data')
        return section.data()[offset:offset+s['st_size']]

    fixed = {
        'setting_load': (0x2ec430, 7344, '6dd19e3c8f09a8db1413aa916bfceeedd1a463ca7b22640812929a6eccf48a36'),
        'setting_save': (0x2ee0e0, 2232, '5bf074aad1be0f4566ac777b183062604481ca23f797c6d5287d4e3bef00f7f5'),
    }
    fixed.update({name: row[:3] for name, row in PARTICLES.items()})
    for name, (start, size, digest) in fixed.items():
        exports = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Script_'+name]
        if len(exports) != 1 or (exports[0]['st_value'], exports[0]['st_size']) != (start, size) or hashlib.sha256(read(start, size)).hexdigest() != digest:
            raise ValueError('unexpected export or bytes: '+name)
    if sym(0x2ec444, 0x2ec450, 0x2ec448).name != 'g_pGlobal' or sym(0x2ee0f4, 0x2ee0fc, 0x2ee0ec).name != 'g_pGlobal':
        raise ValueError('unexpected global pointer')
    check(0x2ec98c, 'vmov.f64', 'd1, #1.000000e+00')
    check(0x2ec9b0, 'vmov', 'r6, r4, d1')
    check(0x2ed238, 'movw', 'r8, #0')
    check(0x2ed240, 'movt', 'r8, #0x3ff0')
    for i, (section, key, alias, slot, loadptr, base, add, s_off, k_off, call, new, saveptr) in enumerate(SETTINGS):
        # The global handle is retrieved in each function prologue and retained.
        get_load = 0x2ec5b0 + 0x24*i if i < 6 else 0x2ec688
        get_save = 0x2ee258 + 0x24*i if i < 6 else 0x2ee330
        check(get_load, 'mov', f'r1, #{hex(slot)}')
        check(get_load+4, 'blx', 'r2')
        check(get_load+8, 'str', f'r0, [sp, #{hex(loadptr)}]')
        check(get_save, 'mov', f'r1, #{hex(slot)}')
        check(get_save+4, 'blx', 'r2')
        check(get_save+8, 'str', f'r0, [sp, #{hex(saveptr)}]')
        for off, expected in ((s_off, section), (k_off, key)):
            s = sym(base, add, off)
            if not s.name.startswith('g_pString') or payload(s) != expected.encode()+b'\0':
                raise ValueError('unexpected read INI key '+alias)
        check(call-8, 'mov', 'r2, r6')
        check(call-4, 'mov', 'r3, r4')
        check(call, 'bl', '#0x176828')
        check(call+12, 'ldr', f'r0, [sp, #{hex(loadptr)}]')
        # In the normal branch the returned real is written to this slot.
        destreg = 'r6' if alias == 'particle' else 'r5'
        offset = 0x44 if alias in ('finger', 'particle') else 0x3c
        check(call+offset, 'ldr', f'{destreg}, [sp, #{hex(loadptr)}]')
        check(call+0x64, 'stm', f'{destreg}, {{r3, r7}}')
        check(new, 'ldr', f'r0, [sp, #{hex(loadptr)}]')
        # Two of the new-path sequences reload zero before writing the same real 1.
        lines = list(dis.disasm(read(new, 24), new))
        writes = [(x.mnemonic, x.op_str) for x in lines]
        for required in [('str', 'r4, [r0, #0xc]'), ('str', 'r8, [r0, #4]'), ('str', 'r4, [r0]')]:
            if required not in writes:
                raise ValueError('unexpected new-setting write: '+alias)
        savebase = 0x2ee588 + i*0x34
        for off, expected in ((savebase+4, section), (savebase+8, key)):
            s = sym(savebase, savebase+12, off)
            if not s.name.startswith('g_pString') or payload(s) != expected.encode()+b'\0':
                raise ValueError('unexpected write INI key '+alias)
        check(savebase-0xc, 'ldr', f'r0, [sp, #{hex(saveptr)}]')
        check(savebase-8, 'bl', '#0x176444')
        check(savebase+0x1c, 'bl', '#0x17681c')
    for name, (start, _, _, get, gate, target, reg) in PARTICLES.items():
        if sym(start+0xc, start+0x18, start+0x1c).name != 'g_pGlobal':
            raise ValueError('particle gate did not read global')
        check(get-8, 'ldr', 'r1, [r0]')
        check(get-4, 'ldr', 'r2, [r1, #8]')
        check(get, 'mov', 'r1, #0x31')
        check(get+4, 'blx', 'r2')
        check(get+8, 'mov', f'{reg}, r0')
        for instruction in dis.disasm(read(get+12, gate-(get+12)), get+12):
            _, writes = instruction.regs_access()
            if reg in (instruction.reg_name(r) for r in writes):
                raise ValueError('particle gate pointer overwritten: '+name)
        for off, op, arg in ((0, 'mov', f'r0, {reg}'), (4, 'bl', '#0x176444'),
                             (8, 'vmov.f64', 'd1, #5.000000e-01'), (12, 'vmov', 'd0, r0, r1'),
                             (16, 'vcmpe.f64', 'd0, d1'), (20, 'vmrs', 'apsr_nzcv, fpscr'),
                             (24, 'ble', '#'+hex(target))):
            check(gate+off, op, arg)
    rp, plt = elf.get_section_by_name('.rel.plt'), elf.get_section_by_name('.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name for i, r in enumerate(rp.iter_relocations())}
    for addr, name in ((0x176444, 'REAL_RValue'), (0x176738, 'YYGML_draw_sprite_ext'), (0x176990, 'YYGML_draw_self')):
        if name not in calls.get(addr, ''):
            raise ValueError('unexpected draw call relocation')
    for name, (start, digest) in SHADOW_OBJECTS.items():
        target = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Object_'+name+'_Draw_0']
        if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, 3932) or hashlib.sha256(read(start, 3932)).hexdigest() != digest:
            raise ValueError('unexpected Draw bytes: '+name)
        if sym(start+0x10, start+0x20, start+0x14).name != 'g_pGlobal':
            raise ValueError('unexpected Draw global pointer: '+name)
        checks = {
            0x38: ('ldr', 'r0, [r1, r0]'), 0x44: ('ldr', 'r0, [r0]'),
            0x74: ('ldr', 'r1, [r0]'), 0x78: ('ldr', 'r2, [r1, #8]'),
            0x7c: ('mov', 'r1, #0x56'), 0x80: ('blx', 'r2'),
            0x84: ('str', 'r0, [sp, #0x34]'), 0x7c4: ('ldr', 'r0, [sp, #0x34]'),
            0x7c8: ('bl', '#0x176444'), 0x7cc: ('vmov.f64', 'd1, #5.000000e-01'),
            0x7d0: ('vmov', 'd0, r0, r1'), 0x7d4: ('vcmpe.f64', 'd0, d1'),
            0x7d8: ('vmrs', 'apsr_nzcv, fpscr'), 0x7dc: ('ble', '#'+hex(start+0x9bc)),
            0x990: ('mov', 'r1, #0'), 0x994: ('mov', 'r0, #0x3f000000'),
            0x998: ('str', 'r1, [sp, #0x10]'), 0x9a0: ('str', 'r0, [sp, #0x14]'),
            0x9b8: ('bl', '#0x176738'), 0x9c4: ('mov', 'r0, sb'), 0x9c8: ('bl', '#0x176990'),
        }
        for off, (op, args) in checks.items():
            check(start+off, op, args)
        # The retained global pointer must not be overwritten before the gate.
        for instruction in dis.disasm(read(start+0x88, 0x7c4-0x88), start+0x88):
            if instruction.mnemonic.startswith(('str', 'stm')) and '[sp, #0x34]' in instruction.op_str:
                raise ValueError('shadow global pointer overwritten: '+name)
    for name, (start, digest) in ACTION_SHADOW_OBJECTS.items():
        target = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Object_'+name+'_Draw_0']
        if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, 4616) or hashlib.sha256(read(start, 4616)).hexdigest() != digest:
            raise ValueError('unexpected action Draw bytes: '+name)
        if sym(start+0x10, start+0x20, start+0x14).name != 'g_pGlobal':
            raise ValueError('unexpected action Draw global pointer: '+name)
        checks = {
            0x38: ('ldr', 'r0, [r1, r0]'), 0x44: ('ldr', 'r0, [r0]'),
            0x74: ('ldr', 'r1, [r0]'), 0x78: ('ldr', 'r2, [r1, #8]'),
            0x7c: ('mov', 'r1, #0x56'), 0x80: ('blx', 'r2'),
            0x84: ('str', 'r0, [sp, #0x34]'), 0x144: ('vmov.f64', 'd8, #5.000000e-01'),
            0x930: ('ldr', 'r0, [sp, #0x34]'), 0x934: ('bl', '#0x176444'),
            0x938: ('vmov', 'd0, r0, r1'), 0x93c: ('vcmpe.f64', 'd0, d8'),
            0x940: ('vmrs', 'apsr_nzcv, fpscr'), 0x944: ('ble', '#'+hex(start+0xbc4)),
            0xb54: ('mov', 'r1, #0'), 0xb58: ('mov', 'r0, #0x3f000000'),
            0xb5c: ('str', 'r1, [sp, #0x10]'), 0xb64: ('str', 'r0, [sp, #0x14]'),
            0xb7c: ('bl', '#0x176738'),
        }
        for off, (op, args) in checks.items():
            check(start+off, op, args)
        for instruction in dis.disasm(read(start+0x88, 0x930-0x88), start+0x88):
            _, writes = instruction.regs_access()
            if instruction.address > start+0x144 and 'd8' in (instruction.reg_name(r) for r in writes):
                raise ValueError('action threshold overwritten: '+name)
            if instruction.mnemonic.startswith(('str', 'stm')) and '[sp, #0x34]' in instruction.op_str:
                raise ValueError('action shadow pointer overwritten: '+name)
    start = 0x3936e0
    target = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Object_par_building_Draw_0']
    if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, 4952) or hashlib.sha256(read(start, 4952)).hexdigest() != '9bb63888bd5e63c006e5238daabbd08185b25a8ee9e6f154f7313589b965dcb7':
        raise ValueError('unexpected building Draw bytes')
    if sym(start+0x10, start+0x20, start+0x14).name != 'g_pGlobal':
        raise ValueError('unexpected building global pointer')
    checks = {
        0x38: ('ldr', 'r0, [r1, r0]'), 0x44: ('ldr', 'r0, [r0]'),
        0x74: ('ldr', 'r1, [r0]'), 0x78: ('ldr', 'r2, [r1, #8]'),
        0x7c: ('mov', 'r1, #0x56'), 0x80: ('blx', 'r2'), 0x84: ('str', 'r0, [sp, #0x40]'),
        0x7d0: ('ldr', 'r0, [sp, #0x40]'), 0x7d4: ('bl', '#0x176444'),
        0x7d8: ('vmov.f64', 'd1, #5.000000e-01'), 0x7dc: ('vmov', 'd0, r0, r1'),
        0x7e0: ('vcmpe.f64', 'd0, d1'), 0x7e4: ('vmrs', 'apsr_nzcv, fpscr'),
        0x7e8: ('ble', '#'+hex(start+0x9f4)), 0x9a4: ('mov', 'r0, #0'),
        0x9ac: ('str', 'r0, [sp, #0x10]'), 0x9cc: ('bl', '#0x176738'),
        0xb98: ('bl', '#0x176738'), 0xdac: ('bl', '#0x176738'),
    }
    for off, (op, args) in checks.items():
        check(start+off, op, args)
    for instruction in dis.disasm(read(start+0x88, 0x7d0-0x88), start+0x88):
        if instruction.mnemonic.startswith(('str', 'stm')) and '[sp, #0x40]' in instruction.op_str:
            raise ValueError('building shadow pointer overwritten')
    start = 0x5db2d8
    target = [s for s in dyn.iter_symbols() if exported_name(s.name) == 'gml_Object_obj_player_Draw_0']
    player_hash = 'd751b67200bf3e14b4c27ed06090d479f81d97824880af8acdd5633363177fbe'
    if len(target) != 1 or (target[0]['st_value'], target[0]['st_size']) != (start, 11820) or hashlib.sha256(read(start, 11820)).hexdigest() != player_hash:
        raise ValueError('unexpected player Draw bytes')
    if sym(start+0x10, start+0x88, start+0x84).name != 'g_pGlobal' or sym(start+0xc, start+0x1c, start+0x10).name != 'g_pGlobal':
        raise ValueError('unexpected player global pointer')
    if 'gml_Script_gp_connect_check' not in calls.get(0x176e28, ''):
        raise ValueError('unexpected feedback gamepad call')
    checks = {
        0x30: ('ldr', 'r0, [r4, r0]'), 0x40: ('ldr', 'r0, [r0]'),
        0x70: ('ldr', 'r1, [r0]'), 0x74: ('ldr', 'r2, [r1, #8]'),
        0x78: ('mov', 'r1, #0x52'), 0x7c: ('blx', 'r2'), 0x80: ('mov', 'r6, r0'),
        0x1c0: ('str', 'r6, [sp, #0x2c]'), 0x3e8: ('ldr', 'r6, [sp, #0x2c]'),
        0x3f4: ('mov', 'r0, r6'), 0x3f8: ('bl', '#0x176444'),
        0x400: ('vmov', 'd0, r0, r1'), 0x404: ('vcmpe.f64', 'd0, d8'),
        0x408: ('vmrs', 'apsr_nzcv, fpscr'), 0x40c: ('ble', '#0x5dbbe4'),
        0x43c: ('bl', '#0x176e28'), 0x440: ('bl', '#0x176444'),
        0x444: ('vmov', 'd0, r0, r1'), 0x448: ('vcmpe.f64', 'd0, d8'),
        0x44c: ('vmrs', 'apsr_nzcv, fpscr'), 0x450: ('bgt', '#0x5dbbe4'),
        0x558: ('bpl', '#0x5dbbc8'), 0x86c: ('bl', '#0x176738'),
        0x90: ('ldr', 'r0, [r0]'), 0x94: ('ldr', 'r1, [r0]'),
        0x98: ('ldr', 'r2, [r1, #8]'), 0x9c: ('mov', 'r1, #0x56'),
        0xa0: ('blx', 'r2'), 0xa4: ('str', 'r0, [sp, #0x30]'),
        0x3fc: ('vmov.f64', 'd8, #5.000000e-01'), 0xef0: ('ldr', 'r0, [sp, #0x30]'),
        0xef4: ('bl', '#0x176444'), 0xef8: ('vmov', 'd0, r0, r1'),
        0xefc: ('vcmpe.f64', 'd0, d8'), 0xf00: ('vmrs', 'apsr_nzcv, fpscr'),
        0xf04: ('ble', '#'+hex(start+0x12e0)), 0x1120: ('bl', '#0x176738'),
        0x12dc: ('bl', '#0x176738'),
    }
    for off, (op, args) in checks.items():
        check(start+off, op, args)
    for instruction in dis.disasm(read(start+0x84, 0x1c0-0x84), start+0x84):
        _, writes = instruction.regs_access()
        if 'r6' in (instruction.reg_name(r) for r in writes):
            raise ValueError('player feedback pointer register overwritten')
    for instruction in dis.disasm(read(start+0x1c4, 0x3e8-0x1c4), start+0x1c4):
        if instruction.mnemonic.startswith(('str', 'stm')) and '[sp, #0x2c]' in instruction.op_str:
            raise ValueError('player feedback pointer stack slot overwritten')
    for instruction in dis.disasm(read(start+0xa8, 0xef0-0xa8), start+0xa8):
        _, writes = instruction.regs_access()
        if instruction.address > start+0x3fc and 'd8' in (instruction.reg_name(r) for r in writes):
            raise ValueError('player threshold overwritten')
        if instruction.mnemonic.startswith(('str', 'stm')) and '[sp, #0x30]' in instruction.op_str:
            raise ValueError('player shadow pointer overwritten')
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'settings': [{'section': x[0], 'key': x[1], 'alias': '__dt_setting_'+x[2], 'native_slot': x[3], 'default': 1} for x in SETTINGS],
            'particle_gates': {name: {'address': hex(v[0]), 'sha256': v[2], 'slot': 49} for name, v in PARTICLES.items()},
            'feedback_gate': {'event': 'obj_player:Draw:0', 'address': hex(start), 'slot': 82, 'gamepad_check': 'gp_connect_check', 'sha256': player_hash},
            'shadow_gates': {name: {'address': hex(v[0]), 'sha256': v[1], 'slot': 86} for name, v in {**SHADOW_OBJECTS, **ACTION_SHADOW_OBJECTS, 'par_building': (0x3936e0, '9bb63888bd5e63c006e5238daabbd08185b25a8ee9e6f154f7313589b965dcb7'), 'obj_player': (start, player_hash)}.items()},
            'limitations': 'Static ARM32 and partial source only; original names, full particle functions, non-finite values, GameMaker compiler, actual display/settings UI, gameplay and iOS unverified.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk', type=Path)
    p.add_argument('project', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    verify_source(a.project)
    a.output.write_text(json.dumps(inspect(a.apk), indent=2)+'\n', encoding='utf-8')
    print('SETTINGS_PARTICLE_EVIDENCE: partial static ARM32 candidates only')


if __name__ == '__main__':
    main()
