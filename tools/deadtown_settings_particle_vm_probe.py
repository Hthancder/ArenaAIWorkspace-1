#!/usr/bin/env python3
"""Probe settings fragments and particle gates with fake INI/particle builtins.

The transformed scripts are diagnostic copies only. No real particle engine,
controller, disk persistence, native Android execution or iOS is tested.
"""
import argparse
import json
from pathlib import Path
import shutil

try:
    from tools.deadtown_settings_particle_evidence import PARTICLES, SETTINGS, SHADOW, SHADOW_OBJECTS, ACTION_SHADOW, ACTION_SHADOW_OBJECTS, shadow_source, verify_source
except ModuleNotFoundError:
    from deadtown_settings_particle_evidence import PARTICLES, SETTINGS, SHADOW, SHADOW_OBJECTS, ACTION_SHADOW, ACTION_SHADOW_OBJECTS, shadow_source, verify_source

EXPECTED = [
    'SETTINGS_PARTICLE_VM:new:1111111',
    'SETTINGS_PARTICLE_VM:load:2345678',
    'SETTINGS_PARTICLE_VM:save:7:2345678',
    'SETTINGS_PARTICLE_VM:disabled:0',
    'SETTINGS_PARTICLE_VM:threshold:0',
    'SETTINGS_PARTICLE_VM:enabled:123:123:1243:1253',
    'SETTINGS_PARTICLE_VM:shadow-off:0:3',
    'SETTINGS_PARTICLE_VM:shadow-half:0:3',
    'SETTINGS_PARTICLE_VM:shadow-on:3:3',
    'SETTINGS_PARTICLE_VM:action-off:0',
    'SETTINGS_PARTICLE_VM:action-half:0',
    'SETTINGS_PARTICLE_VM:action-on:3',
]
PART_BUILTINS = {'part_emitter_region': 1, 'part_type_direction': 2,
                 'part_emitter_burst': 3, 'part_type_size': 4, 'part_type_orientation': 5}


def instrument(events, project):
    # Exercise only the exact gate+draw fragment, replacing actual draw calls
    # with counters. The surrounding original Draw events are not executed.
    fragment = ''
    for name in SHADOW_OBJECTS:
        text = shadow_source(project, name)
        if text.count(SHADOW) != 1:
            raise ValueError('unexpected Draw fragment')
        fragment += SHADOW.replace('draw_sprite_ext(sprite_index,image_index,xx,yy,image_xscale,image_yscale,image_angle,c_black,0.5)', 'global.__dt_shadow_calls += 1;').replace('draw_self()', 'global.__dt_self_calls += 1;') + '\n'
    action_fragment = ''
    for name in ACTION_SHADOW_OBJECTS:
        text = shadow_source(project, name)
        if text.count(ACTION_SHADOW) != 1:
            raise ValueError('unexpected action Draw fragment')
        action_fragment += ACTION_SHADOW.replace('draw_sprite_ext(sprite_index,image_index,xx+shake_x,yy+shake_y,image_xscale,image_yscale,image_angle,c_black,0.5)', 'global.__dt_shadow_calls += 1;') + '\n'
    found = [e for e in events if e.get('object') == 'sys_global' and
             e.get('attributes', {}).get('eventtype') == '0' and
             e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError('expected sys_global Create')
    aliases = [s[2] for s in SETTINGS]
    values = ' + '.join('string(global.__dt_setting_'+x+')' for x in aliases)
    all_calls = 'particle_burst(1,2,3,4,5,6); particle_burst_up(1,2,3,4,5,6); particle_burst_up_size(1,2,3,4,5,6,7); particle_burst_up_out(1,2,3,4,5,6);'
    prefix = f'''global.__dt_ini_has = 0;
global.__dt_ini_write_count = 0;
global.__dt_ini_write_values = "";
setting_load();
show_debug_message("SETTINGS_PARTICLE_VM:new:" + {values});
global.__dt_ini_has = 1;
setting_load();
show_debug_message("SETTINGS_PARTICLE_VM:load:" + {values});
setting_save();
show_debug_message("SETTINGS_PARTICLE_VM:save:" + string(global.__dt_ini_write_count) + ":" + global.__dt_ini_write_values);
global.__dt_pt_order = 0; global.__dt_setting_particle = 0;
{all_calls}
show_debug_message("SETTINGS_PARTICLE_VM:disabled:" + string(global.__dt_pt_order));
global.__dt_pt_order = 0; global.__dt_setting_particle = 0.5;
{all_calls}
show_debug_message("SETTINGS_PARTICLE_VM:threshold:" + string(global.__dt_pt_order));
global.__dt_setting_particle = 1; global.__dt_pt_order = 0;
particle_burst(1,2,3,4,5,6); var pt_a = global.__dt_pt_order; global.__dt_pt_order = 0;
particle_burst_up(1,2,3,4,5,6); var pt_b = global.__dt_pt_order; global.__dt_pt_order = 0;
particle_burst_up_size(1,2,3,4,5,6,7); var pt_c = global.__dt_pt_order; global.__dt_pt_order = 0;
particle_burst_up_out(1,2,3,4,5,6); var pt_d = global.__dt_pt_order;
show_debug_message("SETTINGS_PARTICLE_VM:enabled:" + string(pt_a) + ":" + string(pt_b) + ":" + string(pt_c) + ":" + string(pt_d));
global.__dt_shadow_calls = 0; global.__dt_self_calls = 0; global.__dt_setting_shadow = 0;
{fragment}
show_debug_message("SETTINGS_PARTICLE_VM:shadow-off:" + string(global.__dt_shadow_calls) + ":" + string(global.__dt_self_calls));
global.__dt_shadow_calls = 0; global.__dt_self_calls = 0; global.__dt_setting_shadow = 0.5;
{fragment}
show_debug_message("SETTINGS_PARTICLE_VM:shadow-half:" + string(global.__dt_shadow_calls) + ":" + string(global.__dt_self_calls));
global.__dt_shadow_calls = 0; global.__dt_self_calls = 0; global.__dt_setting_shadow = 1;
{fragment}
show_debug_message("SETTINGS_PARTICLE_VM:shadow-on:" + string(global.__dt_shadow_calls) + ":" + string(global.__dt_self_calls));
global.__dt_shadow_calls = 0; global.__dt_setting_shadow = 0;
{action_fragment}
show_debug_message("SETTINGS_PARTICLE_VM:action-off:" + string(global.__dt_shadow_calls));
global.__dt_shadow_calls = 0; global.__dt_setting_shadow = 0.5;
{action_fragment}
show_debug_message("SETTINGS_PARTICLE_VM:action-half:" + string(global.__dt_shadow_calls));
global.__dt_shadow_calls = 0; global.__dt_setting_shadow = 1;
{action_fragment}
show_debug_message("SETTINGS_PARTICLE_VM:action-on:" + string(global.__dt_shadow_calls));
global.__dt_ini_has = 0;
'''
    found[0]['gml'] = prefix + found[0]['gml']
    return events


def check(log):
    markers = [line.strip() for line in log.splitlines() if line.strip().startswith('SETTINGS_PARTICLE_VM:')]
    if markers != EXPECTED:
        raise ValueError(f'unexpected settings/particle markers: {markers!r}')
    return len(markers)


def make_project(project, dest):
    project, dest = Path(project), Path(dest)
    verify_source(project)
    if dest.exists() or project.resolve() in dest.resolve().parents:
        raise ValueError('destination must be new and outside source')
    dest.mkdir(parents=True)
    try:
        for folder in ('scripts', 'objects'):
            shutil.copytree(project / folder, dest / folder)
        scripts = dest / 'scripts'
        for name in PARTICLES:
            path = scripts / (name+'.gml')
            text = path.read_text(encoding='utf-8')
            for field, number in (('p_system_up', 10), ('p_emitter_up', 11), ('p_system', 12), ('p_emitter', 13)):
                text = text.replace('sys_particle.'+field, str(number))
            for builtin in PART_BUILTINS:
                text = text.replace(builtin+'(', '__dt_probe_'+builtin+'(')
            path.write_text(text, encoding='utf-8')
        for name in ('setting_load', 'setting_save'):
            path = scripts / (name+'.gml')
            text = path.read_text(encoding='utf-8')
            for builtin in ('ini_open', 'ini_close', 'ini_read_real', 'ini_write_real', 'display_get_width', 'os_get_language', 'lang_type_set'):
                text = text.replace(builtin+'(', '__dt_probe_'+builtin+'(')
            path.write_text(text, encoding='utf-8')
        mocks = {name: f'global.__dt_pt_order = global.__dt_pt_order * 10 + {number};\n' for name, number in PART_BUILTINS.items()}
        mocks.update({'ini_open': '', 'ini_close': '', 'display_get_width': 'return 1334;\n',
                      'os_get_language': 'return "en";\n', 'lang_type_set': ''})
        read = 'if (argument0 == "setting" && argument1 == "check") return global.__dt_ini_has;\n'
        write = ''
        for i, (section, key, *_rest) in enumerate(SETTINGS, 2):
            cond = f'argument0 == "{section}" && argument1 == "{key}"'
            read += f'if ({cond}) return {i};\n'
            write += f'if ({cond}) {{ global.__dt_ini_write_count += 1; global.__dt_ini_write_values += string(argument2); }}\n'
        mocks['ini_read_real'] = read + 'return argument2;\n'
        mocks['ini_write_real'] = write
        for name, text in mocks.items():
            path = scripts / ('__dt_probe_'+name+'.gml')
            if path.exists():
                raise ValueError('mock script collision')
            path.write_text(text or '/// mock no-op\n', encoding='utf-8')
    except Exception:
        shutil.rmtree(dest)
        raise


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='mode', required=True)
    i = sub.add_parser('instrument')
    i.add_argument('project', type=Path)
    i.add_argument('dest', type=Path)
    i.add_argument('events', type=Path)
    i.add_argument('output', type=Path)
    c = sub.add_parser('check')
    c.add_argument('log', type=Path)
    a = p.parse_args()
    if a.mode == 'instrument':
        if a.output.exists() or a.output.resolve() == a.events.resolve():
            raise ValueError('events output must be new and distinct')
        events = instrument(json.loads(a.events.read_text(encoding='utf-8')), a.project)
        make_project(a.project, a.dest)
        a.output.write_text(json.dumps(events, ensure_ascii=False), encoding='utf-8')
    else:
        print(f'SETTINGS_PARTICLE_VM:PASS {check(a.log.read_text(errors="replace"))} markers; mocked desktop VM only')


if __name__ == '__main__':
    main()
