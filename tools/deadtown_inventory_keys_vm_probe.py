#!/usr/bin/env python3
"""Run candidate input fragments and a mocked inventory-close action in a VM.

Not keyboard event dispatch, actual inventory, Android, or iOS validation.
"""
import argparse
import json
from pathlib import Path
try:
    from tools.deadtown_inventory_keys_evidence import OPEN, TOGGLE, ESCAPE, CLOSE, verify_source
    from tools.deadtown_item_schedule_vm_probe import find
except ModuleNotFoundError:
    from deadtown_inventory_keys_evidence import OPEN, TOGGLE, ESCAPE, CLOSE, verify_source
    from deadtown_item_schedule_vm_probe import find

MARKERS = [
    'INVENTORY_KEYS_VM:open:1:0',
    'INVENTORY_KEYS_VM:toggle:1:0:1',
    'INVENTORY_KEYS_VM:close:0:1',
    'INVENTORY_KEYS_VM:escape:1:7:0:0:1:0',
]


def instrument(events, project):
    verify_source(project)
    keys = {n:find(events,'sys_UI','9',str(n)) for n in (73,32,27)}
    for n, source in ((73,OPEN),(32,TOGGLE),(27,ESCAPE)):
        if source.strip() not in keys[n]['gml']:
            raise ValueError('unexpected compiled event '+str(n))
    # Execute the exact input fragments within a disposable sys_global context.
    # The close script is replaced with a counter; its real side effects are not tested.
    step = find(events,'sys_UI','3','0')
    if CLOSE not in step['gml']:
        raise ValueError('unexpected compiled close fragment')
    close = CLOSE.replace('backpack_close()', '__dt_close_called += 1')
    event = find(events,'sys_global','0','0')
    event['gml'] = '''backpack_open = 0; backpack_order_open = 0;
''' + OPEN + '''
__dt_open_closed = backpack_order_open;
backpack_open = 1; backpack_order_open = 0;
''' + OPEN + '''
show_debug_message("INVENTORY_KEYS_VM:open:" + string(__dt_open_closed) + ":" + string(backpack_order_open));
backpack_open = 0; backpack_order_open = 0; backpack_order_close = 0;
''' + TOGGLE + '''
__dt_toggle_open = backpack_order_open;
backpack_open = 1; backpack_order_open = 0; backpack_order_close = 0;
''' + TOGGLE + '''
show_debug_message("INVENTORY_KEYS_VM:toggle:" + string(__dt_toggle_open) + ":" + string(backpack_order_open) + ":" + string(backpack_order_close));
__dt_close_called = 0;
''' + close + '''
show_debug_message("INVENTORY_KEYS_VM:close:" + string(backpack_order_close) + ":" + string(__dt_close_called));
pause = 1; pause_kind = 7; pause_request = 0; backpack_open = 1;
''' + ESCAPE + '''
__dt_escape_pause = pause_request; __dt_escape_kind = pause_kind;
pause = 0; pause_kind = 7; pause_request = 0; backpack_open = 1;
''' + ESCAPE + '''
__dt_escape_block = pause_request;
pause = 0; pause_kind = 7; pause_request = 0; backpack_open = 0;
''' + ESCAPE + '''
show_debug_message("INVENTORY_KEYS_VM:escape:" + string(__dt_escape_pause) + ":" + string(__dt_escape_kind) + ":" + string(__dt_escape_block) + ":" + string(backpack_open) + ":" + string(pause_request) + ":" + string(pause_kind));
''' + event['gml']
    return events


def check(log):
    found = [line.strip() for line in log.splitlines() if line.strip().startswith('INVENTORY_KEYS_VM:')]
    if found != MARKERS:
        raise ValueError(f'unexpected inventory markers: {found!r}')
    return len(found)


def main():
    p=argparse.ArgumentParser(description=__doc__); sub=p.add_subparsers(dest='mode',required=True)
    i=sub.add_parser('instrument');i.add_argument('project',type=Path);i.add_argument('input',type=Path);i.add_argument('output',type=Path)
    c=sub.add_parser('check');c.add_argument('log',type=Path)
    a=p.parse_args()
    if a.mode=='instrument':
        if a.output.exists() or a.output.resolve()==a.input.resolve(): raise ValueError('output must be new')
        a.output.write_text(json.dumps(instrument(json.loads(a.input.read_text(encoding='utf-8')),a.project),ensure_ascii=False),encoding='utf-8')
    else:
        print('INVENTORY_KEYS_VM:PASS '+str(check(a.log.read_text(errors='replace'))) + ' markers; mocked fragments only')


if __name__=='__main__': main()
