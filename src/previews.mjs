import { clamp, finite, read, sameLayer, vec } from './core.mjs';

// Source collider wire shapes: circle=0, axis-aligned box=1. Unsupported
// shapes are reported, never silently advertised as an unobstructed shot.
export function rayHit(start, dir, distance, shape) {
  if (!vec(start) || !vec(dir) || !finite(distance) || distance <= 0) return null;
  let t, normal;
  if (read(shape, 'type') === 0 && vec(read(shape, 'pos')) && finite(read(shape, 'rad')) && shape.rad > 0) {
    const x = start.x - shape.pos.x, y = start.y - shape.pos.y;
    const b = x * dir.x + y * dir.y, c = x * x + y * y - shape.rad * shape.rad;
    const det = b * b - c;
    if (det < 0) return null;
    t = -b - Math.sqrt(det);
    if (t < 0) { if (c <= 0) t = 0; else return null; }
    const nx = start.x + dir.x * t - shape.pos.x, ny = start.y + dir.y * t - shape.pos.y, len = Math.hypot(nx, ny);
    normal = len ? { x: nx / len, y: ny / len } : { x: -dir.x, y: -dir.y };
  } else if (read(shape, 'type') === 1 && vec(read(shape, 'min')) && vec(read(shape, 'max'))) {
    let lo = 0, hi = distance; normal = { x: -dir.x, y: -dir.y };
    for (const axis of ['x', 'y']) {
      if (Math.abs(dir[axis]) < 1e-10) { if (start[axis] < shape.min[axis] || start[axis] > shape.max[axis]) return null; continue; }
      const a = (shape.min[axis] - start[axis]) / dir[axis], b = (shape.max[axis] - start[axis]) / dir[axis];
      const enter = Math.min(a, b);
      if (enter > lo) { lo = enter; normal = { x: 0, y: 0 }; normal[axis] = dir[axis] > 0 ? -1 : 1; }
      hi = Math.min(hi, Math.max(a, b)); if (lo > hi) return null;
    }
    t = lo;
  } else return null;
  return t >= 0 && t <= distance ? { distance: t, pos: { x: start.x + dir.x * t, y: start.y + dir.y * t }, normal } : null;
}
export function traceShot(start, direction, distance, obstacles, layer, definitions, maxReflections = 0) {
  const length = Math.hypot(direction?.x, direction?.y);
  if (!vec(start) || !finite(length) || length < .001 || !finite(distance) || distance <= 0) return null;
  let from = { ...start }, dir = { x: direction.x / length, y: direction.y / length }, left = Math.min(distance, 500);
  const points = [from]; let unsupported = 0, collisions = 0;
  const solid = obstacles.slice(0, 1024).filter(o => o.active === true && o.dead !== true && o.collidable !== false
    && (!finite(o.height) || o.height >= .25) && sameLayer(o.layer, layer) && o.collider);
  for (let bounce = 0; bounce <= Math.min(maxReflections, 3); bounce++) {
    let best = null;
    for (const obstacle of solid) {
      if (![0, 1].includes(read(obstacle.collider, 'type'))) { unsupported++; continue; }
      const hit = rayHit(from, dir, left, obstacle.collider);
      if (hit && (!best || hit.distance < best.distance)) best = { ...hit, obstacle };
    }
    if (!best) { points.push({ x: from.x + dir.x * left, y: from.y + dir.y * left }); break; }
    points.push(best.pos); collisions++; left -= best.distance;
    if (!definitions?.[best.obstacle.type]?.reflectBullets || bounce === maxReflections || left <= .02) break;
    const dot = dir.x * best.normal.x + dir.y * best.normal.y;
    dir = { x: dir.x - 2 * dot * best.normal.x, y: dir.y - 2 * dot * best.normal.y };
    from = { x: best.pos.x + dir.x * .02, y: best.pos.y + dir.y * .02 }; left -= .02;
  }
  return { points, collisions, unsupported };
}
// Open-air estimate from source WeaponManager.throwThrowable / Projectile.update:
// max mouse distance=18, spawn z=.5, gravity=10.5, ground drag=2.3.
// No hidden fuse, terrain, perks, player velocity or future collision claim.
export function throwPreview(def, start, direction, mouseDistance) {
  const physics = def?.throwPhysics, len = Math.hypot(direction?.x, direction?.y);
  if (def?.type !== 'throwable' || !vec(start) || !finite(len) || len < .001 || !finite(mouseDistance)
    || !finite(physics?.speed) || !finite(physics?.velZ) || physics.speed < 0) return null;
  const dir = { x: direction.x / len, y: direction.y / len };
  let speed = physics.speed * (def.forceMaxThrowDistance ? 1 : clamp(mouseDistance / 18, 0, 1));
  let height = .5, vz = physics.velZ, pos = { x: start.x + .5 * dir.x + dir.y, y: start.y + .5 * dir.y - dir.x };
  const points = [pos], dt = 1 / 60;
  for (let i = 0; i < 180; i++) {
    if (height <= 0) speed /= 1 + dt * 2.3;
    pos = { x: pos.x + dir.x * speed * dt, y: pos.y + dir.y * speed * dt };
    vz -= 10.5 * dt; height = Math.max(0, height + vz * dt);
    if (i % 6 === 5) points.push(pos);
    if (height === 0 && speed < .25) break;
  }
  return { points, end: pos, nominal: true };
}
export class MovementSmoother {
  reset() { this.direction = null; this.time = null; }
  constructor() { this.reset(); }
  sample(data, smooth, now) {
    const x = Number(!!data.moveRight) - Number(!!data.moveLeft), y = Number(!!data.moveUp) - Number(!!data.moveDown), len = Math.hypot(x, y);
    // Never coast after release: a smoothing slider must not add movement.
    if (!len) { this.reset(); return null; }
    const target = { x: x / len, y: y / len };
    const dt = this.time === null ? 0 : clamp((now - this.time) / 1000, 0, .1); this.time = now;
    if (!this.direction || !finite(smooth) || smooth <= 0) this.direction = target;
    else {
      const gain = 1 - Math.exp(-dt / (.02 + clamp(smooth, 0, 100) / 500));
      const next = { x: this.direction.x + (target.x - this.direction.x) * gain, y: this.direction.y + (target.y - this.direction.y) * gain };
      const n = Math.hypot(next.x, next.y);
      this.direction = n > .05 ? { x: next.x / n, y: next.y / n } : target;
      // Opposite directions have no arc under linear interpolation; choose the
      // new physical direction immediately rather than getting stuck forever.
      if (this.direction.x * target.x + this.direction.y * target.y < -.95) this.direction = target;
    }
    return { ...this.direction };
  }
}
