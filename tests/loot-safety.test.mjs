import test from 'node:test';
import assert from 'node:assert/strict';
import { nearbyLootSafety } from '../src/loot-safety.mjs';

const origin = { x: 10, y: 20 };
const supply = { __id: 9, __type: 3, active: true, type: '9mm', pos: { x: 11.5, y: 20 }, rad: 2, ownerId: 0, layer: 0 };
const gun = { __id: 10, __type: 3, active: true, type: 'mp5', pos: { x: 10.8, y: 20 }, rad: .2, ownerId: 0, layer: 0 };
const check = table => nearbyLootSafety(table, supply, origin, 0, 1);

test('nearby pickup fails closed when another observed item can be nearer to the server', () => {
  assert.ok(Math.hypot(gun.pos.x - origin.x, gun.pos.y - origin.y) > gun.rad, 'gun is not client desktop candidate');
  assert.ok(Math.hypot(gun.pos.x - origin.x, gun.pos.y - origin.y) < 1 + gun.rad, 'gun can be in server desktop pickup range');
  assert.equal(check({ 9: supply, 10: gun }), 'competing-loot');
  assert.equal(check({ 9: supply, 10: { ...gun, pos: { x: 11.5, y: 20 } } }), 'competing-loot', 'equal distance is ambiguous');
  assert.equal(check({ 9: supply, 10: { ...gun, layer: 1 } }), 'clear-observed');
  assert.equal(check({ 9: supply, 10: { ...gun, ownerId: 2 } }), 'clear-observed');
  assert.equal(check({ 9: supply, 10: { ...gun, active: false } }), 'clear-observed');
  assert.equal(check({ 9: supply, 10: { ...gun, pos: { x: 20, y: 20 } } }), 'clear-observed');
});
test('missing, inaccessible or ambiguous replicated loot cannot be treated as safe', () => {
  assert.equal(check(null), 'missing-registry');
  assert.equal(check({}), 'candidate-not-in-registry');
  assert.equal(check({ 9: supply, 10: { ...gun, pos: null } }), 'unknown-loot');
  assert.equal(check(new Proxy({}, { ownKeys() { throw Error('cannot scan'); } })), 'missing-registry');
  const table = { 9: supply }; let calls = 0;
  Object.defineProperty(table, 'unknown', { get() { calls++; return gun; } });
  assert.equal(check(table), 'missing-registry'); assert.equal(calls, 0);
  assert.equal(check(Object.fromEntries(Array.from({ length: 8193 }, (_, i) => [i, null]))), 'registry-budget');
});
