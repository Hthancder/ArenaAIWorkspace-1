import test from 'node:test';
import assert from 'node:assert/strict';
import { GrenadeAutoRelease } from '../src/grenade-auto-release.mjs';
import { assessAutoThrow } from '../src/grenade-release.mjs';
import { solveOpenThrow } from '../src/grenade-aim.mjs';
const def = { type: 'throwable', cookable: true, explodeOnImpact: false, aimDistance: 0, rad: 1, throwPhysics: { speed: 20, velZ: 5, playerVelMult: .6 } };
const origin = { x: 50, y: 50 }, target = { x: 60, y: 50 }, velocity = { x: 0, y: 0 }, fuseRemaining = 1.12;
const solution = solveOpenThrow({ def, origin, target, playerVelocity: velocity, fuseRemaining });
const args = { def, origin, direction: solution.direction, mouseDistance: solution.mouseDistance, playerVelocity: velocity, target, targetVelocity: velocity, fuseRemaining, releaseDelay: 0, layer: 0, bounds: { width: 100, height: 100 }, obstacles: [], groundAt: () => 'ground' };
test('auto throw checks the same aim under fuse uncertainty and rejects walls and unstable motion', () => {
  assert.equal(assessAutoThrow(args).ok, true);
  assert.equal(assessAutoThrow({ ...args, targetVelocity: { x: 10, y: 0 } }).ok, false);
  assert.equal(assessAutoThrow({ ...args, fuseRemaining: .1 }).ok, false);
  assert.equal(assessAutoThrow({ ...args, bounds: null }).reason, 'missing-map-bounds');
  assert.equal(assessAutoThrow({ ...args, bounds: { width: 55, height: 100 } }).reason, 'map-boundary');
  assert.equal(assessAutoThrow({ ...args, groundAt: () => 'water' }).ok, false);
  assert.equal(assessAutoThrow({ ...args, obstacles: [{ layer: 0, collider: { type: 0, pos: { x: 55, y: 50 }, rad: 1 } }] }).ok, false);
});
test('release gate requires physical edge and stability, suppresses recook and resets on physical release', () => {
  const a = new GrenadeAutoRelease(), target = {};
  const s = { held: true, edge: true, enabled: true, ready: true, target: null, viable: false, now: 0 };
  assert.equal(a.observe(s), 'native');
  assert.equal(a.observe({ ...s, edge: false, target, now: 10 }), 'native');
  assert.equal(a.observe({ ...s, edge: false, target, viable: true, now: 209 }), 'native');
  assert.equal(a.observe({ ...s, edge: false, target, viable: true, now: 210 }), 'release');
  assert.equal(a.observe({ ...s, edge: true, enabled: false, now: 220 }), 'suppress');
  assert.equal(a.observe({ ...s, held: false, now: 230 }), 'native');
  assert.equal(a.observe({ ...s, edge: false, now: 240 }), 'native');
  assert.equal(a.observe({ ...s, target, viable: true, now: 1000 }), 'native');
});
test('loss of plan, target changes, invalid input and manual cancellation cannot reacquire during hold', () => {
  for (const change of [{ target: null }, { target: {} }, { ready: false }, { enabled: false }]) {
    const a = new GrenadeAutoRelease(), target = {};
    const s = { held: true, edge: true, enabled: true, ready: true, target: null, viable: false, now: 0 };
    a.observe(s); a.observe({ ...s, edge: false, target, now: 1 });
    assert.equal(a.observe({ ...s, edge: false, target, now: 50, ...change }), 'cancel');
    assert.equal(a.observe({ ...s, target, viable: true, now: 1000 }), 'native');
  }
});
