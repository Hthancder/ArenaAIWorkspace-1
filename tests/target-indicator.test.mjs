import test from 'node:test';
import assert from 'node:assert/strict';
import { drawTargetIndicator } from '../src/target-indicator.mjs';
import { normalizeConfig } from '../src/menu.mjs';

function context() {
  const calls = [];
  const ctx = Object.fromEntries(['save', 'restore', 'setLineDash', 'beginPath', 'arc', 'moveTo', 'lineTo', 'closePath', 'stroke'].map(name => [name, (...args) => calls.push([name, ...args])]));
  return { ctx, calls };
}

test('target indicator validates configuration and draws four distinct styles without retaining canvas state', () => {
  assert.equal(normalizeConfig({}).showTarget, false);
  assert.equal(normalizeConfig({ targetStyle: 'nonsense' }).targetStyle, 'ring');
  const signatures = new Set();
  for (const style of ['ring', 'cross', 'brackets', 'diamond']) {
    assert.equal(normalizeConfig({ targetStyle: style }).targetStyle, style);
    const { ctx, calls } = context();
    assert.equal(drawTargetIndicator(ctx, { x: 100, y: 50 }, 20, style), true);
    assert.equal(calls[0][0], 'save'); assert.equal(calls.at(-1)[0], 'restore');
    assert.equal(calls.filter(c => c[0] === 'stroke').length, 1);
    signatures.add(calls.map(c => c[0]).join(','));
  }
  assert.equal(signatures.size, 4);
  const { ctx, calls } = context();
  assert.equal(drawTargetIndicator(ctx, { x: NaN, y: 0 }, 20), false);
  assert.equal(calls.length, 0);
});
