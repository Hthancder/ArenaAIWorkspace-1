#!/usr/bin/env python3
"""Compare narrow static draw callsites, not visual behavior or decompiled code.

The native side scans ARM32 instructions in the pinned Android YYC ELF, including
its PLT. The source side counts lexical calls in pinned old GMX event actions.
Counts do not establish equivalence: compilation, control flow, indirect calls,
other helpers, and instruction/data ambiguity all matter. They say nothing about
the original iOS binary or actual on-device coordinates.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_inventory import exported_name
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import exported_name
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

FILES = {
    'obj_player': '475043d53c07f158104959e1660e7fb3d69c8167655f358a3087b140d2d49898',
    'sys_view': '7d364c4c65d11a50f720560dc0f510ee33b65a62a1e6d2dc713fee4ab41a0839',
    'sys_spawn_time_light': 'e8f08fe2f7e954ac75a9ecbc9a70e74436d88eb831d8bcec5e32143e9788c6bb',
}
# Native functions are matched by the full ELF symbol, never by substring.
SYMBOLS = {
    'draw_sprite_ext': '_Z21YYGML_draw_sprite_extP9CInstanceiifffffif',
    'draw_surface_part_ext': '_Z27YYGML_draw_surface_part_extiffffffffif',
}
EVENTS = (('obj_player', 0), ('obj_player', 64), ('sys_view', 0),
          ('sys_view', 64), ('sys_spawn_time_light', 74))


def scrub_non_code(text):
    """Blank comments and quoted strings while preserving newlines and offsets."""
    pattern = r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    return re.sub(pattern, lambda m: ''.join('\n' if c == '\n' else ' ' for c in m.group()), text)


def source_calls(project):
    result = {}
    for obj, digest in FILES.items():
        path = Path(project) / 'objects' / f'{obj}.object.gmx'
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError(f'unexpected source SHA-256: {obj}')
        root = ET.fromstring(raw)
        for target, number in EVENTS:
            if target != obj:
                continue
            matches = [e for e in root.findall('./events/event')
                       if e.get('eventtype') == '8' and e.get('enumb') == str(number)]
            if len(matches) != 1:
                raise ValueError(f'expected exactly one Draw event: {obj}:{number}')
            text = '\n'.join(node.text or '' for node in matches[0].findall('.//string'))
            code = scrub_non_code(text)
            result[f'gml_Object_{obj}_Draw_{number}'] = {
                name: len(re.findall(r'\b' + re.escape(name) + r'\s*\(', code)) for name in SYMBOLS}
    return result


def native_calls(apk):
    from elftools.elf.elffile import ELFFile
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CS_GRP_CALL
    from capstone.arm import ARM_OP_IMM

    apk = Path(apk)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        raw = read_zip_member(archive, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(raw).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected native library SHA-256')
    elf = ELFFile(io.BytesIO(raw))
    symtab, text = elf.get_section_by_name('.dynsym'), elf.get_section_by_name('.text')
    plt, rel = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    relsyms = elf.get_section(rel['sh_link'])
    destinations = {name: set() for name in SYMBOLS}
    for sym in symtab.iter_symbols():
        for key, name in SYMBOLS.items():
            if sym.name == name and sym['st_value']:
                destinations[key].add(sym['st_value'])
    for i, relocation in enumerate(rel.iter_relocations()):
        symbol = relsyms.get_symbol(relocation['r_info_sym']).name
        for key, name in SYMBOLS.items():
            if symbol == name:
                destinations[key].add(plt['sh_addr'] + 20 + i * 12)
    if any(not addresses for addresses in destinations.values()):
        raise ValueError('missing expected native draw symbols')
    expected = {f'gml_Object_{obj}_Draw_{number}' for obj, number in EVENTS}
    functions = {}
    for sym in symtab.iter_symbols():
        name = exported_name(sym.name)
        if name in expected:
            if name in functions:
                raise ValueError(f'duplicate native event {name}')
            address, size = sym['st_value'], sym['st_size']
            if not text['sh_addr'] <= address < address + size <= text['sh_addr'] + text['sh_size']:
                raise ValueError(f'native event outside text: {name}')
            functions[name] = (address, size)
    if set(functions) != expected:
        raise ValueError('missing expected native events')
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    dis.detail, dis.skipdata = True, True
    text_bytes = text.data()
    output = {}
    for name, (addr, size) in sorted(functions.items()):
        sites = {key: [] for key in SYMBOLS}
        start = addr - text['sh_addr']
        for ins in dis.disasm(text_bytes[start:start + size], addr):
            if ins.id == 0 or not ins.group(CS_GRP_CALL) or not ins.operands or ins.operands[0].type != ARM_OP_IMM:
                continue
            for key, targets in destinations.items():
                if ins.operands[0].imm in targets:
                    sites[key].append(f'0x{ins.address:x}')
        output[name] = {'address': f'0x{addr:x}', 'size': size, 'candidate_sites': sites}
    return output


def compare(apk, project):
    native, source = native_calls(apk), source_calls(project)
    return {'apk_sha256': APK_SHA256, 'native_library_sha256': LIB_SHA256,
            'events': {name: {'native': native[name], 'old_source_lexical_counts': source[name]}
                       for name in sorted(native)},
            'limitations': 'Static candidate direct ARM calls and lexical GMX calls only; counts may differ '
                           'due to compiler, helpers or indirect calls. No proof of behavior, arguments, '
                           'rendered placement, native iOS, or the cause of iPhone defects.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.apk, args.project)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for name, data in result['events'].items():
        print(name, {key: {'native_direct_candidates': len(sites),
                          'old_source_lexical_calls': data['old_source_lexical_counts'][key]}
                     for key, sites in data['native']['candidate_sites'].items()})


if __name__ == '__main__':
    main()
