import test from 'node:test';
import assert from 'node:assert/strict';
import { movement, trajectory, collision } from '../scripts/benchmark-bot-duel.mjs';

test('bot movement includes independent alternating, diagonal, escape and stop inputs', () => {
  assert.deepEqual(movement('ad-fast', .01, 0), { x: 0, y: 1 });
  assert.deepEqual(movement('ad-fast', .2, 0), { x: 0, y: -1 });
  assert.equal(movement('ad-escape', 2.5, 0).y, 1);
  const d = movement('ad-diagonal', .1, 0); assert.ok(Math.abs(Math.hypot(d.x,d.y)-1)<1e-12);
  assert.deepEqual(movement('stop-go', .5, 0), { x: 0, y: 0 });
});

test('bot speeds include base, boosted and separate firing slowdown', () => {
  const base = trajectory('straight', 0, 12, false), boost = trajectory('straight', 0, 13.85, false), fire = trajectory('straight', 0, 13.85, true);
  assert.ok(Math.abs(base(1).y - 12) < 1e-9); assert.ok(Math.abs(boost(1).y - 13.85) < 1e-9);
  assert.ok(Math.abs(fire(1).y - 6.925) < 1e-9); assert.ok(Math.abs(trajectory('still', 0, 12, false)(1).y) < 1e-9);
  const delayed = trajectory('ad-fast', 0, 12, false, .1);
  assert.ok(delayed(.25).y > trajectory('ad-fast', 0, 12, false)(.25).y, 'uplink delays the reversal without exposing future input');
});

test('duel collision sweeps against the moving target rather than only the end point', () => {
  const still = () => ({ x: 0, y: 0 }), crossing = t => ({ x: 0, y: 5 - 10*t });
  assert.equal(collision({x:0,y:0},{x:1,y:0},20,20,still,0,10).hit,true);
  assert.equal(collision({x:0,y:0},{x:1,y:0},20,20,crossing,0,10).hit,true);
  assert.equal(collision({x:0,y:0},{x:1,y:0},20,8,still,0,10).hit,false);
  assert.equal(collision({x:0,y:3},{x:1,y:0},20,20,still,0,10).hit,false);
});
