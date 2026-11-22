#!/usr/bin/env python3
"""Probe settings fragments and particle gates with fake INI/particle builtins.

The transformed scripts are diagnostic copies only. No real particle engine,
controller, disk persistence, native Android execution or iOS is tested.
"""
import argparse
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

try:
    from tools.deadtown_settings_particle_evidence import ROOF_SHADOW, PLAYER_SHADOW, PLAYER_FEEDBACK, INTERPOLATION_EVENT
    from tools.deadtown_crosshair_evidence import verify_source as verify_crosshair_source
except ModuleNotFoundError:
    from deadtown_settings_particle_evidence import ROOF_SHADOW, PLAYER_SHADOW, PLAYER_FEEDBACK, INTERPOLATION_EVENT
    from deadtown_crosshair_evidence import verify_source as verify_crosshair_source

try:
    from tools.deadtown_settings_particle_evidence import PARTICLES, SETTINGS, SHADOW, SHADOW_OBJECTS, ACTION_SHADOW, ACTION_SHADOW_OBJECTS, shadow_source, verify_source
except ModuleNotFoundError:
    from deadtown_settings_particle_evidence import PARTICLES, SETTINGS, SHADOW, SHADOW_OBJECTS, ACTION_SHADOW, ACTION_SHADOW_OBJECTS, shadow_source, verify_source

EXPECTED = [
    'SETTINGS_PARTICLE_VM:new:1111111',
    'SETTINGS_PARTICLE_VM:load:2345678',
    'SETTINGS_PARTICLE_VM:save:7:2345678',
    'SETTINGS_PARTICLE_VM:sound-new:1:1',
    'SETTINGS_PARTICLE_VM:sound-load:2:3',
    'SETTINGS_PARTICLE_VM:sound-save:1:1',
    'SETTINGS_PARTICLE_VM:audio-init:1:1',
    'SETTINGS_PARTICLE_VM:audio-play:1:1:1',
    'SETTINGS_PARTICLE_VM:disabled:0',
    'SETTINGS_PARTICLE_VM:threshold:0',
    'SETTINGS_PARTICLE_VM:enabled:123:123:1243:1253',
    'SETTINGS_PARTICLE_VM:shadow-off:0:3',
    'SETTINGS_PARTICLE_VM:shadow-half:0:3',
    'SETTINGS_PARTICLE_VM:shadow-on:3:3',
    'SETTINGS_PARTICLE_VM:action-off:0',
    'SETTINGS_PARTICLE_VM:action-half:0',
    'SETTINGS_PARTICLE_VM:action-on:3',
    'SETTINGS_PARTICLE_VM:roof-off:0:2',
    'SETTINGS_PARTICLE_VM:roof-half:0:2',
    'SETTINGS_PARTICLE_VM:roof-on:1:2',
    'SETTINGS_PARTICLE_VM:player-off:0',
    'SETTINGS_PARTICLE_VM:player-half:0',
    'SETTINGS_PARTICLE_VM:player-near:1',
    'SETTINGS_PARTICLE_VM:player-gun:10',
    'SETTINGS_PARTICLE_VM:feedback-off:0:0',
    'SETTINGS_PARTICLE_VM:feedback-half:0:0',
    'SETTINGS_PARTICLE_VM:feedback-gamepad:1:0',
    'SETTINGS_PARTICLE_VM:feedback-idle:1:0',
    'SETTINGS_PARTICLE_VM:feedback-active:1:1',
    'SETTINGS_PARTICLE_VM:crosshair-short:0:1:1:1',
    'SETTINGS_PARTICLE_VM:crosshair-boundary:0:1:1:1',
    'SETTINGS_PARTICLE_VM:crosshair-long:1:1:1:1',
    'SETTINGS_PARTICLE_VM:crosshair-geometry-short:0:1:1',
    'SETTINGS_PARTICLE_VM:crosshair-geometry-vertical:1:1:1',
    'SETTINGS_PARTICLE_VM:interpolate-off:0:1',
    'SETTINGS_PARTICLE_VM:interpolate-on:1:1',
    'SETTINGS_PARTICLE_VM:interpolate-raw:7:1',
]
PART_BUILTINS = {'part_emitter_region': 1, 'part_type_direction': 2,
                 'part_emitter_burst': 3, 'part_type_size': 4, 'part_type_orientation': 5}


def instrument(events, project):
    verify_crosshair_source(project)
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
    roof_text = shadow_source(project, 'par_building')
    if roof_text.count(ROOF_SHADOW) != 1:
        raise ValueError('unexpected roof Draw fragment')
    roof_fragment = ROOF_SHADOW.replace('draw_sprite_ext(roof_sprite,0,xx,yy,image_xscale,image_yscale,image_angle,c_black,0.3*roof_alpha)', 'global.__dt_shadow_calls += 1;')
    foreground = roof_text.split(ROOF_SHADOW)[1]
    foreground = foreground.replace('draw_sprite_ext(mask_index,0,x,y,image_xscale,image_yscale,image_angle,c_white,1)', 'global.__dt_self_calls += 1;')
    foreground = foreground.replace('draw_sprite_ext(roof_sprite,0,x,y,image_xscale,image_yscale,image_angle,roof_color,roof_alpha)', 'global.__dt_self_calls += 1;')
    if foreground.count('global.__dt_self_calls += 1;') != 2 or 'draw_' in foreground:
        raise ValueError('unexpected roof foreground fragment')
    roof_fragment += foreground
    player = PLAYER_SHADOW
    for angle, count in [('player_near_angle', 1), ('player_gun_angle', 10)]:
        draw = f'draw_sprite_ext(player_sprite,player_costume,xx,yy,global.char_aspect,global.char_aspect,{angle},c_black,0.5)'
        if player.count(draw) != 1:
            raise ValueError('unexpected player shadow branch')
        player = player.replace(draw, f'global.__dt_shadow_calls += {count};')
    system = ET.parse(Path(project)/'objects/sys_global.object.gmx').getroot()
    events_room_start = system.findall('./events/event[@eventtype="7"][@enumb="4"]/action/arguments/argument/string')
    if len(events_room_start) != 1 or events_room_start[0].text != INTERPOLATION_EVENT:
        raise ValueError('unexpected interpolation event')
    interpolation = INTERPOLATION_EVENT.replace('texture_set_interpolation(', '__dt_probe_texture_set_interpolation(')
    feedback = PLAYER_FEEDBACK.replace('gp_connect_check()', '__dt_probe_gp_feedback()')
    feedback = feedback.replace('sys_view.left_distance_ratio', 'global.__dt_feedback_distance')
    feedback = feedback.replace('fx = x+lengthdir_x(global.__dt_feedback_distance*100,sys_view.view_a+sys_view.left_direction)', 'global.__dt_feedback_fx = 1;')
    feedback = feedback.replace('fy = y+lengthdir_y(global.__dt_feedback_distance*100,sys_view.view_a+sys_view.left_direction)', 'global.__dt_feedback_fy = 1;')
    feedback = feedback.replace('draw_sprite_ext(spr_player_move,0,fx,fy,0.8,0.8,sys_view.view_a+sys_view.left_direction-90,c_white,0.5)', 'global.__dt_feedback_draws += global.__dt_feedback_fx * global.__dt_feedback_fy;')
    if 'sys_view.' in feedback or 'draw_sprite_ext(' in feedback:
        raise ValueError('unexpected player feedback operations')
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
global.__dt_ini_write_values = ""; global.__dt_sound_new = 0; global.__dt_bgm_new = 0;
setting_load();
global.__dt_sound_new = (global.setting_sound_effect == 0.5); global.__dt_bgm_new = (global.setting_bgm == 0.5);
show_debug_message("SETTINGS_PARTICLE_VM:new:" + {values});
global.__dt_ini_has = 1;
setting_load();
show_debug_message("SETTINGS_PARTICLE_VM:load:" + {values});
setting_save();
show_debug_message("SETTINGS_PARTICLE_VM:save:" + string(global.__dt_ini_write_count) + ":" + global.__dt_ini_write_values);
show_debug_message("SETTINGS_PARTICLE_VM:sound-new:" + string(global.__dt_sound_new) + ":" + string(global.__dt_bgm_new));
show_debug_message("SETTINGS_PARTICLE_VM:sound-load:" + string(global.setting_sound_effect) + ":" + string(global.setting_bgm));
show_debug_message("SETTINGS_PARTICLE_VM:sound-save:" + string(global.__dt_sound_write) + ":" + string(global.__dt_bgm_write));
global.__dt_audio_init_calls = 0; audio_init();
show_debug_message("SETTINGS_PARTICLE_VM:audio-init:" + string(emitter == 77) + ":" + string(global.__dt_audio_init_calls));
global.__dt_audio_gain_ok = 0; global.__dt_audio_play_ok = 0; global.__dt_audio_order = 0;
var sound_result = audio_play(123);
show_debug_message("SETTINGS_PARTICLE_VM:audio-play:" + string(global.__dt_audio_gain_ok) + ":" + string(global.__dt_audio_play_ok) + ":" + string(sound_result == 456 && global.__dt_audio_order == 12));
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
global.__dt_shadow_calls = 0; global.__dt_self_calls = 0; global.__dt_setting_shadow = 0;
{roof_fragment}
show_debug_message("SETTINGS_PARTICLE_VM:roof-off:" + string(global.__dt_shadow_calls) + ":" + string(global.__dt_self_calls));
global.__dt_shadow_calls = 0; global.__dt_self_calls = 0; global.__dt_setting_shadow = 0.5;
{roof_fragment}
show_debug_message("SETTINGS_PARTICLE_VM:roof-half:" + string(global.__dt_shadow_calls) + ":" + string(global.__dt_self_calls));
global.__dt_shadow_calls = 0; global.__dt_self_calls = 0; global.__dt_setting_shadow = 1;
{roof_fragment}
show_debug_message("SETTINGS_PARTICLE_VM:roof-on:" + string(global.__dt_shadow_calls) + ":" + string(global.__dt_self_calls));
weapon_kind = 3; weapon_launched = 1;
global.__dt_shadow_calls = 0; global.__dt_setting_shadow = 0;
{player}
show_debug_message("SETTINGS_PARTICLE_VM:player-off:" + string(global.__dt_shadow_calls));
global.__dt_shadow_calls = 0; global.__dt_setting_shadow = 0.5;
{player}
show_debug_message("SETTINGS_PARTICLE_VM:player-half:" + string(global.__dt_shadow_calls));
global.__dt_shadow_calls = 0; global.__dt_setting_shadow = 1;
{player}
show_debug_message("SETTINGS_PARTICLE_VM:player-near:" + string(global.__dt_shadow_calls));
global.__dt_shadow_calls = 0; weapon_kind = 0;
{player}
show_debug_message("SETTINGS_PARTICLE_VM:player-gun:" + string(global.__dt_shadow_calls));
global.__dt_feedback_distance = 0.8; global.__dt_feedback_gp = 0;
global.__dt_feedback_fx = 0; global.__dt_feedback_fy = 0;
global.__dt_feedback_checks = 0; global.__dt_feedback_draws = 0; global.__dt_setting_feedback = 0;
{feedback}
show_debug_message("SETTINGS_PARTICLE_VM:feedback-off:" + string(global.__dt_feedback_checks) + ":" + string(global.__dt_feedback_draws));
global.__dt_setting_feedback = 0.5;
{feedback}
show_debug_message("SETTINGS_PARTICLE_VM:feedback-half:" + string(global.__dt_feedback_checks) + ":" + string(global.__dt_feedback_draws));
global.__dt_setting_feedback = 1; global.__dt_feedback_gp = 1;
{feedback}
show_debug_message("SETTINGS_PARTICLE_VM:feedback-gamepad:" + string(global.__dt_feedback_checks) + ":" + string(global.__dt_feedback_draws));
global.__dt_feedback_checks = 0; global.__dt_feedback_gp = 0; global.__dt_feedback_distance = 0;
{feedback}
show_debug_message("SETTINGS_PARTICLE_VM:feedback-idle:" + string(global.__dt_feedback_checks) + ":" + string(global.__dt_feedback_draws));
global.__dt_feedback_checks = 0; global.__dt_feedback_distance = 0.8;
{feedback}
show_debug_message("SETTINGS_PARTICLE_VM:feedback-active:" + string(global.__dt_feedback_checks) + ":" + string(global.__dt_feedback_draws));
global.__dt_cross_distance = 50; global.__dt_cross_scale = 0.5; global.__dt_cross_angle = 45;
global.__dt_cross_args = 0; global.__dt_cross_draw_ok = 0; global.__dt_cross_calls = 0;
draw_line_crosshair(11, 22, 33, 44);
show_debug_message("SETTINGS_PARTICLE_VM:crosshair-short:" + string(global.__dt_cross_frame) + ":" + string(global.__dt_cross_args) + ":" + string(global.__dt_cross_draw_ok) + ":" + string(global.__dt_cross_calls));
global.__dt_cross_distance = 100; global.__dt_cross_scale = 1;
global.__dt_cross_args = 0; global.__dt_cross_draw_ok = 0; global.__dt_cross_calls = 0;
draw_line_crosshair(11, 22, 33, 44);
show_debug_message("SETTINGS_PARTICLE_VM:crosshair-boundary:" + string(global.__dt_cross_frame) + ":" + string(global.__dt_cross_args) + ":" + string(global.__dt_cross_draw_ok) + ":" + string(global.__dt_cross_calls));
global.__dt_cross_distance = 150; global.__dt_cross_scale = 1.5;
global.__dt_cross_args = 0; global.__dt_cross_draw_ok = 0; global.__dt_cross_calls = 0;
draw_line_crosshair(11, 22, 33, 44);
show_debug_message("SETTINGS_PARTICLE_VM:crosshair-long:" + string(global.__dt_cross_frame) + ":" + string(global.__dt_cross_args) + ":" + string(global.__dt_cross_draw_ok) + ":" + string(global.__dt_cross_calls));
global.__dt_cross_draw_ok = 0; global.__dt_cross_calls = 0; global.__dt_cross_scale = 0.5; global.__dt_cross_angle = 0;
__dt_cross_geometry(11, 22, 61, 22);
show_debug_message("SETTINGS_PARTICLE_VM:crosshair-geometry-short:" + string(global.__dt_cross_frame) + ":" + string(global.__dt_cross_draw_ok) + ":" + string(global.__dt_cross_calls));
global.__dt_cross_draw_ok = 0; global.__dt_cross_calls = 0; global.__dt_cross_scale = 1.5; global.__dt_cross_angle = 270;
__dt_cross_geometry(11, 22, 11, 172);
show_debug_message("SETTINGS_PARTICLE_VM:crosshair-geometry-vertical:" + string(global.__dt_cross_frame) + ":" + string(global.__dt_cross_draw_ok) + ":" + string(global.__dt_cross_calls));
global.__dt_setting_interpolate = 0; global.__dt_interp_calls = 0;
{interpolation}
show_debug_message("SETTINGS_PARTICLE_VM:interpolate-off:" + string(global.__dt_interp_value) + ":" + string(global.__dt_interp_calls));
global.__dt_setting_interpolate = 1; global.__dt_interp_calls = 0;
{interpolation}
show_debug_message("SETTINGS_PARTICLE_VM:interpolate-on:" + string(global.__dt_interp_value) + ":" + string(global.__dt_interp_calls));
global.__dt_setting_interpolate = 7; global.__dt_interp_calls = 0;
{interpolation}
show_debug_message("SETTINGS_PARTICLE_VM:interpolate-raw:" + string(global.__dt_interp_value) + ":" + string(global.__dt_interp_calls));
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
    verify_crosshair_source(project)
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
        crosshair = scripts/'draw_line_crosshair.gml'
        original_crosshair = crosshair.read_text(encoding='utf-8')
        text = original_crosshair
        for builtin in ('point_direction', 'point_distance', 'draw_get_colour', 'draw_get_alpha', 'draw_sprite_ext'):
            text = text.replace(builtin+'(', '__dt_cross_'+builtin+'(')
        crosshair.write_text(text.replace('spr_crosshair', '181'), encoding='utf-8')
        geometry = original_crosshair
        for builtin in ('draw_get_colour', 'draw_get_alpha', 'draw_sprite_ext'):
            geometry = geometry.replace(builtin+'(', '__dt_cross_'+builtin+'(')
        (scripts/'__dt_cross_geometry.gml').write_text(geometry.replace('spr_crosshair', '181'), encoding='utf-8')
        for name in ('setting_load', 'setting_save'):
            path = scripts / (name+'.gml')
            text = path.read_text(encoding='utf-8')
            for builtin in ('ini_open', 'ini_close', 'ini_read_real', 'ini_write_real', 'display_get_width', 'os_get_language', 'lang_type_set'):
                text = text.replace(builtin+'(', '__dt_probe_'+builtin+'(')
            path.write_text(text, encoding='utf-8')
        audio_init = scripts/'audio_init.gml'
        audio_init.write_text(audio_init.read_text(encoding='utf-8').replace('audio_emitter_create(', '__dt_probe_audio_emitter_create('), encoding='utf-8')
        audio_play = scripts/'audio_play.gml'
        audio_text = audio_play.read_text(encoding='utf-8')
        for builtin in ('audio_emitter_gain', 'audio_play_sound_on'):
            audio_text = audio_text.replace(builtin+'(', '__dt_probe_'+builtin+'(')
        audio_play.write_text(audio_text, encoding='utf-8')
        mocks = {name: f'global.__dt_pt_order = global.__dt_pt_order * 10 + {number};\n' for name, number in PART_BUILTINS.items()}
        mocks['audio_emitter_create'] = 'global.__dt_audio_init_calls += 1; return 77;\n'
        mocks['audio_emitter_gain'] = 'global.__dt_audio_order = global.__dt_audio_order * 10 + 1; global.__dt_audio_gain_ok = (argument0 == 77 && argument1 == 2);\n'
        mocks['audio_play_sound_on'] = 'global.__dt_audio_order = global.__dt_audio_order * 10 + 2; global.__dt_audio_play_ok = (argument0 == 77 && argument1 == 123 && argument2 == 0 && argument3 == 0); return 456;\n'
        cross_mocks = {
            'point_direction': 'if (argument0 == 11 && argument1 == 22 && argument2 == 33 && argument3 == 44) global.__dt_cross_args += 1; return 45;\n',
            'point_distance': 'if (argument0 != 11 || argument1 != 22 || argument2 != 33 || argument3 != 44) global.__dt_cross_args = 0; return global.__dt_cross_distance;\n',
            'draw_get_colour': 'return 123;\n', 'draw_get_alpha': 'return 0.75;\n',
            'draw_sprite_ext': 'global.__dt_cross_calls += 1; global.__dt_cross_frame = argument1; if (argument0 == 181 && argument2 == 11 && argument3 == 22 && argument4 == global.__dt_cross_scale && argument5 == 1 && argument6 == global.__dt_cross_angle && argument7 == 123 && argument8 == 0.75) global.__dt_cross_draw_ok = 1;\n',
        }
        for name, text in cross_mocks.items():
            (scripts/('__dt_cross_'+name+'.gml')).write_text(text, encoding='utf-8')
        mocks['gp_feedback'] = 'global.__dt_feedback_checks += 1; return global.__dt_feedback_gp;\n'
        mocks['texture_set_interpolation'] = 'global.__dt_interp_value = argument0; global.__dt_interp_calls += 1;\n'
        mocks.update({'ini_open': '', 'ini_close': '', 'display_get_width': 'return 1334;\n',
                      'os_get_language': 'return "en";\n', 'lang_type_set': ''})
        read = ('if (argument0 == "setting" && argument1 == "check") return global.__dt_ini_has;\n'
                'if (argument0 == "sound" && argument1 == "effect") return 2;\n'
                'if (argument0 == "sound" && argument1 == "bgm") return 3;\n')
        write = ('if (argument0 == "sound" && argument1 == "effect") global.__dt_sound_write = (argument2 == 2);\n'
                 'if (argument0 == "sound" && argument1 == "bgm") global.__dt_bgm_write = (argument2 == 3);\n')
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
