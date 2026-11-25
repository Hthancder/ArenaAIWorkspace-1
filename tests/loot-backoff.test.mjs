import test from 'node:test';
import assert from 'node:assert/strict';
import { LootBackoff } from '../src/loot-backoff.mjs';

test('loot backoff survives candidate oscillation and enforces a global server-cooldown margin', () => {
  const b = new LootBackoff(), a = { __id: 1, type: '9mm', count: 30 }, c = { __id: 2, type: 'bandage', count: 1 };
  assert.equal(b.attempt(a, 1000).attempts, 1);
  assert.equal(b.attempt(c, 1050), null);
  assert.equal(b.attempt(c, 1120).attempts, 1);
  assert.equal(b.attempt(a, 1240), null);
  assert.equal(b.attempt(a, 1350).attempts, 2);
  a.count = 20;
  assert.equal(b.attempt(a, 1400), null);
  assert.equal(b.attempt(a, 1470).attempts, 1);
  a.__id = 3;
  assert.equal(b.attempt(a, 1590).attempts, 1);
  b.reset(); assert.equal(b.items.size, 0); assert.equal(b.attempt(a, 1591).attempts, 1);
});

test('loot retry state is bounded and expires without extending stale retries', () => {
  const b = new LootBackoff();
  for (let i = 0; i < 150; i++) b.attempt({ __id: i, type: '9mm', count: 1 }, i * 120);
  assert.ok(b.items.size <= 128);
  const a = { __id: 200, type: '9mm', count: 1 };
  assert.equal(b.attempt(a, 20000).attempts, 1);
  assert.equal(b.attempt(a, 30001).attempts, 1);
  assert.equal(b.items.size, 1);
});

test('rapidly alternating unchanged candidates do not reset their retry schedule', () => {
  const b = new LootBackoff();
  const items = [{ __id: 1, type: '9mm', count: 30 }, { __id: 2, type: 'bandage', count: 1 }];
  let pulses = 0;
  for (let t = 0; t < 10000; t += 16) if (b.attempt(items[Math.floor(t / 160) % 2], t)) pulses++;
  assert.equal(pulses, 14);
});
