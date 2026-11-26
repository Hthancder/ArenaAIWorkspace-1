import test from 'node:test';
import assert from 'node:assert/strict';
import { simulateOpenThrow, solveMovingOpenThrow, solveOpenThrow, validateOpenThrow } from '../src/grenade-aim.mjs';

const frag = { type: 'throwable', cookable: true, explodeOnImpact: false, forceMaxThrowDistance: false, aimDistance: 0,
  throwPhysics: { speed: 20, velZ: 5, playerVelMult: .6 } };
const origin = { x: 20, y: 30 }, velocity = { x: 3, y: -4 };

test('open throw follows source initial hand, horizontal velocity and gravity update order', () => {
  const r = simulateOpenThrow({ def: frag, origin, direction: { x: 1, y: 0 }, mouseDistance: 9, playerVelocity: velocity, fuseRemaining: .1, dt: .1 });
  assert.equal(r, null, 'unsupported large tick fails closed');
  const s = simulateOpenThrow({ def: frag, origin, direction: { x: 1, y: 0 }, mouseDistance: 9, playerVelocity: velocity, fuseRemaining: .05, dt: .05 });
  assert.ok(Math.abs(s.end.x - (20.5 + 11.8 * .05)) < 1e-9);
  assert.ok(Math.abs(s.end.y - (29 - 2.4 * .05)) < 1e-9);
  assert.ok(Math.abs(s.points[1].z - (.5 + (5 - 10.5 * .05) * .05)) < 1e-9);
  assert.equal(s.time, .05); assert.equal(s.nominal, true);
});

test('inverse solution reproduces open model for multiple angles, strengths, motion, tick and fuses', () => {
  for (const a of [-3, -1, 0, .7, 2.8]) for (const mouseDistance of [0, 1, 6, 12, 18])
    for (const fuseRemaining of [.3, 1.1, 3]) for (const dt of [1 / 30, 1 / 60]) {
      const args = { def: frag, origin, playerVelocity: velocity, fuseRemaining, dt };
      const actual = simulateOpenThrow({ ...args, direction: { x: Math.cos(a), y: Math.sin(a) }, mouseDistance });
      const solved = solveOpenThrow({ ...args, target: actual.end });
      assert.ok(solved, `missing solution ${a} ${mouseDistance} ${fuseRemaining}`);
      assert.ok(Math.hypot(solved.end.x - actual.end.x, solved.end.y - actual.end.y) < 1e-8);
      assert.ok(Math.abs(solved.mouseDistance - mouseDistance) < 1e-8);
    }
});

test('moving hypothesis includes explicit release delay and tick-rounded fuse, not future steering', () => {
  const args = { def: frag, origin, playerVelocity: velocity, fuseRemaining: 1.1, dt: 1 / 30 };
  const fixed = simulateOpenThrow({ ...args, direction: { x: 1, y: 0 }, mouseDistance: 9 });
  const v = { x: 2, y: -.4 }, releaseDelay = .1, horizon = fixed.time + releaseDelay;
  const target = { x: fixed.end.x - v.x * horizon, y: fixed.end.y - v.y * horizon };
  const shot = solveMovingOpenThrow({ ...args, target, targetVelocity: v, releaseDelay });
  assert.ok(shot); assert.ok(Math.hypot(shot.end.x - fixed.end.x, shot.end.y - fixed.end.y) < 1e-8);
  assert.equal(shot.horizon, horizon);
  assert.equal(solveMovingOpenThrow({ ...args, target, targetVelocity: v, releaseDelay: NaN }), null);
  assert.equal(solveMovingOpenThrow({ ...args, target, targetVelocity: { x: 81, y: 0 } }), null);
});

test('fails closed for unmodeled throwable semantics and missing evidence', () => {
  const args = { def: frag, origin, playerVelocity: velocity, target: { x: 500, y: 30 }, fuseRemaining: 2 };
  assert.equal(solveOpenThrow(args), null, 'outside nominal range');
  for (const def of [{ ...frag, cookable: false }, { ...frag, explodeOnImpact: true }, { ...frag, heavyType: 'other' },
    { ...frag, forceMaxThrowDistance: true }, { ...frag, fuseVariance: .3 }, { ...frag, aimDistance: 2 }, { ...frag, throwPhysics: {} }]) {
    assert.equal(solveOpenThrow({ ...args, def, target: { x: 25, y: 30 } }), null);
  }
  assert.equal(solveOpenThrow({ ...args, target: { x: 25, y: 30 }, playerVelocity: null }), null);
  assert.equal(solveOpenThrow({ ...args, target: { x: 25, y: 30 }, fuseRemaining: 0 }), null);
});
