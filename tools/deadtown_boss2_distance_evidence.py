#!/usr/bin/env python3
"""Check a partial boss 2 End Step distance candidate against pinned ARM32.

No player-existence guard is inferred. This is not native execution or gameplay
proof; comparisons near the epsilon boundary and missing-player cases may differ.
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
    from tools.deadtown_empty_collision_evidence import elf_file_bytes
    from tools.deadtown_native_inventory import exported_name, project_names, resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.deadtown_room_evidence import checked, nested_pointers
    from tools.recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32
except ModuleNotFoundError:
    from deadtown_empty_collision_evidence import elf_file_bytes
    from deadtown_native_inventory import exported_name, project_names, resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from deadtown_room_evidence import checked, nested_pointers
    from recover_deadtown_audio import chunks, pointers, read_string, read_zip_member, u32

CANDIDATE = '''/// Partial Android ARM candidate: remove a boss far from the player.
if (point_distance(x,y,obj_player.x,obj_player.y) > 8000)
{
    instance_destroy()
}
'''
START = 0x712520
SIZE = 944
SHA256 = '5cb41934adc50a2fa3c5578a0211b45922d812c078c2b09db5274a8625d200a5'


def verify_source(project):
    project = Path(project)
    if not {'obj_boss2', 'obj_player'} <= project_names(project, 'objects', 'object'):
        raise ValueError('required objects not declared')
    root = ET.parse(project/'objects/obj_boss2.object.gmx').getroot()
    events = root.findall('./events/event[@eventtype="3"][@enumb="2"]')
    if len(events) != 1 or len(events[0].findall('action')) != 1:
        raise ValueError('unexpected End Step event')
    action = events[0].find('action')
    if (action.findtext('libid'), action.findtext('id'), action.findtext('kind'),
        action.findtext('./arguments/argument/string')) != ('1', '603', '7', CANDIDATE):
        raise ValueError('unexpected End Step source')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        lib = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
        game = read_zip_member(z, 'assets/game.droid')
    if hashlib.sha256(lib).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected native library SHA-256')
    if resource_names(game, b'OBJT')[142] != 'obj_player':
        raise ValueError('unexpected player object ID')
    regions = chunks(game)
    region = regions[b'OBJT']
    objects = [p for p in pointers(game, region) if read_string(game, u32(game, p), regions[b'STRG']) == 'obj_boss2']
    if len(objects) != 1:
        raise ValueError('unexpected boss object')
    pos = objects[0]
    checked(game, pos, 80, region)
    ev = pos + 80 + 8 * u32(game, pos+64)
    checked(game, ev, 4 + 12*4, region)
    if u32(game, ev) != 12:
        raise ValueError('unexpected event type count')
    steps = nested_pointers(game, u32(game, ev+4+3*4), region, 8)
    if len([p for p in steps if u32(game, p) == 2]) != 1:
        raise ValueError('native End Step missing or duplicated')
    elf = ELFFile(io.BytesIO(lib))
    exports = [s for s in elf.get_section_by_name('.dynsym').iter_symbols()
               if exported_name(s.name) == 'gml_Object_obj_boss2_Step_2']
    if len(exports) != 1 or (exports[0]['st_value'], exports[0]['st_size']) != (START, SIZE):
        raise ValueError('unexpected native export')
    if hashlib.sha256(elf_file_bytes(lib, START, SIZE)).hexdigest() != SHA256:
        raise ValueError('unexpected native function bytes')
    rel = elf.get_section_by_name('.rel.dyn')
    rs = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: rs.get_symbol(r['r_info_sym']) for r in rel.iter_relocations() if r['r_info_type'] == 21}
    plt, rp = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr']+20+i*12: ps.get_symbol(r['r_info_sym']).name for i, r in enumerate(rp.iter_relocations())}
    for addr, name in ((0x17642c, 'Variable_GetValue_Direct'), (0x176720, 'Variable_GetValue'),
                       (0x17654c, 'YYGML_CallLegacyFunction'), (0x176444, 'REAL_RValue'),
                       (0x176408, 'YYGML_instance_destroy')):
        if name not in calls.get(addr, ''):
            raise ValueError('unexpected native call: '+hex(addr))
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True
    def ins(a):
        i = list(dis.disasm(elf_file_bytes(lib, a, 4), a))
        if len(i) != 1:
            raise ValueError('invalid instruction')
        return i[0]
    def check(a, op, args):
        i = ins(a)
        if (i.mnemonic, i.op_str) != (op, args):
            raise ValueError(f'instruction mismatch at {a:#x}')
    def literal(a):
        i = ins(a)
        if i.mnemonic != 'ldr' or len(i.operands) != 2 or i.operands[1].type != ARM_OP_MEM or i.reg_name(i.operands[1].mem.base) != 'pc':
            raise ValueError('expected literal load')
        return struct.unpack('<I', elf_file_bytes(lib, a+8+i.operands[1].mem.disp, 4))[0]
    def relocation(base, add, offset, expected):
        addr = (add+8+literal(base)+literal(offset)) & 0xffffffff
        symbol = got.get(addr)
        if symbol is None or symbol.name != expected:
            raise ValueError('unexpected relocation: '+expected)
        return symbol
    relocation(0x71252c, 0x712538, 0x71253c, 'g_VAR_x')
    relocation(0x7125b8, 0x7125c0, 0x7125bc, 'g_VAR_y')
    relocation(0x7125e0, 0x7125e4, 0x71253c, 'g_VAR_x')
    relocation(0x712604, 0x712608, 0x7125bc, 'g_VAR_y')
    relocation(0x712628, 0x712630, 0x71262c, 'g_FUNC_point_distance')
    epsilon = relocation(0x712670, 0x712678, 0x712674, 'g_GMLMathEpsilon')
    if epsilon['st_size'] != 8 or struct.unpack('<d', elf_file_bytes(lib, epsilon['st_value'], 8))[0] != 1e-10:
        raise ValueError('unexpected static epsilon')
    if struct.unpack('<d', elf_file_bytes(lib, 0x712890, 8))[0] != 8000:
        raise ValueError('unexpected distance constant')
    for a, op, args in ((0x712538,'add','r0, pc, r0'), (0x712548,'ldr','r3, [r5, r0]'),
        (0x71259c,'ldr','r1, [r3, #4]'), (0x7125a4,'add','sb, sp, #0x58'),
        (0x7125a8,'mov','r0, r4'), (0x7125b0,'mov','r3, sb'), (0x7125b4,'bl','#0x17642c'),
        (0x7125c0,'add','r0, pc, r0'), (0x7125c8,'ldr','r1, [r0, #4]'),
        (0x7125cc,'add','r7, sp, #0x48'), (0x7125d0,'mov','r0, r4'), (0x7125d8,'mov','r3, r7'),
        (0x7125dc,'bl','#0x17642c'), (0x7125e4,'add','r0, pc, r0'),
        (0x7125ec,'ldr','r1, [r0, #4]'), (0x7125f0,'add','r5, sp, #0x38'),
        (0x7125f4,'mov','r0, #0x8e'), (0x7125fc,'mov','r3, r5'), (0x712600,'bl','#0x176720'),
        (0x712608,'add','r0, pc, r0'), (0x712610,'ldr','r1, [r0, #4]'),
        (0x712614,'add','r6, sp, #0x28'), (0x712618,'mov','r0, #0x8e'),
        (0x712620,'mov','r3, r6'), (0x712624,'bl','#0x176720'),
        (0x712630,'add','r0, pc, r0'), (0x712634,'str','sb, [sp, #8]'),
        (0x712638,'str','r7, [sp, #0xc]'), (0x712640,'str','r5, [sp, #0x10]'),
        (0x712644,'str','r6, [sp, #0x14]'), (0x712660,'mov','r3, #4'),
        (0x712664,'bl','#0x17654c'), (0x712668,'bl','#0x176444'),
        (0x712678,'add','r0, pc, r0'), (0x71267c,'vldr','d1, [pc, #0x20c]'),
        (0x712684,'vsub.f64','d0, d1, d0'), (0x712688,'vldr','d1, [r0]'),
        (0x71268c,'vneg.f64','d1, d1'), (0x712690,'vcmpe.f64','d0, d1'),
        (0x712698,'bpl','#0x7126e4'), (0x7126dc,'mov','r0, r4'), (0x7126e0,'bl','#0x176408')):
        check(a, op, args)
    return {'event': 'obj_boss2:Step:2', 'address': hex(START), 'sha256': SHA256,
            'distance_arguments': ['self.x', 'self.y', 'obj_player.x', 'obj_player.y'],
            'finite_true_condition': 'distance > 8000 + current epsilon',
            'static_epsilon_initializer': 1e-10, 'true_action': 'instance_destroy(self)',
            'limitations': 'Static ARM only; no missing-player, NaN, inherited event, native runtime or iOS proof. Candidate comparison near epsilon boundary may differ.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2)+'\n', encoding='utf-8')
    print('BOSS2_DISTANCE_EVIDENCE: partial static ARM candidate only')


if __name__ == '__main__':
    main()
