#!/usr/bin/env python3
"""Check isolated desktop motion traces; not evidence of iOS trails or a fix."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageChops

MARKER = 'DT_MOTION|'
FIELDS = ('tick', 'x', 'y', 'xprevious', 'yprevious', 'background', 'view_x', 'view_y',
          'view_w', 'view_h', 'port_w', 'port_h', 'view1', 'app_w', 'app_h', 'key_d', 'players')
FRAMES = (175, 190, 210)


def parse(log):
    records = {}
    for line in log.splitlines():
        start = line.find(MARKER)
        if start < 0:
            continue
        values = line[start + len(MARKER):].strip().split('|')
        if len(values) != len(FIELDS):
            raise ValueError('invalid motion marker length')
        try:
            numbers = [float(x) for x in values]
        except ValueError as exc:
            raise ValueError('non-numeric motion marker') from exc
        if any(not math.isfinite(x) for x in numbers):
            raise ValueError('nonfinite motion marker')
        record = dict(zip(FIELDS, numbers))
        tick = record['tick']
        if not tick.is_integer() or tick < 1 or tick in records or record['players'] != 1:
            raise ValueError('duplicate/invalid tick or unexpected player count')
        for key in ('background', 'view1', 'key_d'):
            if record[key] not in (0, 1):
                raise ValueError('invalid boolean ' + key)
        records[int(tick)] = record
    if len(records) < 25:
        raise ValueError('insufficient motion samples')
    if sorted(records) != list(range(1, len(records) + 1)):
        raise ValueError('missing motion ticks')
    return records


def compare(still_log, moving_log, still_shots, moving_shots):
    still, moving = parse(still_log), parse(moving_log)
    common = sorted(still.keys() & moving.keys())
    if len(common) < 25:
        raise ValueError('insufficient paired samples')
    if any(r['key_d'] for r in still.values()) or not any(moving[n]['key_d'] for n in common):
        raise ValueError('scripted keyboard input not observed')
    displacements = [math.hypot(moving[n]['x'] - still[n]['x'], moving[n]['y'] - still[n]['y']) for n in common]
    if max(displacements) < 1:
        raise ValueError('scripted input did not displace the player relative to baseline')
    images = {}
    for frame in FRAMES:
        with Image.open(Path(still_shots) / f'shot_{frame}.png') as a, Image.open(Path(moving_shots) / f'shot_{frame}.png') as b:
            a, b = a.convert('RGB'), b.convert('RGB')
            if a.size != b.size or not (0 < a.width <= 4096 and 0 < a.height <= 4096):
                raise ValueError('unexpected screenshot size')
            red, green, blue = ImageChops.difference(a, b).split()
            diff = ImageChops.lighter(ImageChops.lighter(red, green), blue)
            histogram = diff.histogram()
            images[str(frame)] = {'width': a.width, 'height': a.height,
                                  'different_pixels': a.width * a.height - histogram[0]}
    return {'samples': len(common), 'max_player_distance_from_baseline': max(displacements),
            'observed_background_flags': sorted(set(r['background'] for r in moving.values())),
            'view0_sizes': sorted({(r['view_w'], r['view_h']) for r in moving.values()}),
            'port0_sizes': sorted({(r['port_w'], r['port_h']) for r in moving.values()}),
            'application_sizes': sorted({(r['app_w'], r['app_h']) for r in moving.values()}),
            'view1_flags': sorted(set(r['view1'] for r in moving.values())),
            'key_d_ticks': [n for n in common if moving[n]['key_d']], 'screenshots': images,
            'limitations': 'Forced room and scripted keyboard on incomplete desktop VM; pixel difference is not '
                           'a ghosting detector. Not iOS, native APK/IPA, touch input or a graphics fix.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('still_log', type=Path)
    p.add_argument('moving_log', type=Path)
    p.add_argument('still_shots', type=Path)
    p.add_argument('moving_shots', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    result = compare(args.still_log.read_text(errors='replace'), args.moving_log.read_text(errors='replace'),
                     args.still_shots, args.moving_shots)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('MOTION_PROBE_PASS:', json.dumps(result, separators=(',', ':')))
    print('MOTION_PROBE_LIMIT: forced desktop VM only; no iPhone diagnosis')


if __name__ == '__main__':
    main()
