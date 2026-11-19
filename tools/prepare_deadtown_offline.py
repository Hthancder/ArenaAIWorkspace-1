#!/usr/bin/env python3
"""Prepare an untested, local-only Dead Town GMX copy from the staged project."""
import argparse
import hashlib
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

EXPECTED_INPUT_HASHES = {
    'Configs/Default.config.gmx': '2459e02a57e1a46e0870ed0c805e3007947322f9bed9c7b2be3ca3b2e4d169ea',
    'deadtown.project.gmx': '230d021445d610ece7e3813dc4d6a4e40b7222c996c412a1a6d88a547c519182',
    'objects/obj_lobby_ach.object.gmx': '1d49fba812aad4ede67a56ae02f52f961c800de1918304a37ecc16ffa92860d6',
    'objects/obj_lobby_leader.object.gmx': '6f0a6884f1ddfb5bebe47262014e81ee9740356a2a0616649ea5ad5a8f304bc0',
    'objects/obj_lobby_test2.object.gmx': 'cc15b03f19bba3289faab68dec9704199739b9b20a633b36e525849e33c65b1b',
    'objects/obj_shop_item.object.gmx': '7bc4f3355142c056da579b5afef242b30767cb4aa7a2ed85f9bd6d493bd06e5b',
    'objects/obj_shop_restore.object.gmx': '551cf5cebd79ef525b06f9110c923a6c883e7d6f2ee7743ea68dcf9f40d75da7',
    'objects/sys_UI.object.gmx': 'd5d8a85b799cf3bf0399de51407c4c83c46c6ad73d6ecac32f76635cf886885a',
    'objects/sys_global.object.gmx': '53129e7c25e460a9f176902009c13c7589956f0ae13312698c9dfafba7c8c98a',
    'objects/sys_spawn_time_light.object.gmx': 'e8f08fe2f7e954ac75a9ecbc9a70e74436d88eb831d8bcec5e32143e9788c6bb',
    'scripts/achievement_plus.gml': '349984a57c540582bb262f6705c7aae97f0be9b4b292648b85344badffc344d7',
    'scripts/iap_activate_auto.gml': '5241edc2c8a4b2560317edbc8db27116e294a0995981acbf920aa212bbb65fde',
    'scripts/iap_consume_auto.gml': 'fdbf45e7dad3d9e99a00c3df4c1a51a54e7d1d419da81df29efc3b3a1eb6d2d5',
    'scripts/leaderboard_post.gml': 'd7c9f80e50322b8df62c7cf498e8695cf0f599d63a25ece81180c197d8974bee',
    'scripts/shop_db_add.gml': '7deccd0b660f54b2f6a8402680bba303ca905422a02b6026aee28fb98e6485c7',
    'scripts/unity_ads_show_scr.gml': '16d25bbb1c20989470473e35a1c3c649c61d410b44ea5fbc72d42ff5c975b23a',
}


class PatchError(ValueError):
    pass


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise PatchError(f'{label}: expected one matching block, found {count}')
    return text.replace(old, new, 1)


def replace_in_strings(tree, old, new, label):
    nodes = [node for node in tree.iter('string') if old in (node.text or '')]
    if len(nodes) != 1:
        raise PatchError(f'{label}: expected one matching GML action, found {len(nodes)}')
    nodes[0].text = replace_once(nodes[0].text, old, new, label)


def plan(project):
    project = Path(project)
    files = {}

    def xml(rel):
        tree = ET.parse(project / rel)
        files[rel] = tree
        return tree

    def script(rel, value):
        files[rel] = value

    tree = xml('deadtown.project.gmx')
    ext = tree.find('NewExtensions')
    if ext is None or [x.text for x in ext] != [r'extensions\GooglePlayServicesExtension', r'extensions\UnityAds']:
        raise PatchError('unexpected extension list')
    ext.clear()

    config = xml('Configs/Default.config.gmx')
    setting = config.find('.//option_android_google_play')
    if setting is None or setting.text != '-1':
        raise PatchError('unexpected Google Play configuration')
    setting.text = '0'

    global_obj = xml('objects/sys_global.object.gmx')
    replace_in_strings(global_obj, 'iap_item_load()\n',
        'iap_item_load()\n\n// Offline test: grant the nine non-consumable shop items in memory.\n'
        'for (var offline_i = 5; offline_i <= 13; offline_i += 1)\n'
        '{ global.iap_purchase_info[offline_i,0] = 1; }\n', 'unlock items')
    replace_in_strings(global_obj, '    achievement_login();', '    // Offline: no social login.', 'social login')
    ad_setup = "if (os_type == os_android) {\n    unity_ads_init('1150782');\n} else if (os_type == os_ios) {\n    unity_ads_init('1150781');\n}\n\nunity_ads_set_test_mode(true);"
    replace_in_strings(global_obj, ad_setup, '// Offline: advertising service disabled.', 'ads init')
    nodes = [node for node in global_obj.iter('string') if 'var val = ds_map_find_value(iap_data, "type");' in (node.text or '')]
    if len(nodes) != 1 or 'iap_ev_consume' not in nodes[0].text:
        raise PatchError('purchase event differs from expected source')
    nodes[0].text = '// Offline: external purchase and restore callbacks disabled.\n'

    obj = xml('objects/obj_shop_item.object.gmx')
    purchase = '''if iap_status() == iap_status_available
                {
                    if item_product_id != ""
                    {
                        iap_acquire(item_product_id, "");
                    }
                }
                else
                {}'''
    replace_in_strings(obj, purchase, '// Offline: purchase service disabled.', 'shop purchase')

    obj = xml('objects/obj_shop_restore.object.gmx')
    replace_in_strings(obj, 'if os_type != os_ios', 'if true', 'hide restore button')
    replace_in_strings(obj, '    iap_restore_all();', '    // Offline: no store restore.', 'restore call')

    for obj_name, call in [('obj_lobby_ach', 'achievement_show_achievements();'),
                           ('obj_lobby_leader', 'achievement_show_leaderboards();'),
                           ('obj_lobby_test2', 'achievement_reset();')]:
        obj = xml(f'objects/{obj_name}.object.gmx')
        replace_in_strings(obj, 'achievement_available()', 'false', obj_name + ' availability')
        replace_in_strings(obj, call, '// Offline: social service disabled.', obj_name + ' call')

    path = 'scripts/achievement_plus.gml'
    text = (project / path).read_text(encoding='utf-8')
    old = '''if achievement_available()
{
    if os_type == os_android
    {ach = global.achievement_info[argument0,2]}
    if os_type == os_ios
    {ach = global.achievement_info[argument0,3]}
    
    achievement_post(ach, floor(100*global.achievement_info[argument0,0]/global.achievement_info[argument0,1]));
}
'''
    script(path, replace_once(text, old, '// Offline: retain local progress without posting.\n', 'achievement posting'))
    script('scripts/leaderboard_post.gml', '// Offline: leaderboard service disabled.\n')
    script('scripts/iap_activate_auto.gml', '// Offline: store activation disabled.\n')
    script('scripts/iap_consume_auto.gml', '// Offline: store consumption disabled.\n')
    script('scripts/unity_ads_show_scr.gml', '// Offline: ads disabled.\n')
    path = 'scripts/shop_db_add.gml'
    text = (project / path).read_text(encoding='utf-8')
    script(path, replace_once(text, 'global.shop_db[global.shop_db_index,4] = argument4 // price',
        'global.shop_db[global.shop_db_index,4] = 0 // offline: free shop', 'shop prices'))

    for name, expected in [('sys_spawn_time_light', 1), ('sys_UI', 2), ('obj_shop_item', 2)]:
        rel = f'objects/{name}.object.gmx'
        obj = files[rel] if rel in files else xml(rel)
        count = 0
        for node in obj.iter('string'):
            if node.text:
                count += node.text.count('unity_ads_check_is_can_show()')
                node.text = node.text.replace('unity_ads_check_is_can_show()', 'false')
        if count != expected:
            raise PatchError(f'{name}: expected {expected} ad checks, found {count}')
    return files


def prepare(source, output):
    source, output = Path(source), Path(output)
    if not (source / 'deadtown.project.gmx').is_file():
        raise PatchError('source must contain deadtown.project.gmx')
    if output.exists():
        raise PatchError('output already exists; refusing to overwrite')
    if source.resolve() in output.resolve().parents:
        raise PatchError('output must not be inside the source')
    for rel, expected in EXPECTED_INPUT_HASHES.items():
        if hashlib.sha256((source / rel).read_bytes()).hexdigest() != expected:
            raise PatchError(f'unexpected source file: {rel}')
    files = plan(source)
    shutil.copytree(source, output)
    for rel, value in files.items():
        if isinstance(value, ET.ElementTree):
            value.write(output / rel, encoding='utf-8', xml_declaration=True)
        else:
            (output / rel).write_text(value, encoding='utf-8')
    return len(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', help='staged GMX directory with recovered audio')
    parser.add_argument('output', help='new GMX directory for offline experiment')
    args = parser.parse_args()
    try:
        count = prepare(args.source, args.output)
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 2
    print(f'Prepared {count} changed files in {args.output}; no build or runtime test performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
