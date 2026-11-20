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


def check(zero_log, live_log, fix_log):
    zero, live, fix = one(zero_log, 'zero'), one(live_log, 'live'), one(fix_log, 'fix')
    if zero['angle'] != 0 or abs(live['angle']) < 1 or abs(fix['angle'] - live['angle']) > 0.05:
        raise ValueError('control and rotated angle mismatch')
    if zero['observed_fraction'] > 0.005 or fix['observed_fraction'] > 0.005 or live['observed_fraction'] < 0.05:
        raise ValueError('expected control coverage and rotated uncovered region were not observed')
    if abs(live['observed_fraction'] - live['idealized_gap_fraction']) > 0.02:
        raise ValueError('rotated measurement diverges from idealized geometry')
    for mode, report, log in (('zero', zero, zero_log), ('live', live, live_log), ('fix', fix, fix_log)):
        report['after_room_draw'] = final(log, mode, report['magenta_pixels'])
    return {'zero': zero, 'rotated': live, 'synthetic_fix': fix,
            'limitations': 'Single prepainted desktop GLES pass, intentionally changes target; '
                           'not natural gameplay, iOS, original renderer or proof of device defect.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('zero', type=Path)
    p.add_argument('live', type=Path)
    p.add_argument('fix', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    report = check(a.zero.read_text(errors='replace'), a.live.read_text(errors='replace'),
                   a.fix.read_text(errors='replace'))
    a.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('BACKGROUND_PROBE_PASS:', json.dumps(report, separators=(',', ':')))


if __name__ == '__main__':
    main()
