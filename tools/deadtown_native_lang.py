#!/usr/bin/env python3
"""Extract candidate lang_add literals from the pinned Dead Town Android YYC.

Requires capstone 5 and pyelftools. This narrow static pattern scanner does not
execute code or reconstruct GML, and does not prove control flow or arguments.
Use --compare-gmx to compare tuples against the old source for validation.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from recover_deadtown_audio import read_zip_member

APK_SHA256 = 'bc8fa1990cb2cdde8d184f2a942fe4010820f0592d88a36e1cbee0a6aac081fb'
LIB_SHA256 = '7f3895e245d83edc498859d0869017acf55ec1e92fc801cb734f7fe8315e1c23'
GMX_CALL = re.compile(r'lang_add\("([^"\n]*)","([^"\n]*)","([^"\n]*)","([^"\n]*)"\)')


def compare_source(entries, gmx):
    tree = ET.parse(Path(gmx) / 'objects/sys_global.object.gmx')
    texts = '\n'.join(node.text or '' for node in tree.iter('string'))
    old = set(GMX_CALL.findall(texts))
    if not old:
        raise ValueError('no expected lang_add literals in source')
    recovered = {tuple(item['candidate_arguments']) for item in entries}
    return {
        'source_distinct_literal_tuples': len(old),
        'recovered_distinct_candidate_tuples': len(recovered),
        'source_tuples_matching_candidates': len(old & recovered),
        'source_tuples_not_seen': len(old - recovered),
        'candidate_tuples_not_in_source': len(recovered - old),
    }


def extract(apk_path):
    # Lazy imports keep compare_source usable by tests without RE dependencies.
    from elftools.elf.elffile import ELFFile
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CsError
    from capstone.arm import (ARM_OP_REG, ARM_OP_MEM, ARM_OP_IMM, ARM_REG_PC,
                              ARM_REG_R0, ARM_REG_R1, ARM_REG_R2, ARM_REG_R3, ARM_REG_R12)

    apk = Path(apk_path)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256; scanner supports only the pinned APK')
    with zipfile.ZipFile(apk) as archive:
        raw = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    stream = io.BytesIO(raw)
    elf = ELFFile(stream)
    symbols = list(elf.get_section_by_name('.dynsym').iter_symbols())
    matches = [s for s in symbols if s.name.startswith('_Z30gml_Object_sys_global_Create_0')]
    if len(matches) != 1:
        raise ValueError('expected exactly one sys_global Create export')
    function = matches[0]
    text = elf.get_section_by_name('.text')
    start, size = function['st_value'], function['st_size']
    if not text['sh_addr'] <= start < start + size <= text['sh_addr'] + text['sh_size']:
        raise ValueError('function outside .text')
    body = text.data()[start - text['sh_addr']:start - text['sh_addr'] + size]

    # This pinned ARM32 ELF uses 20-byte PLT header and 12-byte slots. The hash
    # guard and explicit symbol checks below make this layout assumption narrow.
    plt = elf.get_section_by_name('.plt')
    plt_reloc = elf.get_section_by_name('.rel.plt')
    plt_symbols = elf.get_section(plt_reloc['sh_link'])
    calls = {plt['sh_addr'] + 20 + index * 12: plt_symbols.get_symbol(rel['r_info_sym']).name
             for index, rel in enumerate(plt_reloc.iter_relocations())}
    if not any('YYSetString' in name for name in calls.values()) or not any('gml_Script_lang_add' in name for name in calls.values()):
        raise ValueError('expected PLT symbols missing')
    dynrel = elf.get_section_by_name('.rel.dyn')
    dynsymbols = elf.get_section(dynrel['sh_link'])
    # R_ARM_GLOB_DAT relocations put the address of the named C string in the GOT.
    got = {r['r_offset']: dynsymbols.get_symbol(r['r_info_sym']) for r in dynrel.iter_relocations()
           if r['r_info_type'] == 21}
    segments = list(elf.iter_segments())

    def word(address):
        for seg in segments:
            if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= address and address + 4 <= seg['p_vaddr'] + seg['p_filesz']:
                offset = seg['p_offset'] + address - seg['p_vaddr']
                return struct.unpack_from('<I', raw, offset)[0]
        return None

    def symbol_string(sym):
        if not sym.name.startswith('g_pString') or not isinstance(sym['st_shndx'], int):
            return None
        section = elf.get_section(sym['st_shndx'])
        n, offset = sym['st_size'], sym['st_value'] - section['sh_addr']
        if not 0 < n <= 10000 or offset < 0 or offset + n > section['sh_size']:
            return None
        payload = bytes(n) if section['sh_type'] == 'SHT_NOBITS' else section.data()[offset:offset + n]
        if not payload.endswith(b'\0') or b'\0' in payload[:-1]:
            return None
        try:
            return payload[:-1].decode('utf-8')
        except UnicodeDecodeError:
            return None

    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail = True
    dis.skipdata = True  # ARM literal pools are embedded in this large function.
    regs, pending, entries, unresolved = {}, [], [], []
    for ins in dis.disasm(body, start):
        if ins.id == 0:
            regs.clear()
            continue
        op = ins.operands
        value, dst = None, None
        if ins.mnemonic == 'ldr' and len(op) == 2 and op[0].type == ARM_OP_REG and op[1].type == ARM_OP_MEM:
            dst, mem = op[0].reg, op[1].mem
            if mem.base == ARM_REG_PC and mem.index == 0:
                value = word((ins.address + 8 + mem.disp) & 0xffffffff)
            elif mem.base in regs and mem.index in regs and isinstance(regs[mem.base], int) and isinstance(regs[mem.index], int):
                loc = (regs[mem.base] + regs[mem.index] + mem.disp) & 0xffffffff
                symbol = got.get(loc)
                if symbol is not None:
                    string = symbol_string(symbol)
                    if string is not None:
                        value = (symbol.name, string)
        elif (ins.mnemonic == 'add' and len(op) == 3 and op[0].type == ARM_OP_REG
              and op[1].type == ARM_OP_REG and op[1].reg == ARM_REG_PC and op[2].type == ARM_OP_REG):
            dst = op[0].reg
            previous = regs.get(op[2].reg)
            if isinstance(previous, int):
                value = (ins.address + 8 + previous) & 0xffffffff
        elif ins.mnemonic == 'mov' and len(op) == 2 and op[0].type == ARM_OP_REG:
            dst = op[0].reg
            if op[1].type == ARM_OP_REG:
                value = regs.get(op[1].reg)
            elif op[1].type == ARM_OP_IMM:
                value = op[1].imm & 0xffffffff
        if ins.mnemonic in ('bl', 'blx') and op and op[0].type == ARM_OP_IMM:
            name = calls.get(op[0].imm, '')
            if 'YYSetString' in name:
                pending.append((ins.address, regs.get(ARM_REG_R1)))
            elif 'gml_Script_' in name:
                if 'gml_Script_lang_add' in name:
                    if len(pending) == 4 and all(isinstance(x[1], tuple) for x in pending):
                        entries.append({'call_address': f'0x{ins.address:x}',
                                        'candidate_arguments': [x[1][1] for x in pending],
                                        'string_symbols': [x[1][0] for x in pending],
                                        'set_string_addresses': [f'0x{x[0]:x}' for x in pending]})
                    else:
                        unresolved.append({'call_address': f'0x{ins.address:x}',
                                           'preceding_string_calls': len(pending),
                                           'resolved_strings': sum(isinstance(x[1], tuple) for x in pending)})
                pending = []
            for reg in (ARM_REG_R0, ARM_REG_R1, ARM_REG_R2, ARM_REG_R3, ARM_REG_R12):
                regs.pop(reg, None)
            continue
        try:
            _, writes = ins.regs_access()
        except CsError:
            regs.clear()
            continue
        for reg in writes:
            regs.pop(reg, None)
        if dst is not None and value is not None:
            regs[dst] = value
    return {
        'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
        'function': function.name, 'function_address': f'0x{start:x}', 'function_size': size,
        'method': 'Linear ARM disassembly: consecutive resolved YYSetString literals before each lang_add. '
                  'Candidate order assumes string-construction order equals argument order; no CFG or stack/argument validation.',
        'candidate_call_count': len(entries), 'unresolved_call_count': len(unresolved),
        'unresolved': unresolved, 'entries': entries,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--compare-gmx', type=Path, help='optional unmodified GMX project directory')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.apk)
    if args.compare_gmx:
        result['source_comparison'] = compare_source(result['entries'], args.compare_gmx)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"Candidate calls: {result['candidate_call_count']}, unresolved patterns: {result['unresolved_call_count']}")
    if args.compare_gmx:
        print('Source comparison:', result['source_comparison'])
    print('Report:', args.output)


if __name__ == '__main__':
    main()
