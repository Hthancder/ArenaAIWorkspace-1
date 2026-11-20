#!/usr/bin/env python3
"""Validate controlled desktop background-fill measurements, not device behavior."""
import argparse
import json
import math
from pathlib import Path
try:
    from tools.check_deadtown_motion_probe import idealized_background_gap
except ModuleNotFoundError:
    from check_deadtown_motion_probe import idealized_background_gap


def one(log, expected_mode):
    rows = [line[line.find('DT_BG_COVERAGE|'):].strip().split('|')
            for line in log.splitlines() if 'DT_BG_COVERAGE|' in line]
    if len(rows) != 1 or len(rows[0]) != 6 or rows[0][1] != expected_mode:
        raise ValueError('expected one matching diagnostic marker')
    try:
        angle = float(rows[0][2]); width, height, pink = map(int, rows[0][3:])
    except ValueError as exc:
        raise ValueError('invalid marker number') from exc
    if not math.isfinite(angle) or (width, height) != (1232, 693) or not 0 <= pink <= width * height:
        raise ValueError('invalid diagnostic dimensions or angle')
    return {'angle': angle, 'width': width, 'height': height, 'magenta_pixels': pink,
            'observed_fraction': pink / (width * height),
            'idealized_gap_fraction': idealized_background_gap(width, height, angle)}


def final(log, expected_mode, expected_initial):
    rows = [line[line.find('DT_BG_FINAL|'):].strip().split('|')
            for line in log.splitlines() if 'DT_BG_FINAL|' in line]
    if len(rows) != 1 or len(rows[0]) != 4 or rows[0][1] != expected_mode:
        raise ValueError('expected one final-pass marker')
    try:
        initial, remaining = map(int, rows[0][2:])
    except ValueError as exc:
        raise ValueError('invalid final-pass marker') from exc
    if initial != expected_initial or not 0 <= remaining <= initial:
        raise ValueError('invalid final-pass counts')
    return {'initial_marked_pixels': initial, 'remaining_after_room_draw': remaining}


def next_frame(log, expected_mode, expected_initial):
    rows = [line[line.find('DT_BG_NEXT|'):].strip().split('|')
            for line in log.splitlines() if 'DT_BG_NEXT|' in line]
    if len(rows) != 1 or len(rows[0]) != 4 or rows[0][1] != expected_mode:
        raise ValueError('expected one next-frame marker')
    try:
        initial, remaining = map(int, rows[0][2:])
    except ValueError as exc:
        raise ValueError('invalid next-frame marker') from exc
    if initial != expected_initial or not 0 <= remaining <= initial:
        raise ValueError('invalid next-frame counts')
    return {'marked_after_previous_frame': initial, 'remaining_after_next_frame': remaining}


def player_movement(log, expected_mode):
    rows = [line[line.find('DT_BG_PLAYER|'):].strip().split('|')
            for line in log.splitlines() if 'DT_BG_PLAYER|' in line]
    if len(rows) != 2 or any(len(row) != 5 or row[1] != expected_mode for row in rows):
        raise ValueError('expected two player movement markers')
    stages = {}
    try:
        for row in rows:
            if row[2] in stages or row[2] not in ('first', 'next'):
                raise ValueError('invalid player marker stage')
            stages[row[2]] = (float(row[3]), float(row[4]))
    except ValueError as exc:
        raise ValueError('invalid player coordinates') from exc
    if set(stages) != {'first', 'next'} or not all(math.isfinite(x) for pair in stages.values() for x in pair):
        raise ValueError('invalid player movement markers')
    distance = math.dist(stages['first'], stages['next'])
    if distance < 0.1:
        raise ValueError('diagnostic player did not move between sampled frames')
    return {'first': stages['first'], 'next': stages['next'], 'distance': distance}


def check(zero_log, live_log, fix_log, repair_log, moving_log, moving_repair_log):
    zero, live, fix, repair = (one(zero_log, 'zero'), one(live_log, 'live'),
                               one(fix_log, 'fix'), one(repair_log, 'repair'))
    if zero['angle'] != 0 or abs(live['angle']) < 1 or abs(fix['angle'] - live['angle']) > 0.05 or abs(repair['angle'] - live['angle']) > 0.05:
        raise ValueError('control and rotated angle mismatch')
    if zero['observed_fraction'] > 0.005 or fix['observed_fraction'] > 0.005 or live['observed_fraction'] < 0.05:
        raise ValueError('expected control coverage and rotated uncovered region were not observed')
    if abs(live['observed_fraction'] - live['idealized_gap_fraction']) > 0.02:
        raise ValueError('rotated measurement diverges from idealized geometry')
    for mode, report, log in (('zero', zero, zero_log), ('live', live, live_log),
                              ('fix', fix, fix_log), ('repair', repair, repair_log)):
        report['after_room_draw'] = final(log, mode, report['magenta_pixels'])
        report['next_room_draw'] = next_frame(log, mode, report['after_room_draw']['remaining_after_room_draw'])
    previous = repair['after_room_draw']['remaining_after_room_draw']
    remaining = repair['next_room_draw']['remaining_after_next_frame']
    if previous < 1000 or remaining > previous * 0.005:
        raise ValueError('next-frame diagnostic correction did not clear the synthetic marker')
    if abs(repair['observed_fraction'] - live['observed_fraction']) > 0.005:
        raise ValueError('repair first pass is not comparable to baseline')
    moving, moving_repair = one(moving_log, 'live'), one(moving_repair_log, 'repair')
    for mode, report, log in (('live', moving, moving_log), ('repair', moving_repair, moving_repair_log)):
        report['after_room_draw'] = final(log, mode, report['magenta_pixels'])
        report['next_room_draw'] = next_frame(log, mode, report['after_room_draw']['remaining_after_room_draw'])
        report['player_motion'] = player_movement(log, mode)
    if moving['next_room_draw']['remaining_after_next_frame'] < 1000:
        raise ValueError('moving baseline has no significant retained marker')
    old = moving_repair['after_room_draw']['remaining_after_room_draw']
    if old < 1000 or moving_repair['next_room_draw']['remaining_after_next_frame'] > old * 0.005:
        raise ValueError('moving correction did not clear synthetic marker')
    return {'zero': zero, 'rotated': live, 'synthetic_fix': fix, 'next_frame_repair': repair,
            'moving': moving, 'moving_next_frame_repair': moving_repair,
            'limitations': 'One prepainted desktop GLES pass plus follow-up, intentionally changes target; '
                           'not natural gameplay, iOS, original renderer or proof of device defect.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('zero', type=Path)
    p.add_argument('live', type=Path)
    p.add_argument('fix', type=Path)
    p.add_argument('repair', type=Path)
    p.add_argument('moving', type=Path)
    p.add_argument('moving_repair', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    report = check(a.zero.read_text(errors='replace'), a.live.read_text(errors='replace'),
                   a.fix.read_text(errors='replace'), a.repair.read_text(errors='replace'),
                   a.moving.read_text(errors='replace'), a.moving_repair.read_text(errors='replace'))
    a.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('BACKGROUND_PROBE_PASS:', json.dumps(report, separators=(',', ':')))


if __name__ == '__main__':
    main()
