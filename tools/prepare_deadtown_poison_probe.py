#!/usr/bin/env python3
"""Make a disposable candidate poison reconstruction for VM research only.

This is NOT a complete game, an IPA, or a validated APK-equivalent patch. It
only creates a new directory from the exact pinned offline GMX and APK, never
modifies the source, never touches saves, and is not used by IPA workflows.
It applies selected static findings so they can be exercised in isolation in
an incomplete desktop VM. Native control flow, other game modes, content, UI,
resource IDs and iOS behavior remain incomplete or unverified.
"""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.deadtown_native_inventory import resource_names
    from tools.deadtown_native_tables import extract
    from tools.deadtown_poison_evidence import inspect
    from tools.prepare_deadtown_offline import PatchError, replace_in_strings, replace_once
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_native_inventory import resource_names
    from deadtown_native_tables import extract
    from deadtown_poison_evidence import inspect
    from prepare_deadtown_offline import PatchError, replace_in_strings, replace_once
    from recover_deadtown_audio import read_zip_member

EXPECTED = {
    'objects/sys_global.object.gmx': '602eee057b86aba0c4603e4477fdf3844eac8ce3846530b6584618c9dbfdd0ea',
    'objects/sys_player_buff.object.gmx': 'a41582ab55866b878b9caed7ee121a0a66c8a23f77bd84966603b17c70d1c073',
    'objects/obj_player.object.gmx': '475043d53c07f158104959e1660e7fb3d69c8167655f358a3087b140d2d49898',
    'scripts/db_use_add.gml': '4087bacaf9b7fbc60d791db7fbc1f33a4f41522b62dd7a79e97623f3bbfd8d7d',
    'scripts/item_use.gml': '51f23d4822fef3010f5cc3a506b432340f192ad1143552efb0ba98a89c61211b',
    'scripts/game_save_protect.gml': '065e15eea216dd3d62a4061e79fadacd3040f86cbebeb884408f3e48be2ae8ea',
    'scripts/game_load_protect.gml': '215ba64681c568a97247a0cab286ed8af66d9846e9bc22a8786d495556621cb7',
}
ROW = re.compile(r'^db_use_add\("([^"\n]+)"[^\n]*\)$', re.MULTILINE)
NOTICE = ('DISPOSABLE RESEARCH PROBE ONLY: this is NOT a complete game, release or IPA.\n'
          'Never use this directory as a release input or with a user save.\n')


def quoted(value):
    if not isinstance(value, str) or any(ord(c) < 32 or c in '\\"' for c in value):
        raise PatchError('unsupported native string literal')
    return '"' + value + '"'


def replace_use_rows(action, entries):
    """Validate source ordering and format the 22 static native candidates."""
    old = list(ROW.finditer(action))
    if len(old) != 20 or len(entries) != 22:
        raise PatchError('unexpected consumable table size')
    names, lines = [], []
    for entry in entries:
        args = entry.get('arguments', [])
        if len(args) != 10 or [x.get('type') for x in args] != ['string', 'number', 'string'] + ['number'] * 7:
            raise PatchError('unexpected consumable argument layout')
        values = [x.get('value') for x in args]
        if values[1] != 0:
            raise PatchError('unexpected consumable sprite index')
        if any(not isinstance(x, (float, int)) or isinstance(x, bool) or not float(x).is_integer()
               for x in values[3:]):
            raise PatchError('unexpected noninteger consumable value')
        names.append(values[0])
        fields = [quoted(values[0]), 'spr_noone', quoted(values[2])] + [str(int(x)) for x in values[3:]]
        lines.append('db_use_add(' + ','.join(fields) + ')')
    if names[:20] != [x.group(1) for x in old] or names[20:] != ['Gas mask', 'Splint']:
        raise PatchError('native consumable ordering differs from expected source prefix')
    if [x['value'] for x in entries[20]['arguments']][9] != 3:
        raise PatchError('unexpected Gas mask protection candidate')
    if any([x['value'] for x in item['arguments']][9] != 0 for i, item in enumerate(entries) if i != 20):
        raise PatchError('unexpected additional protection candidate')
    begin, end = old[0].start(), old[-1].end()
    if action[begin:end].splitlines() != [x.group(0) for x in old]:
        raise PatchError('source consumable calls are not contiguous')
    return action[:begin] + '\n'.join(lines) + action[end:]


def plan(source, apk):
    """Return planned edits; all validation happens before output creation."""
    source = Path(source)
    for rel, digest in EXPECTED.items():
        if hashlib.sha256((source / rel).read_bytes()).hexdigest() != digest:
            raise PatchError(f'unexpected offline source: {rel}')
    evidence = inspect(apk)
    if (evidence['field'], evidence['variable_index'], evidence['player_object_name']) != (9, 32, 'obj_player'):
        raise PatchError('unexpected native field evidence')
    if evidence['save_load_evidence']['keys_to_player_indices'] != {'buffpoison': 171, 'buffpoisonprotect': 32}:
        raise PatchError('unexpected native save evidence')
    if (evidence['player_create_evidence']['candidate_bound_initial_value'],
        evidence['poison_damage_evidence']['create_divisor']) != (18000, 4500):
        raise PatchError('unexpected native player evidence')
    table = extract(apk)
    if table['counts']['db_use_add'] != {'resolved': 22, 'unresolved': 0}:
        raise PatchError('incomplete native consumable candidates')
    with zipfile.ZipFile(apk) as archive:
        game = read_zip_member(archive, 'assets/game.droid')
    if resource_names(game, b'SPRT')[0] != 'spr_noone':
        raise PatchError('unexpected APK sprite index zero')

    changed = {}
    obj = ET.parse(source / 'objects/sys_global.object.gmx')
    actions = [node for node in obj.iter('string') if 'db_use_add(' in (node.text or '')]
    if len(actions) != 1:
        raise PatchError('expected one consumable database action')
    actions[0].text = replace_use_rows(actions[0].text, table['entries']['db_use_add'])
    changed['objects/sys_global.object.gmx'] = obj

    path = 'scripts/db_use_add.gml'
    changed[path] = replace_once((source / path).read_text(encoding='utf-8'),
        'global.use_db[global.use_db_target,8]=item_cooked\n',
        'global.use_db[global.use_db_target,8]=item_cooked\n'
        'global.use_db[global.use_db_target,9]=argument9 // RE probe only\n', 'use DB column 9')
    path = 'scripts/item_use.gml'
    old = 'ins.buff_painkiller = db_info_get(target_inven,pointer,7)*30*60 // painkiller \n'
    changed[path] = replace_once((source / path).read_text(encoding='utf-8'), old,
        old + 'ins.buff_poison_protect = db_info_get(target_inven,pointer,9)*30*60 // RE probe only\n',
        'item use buff')

    path = 'objects/sys_player_buff.object.gmx'
    obj = ET.parse(source / path)
    replace_in_strings(obj, 'buff_painkiller = 0\n',
                       'buff_painkiller = 0\nbuff_poison_protect = 0 // RE probe only\n', 'buff initialization')
    replace_in_strings(obj, '    obj_player.buff_painkiller += buff_painkiller\n',
                       '    obj_player.buff_painkiller += buff_painkiller\n'
                       '    obj_player.buff_poison_protect += buff_poison_protect // RE probe only\n', 'buff transfer')
    changed[path] = obj

    path = 'objects/obj_player.object.gmx'
    obj = ET.parse(source / path)
    old = 'buff_poison = 0\nbuff_poison_max = 30*60 // 1 minutes\n'
    replace_in_strings(obj, old, old + 'buff_poison_protect = 0 // RE probe only\n'
                       'buff_poison_protect_max = 30*60*10\n', 'player initialization')
    replace_in_strings(obj, 'buff_poison_hurt = 0.06\n',
                       'buff_poison_hurt = hp_max/4500 // RE probe only\n', 'player poison damage')
    old = 'if buff_poison_max < buff_poison\n{buff_poison = buff_poison_max}\n'
    new = old + '''
// RE probe only; native event ordering and runtime equivalence are not proven.
if 0 < buff_poison_protect
{
    buff_poison_protect -= 1
    buff_poison = 0
}
else
{buff_poison_protect = 0}
if buff_poison_protect_max < buff_poison_protect
{buff_poison_protect = buff_poison_protect_max}
'''
    replace_in_strings(obj, old, new, 'player poison timer')
    changed[path] = obj

    path = 'scripts/game_save_protect.gml'
    old = 'ini_write_real("player","buffpoison",obj_player.buff_poison)\n'
    changed[path] = replace_once((source / path).read_text(encoding='utf-8'), old,
        old + 'ini_write_real("player","buffpoisonprotect",obj_player.buff_poison_protect) // RE probe only\n', 'save')
    path = 'scripts/game_load_protect.gml'
    old = 'obj_player.buff_poison = ini_read_real("player","buffpoison",0)\n'
    changed[path] = replace_once((source / path).read_text(encoding='utf-8'), old,
        old + 'obj_player.buff_poison_protect = ini_read_real("player","buffpoisonprotect",0) // RE probe only\n', 'load')
    return changed


def prepare(source, apk, output):
    source, output = Path(source), Path(output)
    if not (source / 'deadtown.project.gmx').is_file():
        raise PatchError('source must contain deadtown.project.gmx')
    if output.exists() or output.is_symlink():
        raise PatchError('output already exists; refusing to overwrite')
    if source.resolve() in output.resolve().parents or output.resolve() in source.resolve().parents:
        raise PatchError('source and output must not contain one another')
    changed = plan(source, apk)
    # Atomically claim the output so cleanup never removes a pre-existing path.
    output.mkdir()
    try:
        shutil.copytree(source, output, dirs_exist_ok=True)
        for rel, value in changed.items():
            if isinstance(value, ET.ElementTree):
                value.write(output / rel, encoding='utf-8', xml_declaration=True)
            else:
                (output / rel).write_text(value, encoding='utf-8')
        (output / 'RESEARCH-PROBE-NOT-A-RELEASE.txt').write_text(NOTICE, encoding='utf-8')
    except Exception:
        shutil.rmtree(output)
        raise
    return len(changed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('offline_source', type=Path)
    parser.add_argument('apk', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        count = prepare(args.offline_source, args.apk, args.output)
    except (OSError, ValueError, ET.ParseError) as exc:
        print('Error:', exc, file=sys.stderr)
        return 2
    print(f'Prepared {count} files in a disposable research probe; NOT a complete game or IPA.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
