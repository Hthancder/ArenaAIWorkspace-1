import test from 'node:test';
import assert from 'node:assert/strict';
import { RuntimePerf } from '../src/runtime-perf.mjs';
test('timings use a bounded ring, ignore invalid samples and retain session peak', () => {
  const p = new RuntimePerf(3);
  p.add('frame', 8); p.add('frame', 1); p.add('frame', 2); p.add('frame', 3); p.add('frame', 4); p.add('frame', NaN); p.add('frame', -1);
  const row = p.snapshot().frame;
  assert.equal(row.samples, 3); assert.equal(row.count, 5); assert.equal(row.p95Ms, 3); assert.equal(row.maxMs, 4); assert.equal(row.sessionPeakMs, 8);
});
