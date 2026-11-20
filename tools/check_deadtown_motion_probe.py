#!/usr/bin/env python3
"""Check isolated desktop motion traces; not evidence of iOS trails or a fix."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageChops

MARKER = 'DT_MOTION|'
FIELDS = ('tick', 'x', 'y', 'xprevious', 'yprevious', 'background', 'view_x', 'view_y',
          'view_w', 'view_h', 'view_angle', 'port_w', 'port_h', 'view1', 'app_w', 'app_h', 'key_d', 'players')
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


def idealized_background_gap(w, h, angle):
    """Area fraction outside the runner's rotated room-background rectangle.

    This models an untransformed world-space rect of view size plus the runner's
    1-unit margin, rotated around view center and clipped to the viewport. It
    ignores rasterization, other draw calls, GPU state and custom matrices.
    """
    if not all(math.isfinite(x) for x in (w, h, angle)) or w <= 0 or h <= 0:
        raise ValueError('invalid view geometry')
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    half_w, half_h = w / 2, h / 2
    corners = [(-half_w - 1, -half_h - 1), (half_w + 1, -half_h - 1),
               (half_w + 1, half_h + 1), (-half_w - 1, half_h + 1)]
    polygon = [(c*x + s*y, -s*x + c*y) for x, y in corners]
    for axis, limit, direction in ((0, -half_w, 1), (0, half_w, -1),
                                    (1, -half_h, 1), (1, half_h, -1)):
        if not polygon:
            break
        clipped = []
        previous = polygon[-1]
        pin = direction * (previous[axis] - limit) >= 0
        for current in polygon:
            cin = direction * (current[axis] - limit) >= 0
            if cin != pin:
                t = (limit - previous[axis]) / (current[axis] - previous[axis])
                clipped.append((previous[0] + t * (current[0] - previous[0]),
                                previous[1] + t * (current[1] - previous[1])))
            if cin:
                clipped.append(current)
            previous, pin = current, cin
        polygon = clipped
    area = abs(sum(x0*y1 - x1*y0 for (x0, y0), (x1, y1) in
                   zip(polygon, polygon[1:] + polygon[:1]))) / 2
    return max(0.0, min(1.0, 1.0 - area / (w * h)))


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
            'view0_angles': sorted({r['view_angle'] for r in moving.values()}),
            'max_idealized_background_gap_fraction': max(idealized_background_gap(r['view_w'], r['view_h'], r['view_angle']) for r in moving.values()),
            'port0_sizes': sorted({(r['port_w'], r['port_h']) for r in moving.values()}),
            'application_sizes': sorted({(r['app_w'], r['app_h']) for r in moving.values()}),
            'view1_flags': sorted(set(r['view1'] for r in moving.values())),
            'key_d_ticks': [n for n in common if moving[n]['key_d']], 'screenshots': images,
            'limitations': 'Forced room and scripted keyboard on incomplete desktop VM; pixel difference is not '
                           'a ghosting detector; background gap is idealized geometry, not measured coverage. Not iOS, native APK/IPA, touch input or a graphics fix.'}


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
