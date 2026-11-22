#!/usr/bin/env python3
"""Exercise item motion fragment with its collision check replaced by constants.

Not actual collision dispatch, a complete item Step, native Android, or iOS.
"""
import argparse
import json
from pathlib import Path
try:
    from tools.deadtown_item_motion_evidence import MOTION, verify_source
    from tools.deadtown_item_schedule_vm_probe import find
except ModuleNotFoundError:
    from deadtown_item_motion_evidence import MOTION, verify_source
    from deadtown_item_schedule_vm_probe import find

MARKER='ITEM_MOTION_VM:1:1:1'
EXPR='collision_rectangle(x+xx-20,y+yy-20,x+xx+20,y+yy+20,par_action,1,1)'


def instrument(events,project):
    verify_source(project)
    # The scheduling diagnostic intentionally stubs item Step. Confirm its
    # original source separately, then embed the same movement fragment here.
    if MOTION.count(EXPR)!=1: raise ValueError('unexpected collision expression')
    clear=MOTION.replace(EXPR,'noone')
    blocked=MOTION.replace(EXPR,'123456')
    create=find(events,'sys_global','0','0')
    create['gml']='''__dt_old_x = x; __dt_old_y = y;
x = 100; y = 200; sp = 0; dir = 0; fric = 0.2; xx = 99; yy = 99;
'''+clear+'''
__dt_stationary = x == 100 && y == 200 && xx == 99 && yy == 99;
x = 100; y = 200; sp = 3; dir = 0; fric = 0.2;
'''+clear+'''
__dt_clear = abs(x-103) < 0.001 && abs(y-200) < 0.001 && abs(sp-2.8) < 0.001;
x = 100; y = 200; sp = 3; dir = 0; fric = 0.2;
'''+blocked+'''
__dt_blocked = x == 100 && y == 200 && abs(sp-2.8) < 0.001;
show_debug_message("ITEM_MOTION_VM:" + string(__dt_stationary) + ":" + string(__dt_clear) + ":" + string(__dt_blocked));
x = __dt_old_x; y = __dt_old_y;
'''+create['gml']
    return events


def check(log):
    lines=[s.strip() for s in log.splitlines() if s.strip().startswith('ITEM_MOTION_VM:')]
    if lines!=[MARKER]:raise ValueError(f'unexpected item motion markers: {lines!r}')
    return 1


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='mode',required=True)
    i=sub.add_parser('instrument');i.add_argument('project',type=Path);i.add_argument('input',type=Path);i.add_argument('output',type=Path)
    c=sub.add_parser('check');c.add_argument('log',type=Path);a=p.parse_args()
    if a.mode=='instrument':
        if a.output.exists() or a.output.resolve()==a.input.resolve():raise ValueError('output must be new')
        a.output.write_text(json.dumps(instrument(json.loads(a.input.read_text(encoding='utf-8')),a.project),ensure_ascii=False),encoding='utf-8')
    else:print('ITEM_MOTION_VM:PASS '+str(check(a.log.read_text(errors='replace'))) + ' marker; collision mocked')
if __name__=='__main__':main()
