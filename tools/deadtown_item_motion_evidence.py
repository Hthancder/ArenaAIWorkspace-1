#!/usr/bin/env python3
"""Pin a deliberately partial dropped-item collision repair to Android ARM32."""
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
    from tools.deadtown_native_inventory import exported_name, resource_names
    from tools.deadtown_native_lang import APK_SHA256, LIB_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_empty_collision_evidence import elf_file_bytes
    from deadtown_native_inventory import exported_name, resource_names
    from deadtown_native_lang import APK_SHA256, LIB_SHA256
    from recover_deadtown_audio import read_zip_member

MOTION = '''/// Partial Android ARM candidate: prevent dropped items entering action objects.
if sp > 0
{
    xx = lengthdir_x(sp,dir)
    yy = lengthdir_y(sp,dir)

    if fric < sp
    {sp -= fric}
    else
    {sp = 0}

    // Native performs another collision check first; its target is unresolved.
    if collision_rectangle(x+xx-20,y+yy-20,x+xx+20,y+yy+20,par_action,1,1) == noone
    {
        x += xx
        y += yy
    }
}
'''
START, SIZE = 0x625518, 10724
DIGEST = 'ebbdfcddff9f18fece1dfd64a26233674a585cf44b1d0a4cd9e4ce35c88e6b11'


def verify_source(project):
    root = ET.parse(Path(project)/'objects/obj_item.object.gmx').getroot()
    events = root.findall('./events/event[@eventtype="3"][@enumb="0"]')
    if len(events) != 1 or not events[0].findall('action'):
        raise ValueError('unexpected item Step')
    action = events[0].findall('action')[0]
    if (action.findtext('libid'),action.findtext('id'),action.findtext('kind'),action.findtext('./arguments/argument/string')) != ('1','603','7',MOTION):
        raise ValueError('unexpected item movement candidate')
    create = root.find('./events/event[@eventtype="0"][@enumb="0"]/action/arguments/argument/string')
    if create is None or 'dir = 0\nsp = 0\nfric = 0.2' not in (create.text or ''):
        raise ValueError('unexpected item initialization')


def inspect(apk):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    from capstone.arm import ARM_OP_MEM
    from elftools.elf.elffile import ELFFile
    if hashlib.sha256(Path(apk).read_bytes()).hexdigest()!=APK_SHA256:
        raise ValueError('unexpected APK')
    with zipfile.ZipFile(apk) as z:
        raw=read_zip_member(z,'lib/armeabi-v7a/libyoyo.so')
        data=read_zip_member(z,'assets/game.droid')
    if hashlib.sha256(raw).hexdigest()!=LIB_SHA256 or resource_names(data,b'OBJT')[184]!='par_action':
        raise ValueError('unexpected native inputs')
    elf=ELFFile(io.BytesIO(raw)); symbols=elf.get_section_by_name('.dynsym')
    for name,addr,size,digest in [('gml_Object_obj_item_Step_0',START,SIZE,DIGEST),
        ('gml_Object_obj_item_Create_0',0x6242f0,1140,'0c10fa52f80d8134b69c3e307e8567ab351b502c26c19f3cc87e23dfbe49a86c')]:
        x=[s for s in symbols.iter_symbols() if exported_name(s.name)==name]
        if len(x)!=1 or (x[0]['st_value'],x[0]['st_size'])!=(addr,size) or hashlib.sha256(elf_file_bytes(raw,addr,size)).hexdigest()!=digest:
            raise ValueError('unexpected native function '+name)
    rel=elf.get_section_by_name('.rel.dyn'); sy=elf.get_section(rel['sh_link'])
    got={x['r_offset']:sy.get_symbol(x['r_info_sym']) for x in rel.iter_relocations() if x['r_info_type']==21}
    plt=elf.get_section_by_name('.plt'); rp=elf.get_section_by_name('.rel.plt'); ps=elf.get_section(rp['sh_link'])
    calls={plt['sh_addr']+20+i*12:ps.get_symbol(x['r_info_sym']).name for i,x in enumerate(rp.iter_relocations())}
    for a,n in ((0x176744,'YYGML_lengthdir_x'),(0x17675c,'YYGML_lengthdir_y'),
                (0x17654c,'YYGML_CallLegacyFunction'),(0x17642c,'Variable_GetValue_Direct'),
                (0x1768dc,'Variable_SetValue_Direct')):
        if n not in calls.get(a,''):raise ValueError('unexpected native call')
    d=Cs(CS_ARCH_ARM,CS_MODE_ARM);d.detail=True
    def ins(a):
        it=list(d.disasm(elf_file_bytes(raw,a,4),a))
        if len(it)!=1:raise ValueError('bad instruction')
        return it[0]
    def check(a,op,args):
        i=ins(a)
        if (i.mnemonic,i.op_str)!=(op,args):raise ValueError('unexpected instruction '+hex(a))
    def lit(a):
        i=ins(a)
        if i.mnemonic!='ldr' or len(i.operands)!=2 or i.operands[1].type!=ARM_OP_MEM or i.reg_name(i.operands[1].mem.base)!='pc':raise ValueError('bad literal')
        return struct.unpack('<I',elf_file_bytes(raw,a+8+i.operands[1].mem.disp,4))[0]
    def symbol(base,add,off,name):
        s=got.get((add+8+lit(base)+lit(off))&0xffffffff)
        if s is None or s.name!=name:raise ValueError('unexpected relocation '+name)
        return s
    symbol(0x625da8,0x625db0,0x625dac,'g_FUNC_collision_rectangle')
    target=symbol(0x625da8,0x625db0,0x625db4,'gs_constArg2_703')
    precise=symbol(0x625da8,0x625db0,0x625b2c,'gs_constArg1_703')
    for s,value in ((target,184.0),(precise,1.0)):
        if s['st_size']!=16 or elf_file_bytes(raw,s['st_value'],16)!=struct.pack('<dII',value,0,0):
            raise ValueError('unexpected collision argument')
    for a,op,args in ((0x625658,'movw','r1, #0x12d'),(0x625698,'bpl','#0x62601c'),
        (0x6256b0,'movw','r1, #0x12d'),(0x6256c8,'mov','r1, #0x12c'),
        (0x6256e0,'mov','r1, #0xca'),(0x62571c,'bl','#0x176744'),
        (0x625780,'mov','r1, #0xcb'),(0x6257bc,'bl','#0x17675c'),
        (0x625818,'movw','r1, #0x447'),(0x62583c,'bl','#0x176594'),
        (0x625844,'blt','#0x625898'),(0x62585c,'movw','r1, #0x12d'),
        (0x6258ac,'movw','r1, #0x12d'),(0x6258c4,'movw','r1, #0x447'),
        (0x625c60,'bl','#0x17660c'),(0x625cc4,'bl','#0x17660c'),
        (0x625d24,'bl','#0x176660'),(0x625d88,'bl','#0x176660'),
        (0x625db0,'add','r0, pc, r0'),(0x625dd4,'str','r1, [sp, #0x17c]'),
        (0x625dd8,'str','r0, [sp, #0x180]'),(0x625ddc,'str','r0, [sp, #0x184]'),
        (0x625df4,'mov','r3, #7'),(0x625dfc,'bl','#0x17654c'),
        (0x625e14,'vadd.f64','d0, d0, d9'),(0x625e38,'bhi','#0x625f4c'),
        (0x625e80,'mov','r1, #0xca'),(0x625eac,'bl','#0x17642c'),
        (0x625edc,'bl','#0x1768dc'),(0x625ef4,'mov','r1, #0xcb'),
        (0x625f48,'bl','#0x1768dc')):check(a,op,args)
    return {'event':'obj_item:Step:0','address':hex(START),'sha256':DIGEST,
        'recovered':'moving item rectangle with 20-unit margins checks par_action, precise=1, notme=1; update x/y only when clear',
        'limitations':'Partial: earlier native collision check is omitted because its target is unresolved; aliases are inferred from older source, near-zero epsilon and float behavior may differ. No native or iOS execution.'}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('apk',type=Path);p.add_argument('project',type=Path);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();verify_source(a.project);a.output.write_text(json.dumps(inspect(a.apk),indent=2)+'\n',encoding='utf-8');print('ITEM_MOTION_EVIDENCE: partial static candidate')
if __name__=='__main__':main()
