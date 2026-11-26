import { clamp, finite, read, sameLayer, segmentBlocked, vec } from './core.mjs';

// Nominal, flat-ground, unobstructed model only. Caller must verify terrain,
// obstacles, player velocity, perks, target and release/fuse state independently.
// No input modifications or target selection are performed here.
const GRAVITY = 10.5, GROUND_DRAG = 2.3, MAX_HEIGHT = 5, MOUSE_RANGE = 18;
const supported = def => def?.type === 'throwable' && def.cookable === true
  && def.explodeOnImpact === false && def.forceMaxThrowDistance !== true
  && !def.heavyType && !def.fuseVariance && def.playerCollision !== true && def.aimDistance === 0
  && finite(def.throwPhysics?.speed) && def.throwPhysics.speed > 0
  && finite(def.throwPhysics?.velZ) && finite(def.throwPhysics?.playerVelMult);

// Simulation matches the source's ordering: ground drag, horizontal advance,
// gravity / height, then fuse decrement. No water, collisions or variance.
export function simulateOpenThrow({ def, origin, direction, mouseDistance, playerVelocity, fuseRemaining, dt = 1 / 30 }) {
  const len = Math.hypot(direction?.x, direction?.y);
  if (!supported(def) || !vec(origin) || !vec(playerVelocity) || !finite(len) || len < 1e-6
    || !finite(mouseDistance) || mouseDistance < 0 || mouseDistance > MOUSE_RANGE
    || !finite(fuseRemaining) || fuseRemaining <= 0 || fuseRemaining > 10
    || !finite(dt) || dt < 1 / 240 || dt > 1 / 15) return null;
  const dir = { x: direction.x / len, y: direction.y / len }, p = def.throwPhysics;
  const speed = p.speed * clamp(mouseDistance / MOUSE_RANGE, 0, 1);
  let x = origin.x + .5 * dir.x + dir.y, y = origin.y + .5 * dir.y - dir.x;
  let vx = dir.x * speed + playerVelocity.x * p.playerVelMult;
  let vy = dir.y * speed + playerVelocity.y * p.playerVelMult;
  let z = .5, vz = p.velZ, time = 0, fuse = fuseRemaining;
  const points = [{ x, y, z, t: 0 }];
  for (let i = 0; i < 2400 && fuse > 0; i++) {
    if (z <= 0) { vx /= 1 + dt * GROUND_DRAG; vy /= 1 + dt * GROUND_DRAG; }
    x += vx * dt; y += vy * dt;
    vz -= GRAVITY * dt; z = clamp(z + vz * dt, 0, MAX_HEIGHT);
    fuse -= dt; time += dt;
    points.push({ x, y, z, t: time });
  }
  if (fuse > 0) return null;
  return { end: { x, y }, time, points, nominal: true };
}

// Solve the open-air nominal endpoint at the specified fuse; returns null when
// the desired point is not reachable. This is a model primitive, NOT an aim
// decision: the caller must reject uncertain context and validate obstacles.
export function solveOpenThrow({ def, origin, target, playerVelocity, fuseRemaining, dt = 1 / 30 }) {
  if (!vec(origin) || !vec(target) || !vec(playerVelocity)) return null;
  const args = { def, origin, playerVelocity, fuseRemaining, dt, direction: { x: 1, y: 0 } };
  const zero = simulateOpenThrow({ ...args, mouseDistance: 0 });
  const full = simulateOpenThrow({ ...args, mouseDistance: MOUSE_RANGE });
  if (!zero || !full) return null;
  // Spawn offset in the throw direction is (.5, -1), rotated by the aim angle.
  // Both inherited motion and throw velocity experience the same linear drag.
  const drift = { x: zero.end.x - origin.x - .5, y: zero.end.y - origin.y + 1 };
  const displacement = { x: target.x - origin.x - drift.x, y: target.y - origin.y - drift.y };
  const r = Math.hypot(displacement.x, displacement.y), maxForward = full.end.x - zero.end.x + .5;
  if (!finite(r) || r < Math.hypot(.5, 1) - 1e-8 || !finite(maxForward) || maxForward <= .5) return null;
  const forward = Math.sqrt(Math.max(0, r * r - 1));
  const fraction = (forward - .5) / (maxForward - .5);
  if (fraction < -1e-8 || fraction > 1 + 1e-8) return null;
  const angle = Math.atan2(displacement.y, displacement.x) + Math.atan2(1, forward);
  const direction = { x: Math.cos(angle), y: Math.sin(angle) }, mouseDistance = clamp(fraction, 0, 1) * MOUSE_RANGE;
  const simulated = simulateOpenThrow({ ...args, direction, mouseDistance });
  return simulated ? { direction, mouseDistance, ...simulated } : null;
}

// Conservative flat-ground validation, not a server collision simulation. Reject
// all collidable objects intersecting the swept XY path regardless of height,
// including the player-to-hand segment. Unsupported geometry/layer/terrain fails
// closed. Surface callback must positively identify ground, not merely non-water.
export function validateOpenThrow({ solution, origin, def, layer, obstacles, groundAt }) {
  if (!solution || !Array.isArray(solution.points) || solution.points.length < 2 || solution.points.length > 2401
    || !vec(origin) || !supported(def) || !finite(def.rad) || def.rad <= 0 || !Number.isInteger(layer)
    || (layer & 2) || !Array.isArray(obstacles) || obstacles.length > 1024 || typeof groundAt !== 'function') return { ok: false, reason: 'missing-contract' };
  const points = [origin, ...solution.points];
  const solid = [];
  for (const obstacle of obstacles) {
    if (read(obstacle, 'active') === false || read(obstacle, 'dead') === true || read(obstacle, 'collidable') === false) continue;
    const otherLayer = read(obstacle, 'layer');
    if (!Number.isInteger(otherLayer)) return { ok: false, reason: 'unknown-layer' };
    if (!sameLayer(layer, otherLayer)) continue;
    const shape = read(obstacle, 'collider'), kind = read(shape, 'type');
    const margin = def.rad * .25 + .1;
    if (kind === 0 && vec(read(shape, 'pos')) && finite(read(shape, 'rad')) && shape.rad >= 0) {
      solid.push({ type: 0, pos: shape.pos, rad: shape.rad + margin });
    } else if (kind === 1 && vec(read(shape, 'min')) && vec(read(shape, 'max')) && shape.min.x <= shape.max.x && shape.min.y <= shape.max.y) {
      solid.push({ type: 1, min: { x: shape.min.x - margin, y: shape.min.y - margin }, max: { x: shape.max.x + margin, y: shape.max.y + margin } });
    } else return { ok: false, reason: 'unknown-collider' };
  }
  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    if (!vec(p) || p.x < 0 || p.x > 1024 || p.y < 0 || p.y > 1024) return { ok: false, reason: 'invalid-point' };
    try { if (groundAt(p, layer) !== 'ground') return { ok: false, reason: 'unknown-or-water' }; }
    catch { return { ok: false, reason: 'unknown-or-water' }; }
    if (i && solid.some(shape => segmentBlocked(points[i - 1], p, shape))) return { ok: false, reason: 'obstructed' };
  }
  return { ok: true, reason: 'nominal-clear' };
}

// Constant-velocity hypothesis only; arrival delay and release time are explicit
// caller inputs, never inferred from an unconfirmed cook timer. A live caller
// must independently check history freshness, terrain and input confidence.
export function solveMovingOpenThrow({ target, targetVelocity, releaseDelay = 0, ...args }) {
  if (!vec(target) || !vec(targetVelocity) || !finite(releaseDelay) || releaseDelay < 0 || releaseDelay > 1
    || Math.hypot(targetVelocity.x, targetVelocity.y) > 80) return null;
  const probe = simulateOpenThrow({ ...args, direction: { x: 1, y: 0 }, mouseDistance: 0 });
  if (!probe) return null;
  const horizon = releaseDelay + probe.time;
  const projected = { x: target.x + targetVelocity.x * horizon, y: target.y + targetVelocity.y * horizon };
  const solution = solveOpenThrow({ ...args, target: projected });
  return solution ? { ...solution, projectedTarget: projected, horizon } : null;
}
