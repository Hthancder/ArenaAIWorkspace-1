#!/usr/bin/env python3
"""Pin two item-kind range checks in the Android ARM32 YYC executable.

The GML is a numeric-item-index candidate; this static analysis is not native
execution or proof of string/NaN coercion, GameMaker compilation, or iOS.
"""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name, project_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name, project_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

RANGES = {'item_check_pet': (17, 22), 'item_check_skin': (23, 26)}
ADDRESSES = {'item_check_pet': 0x1ba9c4, 'item_check_skin': 0x1baca0}


def numeric_rule(value, lower, upper, epsilon):
    if not math.isfinite(value) or not math.isfinite(epsilon) or epsilon < 0:
        raise ValueError('only finite values and nonnegative epsilon modeled')
    return int(lower - value <= epsilon and value - upper <= epsilon)


def verify_source(project):
    project = Path(project)
    declared = project_names(project, 'scripts', 'script')
    for name, (lower, upper) in RANGES.items():
        if name not in declared:
            raise ValueError(f'missing declared script: {name}')
        expected = ('/// Candidate restored from Android ARM32; intended for numeric item indices.\n'
                    f'if (argument0 >= {lower} && argument0 <= {upper})\n'
                    '{\n    return 1;\n}\nreturn 0;\n')
        if (project / 'scripts' / (name + '.gml')).read_text(encoding='utf-8') != expected:
            raise ValueError(f'unexpected candidate script: {name}')


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
    syms = elf.get_section_by_name('.dynsym')
    rel = elf.get_section_by_name('.rel.dyn')
    relsyms = elf.get_section(rel['sh_link'])
    got = {r['r_offset']: relsyms.get_symbol(r['r_info_sym']) for r in rel.iter_relocations()
           if r['r_info_type'] == 21}
    plt, rp = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    ps = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: ps.get_symbol(r['r_info_sym']).name
             for i, r in enumerate(rp.iter_relocations())}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True

    def read(address, size):
        for seg in elf.iter_segments():
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and address + size <= seg['p_vaddr'] + seg['p_filesz']:
                start = seg['p_offset'] + address - seg['p_vaddr']
                return raw[start:start + size]
        raise ValueError(f'address outside ELF bytes: {address:#x}')

    def instruction(address):
        result = list(dis.disasm(read(address, 4), address))
        if len(result) != 1:
            raise ValueError(f'invalid instruction: {address:#x}')
        return result[0]

    def require(address, mnemonic, operands):
        ins = instruction(address)
        if (ins.mnemonic, ins.op_str) != (mnemonic, operands):
            raise ValueError(f'instruction mismatch at {address:#x}')

    def literal(address):
        ins = instruction(address)
        if (ins.mnemonic != 'ldr' or len(ins.operands) != 2 or ins.operands[1].type != ARM_OP_MEM
                or ins.reg_name(ins.operands[1].mem.base) != 'pc'):
            raise ValueError(f'expected literal load at {address:#x}')
        return struct.unpack('<I', read(address + 8 + ins.operands[1].mem.disp, 4))[0]

    def epsilon(offset_load, base_load, add):
        ptr = (add + 8 + literal(offset_load) + literal(base_load)) & 0xffffffff
        sym = got.get(ptr)
        if sym is None or sym.name != 'g_GMLMathEpsilon' or sym['st_size'] != 8:
            raise ValueError('epsilon relocation mismatch')
        if struct.unpack('<d', read(sym['st_value'], 8))[0] != 1e-10:
            raise ValueError('epsilon initializer mismatch')

    def call(address, target):
        ins = instruction(address)
        if ins.mnemonic != 'bl' or target not in calls.get(int(ins.op_str[1:], 16), ''):
            raise ValueError(f'call mismatch at {address:#x}')

    result = {}
    for name, (lower, upper) in RANGES.items():
        start = ADDRESSES[name]
        found = [s for s in syms.iter_symbols() if exported_name(s.name) == 'gml_Script_' + name]
        if len(found) != 1 or (found[0]['st_value'], found[0]['st_size']) != (start, 732):
            raise ValueError(f'unexpected export: {name}')
        # The first stack argument is the argv array: its first RValue is copied
        # to a local, then converted to real twice before the range comparisons.
        checks = (
            (0x00, 'push', '{r4, r5, r6, lr}'), (0x04, 'sub', 'sp, sp, #0x28'),
            (0x0c, 'mov', 'r4, r2'), (0x1c, 'ldr', 'r3, [sp, #0x38]'),
            (0x54, 'ldr', 'r1, [r3]'),
            (0x144, 'bl', '#0x176444'), (0x148, 'vmov.f64', f'd1, #{float(lower):.6e}'),
            (0x158, 'add', 'r0, pc, r0'), (0x15c, 'vsub.f64', 'd0, d1, d0'),
            (0x160, 'ldr', 'r0, [r6, r0]'), (0x164, 'vldr', 'd1, [r0]'),
            (0x168, 'vcmpe.f64', 'd0, d1'), (0x16c, 'vmrs', 'apsr_nzcv, fpscr'),
            (0x170, 'bhi', f'#{start + 0x1a4:#x}'),
            (0x178, 'bl', '#0x176444'), (0x17c, 'vmov.f64', f'd1, #{-float(upper):.6e}'),
            (0x188, 'add', 'r0, pc, r0'), (0x18c, 'vadd.f64', 'd0, d0, d1'),
            (0x190, 'ldr', 'r0, [r6, r0]'), (0x194, 'vldr', 'd1, [r0]'),
            (0x198, 'vcmpe.f64', 'd0, d1'), (0x19c, 'vmrs', 'apsr_nzcv, fpscr'),
            (0x1a0, 'bls', f'#{start + 0x1e0:#x}'),
            (0x1d0, 'mov', 'r0, #0'), (0x1d4, 'str', 'r0, [r4, #0xc]'),
            (0x1d8, 'str', 'r0, [r4, #4]'), (0x1dc, 'b', f'#{start + 0x220:#x}'),
            (0x20c, 'movw', 'r1, #0'), (0x210, 'mov', 'r0, #0'),
            (0x214, 'movt', 'r1, #0x3ff0'), (0x218, 'str', 'r0, [r4, #0xc]'),
            (0x21c, 'str', 'r1, [r4, #4]'), (0x220, 'str', 'r0, [r4]'),
        )
        for offset, op, operands in checks:
            require(start + offset, op, operands)
        for offset in (0x144, 0x178):
            call(start + offset, 'REAL_RValue')
        epsilon(start + 0x14c, start + 0x154, start + 0x158)
        epsilon(start + 0x14c, start + 0x184, start + 0x188)
        result[name] = {'address': hex(start), 'lower': lower, 'upper': upper,
                        'input': 'first argument converted with REAL_RValue',
                        'rule': 'lower - value <= current epsilon and value - upper <= current epsilon',
                        'returns': [0, 1]}
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'static_epsilon_initializer': 1e-10, 'scripts': result,
            'limitations': 'Static ARM32; epsilon may vary. Candidate GML tested only for integer indices; '
                           'no proof for non-numeric/NaN values, fractional boundary semantics, compiler or iOS.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    verify_source(args.project)
    report = inspect(args.apk)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('ITEM_KIND_EVIDENCE: two native numeric range candidates; static only')


if __name__ == '__main__':
    main()
