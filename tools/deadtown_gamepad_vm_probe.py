#!/usr/bin/env python3
"""Create a disposable mocked-device VM probe; not a controller/iOS test.

Copies the source scripts and objects into a new directory, replacing only
GameMaker gamepad builtins in the four candidate scripts with deterministic
mock scripts. This must never be used as a real game build.
"""
import argparse
import json
from pathlib import Path
import shutil

try:
    from tools.deadtown_gamepad_evidence import FUNCTIONS, verify_source
except ModuleNotFoundError:
    from deadtown_gamepad_evidence import FUNCTIONS, verify_source

EXPECTED = ['GAMEPAD_VM:unsupported:0:0:0', 'GAMEPAD_VM:none:4:0:0',
            'GAMEPAD_VM:first:111:211:311:411:4:8:4',
            'GAMEPAD_VM:connect-gates:0:0:0:0:0:0',
            'GAMEPAD_VM:connect-empty:0:1:0:0',
            'GAMEPAD_VM:connect-active:1:1:4:2:13:0.2']

MOCKS = {
    'is_supported': 'return global.__dt_gp_supported;\n',
    'get_device_count': 'global.__dt_gp_count_calls += 1; return global.__dt_gp_count;\n',
    'is_connected': 'global.__dt_gp_connected_calls += 1; return (argument0 == 1 || argument0 == 3);\n',
    'set_axis_deadzone': 'global.__dt_gp_deadzone_calls += 1; global.__dt_gp_deadzone_order = global.__dt_gp_deadzone_order * 10 + argument0; global.__dt_gp_deadzone_value = argument1;\n',
}
for i, name in enumerate(('button_check', 'button_check_pressed', 'button_check_released', 'axis_value'), 1):
    MOCKS[name] = f'global.__dt_gp_read_calls += 1; return {i*100} + argument0 * 10 + argument1;\n'


def instrument(events):
    found = [e for e in events if e.get('object') == 'sys_global'
             and e.get('attributes', {}).get('eventtype') == '0'
             and e.get('attributes', {}).get('enumb') == '0']
    if len(found) != 1:
        raise ValueError('expected one sys_global Create')
    prefix = '''global.__dt_gp_supported = 0;
global.__dt_gp_count = 0;
global.__dt_gp_count_calls = 0;
global.__dt_gp_connected_calls = 0;
global.__dt_gp_read_calls = 0;
gp_button_check(1); gp_button_check_pressed(1); gp_button_check_released(1); gp_axis_value(1);
show_debug_message("GAMEPAD_VM:unsupported:" + string(global.__dt_gp_count_calls) + ":" + string(global.__dt_gp_connected_calls) + ":" + string(global.__dt_gp_read_calls));
global.__dt_gp_supported = 1;
gp_button_check(1); gp_button_check_pressed(1); gp_button_check_released(1); gp_axis_value(1);
show_debug_message("GAMEPAD_VM:none:" + string(global.__dt_gp_count_calls) + ":" + string(global.__dt_gp_connected_calls) + ":" + string(global.__dt_gp_read_calls));
global.__dt_gp_count_calls = 0;
global.__dt_gp_count = 4;
var gpa, gpb, gpc, gpd;
gpa = gp_button_check(1); gpb = gp_button_check_pressed(1); gpc = gp_button_check_released(1); gpd = gp_axis_value(1);
show_debug_message("GAMEPAD_VM:first:" + string(gpa) + ":" + string(gpb) + ":" + string(gpc) + ":" + string(gpd) + ":" + string(global.__dt_gp_count_calls) + ":" + string(global.__dt_gp_connected_calls) + ":" + string(global.__dt_gp_read_calls));
global.__dt_gp_count_calls = 0; global.__dt_gp_connected_calls = 0;
global.__dt_gp_deadzone_calls = 0; global.__dt_gp_deadzone_order = 0; global.__dt_gp_deadzone_value = 0;
global.__dt_gp_os_type = 0; global.__dt_setting_gamepad = 1;
gpa = gp_connect_check();
global.__dt_gp_os_type = 4; global.__dt_setting_gamepad = 0.9; gpb = gp_connect_check();
global.__dt_setting_gamepad = 1; global.__dt_gp_supported = 0; gpc = gp_connect_check();
show_debug_message("GAMEPAD_VM:connect-gates:" + string(gpa) + ":" + string(gpb) + ":" + string(gpc) + ":" + string(global.__dt_gp_count_calls) + ":" + string(global.__dt_gp_connected_calls) + ":" + string(global.__dt_gp_deadzone_calls));
global.__dt_gp_supported = 1; global.__dt_gp_count = 0;
gpa = gp_connect_check();
show_debug_message("GAMEPAD_VM:connect-empty:" + string(gpa) + ":" + string(global.__dt_gp_count_calls) + ":" + string(global.__dt_gp_connected_calls) + ":" + string(global.__dt_gp_deadzone_calls));
global.__dt_gp_count_calls = 0; global.__dt_gp_count = 4;
gpa = gp_connect_check();
show_debug_message("GAMEPAD_VM:connect-active:" + string(gpa) + ":" + string(global.__dt_gp_count_calls) + ":" + string(global.__dt_gp_connected_calls) + ":" + string(global.__dt_gp_deadzone_calls) + ":" + string(global.__dt_gp_deadzone_order) + ":" + string(global.__dt_gp_deadzone_value));
'''
    found[0]['gml'] = prefix + found[0]['gml']
    return events


def check(log):
    markers = [line.strip() for line in log.splitlines() if line.strip().startswith('GAMEPAD_VM:')]
    if markers != EXPECTED:
        raise ValueError(f'unexpected gamepad markers: {markers!r}')
    return len(markers)


def make_project(project, dest):
    project, dest = Path(project), Path(dest)
    verify_source(project)
    if dest.exists() or project.resolve() in dest.resolve().parents:
        raise ValueError('destination must be new and outside project')
    dest.mkdir(parents=True)
    try:
        for folder in ('scripts', 'objects'):
            shutil.copytree(project / folder, dest / folder)
        for name in (*FUNCTIONS, 'gp_connect_check'):
            path = dest / 'scripts' / (name + '.gml')
            text = path.read_text(encoding='utf-8')
            # Only replace builtin call tokens; do not rename the setting alias.
            for builtin in MOCKS:
                text = text.replace('gamepad_' + builtin + '(', '__dt_probe_gamepad_' + builtin + '(')
            if name == 'gp_connect_check':
                text = text.replace('os_type == 4', 'global.__dt_gp_os_type == 4')
            path.write_text(text, encoding='utf-8')
        for name, text in MOCKS.items():
            path = dest / 'scripts' / ('__dt_probe_gamepad_' + name + '.gml')
            if path.exists():
                raise ValueError('mock name collision')
            path.write_text(text, encoding='utf-8')
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
        data = instrument(json.loads(a.events.read_text(encoding='utf-8')))
        make_project(a.project, a.dest)
        a.output.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    else:
        print(f'GAMEPAD_VM:PASS {check(a.log.read_text(errors="replace"))} markers; mocked desktop VM only')


if __name__ == '__main__':
    main()
