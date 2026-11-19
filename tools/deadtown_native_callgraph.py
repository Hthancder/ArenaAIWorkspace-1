#!/usr/bin/env python3
"""Collect candidate direct native-to-GML calls from the pinned Android YYC APK.

This is a static ARM instruction scan, not a decompiler or an execution trace.
It does not follow control flow or indirect calls. Literal pools may be decoded
as instructions. Treat results as leads requiring manual validation.
"""
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member


def extract(apk_path):
    from elftools.elf.elffile import ELFFile
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CS_GRP_CALL
    from capstone.arm import ARM_OP_IMM

    apk = Path(apk_path)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        raw = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected ARM library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    symtab = elf.get_section_by_name('.dynsym')
    text = elf.get_section_by_name('.text')
    text_bytes = text.data()
    functions = {}
    for symbol in symtab.iter_symbols():
        name = exported_name(symbol.name)
        if not name:
            continue
        if name in functions:
            raise ValueError('duplicate exported GML name: ' + name)
        address, size = symbol['st_value'], symbol['st_size']
        if not text['sh_addr'] <= address < address + size <= text['sh_addr'] + text['sh_size']:
            raise ValueError('GML function outside .text: ' + name)
        functions[name] = (address, size)
    if not functions:
        raise ValueError('no exported GML functions')
    direct = {address: name for name, (address, _) in functions.items()}
    plt, reloc = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    plt_syms = elf.get_section(reloc['sh_link'])
    for i, rel in enumerate(reloc.iter_relocations()):
        name = exported_name(plt_syms.get_symbol(rel['r_info_sym']).name)
        if name:
            direct[plt['sh_addr'] + 20 + i * 12] = name
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail, dis.skipdata = True, True
    results = {}
    for caller, (address, size) in sorted(functions.items()):
        body = text_bytes[address - text['sh_addr']:address - text['sh_addr'] + size]
        counts = Counter()
        sites = {}
        for ins in dis.disasm(body, address):
            if ins.id == 0 or not ins.group(CS_GRP_CALL) or not ins.operands:
                continue
            if ins.operands[0].type != ARM_OP_IMM:
                continue
            callee = direct.get(ins.operands[0].imm)
            if callee:
                counts[callee] += 1
                sites.setdefault(callee, []).append(f'0x{ins.address:x}')
        results[caller] = {'address': f'0x{address:x}', 'size': size,
                           'candidate_calls': {callee: {'count': counts[callee], 'sites': sites[callee]}
                                               for callee in sorted(counts)}}
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'function_count': len(results), 'functions': results,
            'limitations': 'Direct BL/BLX only, including conditionals; no control flow or indirect calls. '
                           'Literal data can look like code, and exported symbols need not include all code.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.apk)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    edge_count = sum(len(x['candidate_calls']) for x in result['functions'].values())
    print(f"Scanned {result['function_count']} exported GML functions and found {edge_count} candidate directed edges")
    print('Report:', args.output)


if __name__ == '__main__':
    main()
