import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateReleaseWindow } from '../src/grenade-release.mjs';
const base = { target: { x: 10, y: 0 }, targetVelocity: { x: 0, y: 0 }, releaseDelay: 0, radius: 1 };
const points = [{ x: 5, y: 0, z: 0, t: 0 }, { x: 9.2, y: 0, z: 0, t: .8 }, { x: 10, y: 0, z: 0, t: 1 }];
test('only an arrival shortly before nominal detonation qualifies', () => {
  const result = evaluateReleaseWindow({ ...base, solution: { points } });
  assert.equal(result.ok, true); assert.ok(Math.abs(result.dwell - .2) < 1e-9);
  assert.equal(evaluateReleaseWindow({ ...base, solution: { points: [{ x: 5, y: 0, z: 0, t: 0 }, { x: 9.9, y: 0, z: 0, t: 1 }] } }).reason, 'outside-window');
  assert.equal(evaluateReleaseWindow({ ...base, solution: { points: [{ x: 10, y: 0, z: 0, t: 0 }, { x: 10, y: 0, z: 0, t: 1 }] } }).reason, 'outside-window');
  assert.equal(evaluateReleaseWindow({ ...base, solution: { points: [{ x: 10, y: 0, z: 0, t: 0 }, { x: 8, y: 0, z: 0, t: 1 }] } }).reason, 'no-arrival-at-detonation');
});
test('models target movement and rejects stale or malformed samples', () => {
  assert.equal(evaluateReleaseWindow({ ...base, targetVelocity: { x: 5, y: 0 }, solution: { points } }).ok, false);
  assert.equal(evaluateReleaseWindow({ ...base, solution: { points: points.map(p => ({ ...p, z: 1 })) } }).ok, false);
  assert.equal(evaluateReleaseWindow({ ...base, releaseDelay: NaN, solution: { points } }).reason, 'invalid');
  assert.equal(evaluateReleaseWindow({ ...base, solution: { points: [points[0], { ...points[1], t: 0 }] } }).reason, 'invalid-path');
  const exitReenter = [{ x: 10, y: 0, z: 0, t: 0 }, { x: 5, y: 0, z: 0, t: .5 }, { x: 10, y: 0, z: 0, t: .9 }, { x: 10, y: 0, z: 0, t: 1 }];
  assert.ok(Math.abs(evaluateReleaseWindow({ ...base, solution: { points: exitReenter } }).dwell - .1) < 1e-9);
});
