// Synthetic registry scan microbenchmark; not live FPS or total frame time.
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { entries, read, object, finite, sameLayer } from '../src/core.mjs';
import { geometryObjects, segmentCandidates } from '../src/aim-geometry.mjs';
const table = {};
for (let i = 0; i < 4000; i++) table[i] = i % 4 === 0
  ? { __type: 2, active: true, collidable: true, layer: 0, height: 1, collider: { type: 0, pos: { x: (i % 100) * 3, y: Math.floor(i / 100) * 3 }, rad: 1 } }
  : i % 100 === 1 ? { stairs: [] } : { __type: 1 };
const from = { x: 8, y: 8 }, to = { x: 30, y: 10 };
const eligible = o => read(o, 'active') !== false && !read(o, 'dead') && read(o, 'collidable') !== false
  && !(finite(read(o, 'height')) && read(o, 'height') < .25) && (!finite(read(o, 'layer')) || sameLayer(read(o, 'layer'), 0));
function old() {
  const structures = entries(table).map(([, o]) => o).filter(o => Array.isArray(read(o, 'stairs')));
  const obstacles = entries(table).map(([, o]) => o).filter(o => read(o, '__type') === 2 || object(read(o, 'collider')) && typeof read(o, 'collidable') === 'boolean');
  return { structures, obstacles, relevant: segmentCandidates(obstacles.filter(eligible), from, to) };
}
function optimized() {
  const { structures, obstacles } = geometryObjects(table);
  return { structures, obstacles, relevant: segmentCandidates(obstacles, from, to).filter(eligible) };
}
assert.deepEqual(optimized(), old());
for (let i = 0; i < 20; i++) { old(); optimized(); }
for (const [name, fn] of [['old', old], ['optimized', optimized]]) {
  const durations = [];
  for (let i = 0; i < 300; i++) { const start = performance.now(); fn(); durations.push(performance.now() - start); }
  durations.sort((a,b) => a-b);
  console.log(`${name}: median ${durations[150].toFixed(3)} ms, p95 ${durations[285].toFixed(3)} ms / solve, synthetic registry ${Object.keys(table).length}`);
}
