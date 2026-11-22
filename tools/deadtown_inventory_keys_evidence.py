#!/usr/bin/env python3
"""Evidence for partial inventory/pause input repairs, not native execution."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_empty_collision_evidence import elf_file_bytes
    from tools.deadtown_native_inventory import exported_name
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_empty_collision_evidence import elf_file_bytes
    from deadtown_native_inventory import exported_name
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

OPEN = '''/// Android ARM candidate: open inventory only while closed.
if backpack_open == 0
{
    backpack_order_open = 1
}
'''
TOGGLE = '''/// Android ARM candidate: toggle inventory on space.
if backpack_open != 0
{
    backpack_order_close = 1
}
else
{
    backpack_order_open = 1
}
'''
ESCAPE = '''/// Android ARM candidate: pause or resume on escape.
if pause > 0.5
{
    pause_request = 1
}
else if backpack_open == 0
{
    pause_request = 1
    pause_kind = 0
}
'''
CLOSE = '''if backpack_order_close
{
    backpack_order_close = 0
    backpack_close()
}'''
FUNCTIONS = {
    'KeyPress_73': (0x5716b0, 304, 'f4042f5611a07bcb84c364bb102719e2aa27b26c999ecdafaa45d9acc696f80b'),
    'KeyPress_32': (0x5717e0, 376, 'e47a52cba066ed3b1f3c57153bf52105df2818833d028eec00880c6354452681'),
    'KeyPress_27': (0x571958, 524, '4cbc7b0d77170e8689715c65c33f66eb9c7c14fd10a8c9b32919bcf11fa657a3'),
    'Create_0': (0x4f78c8, 17332, '3b00e759a644dae0a3fd87dd653e4d002cebb9183bdccd1b9b07c8f0a3e35d06'),
    'Step_0': (0x4fc100, 159036, '65527b77f9d947aa4625153104288e88b327b0adcce7d005a3af0878f019a6c4'),
}


def verify_source(project):
    root = ET.parse(Path(project)/'objects/sys_UI.object.gmx').getroot()
    for number, expected in ((73, OPEN), (32, TOGGLE), (27, ESCAPE)):
        events = root.findall(f'./events/event[@eventtype="9"][@enumb="{number}"]')
        if len(events) != 1 or len(events[0].findall('action')) != 1:
            raise ValueError('unexpected key event '+str(number))
        action = events[0].find('action')
        if (action.findtext('libid'), action.findtext('id'), action.findtext('kind'), action.findtext('./arguments/argument/string')) != ('1','603','7',expected):
            raise ValueError('unexpected key source '+str(number))
    step = root.findall('./events/event[@eventtype="3"][@enumb="0"]')
    if len(step) != 1 or sum((a.findtext('./arguments/argument/string') or '').count(CLOSE) for a in step[0].findall('action')) != 1:
        raise ValueError('unexpected close fragment')
    return {'open': OPEN, 'toggle': TOGGLE, 'escape': ESCAPE, 'close': CLOSE}


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK')
    with zipfile.ZipFile(apk) as z:
        lib = read_zip_member(z, 'lib/armeabi-v7a/libyoyo.so')
    if hashlib.sha256(lib).hexdigest() != LIB_SHA256:
        raise ValueError('unexpected native library')
    elf = ELFFile(io.BytesIO(lib))
    for name, (start, size, digest) in FUNCTIONS.items():
        sym = [s for s in elf.get_section_by_name('.dynsym').iter_symbols() if exported_name(s.name) == 'gml_Object_sys_UI_'+name]
        if len(sym) != 1 or (sym[0]['st_value'], sym[0]['st_size']) != (start,size):
            raise ValueError('unexpected export '+name)
        if hashlib.sha256(elf_file_bytes(lib,start,size)).hexdigest() != digest:
            raise ValueError('unexpected function bytes '+name)
    plt, rp = elf.get_section_by_name('.plt'), elf.get_section_by_name('.rel.plt')
    symbols = elf.get_section(rp['sh_link'])
    calls = {plt['sh_addr']+20+i*12: symbols.get_symbol(r['r_info_sym']).name for i,r in enumerate(rp.iter_relocations())}
    if 'gml_Script_backpack_close' not in calls.get(0x176678,'') or 'REAL_RValue' not in calls.get(0x176444,''):
        raise ValueError('unexpected call relocations')
    dis = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    def check(addr, op, args):
        x = list(dis.disasm(elf_file_bytes(lib,addr,4),addr))
        if len(x) != 1 or (x[0].mnemonic,x[0].op_str) != (op,args):
            raise ValueError('unexpected instruction at '+hex(addr))
    checks = [
        (0x5716fc,'mov','r1, #0x64'), (0x571734,'bhi','#0x571790'),
        (0x57174c,'movw','r1, #0x242'), (0x571784,'movt','r1, #0x3ff0'),
        (0x57182c,'mov','r1, #0x64'), (0x571864,'bls','#0x5718b0'),
        (0x57187c,'mov','r1, #0x25c'), (0x5718c4,'movw','r1, #0x242'),
        (0x5718fc,'movt','r1, #0x3ff0'), (0x5719a4,'movw','r1, #0x21a'),
        (0x5719b0,'vmov.f64','d1, #5.000000e-01'), (0x5719c0,'ble','#0x571a20'),
        (0x5719d8,'movw','r1, #0x155'), (0x571a34,'mov','r1, #0x64'),
        (0x571a6c,'bhi','#0x571b14'), (0x571a84,'movw','r1, #0x155'),
        (0x571adc,'movw','r1, #0x156'), (0x571b04,'mov','r0, #0'),
        (0x4f7fd0,'movw','r1, #0x21a'), (0x4f801c,'movw','r1, #0x155'),
        (0x4f8068,'movw','r1, #0x156'), (0x4f8394,'movw','r1, #0x242'),
        (0x4f83e0,'mov','r1, #0x25c'), (0x50aff4,'mov','r1, #0x25c'),
        (0x50b010,'ble','#0x50b0e8'), (0x50b028,'mov','r1, #0x25c'),
        (0x50b068,'str','r1, [r4]'), (0x50b088,'bl','#0x176678'),
    ]
    for c in checks: check(*c)
    return {'exports': {k:{'address':hex(v[0]),'sha256':v[2]} for k,v in FUNCTIONS.items()},
            'slot_aliases': {'0x64':'backpack_open', '0x242':'backpack_order_open',
                             '0x25c':'backpack_order_close', '0x21a':'pause',
                             '0x155':'pause_request', '0x156':'pause_kind'},
            'limitations':'Aliases inferred from corresponding old source and native access patterns. Native comparison uses epsilon for near-zero, and close uses >0.5; source may differ for unusual values. No Android/iOS execution.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk',type=Path); p.add_argument('project',type=Path); p.add_argument('--output',type=Path,required=True)
    a = p.parse_args(); verify_source(a.project)
    a.output.write_text(json.dumps(inspect(a.apk),indent=2)+'\n',encoding='utf-8')
    print('INVENTORY_KEYS_EVIDENCE: partial static candidate only')


if __name__ == '__main__': main()
