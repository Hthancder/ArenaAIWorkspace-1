import test from 'node:test';
import assert from 'node:assert/strict';
import { movement, trajectory, collision, tickSegmentCircle, tickCollisionSweep, eventWindow } from '../scripts/benchmark-bot-duel.mjs';

test('bot movement includes independent alternating, diagonal, escape and stop inputs', () => {
  assert.deepEqual(movement('ad-fast', .01, 0), { x: 0, y: 1 });
  assert.deepEqual(movement('ad-fast', .2, 0), { x: 0, y: -1 });
  assert.equal(movement('ad-escape', 2.5, 0).y, 1);
  assert.equal(movement('ad-escape-stop', 2.8, 0).y, 0);
  assert.equal(movement('ad-escape-return', 2.8, 0).y, -1);
  assert.equal(movement('ad-shrink-escape', 3.1, 0).y, 1);
  assert.deepEqual(movement('approach', .1, 0), {x:-1,y:0});
  assert.deepEqual(movement('retreat', .1, 0), {x:1,y:0});
  assert.equal(movement('speed-change', .1, 0).y, .3);
  assert.equal(movement('speed-change', .9, 0).y, 1);
  assert.deepEqual(movement('irregular-alt', .2, 0), {x:1,y:0});
  assert.deepEqual(movement('irregular-escape', 3, 0), {x:0,y:1});
  const d = movement('ad-diagonal', .1, 0); assert.ok(Math.abs(Math.hypot(d.x,d.y)-1)<1e-12);
  assert.deepEqual(movement('stop-go', .5, 0), { x: 0, y: 0 });
});

test('event windows use server shot time and undo holdout time scaling', () => {
  const event = 2.4 / 1.13 - .37;
  assert.equal(eventWindow('ad-escape', event - .001, .37, true), null);
  assert.equal(eventWindow('ad-escape', event + .1, .37, true), '0-200ms');
  assert.equal(eventWindow('ad-escape', event + .3, .37, true), '200-500ms');
  assert.equal(eventWindow('ad-escape', event + .8, .37, true), '500-1000ms');
  assert.equal(eventWindow('ad-escape', event + 1.1, .37, true), null);
  assert.equal(eventWindow('straight', event + .1, .37, true), null);
  assert.equal(eventWindow('ad-escape-stop', 2.4 - .19 + .1, .19), '0-200ms');
  assert.equal(eventWindow('ad-shrink-escape', 3.12 - .19 + .1, .19), '0-200ms');
  const continuedShrink = x => Math.floor((x - 2) / .16) % 2 ? -1 : 1;
  assert.equal(movement('ad-shrink-escape', 3.1, 0).y, continuedShrink(3.1));
  assert.notEqual(movement('ad-shrink-escape', 3.13, 0).y, continuedShrink(3.13));
  assert.notEqual(movement('ad-escape', 2.41, 0).y, movement('ad-wide', 2.41, 0).y);
  assert.equal(movement('ad-delayed-escape', 2.7, 0).y, movement('ad-wide', 2.7, 0).y);
  assert.notEqual(movement('ad-delayed-escape', 2.89, 0).y, movement('ad-wide', 2.89, 0).y);
  assert.equal(eventWindow('ad-delayed-escape', 2.88 + .1, 0), '0-200ms');
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

test('source-shaped tick collision tests circle at tick time and detects exit from an overlapping muzzle', () => {
  const center = {x:0,y:0};
  assert.equal(tickSegmentCircle({x:-2,y:0},{x:2,y:0},center,1),true);
  assert.equal(tickSegmentCircle({x:0,y:0},{x:.1,y:0},center,1),false, 'segment wholly inside does not reach source exit intersection');
  assert.equal(tickSegmentCircle({x:0,y:0},{x:2,y:0},center,1),true);
  assert.equal(tickSegmentCircle({x:-2,y:1.1},{x:2,y:1.1},center,1),false);
  const still = () => ({x:0,y:0});
  assert.equal(tickCollisionSweep({x:0,y:0},{x:1,y:0},100,20,still,0,10).hit,true);
  assert.equal(tickCollisionSweep({x:0,y:0},{x:1,y:0},100,8,still,0,10).hit,false);
});
