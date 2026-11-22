#!/usr/bin/env python3
"""Check six partial linked-light Destroy candidates against pinned ARM32.

The variable names are inferred from a matching old-source Step cleanup, not
recovered symbols. Does not establish full object behavior or device semantics.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_empty_collision_evidence import elf_file_bytes
    from tools.deadtown_native_inventory import exported_name, project_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.deadtown_object_evidence import native_objects
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_empty_collision_evidence import elf_file_bytes
    from deadtown_native_inventory import exported_name, project_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from deadtown_object_evidence import native_objects
    from recover_deadtown_audio import read_zip_member

# name: source variable, native slot, Destroy address/hash, Step address/size/hash,
# Step's instance_exists call. Each Destroy body has the same structure.
TARGETS = {
    'obj_bettery': ('light_obj', 0x158, 0x6cfcc8, '1a722c024d2d02e332a9da6d1ea0d55d30057b2534ecb3f2fb78f1c946702887', 0x6cfe20, 2976, 'e9415ccc6742edd65f20301d5a69289545c0270dfca287a723c70c9c55b43a8f', 0x6d0000),
    'obj_lightaction': ('light_obj', 0x158, 0x6c7708, 'c3702865df524ca5df56cce03148375d137c5eaeccd872633c1bdcf9386c2595', 0x6c7860, 5960, '0a1d0e5c75873f0ac84e8007274f5072bc9e080846a53fedbc27a67b29574548', 0x6c87d4),
    'obj_cooker': ('craft_light_obj', 0x48a, 0x6f4044, 'ce08b2e5ff7dcae46935816d67f1c81a12ff900f69bb16eb0176700d4af53721', 0x6f41a0, 5072, '247634cfa01e89d19442a5eb04d8ef3ed73a41d013bb9b56c2c0d7dcbd46158d', 0x6f43bc),
    'obj_craftdesk': ('craft_light_obj', 0x48a, 0x6b6f00, 'd8e5a9d1402bac63fbb2d295797a7abb60e5995ec443a4964ffbca56a3323b90', 0x6b7058, 6408, 'f83ef0975bcff82c58f23aeaf1344f4344f9b0d087162bad508ae4d6b5b9ea48', 0x6b7284),
    'obj_craftdesk_pro': ('craft_light_obj', 0x48a, 0x6ba640, 'ed056fda90715c3ff914112e208a02ef612e3ac8af9eaabcdd916ad1da127757', 0x6ba798, 5916, '9bd8a629244fb363b5bfbdc3e79fcc69b26754cdeff2254d81555d38818c37fe', 0x6ba9b4),
    'obj_brazier_electric': ('craft_light_obj', 0x48a, 0x6f81f4, '83a97cb33f9ce4f1a89887b5ada9c88b1368742bdac2a464420011b780043203', 0x6f8350, 5072, '5fb72505fdb09615e3fde7b8e2b32c36ddc2031d045a670a256572f1591fb19e', 0x6f856c),
}


def candidate(variable):
    return ('/// Partial Android ARM candidate: clean up linked light.\n'
            f'if instance_exists({variable})\n{{\n    with ({variable})\n'
            '    {\n        instance_destroy()\n    }\n}\n')


def verify_source(project):
    project = Path(project)
    declared = project_names(project, 'objects', 'object')
    for name, row in TARGETS.items():
        variable = row[0]
        if name not in declared:
            raise ValueError(f'object not declared: {name}')
        root = ET.parse(project/'objects'/(name+'.object.gmx')).getroot()
        create = root.findall('./events/event[@eventtype="0"][@enumb="0"]/action/arguments/argument/string')
        step = root.findall('./events/event[@eventtype="3"][@enumb="0"]/action/arguments/argument/string')
        destroy = root.findall('./events/event[@eventtype="1"][@enumb="0"]')
        if not create or f'{variable} = noone' not in '\n'.join(x.text or '' for x in create):
            raise ValueError(f'unexpected Create: {name}')
        step_text = '\n'.join(x.text or '' for x in step)
        if f'if instance_exists({variable})\n    {{\n        with ({variable})\n        {{\n            instance_destroy()\n        }}\n    }}' not in step_text:
            raise ValueError(f'unexpected Step evidence: {name}')
        if len(destroy) != 1 or len(destroy[0].findall('action')) != 1:
            raise ValueError(f'unexpected Destroy event: {name}')
        action = destroy[0].find('action')
        if (action.findtext('libid'), action.findtext('id'), action.findtext('kind'),
            action.findtext('./arguments/argument/string')) != ('1', '603', '7', candidate(variable)):
            raise ValueError(f'unexpected Destroy action: {name}')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as z:
        lib = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
        game = read_zip_member(z, 'assets/game.droid')
    if hashlib.sha256(lib).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    objects = native_objects(game)
    elf = ELFFile(io.BytesIO(lib))
    symbols = {}
    for symbol in elf.get_section_by_name('.dynsym').iter_symbols():
        name = exported_name(symbol.name)
        if name:
            symbols.setdefault(name, []).append((symbol['st_value'], symbol['st_size']))
    plt, rel = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    relsyms = elf.get_section(rel['sh_link'])
    calls = {plt['sh_addr']+20+i*12: relsyms.get_symbol(r['r_info_sym']).name
             for i, r in enumerate(rel.iter_relocations())}
    for address, expected in ((0x176444, 'REAL_RValue'), (0x176630, 'YYGML_instance_exists'),
                              (0x1763fc, 'YYGML_NewWithIterator'), (0x176408, 'YYGML_instance_destroy'),
                              (0x176414, 'YYGML_WithIteratorNext'), (0x176420, 'YYGML_DeleteWithIterator')):
        if expected not in calls.get(address, ''):
            raise ValueError('unexpected call relocation: '+hex(address))
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    def check(address, op, args):
        instructions = list(dis.disasm(elf_file_bytes(lib, address, 4), address))
        if len(instructions) != 1 or (instructions[0].mnemonic, instructions[0].op_str) != (op, args):
            raise ValueError(f'instruction mismatch at {address:#x}')
    result = []
    for name, (var, slot, destroy, digest, step, size, step_digest, exists) in TARGETS.items():
        if objects[name]['event_counts'][1] != 1 or objects[name]['event_counts'][3] != 1:
            raise ValueError('unexpected native event counts: '+name)
        for event, addr, length, expected in (('Destroy_0', destroy, 344, digest), ('Step_0', step, size, step_digest)):
            if symbols.get(f'gml_Object_{name}_{event}') != [(addr, length)]:
                raise ValueError('unexpected native export: '+name+' '+event)
            if hashlib.sha256(elf_file_bytes(lib, addr, length)).hexdigest() != expected:
                raise ValueError('unexpected native event bytes: '+name+' '+event)
        mov = 'mov' if slot == 0x158 else 'movw'
        for off, op, args in ((0x58, mov, f'r1, #{slot:#x}'), (0x5c, 'blx', 'r2'),
                              (0x60, 'bl', '#0x176444'), (0x78, 'bl', '#0x176630'),
                              (0x7c, 'cmp', 'r0, #1'), (0x80, 'bne', f'#{destroy+0x10c:#x}'),
                              (0x98, mov, f'r1, #{slot:#x}'), (0x9c, 'blx', 'r2'),
                              (0xa0, 'bl', '#0x176444'), (0xbc, 'bl', '#0x1763fc'),
                              (0xe0, 'bl', '#0x176408'), (0xf0, 'bl', '#0x176414'),
                              (0xf8, 'bne', f'#{destroy+0xd8:#x}'), (0x108, 'bl', '#0x176420')):
            check(destroy+off, op, args)
        # Same variable and guard/with/destroy pattern occur in the Step path,
        # corresponding to the cleanup already present in the old source.
        for off, op, args in ((-0x28, mov, f'r1, #{slot:#x}'), (-0x24, 'blx', 'r2'),
                              (-0x18, 'bl', '#0x176444'), (0, 'bl', '#0x176630'),
                              (4, 'cmp', 'r0, #1'), (0x44, 'bl', '#0x1763fc'),
                              (0x68, 'bl', '#0x176408'), (0x78, 'bl', '#0x176414'),
                              (0x90, 'bl', '#0x176420')):
            check(exists+off, op, args)
        result.append({'object': name, 'native_instance_slot': slot, 'source_variable_candidate': var,
                       'destroy_address': hex(destroy), 'step_exists_address': hex(exists)})
    return {'events': result, 'limitations': 'Partial static ARM and source correspondence; slot names inferred. '
            'No proof of lifecycle ordering, double cleanup effects, complete Step/Create equivalence, Android or iOS execution.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    verify_source(args.project)
    args.output.write_text(json.dumps(inspect(args.apk), indent=2)+'\n', encoding='utf-8')
    print('LIGHT_CLEANUP_EVIDENCE: six partial ARM candidates; static only')


if __name__ == '__main__':
    main()
