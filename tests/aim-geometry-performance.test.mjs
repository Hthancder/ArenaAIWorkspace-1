import test from 'node:test';
import assert from 'node:assert/strict';
import { entries, read, object, sameLayer, finite } from '../src/core.mjs';
import { geometryObjects, segmentCandidates } from '../src/aim-geometry.mjs';

test('single fresh geometry scan matches legacy selection without invoking accessors', () => {
  let calls = 0;
  const wall = { __type: 2, active: true, collidable: true, layer: 0, collider: { type: 0, pos: { x: 1, y: 1 }, rad: 1 } };
  const table = { a: wall, b: { stairs: [] }, c: { collider: {}, collidable: false }, d: { __type: 1 } };
  Object.defineProperty(table, 'hidden', { value: { __type: 2 }, enumerable: false, configurable: true });
  Object.defineProperty(table, 'getter', { get() { calls++; throw Error('must not run'); }, configurable: true });
  const legacy = () => ({ structures: entries(table).map(([, o]) => o).filter(o => Array.isArray(read(o, 'stairs'))),
    obstacles: entries(table).map(([, o]) => o).filter(o => read(o, '__type') === 2 || object(read(o, 'collider')) && typeof read(o, 'collidable') === 'boolean') });
  assert.deepEqual(geometryObjects(table), legacy());
  delete table.a; table.newWall = { __type: 2, collider: { type: 1, min: { x: 0, y: 0 }, max: { x: 2, y: 2 } } };
  assert.deepEqual(geometryObjects(table), legacy(), 'registry mutations are reflected on the next solve');
  assert.equal(calls, 0);
});

test('wallcheck broadphase reorder preserves relevant obstacle set and unsupported shapes', () => {
  const from = { x: 0, y: 0 }, to = { x: 10, y: 0 };
  const objects = Array.from({ length: 200 }, (_, i) => ({ active: i % 5 !== 0, dead: i % 7 === 0, collidable: i % 11 !== 0,
    height: i % 3 ? 1 : .1, layer: i % 2, collider: i % 13 ? { type: 0, pos: { x: i % 20, y: i % 17 }, rad: 1 } : { type: 99 } }));
  const eligible = o => read(o, 'active') !== false && !read(o, 'dead') && read(o, 'collidable') !== false
    && !(finite(read(o, 'height')) && read(o, 'height') < .25) && (!finite(read(o, 'layer')) || sameLayer(read(o, 'layer'), 0));
  assert.deepEqual(segmentCandidates(objects, from, to).filter(eligible), segmentCandidates(objects.filter(eligible), from, to));
  assert.ok(segmentCandidates(objects, from, to).filter(eligible).some(o => o.collider.type === 99));
});
