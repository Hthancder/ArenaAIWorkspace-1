import test from 'node:test';
import assert from 'node:assert/strict';
import { validateOpenThrow } from '../src/grenade-aim.mjs';
const def = { type: 'throwable', cookable: true, explodeOnImpact: false, aimDistance: 0, rad: 1, throwPhysics: { speed: 20, velZ: 5, playerVelMult: .6 } };
const base = { def, origin: { x: 10, y: 10 }, layer: 0, obstacles: [], groundAt: () => 'ground', solution: { points: [{ x: 10.5, y: 9 }, { x: 14, y: 9 }, { x: 18, y: 9 }] } };
test('conservative open path checks spawn, swept collision, layers and unknown geometry', () => {
  assert.equal(validateOpenThrow(base).ok, true);
  for (const collider of [
    { type: 0, pos: { x: 13, y: 9.3 }, rad: .1 },
    { type: 1, min: { x: 13, y: 8.9 }, max: { x: 14, y: 9.1 } },
    { type: 0, pos: { x: 10.25, y: 9.5 }, rad: .1 },
  ]) assert.equal(validateOpenThrow({ ...base, obstacles: [{ active: true, layer: 0, collidable: true, collider }] }).reason, 'obstructed');
  assert.equal(validateOpenThrow({ ...base, obstacles: [{ active: true, layer: 1, collider: { type: 0, pos: { x: 13, y: 9 }, rad: 2 } }] }).ok, true);
  assert.equal(validateOpenThrow({ ...base, obstacles: [{ active: true, layer: 0, collider: { type: 6 } }] }).reason, 'unknown-collider');
  assert.equal(validateOpenThrow({ ...base, obstacles: [{ active: true, collider: { type: 0, pos: { x: 50, y: 50 }, rad: 1 } }] }).reason, 'unknown-layer');
  assert.equal(validateOpenThrow({ ...base, layer: 2 }).ok, false);
});
test('unknown, wet or failing terrain and invalid world inputs fail closed', () => {
  assert.equal(validateOpenThrow({ ...base, groundAt: () => 'water' }).reason, 'unknown-or-water');
  assert.equal(validateOpenThrow({ ...base, groundAt: () => undefined }).reason, 'unknown-or-water');
  assert.equal(validateOpenThrow({ ...base, groundAt: () => { throw Error('no map'); } }).reason, 'unknown-or-water');
  assert.equal(validateOpenThrow({ ...base, obstacles: null }).ok, false);
  assert.equal(validateOpenThrow({ ...base, solution: { points: [{ x: -1, y: 1 }, { x: 0, y: 0 }] } }).reason, 'invalid-point');
  assert.equal(validateOpenThrow({ ...base, def: { ...def, playerCollision: true } }).ok, false);
});
