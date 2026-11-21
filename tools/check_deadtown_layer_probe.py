#!/usr/bin/env python3
"""Validate a disposable desktop player Draw trace, not on-device placement."""
import argparse
import json
import math
from pathlib import Path

EVENT_FIELDS = ('x', 'y', 'right_x', 'right_y', 'left_x', 'left_y',
                'view_x', 'view_y', 'view_w', 'view_h', 'view_angle', 'custom', 'app_target')
SPRITE_FIELDS = ('x', 'y', 'xs', 'ys', 'rotation', 'origin_x', 'origin_y',
                 'target_x', 'target_y', 'target_w', 'target_h', 'alpha', 'color')
BODY = {'spr_player', 'spr_player_near', 'spr_player_near_attack', 'spr_player_vehicle'}
FEET = {'spr_player_foot_right': 'right', 'spr_player_foot_left': 'left'}


def floats(values):
    try:
        nums = [float(v) for v in values]
    except ValueError as exc:
        raise ValueError('invalid numeric field') from exc
    if any(not math.isfinite(v) for v in nums):
        raise ValueError('nonfinite field')
    return nums


def parse(log):
    events, sprites, vertices = {}, {}, {}
    for line in log.splitlines():
        pos = line.find('DT_LAYER_')
        if pos < 0:
            continue
        parts = line[pos:].strip().split('|')
        tag = parts[0]
        try:
            tick = int(parts[1])
        except (ValueError, IndexError) as exc:
            raise ValueError('invalid tick') from exc
        if tick < 1 or tick > 45:
            raise ValueError('tick out of range')
        if tag == 'DT_LAYER_EVENT':
            if len(parts) != 2 + len(EVENT_FIELDS) or tick in events:
                raise ValueError('invalid or duplicate event')
            events[tick] = dict(zip(EVENT_FIELDS, floats(parts[2:])))
        elif tag in ('DT_LAYER_SPRITE', 'DT_LAYER_VERT'):
            if len(parts) < 3:
                raise ValueError('missing sequence')
            try:
                seq = int(parts[2])
            except ValueError as exc:
                raise ValueError('invalid sequence') from exc
            if seq < 1:
                raise ValueError('invalid sequence')
            key = (tick, seq)
            if tag == 'DT_LAYER_SPRITE':
                if len(parts) != 4 + len(SPRITE_FIELDS) or key in sprites or not parts[3]:
                    raise ValueError('invalid or duplicate sprite')
                sprites[key] = {'name': parts[3], **dict(zip(SPRITE_FIELDS, floats(parts[4:])))}
            else:
                if len(parts) != 11 or key in vertices:
                    raise ValueError('invalid or duplicate vertices')
                v = floats(parts[3:])
                vertices[key] = list(zip(v[::2], v[1::2]))
        else:
            raise ValueError('unknown marker')
    if len(events) < 25 or sorted(events) != list(range(1, len(events) + 1)):
        raise ValueError('missing player events')
    if set(sprites) != set(vertices) or not sprites:
        raise ValueError('sprite/quad mismatch')
    if any(t not in events for t, _ in sprites):
        raise ValueError('orphan sprite')
    for tick, event in events.items():
        seqs = sorted(s for t, s in sprites if t == tick)
        if seqs != list(range(1, len(seqs) + 1)) or not seqs:
            raise ValueError('missing draw sequence')
        if event['custom'] != 0 or event['app_target'] != 1 or event['view_w'] <= 0 or event['view_h'] <= 0:
            raise ValueError('unexpected target or custom projection')
    return events, sprites, vertices


def expected_vertices(s):
    l = s['target_x'] - s['origin_x']
    t = s['target_y'] - s['origin_y']
    w, h = s['target_w'], s['target_h']
    angle = math.radians(s['rotation'])
    c, sin = math.cos(angle), math.sin(angle)
    result = []
    for xx, yy in ((l, t), (l+w, t), (l+w, t+h), (l, t+h)):
        qx, qy = xx * s['xs'], yy * s['ys']
        result.append((s['x'] + qx*c + qy*sin, s['y'] - qx*sin + qy*c))
    return result


def analyze(log):
    events, sprites, vertices = parse(log)
    quad_err = 0.0
    body_err = 0.0
    foot_err = 0.0
    offsets = {'left': [], 'right': []}
    names = set()
    for tick, event in events.items():
        rows = [s for (t, _), s in sprites.items() if t == tick]
        # The opaque white body is distinct from the intentionally offset shadow.
        bodies = [s for s in rows if s['name'] in BODY and s['alpha'] >= 0.999 and s['color'] == 0xffffff]
        if len(bodies) != 1:
            raise ValueError('expected one opaque body call per event')
        body_err = max(body_err, math.hypot(bodies[0]['x'] - event['x'], bodies[0]['y'] - event['y']))
        for name, side in FEET.items():
            feet = [s for s in rows if s['name'] == name and s['alpha'] >= 0.999 and s['color'] == 0xffffff]
            if len(feet) != 1:
                raise ValueError('expected one call per foot and event')
            dx, dy = feet[0]['x'] - event['x'], feet[0]['y'] - event['y']
            offsets[side].append(math.hypot(dx, dy))
            foot_err = max(foot_err, math.hypot(dx - event[side+'_x'], dy - event[side+'_y']))
    for key, sprite in sprites.items():
        names.add(sprite['name'])
        for actual, expected in zip(vertices[key], expected_vertices(sprite)):
            quad_err = max(quad_err, math.dist(actual, expected))
    if max(body_err, foot_err, quad_err) > 1e-5:
        raise ValueError('unexpected anchor or CPU quad geometry')
    return {'events': events, 'summary': {'event_count': len(events), 'sprite_calls': len(sprites),
            'sprite_names': sorted(names), 'max_body_anchor_error': body_err,
            'max_foot_anchor_error_vs_instance_variables': foot_err, 'max_quad_formula_error': quad_err,
            'foot_anchor_offset_range': {side: [min(v), max(v)] for side, v in offsets.items()},
            'view_angles': sorted({e['view_angle'] for e in events.values()})}}


def compare(still_log, moving_log):
    still, moving = analyze(still_log), analyze(moving_log)
    ticks = sorted(still['events'].keys() & moving['events'].keys())
    if len(ticks) < 25:
        raise ValueError('insufficient paired events')
    displacement = max(math.hypot(still['events'][t]['x'] - moving['events'][t]['x'],
                                  still['events'][t]['y'] - moving['events'][t]['y']) for t in ticks)
    if displacement < 1:
        raise ValueError('scripted movement not observed relative to baseline')
    return {'still': still['summary'], 'moving': moving['summary'],
            'max_player_displacement_from_still': displacement,
            'limitations': 'CPU-side calls during normal player Draw, forced desktop room and incomplete VM; '
                           'no GPU pixel/readback, no comparison with native Android or iOS, no proof of '
                           'correct game logic, visual placement, device defect or a fix.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('still', type=Path)
    parser.add_argument('moving', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.still.read_text(errors='replace'), args.moving.read_text(errors='replace'))
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('LAYER_PROBE_PASS:', json.dumps(result, separators=(',', ':')))


if __name__ == '__main__':
    main()
