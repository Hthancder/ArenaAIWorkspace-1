import test from 'node:test';
import assert from 'node:assert/strict';
import { GrenadeTimer, drawGrenadeTimer } from '../src/grenade-timer.mjs';

const owner = {}, definitions = { frag: { type: 'throwable', cookable: true, fuseTime: 4 }, short: { type: 'throwable', cookable: true, fuseTime: 1.8 }, smoke: { type: 'throwable', cookable: false, fuseTime: 2.5 } };
const base = { enabled: true, ready: true, owner, slot: 3, type: 'frag', activeType: 'frag', definitions };
const edge = { shootStart: true, shootHold: true }, hold = { shootStart: false, shootHold: true }, release = { shootStart: false, shootHold: false };

test('starts only at observed forwarded edge and counts down without restarting for duplicate holds', () => {
  const timer = new GrenadeTimer();
  timer.forwarded(base, hold, 1000); assert.equal(timer.sample(base, 1000), null);
  timer.forwarded(base, edge, 1000); assert.equal(timer.sample(base, 1000).seconds, 4);
  timer.forwarded(base, edge, 1700); assert.equal(timer.sample(base, 2000).seconds, 3);
  assert.equal(timer.sample(base, 6000).seconds, 0, 'clamp at zero, do not assert server detonation');
  timer.forwarded(base, release, 6001); assert.equal(timer.sample(base, 6001), null);
  timer.forwarded(base, edge, 6100); assert.equal(timer.sample(base, 6200).seconds, 3.9);
});

test('uses per-type fuse; unknown, non-cookable, unsafe or mismatched states do not arm', () => {
  const timer = new GrenadeTimer(), short = { ...base, type: 'short', activeType: 'short' };
  timer.forwarded(short, edge, 1000); assert.equal(timer.sample(short, 1500).seconds, 1.3);
  for (const context of [
    { ...base, enabled: false }, { ...base, ready: false }, { ...base, slot: 0 }, { ...base, activeType: 'short' },
    { ...base, type: 'unknown', activeType: 'unknown' }, { ...base, type: 'smoke', activeType: 'smoke' },
    { ...base, definitions: { frag: { type: 'throwable', cookable: true, fuseTime: Infinity } } },
    { ...base, definitions: { frag: { type: 'throwable', cookable: true, fuseTime: 9999 } } },
  ]) { timer.reset(); timer.forwarded(context, edge, 1000); assert.equal(timer.sample(context, 1000), null); }
  timer.forwarded(base, edge, 1000, true); assert.equal(timer.sample(base, 1000), null, 'equip input invalidates uncertain selection');
});

test('identity, selection, timer toggle, backwards clock and cleanup invalidate evidence', () => {
  const timer = new GrenadeTimer();
  for (const changed of [{ ...base, owner: {} }, { ...base, type: 'short', activeType: 'short' }, { ...base, ready: false }, { ...base, enabled: false }]) {
    timer.forwarded(base, edge, 1000); assert.equal(timer.sample(changed, 1010), null);
    assert.equal(timer.sample(base, 1010), null, 'never resume stale timer');
  }
  timer.forwarded(base, edge, 1000); assert.equal(timer.sample(base, 999), null);
  timer.forwarded(base, edge, 1000); timer.reset(); assert.equal(timer.sample(base, 1000), null);
});

test('draws only an approximate visual label, with urgent colour', () => {
  const fills = [], labels = [], ctx = { save() {}, restore() {}, fillRect() {}, fillText(text, x, y) { labels.push([text, x, y]); }, set fillStyle(v) { fills.push(v); } };
  drawGrenadeTimer(ctx, { x: 100, y: 120 }, .4);
  assert.deepEqual(labels[0], ['Bom ~0.4s', 100, 42]); assert.equal(labels[1][0], 'chưa xác nhận'); assert.ok(fills.includes('#ff6b6b'));
  drawGrenadeTimer(ctx, null, 1); assert.equal(labels.length, 2);
});
