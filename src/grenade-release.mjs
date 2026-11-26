import { finite, vec } from './core.mjs';
import { simulateOpenThrow, validateOpenThrow } from './grenade-aim.mjs';

// Nominal decision primitive; no input synthesis. The point represents a moving
// target under constant-velocity only, not an observed future or a hit guarantee.
// Caller must independently verify server state, network, geometry and control.
export function evaluateReleaseWindow({ solution, target, targetVelocity, releaseDelay, radius = 1, minDwell = .05, maxDwell = .4 }) {
  if (!solution || !Array.isArray(solution.points) || solution.points.length < 2 || solution.points.length > 2401
    || !vec(target) || !vec(targetVelocity) || !finite(releaseDelay) || releaseDelay < 0 || releaseDelay > 1
    || !finite(radius) || radius <= 0 || radius > 5 || !finite(minDwell) || !finite(maxDwell)
    || minDwell < 0 || maxDwell < minDwell || maxDwell > 2) return { ok: false, reason: 'invalid' };
  let arrival = null, lastTime = -1, endDistance = Infinity;
  for (const p of solution.points) {
    if (!vec(p) || !finite(p.z) || p.z < 0 || !finite(p.t) || p.t <= lastTime || p.t < 0) return { ok: false, reason: 'invalid-path' };
    lastTime = p.t;
    const t = releaseDelay + p.t;
    const d = Math.hypot(p.x - (target.x + targetVelocity.x * t), p.y - (target.y + targetVelocity.y * t));
    const settledInRegion = d <= radius && p.z <= .05;
    if (settledInRegion && arrival === null) arrival = p.t;
    if (!settledInRegion) arrival = null; // Continuous final stay, on the ground.
    endDistance = d;
  }
  if (arrival === null || endDistance > radius) return { ok: false, reason: 'no-arrival-at-detonation' };
  const dwell = lastTime - arrival;
  if (dwell < minDwell || dwell > maxDwell) return { ok: false, reason: 'outside-window', dwell };
  return { ok: true, reason: 'nominal-window', arrival, detonation: lastTime, dwell, endDistance };
}

// Test the *same* wire aim across bounded fuse uncertainty, not independently
// re-solved trajectories. This remains a hypothesis, not server confirmation.
export function assessAutoThrow({ def, origin, direction, mouseDistance, playerVelocity, target, targetVelocity,
  fuseRemaining, releaseDelay, layer, obstacles, groundAt, bounds, dt = 1 / 30 }) {
  if (!finite(bounds?.width) || !finite(bounds?.height) || bounds.width <= 0 || bounds.height <= 0
    || !finite(def?.rad) || def.rad <= 0) return { ok: false, reason: 'missing-map-bounds' };
  if (!vec(playerVelocity) || !vec(targetVelocity) || Math.hypot(playerVelocity.x, playerVelocity.y) > 4
    || Math.hypot(targetVelocity.x, targetVelocity.y) > 4 || !finite(fuseRemaining) || fuseRemaining < .35)
    return { ok: false, reason: 'uncertain-motion-or-fuse' };
  for (const adjustment of [-.08, 0, .08]) {
    const solution = simulateOpenThrow({ def, origin, direction, mouseDistance, playerVelocity, fuseRemaining: fuseRemaining + adjustment, dt });
    // Server clamps the projectile by its radius (definition radius / 2).
    const margin = def.rad * .5 + .1;
    if (!solution || solution.points.some(p => p.x < margin || p.y < margin || p.x > bounds.width - margin || p.y > bounds.height - margin))
      return { ok: false, reason: 'map-boundary' };
    const window = evaluateReleaseWindow({ solution, target, targetVelocity, releaseDelay, radius: .75, minDwell: .03, maxDwell: .5 });
    if (!window.ok) return { ok: false, reason: window.reason };
    const path = validateOpenThrow({ solution, origin, def, layer, obstacles, groundAt });
    if (!path.ok) return path;
  }
  return { ok: true, reason: 'nominal-window' };
}
