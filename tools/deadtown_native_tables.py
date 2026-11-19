#!/usr/bin/env python3
"""Inspect candidate static table call arguments in the pinned Android YYC APK.

Requires capstone 5 and pyelftools. This analyzes ARM instructions; it does not
execute the binary, follow branches, or reconstruct GML. Outputs are candidates
with call addresses and symbol provenance, not automatically safe game patches.
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
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

TARGETS = {
    'db_weapon_add': 13, 'db_equip_add': 7, 'db_use_add': 10,
    'db_craft_add': 15, 'db_etc_add': 4, 'db_skill_add': 4,
    'db_spawn_add': 5, 'lang_add': 4,
}


def multi_store_offset(mnemonic, register_count):
    """Offset of the lowest numbered register in an ARM STM sequence."""
    if register_count <= 0:
        raise ValueError('empty register list')
    offsets = {'stm': 0, 'stmia': 0, 'stmib': 4,
               'stmda': -4 * (register_count - 1), 'stmdb': -4 * register_count}
    if mnemonic not in offsets:
        raise ValueError('unsupported store mode')
    return offsets[mnemonic]


def extract(apk_path):
    from elftools.elf.elffile import ELFFile
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CsError
    from capstone.arm import (ARM_CC_AL, ARM_OP_IMM, ARM_OP_MEM, ARM_OP_REG,
                              ARM_REG_PC, ARM_REG_SP, ARM_REG_R0, ARM_REG_R1,
                              ARM_REG_R2, ARM_REG_R3, ARM_REG_R12)

    apk = Path(apk_path)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        raw = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    symtab = elf.get_section_by_name('.dynsym')
    functions = [s for s in symtab.iter_symbols() if s.name.startswith('_Z30gml_Object_sys_global_Create_0')]
    if len(functions) != 1:
        raise ValueError('unexpected sys_global Create export')
    function = functions[0]
    text = elf.get_section_by_name('.text')
    start, size = function['st_value'], function['st_size']
    if not text['sh_addr'] <= start < start + size <= text['sh_addr'] + text['sh_size']:
        raise ValueError('function outside .text')
    body = text.data()[start - text['sh_addr']:start - text['sh_addr'] + size]

    plt, relplt = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    pltsyms = elf.get_section(relplt['sh_link'])
    calls = {plt['sh_addr'] + 20 + i * 12: pltsyms.get_symbol(r['r_info_sym']).name
             for i, r in enumerate(relplt.iter_relocations())}
    if not any('YYSetString' in x for x in calls.values()):
        raise ValueError('YYSetString PLT entry missing')
    for target in TARGETS:
        if sum(('gml_Script_' + target) in x for x in calls.values()) != 1:
            raise ValueError(f'unexpected PLT entries for {target}')
    rel = elf.get_section_by_name('.rel.dyn')
    relsyms = elf.get_section(rel['sh_link'])
    relocations = {r['r_offset']: (r['r_info_type'], relsyms.get_symbol(r['r_info_sym']))
                   for r in rel.iter_relocations()}
    segments = list(elf.iter_segments())

    def read_word(address):
        for segment in segments:
            if (segment['p_type'] == 'PT_LOAD' and segment['p_vaddr'] <= address and
                    address + 4 <= segment['p_vaddr'] + segment['p_filesz']):
                return struct.unpack_from('<I', raw, segment['p_offset'] + address - segment['p_vaddr'])[0]
        return None

    def symbol_bytes(sym, limit):
        if not isinstance(sym['st_shndx'], int):
            return None
        sec = elf.get_section(sym['st_shndx'])
        length, offset = sym['st_size'], sym['st_value'] - sec['sh_addr']
        if not 0 < length <= limit or offset < 0 or offset + length > sec['sh_size']:
            return None
        return bytes(length) if sec['sh_type'] == 'SHT_NOBITS' else sec.data()[offset:offset + length]

    def relocation_value(address):
        entry = relocations.get(address)
        if not entry or entry[0] not in (2, 21):  # R_ARM_ABS32 / R_ARM_GLOB_DAT
            return None
        symbol = entry[1]
        if symbol.name.startswith('gs_constArg'):
            payload = symbol_bytes(symbol, 16)
            if payload is None or len(payload) != 16:
                return None
            value, flags, kind = struct.unpack('<dII', payload)
            if flags != 0 or kind != 0 or not math.isfinite(value):
                return None
            return ('number', value, symbol.name, address)
        if symbol.name.startswith('g_pString'):
            payload = symbol_bytes(symbol, 10000)
            if not payload or not payload.endswith(b'\0') or b'\0' in payload[:-1]:
                return None
            try:
                return ('string', payload[:-1].decode('utf-8'), symbol.name, address)
            except UnicodeDecodeError:
                return None
        return None

    # The abstract values tracked here are deliberately limited. `regs` holds
    # literal integer addresses and recognized relocation values; `tokens` holds
    # symbolic pointer identities and constant offsets for stack copies. `slots`
    # records the last value written to each symbolic address in this call group.
    regs, tokens, objects, slots = {}, {}, {}, {}
    argv = None
    entries, unresolved = {name: [] for name in TARGETS}, {name: [] for name in TARGETS}
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail, dis.skipdata = True, True

    def current_pointer(register):
        return tokens.get(register, (('unknown-register', register), 0))

    def store(register, pointer):
        reference = regs.get(register)
        if isinstance(reference, tuple) and reference[0] == 'number':
            slots[pointer] = reference
        elif tokens.get(register) in objects:
            slots[pointer] = objects[tokens[register]]
        else:
            slots.pop(pointer, None)  # a later unknown write invalidates the slot

    for ins in dis.disasm(body, start):
        # Literal pools are interspersed with code. Predicated instructions are
        # ignored, not executed. This is not CFG/branch-aware symbolic execution.
        if ins.id == 0 or ins.cc != ARM_CC_AL:
            continue
        ops = ins.operands
        dst, value, writeback, token, ldm_values = None, None, None, None, {}
        if ins.mnemonic == 'ldr' and len(ops) == 2 and ops[0].type == ARM_OP_REG and ops[1].type == ARM_OP_MEM:
            dst, mem = ops[0].reg, ops[1].mem
            if mem.base == ARM_REG_PC and not mem.index:
                value = read_word((ins.address + 8 + mem.disp) & 0xffffffff)
            elif isinstance(regs.get(mem.base), int) and (not mem.index or isinstance(regs.get(mem.index), int)):
                address = (regs[mem.base] + (regs[mem.index] if mem.index else 0) + mem.disp) & 0xffffffff
                if ins.writeback:
                    writeback = (mem.base, address)
                value = relocation_value(address)
        elif (ins.mnemonic == 'add' and len(ops) == 3 and ops[0].type == ARM_OP_REG
              and ops[1].type == ARM_OP_REG):
            dst = ops[0].reg
            if ops[1].reg == ARM_REG_PC and ops[2].type == ARM_OP_REG and isinstance(regs.get(ops[2].reg), int):
                value = (ins.address + 8 + regs[ops[2].reg]) & 0xffffffff
            elif ops[2].type == ARM_OP_IMM:
                if isinstance(regs.get(ops[1].reg), int):
                    value = (regs[ops[1].reg] + ops[2].imm) & 0xffffffff
                if ops[1].reg in tokens:
                    base, off = tokens[ops[1].reg]
                    token = (base, off + ops[2].imm)
        elif ins.mnemonic == 'mov' and len(ops) == 2 and ops[0].type == ARM_OP_REG:
            dst = ops[0].reg
            if ops[1].type == ARM_OP_REG:
                value, token = regs.get(ops[1].reg), tokens.get(ops[1].reg)
            elif ops[1].type == ARM_OP_IMM:
                value = ops[1].imm & 0xffffffff

        if (ins.mnemonic in ('ldm', 'ldmia', 'ldmib') and len(ops) > 1
                and ops[0].type == ARM_OP_REG and isinstance(regs.get(ops[0].reg), int)):
            address = regs[ops[0].reg] + (4 if ins.mnemonic == 'ldmib' else 0)
            for index, operand in enumerate(ops[1:]):
                reference = relocation_value(address + 4 * index)
                if reference is not None:
                    ldm_values[operand.reg] = reference

        if (ins.mnemonic == 'str' and len(ops) == 2 and ops[0].type == ARM_OP_REG
                and ops[1].type == ARM_OP_MEM and not ops[1].mem.index):
            mem = ops[1].mem
            if mem.base == ARM_REG_SP and mem.disp == 0:
                argv = tokens.get(ops[0].reg)
            base, off = current_pointer(mem.base)
            store(ops[0].reg, (base, off + mem.disp))
        if ins.mnemonic in ('stm', 'stmia', 'stmib', 'stmda', 'stmdb') and len(ops) > 1 and ops[0].type == ARM_OP_REG:
            base, off = current_pointer(ops[0].reg)
            off += multi_store_offset(ins.mnemonic, len(ops) - 1)
            for index, operand in enumerate(ops[1:]):
                store(operand.reg, (base, off + index * 4))

        if ins.mnemonic in ('bl', 'blx') and ops and ops[0].type == ARM_OP_IMM:
            name = calls.get(ops[0].imm, '')
            if 'YYSetString' in name:
                source, address = regs.get(ARM_REG_R1), tokens.get(ARM_REG_R0)
                if isinstance(source, tuple) and source[0] == 'string' and address is not None:
                    objects[address] = source
            target = next((t for t in TARGETS if 'gml_Script_' + t in name), None)
            if target:
                argc = regs.get(ARM_REG_R3)
                values = []
                if argc == TARGETS[target] and argv is not None:
                    base, off = argv
                    values = [slots.get((base, off + 4 * i)) for i in range(argc)]
                if len(values) == TARGETS[target] and all(v is not None for v in values):
                    entries[target].append({
                        'call_address': f'0x{ins.address:x}',
                        'arguments': [{'type': v[0], 'value': v[1], 'symbol': v[2],
                                       'relocation_address': f'0x{v[3]:x}'} for v in values],
                    })
                else:
                    unresolved[target].append({'call_address': f'0x{ins.address:x}',
                                               'observed_argc': argc,
                                               'resolved_slots': sum(v is not None for v in values)})
            if 'gml_Script_' in name:
                slots.clear()
                objects.clear()
                argv = None
            for reg in (ARM_REG_R0, ARM_REG_R1, ARM_REG_R2, ARM_REG_R3, ARM_REG_R12):
                regs.pop(reg, None)
                tokens.pop(reg, None)
            continue
        try:
            _, writes = ins.regs_access()
        except CsError:
            regs.clear()
            continue
        for reg in writes:
            regs.pop(reg, None)
            tokens[reg] = ((ins.address, reg), 0)
        if dst is not None and token is not None:
            tokens[dst] = token
        regs.update(ldm_values)
        if writeback is not None:
            regs[writeback[0]] = writeback[1]
        if dst is not None and value is not None:
            regs[dst] = value

    return {
        'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
        'function_address': f'0x{start:x}', 'function_size': size,
        'limitations': 'Linear static analysis; skips predicated instructions and does not follow control flow. '
                       'Each candidate traces RValue pointers into the stack argument array, but runtime '
                       'initialization and call execution are not verified. Do not auto-apply.',
        'counts': {name: {'resolved': len(entries[name]), 'unresolved': len(unresolved[name])} for name in TARGETS},
        'entries': entries, 'unresolved': unresolved,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.apk)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for name, counts in result['counts'].items():
        print(f"{name}: {counts['resolved']} candidates, {counts['unresolved']} unresolved")
    print('Report:', args.output)


if __name__ == '__main__':
    main()
