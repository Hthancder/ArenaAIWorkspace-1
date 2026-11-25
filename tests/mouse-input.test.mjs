import test from 'node:test';
import assert from 'node:assert/strict';
import { MouseInputFrame } from '../src/mouse-input.mjs';
import { normalizeConfig } from '../src/menu.mjs';

const camera = () => ({ camera: { w: 800, h: 600, pixels: 16, zoom: 2 }, widthKey: 'w', heightKey: 'h', scaleKeys: ['pixels', 'zoom'] });
const plan = { dir: { x: .6, y: .8 }, distance: 10, toMouseHit: false };

test('native mouse transaction changes direction but preserves real cursor radius and identity', () => {
  const input = { mousePos: { x: 440, y: 300 }, mouseButtons: { 0: true } }, mouse = input.mousePos;
  const frame = new MouseInputFrame();
  assert.ok(frame.apply(input, camera(), plan));
  assert.equal(input.mousePos, mouse); assert.deepEqual(mouse, { x: 424, y: 268 });
  assert.deepEqual(frame.physical(input), { x: 440, y: 300 });
  assert.equal(input.mouseButtons[0], true);
  frame.restore(); assert.deepEqual(mouse, { x: 440, y: 300 });
  frame.restore(); assert.equal(frame.snapshot().active, false);
});

test('sender raw intent reconstruction uses current zoom and retains native prototype/fields', () => {
  class Input { serialize() {} addInput() {} }
  const native = Object.assign(new Input(), { toMouseDir: { x: .6, y: .8 }, toMouseLen: 2, shootHold: true, moveLeft: true, inputs: [11] });
  const input = { mousePos: { x: 440, y: 300 } }, frame = new MouseInputFrame(), c = camera();
  frame.apply(input, c, plan); c.camera.zoom = 4;
  const raw = frame.intent(input, c, native);
  assert.ok(raw instanceof Input); assert.deepEqual(raw.toMouseDir, { x: 1, y: 0 }); assert.equal(raw.toMouseLen, .625);
  assert.equal(raw.shootHold, true); assert.equal(raw.moveLeft, true); assert.deepEqual(raw.inputs, [11]);
  assert.deepEqual(native.toMouseDir, { x: .6, y: .8 });
  frame.restore(); assert.equal(frame.intent(input, c, native), native);
});

test('toMouseHit changes native distance only when requested, bounded by native range', () => {
  const input = { mousePos: { x: 440, y: 300 } }, frame = new MouseInputFrame(), c = camera();
  frame.apply(input, c, { ...plan, toMouseHit: true, distance: 3 });
  assert.ok(Math.abs(Math.hypot(input.mousePos.x - 400, 300 - input.mousePos.y) / 32 - 3) < 1e-9);
  frame.apply(input, c, { ...plan, toMouseHit: true, distance: 1000 });
  assert.ok(Math.abs(Math.hypot(input.mousePos.x - 400, 300 - input.mousePos.y) / 32 - 64) < 1e-9);
  frame.restore(); assert.deepEqual(input.mousePos, { x: 440, y: 300 });
});

test('restore preserves newer coordinate writers and input-vector replacements', () => {
  const input = { mousePos: { x: 440, y: 300 } }, frame = new MouseInputFrame();
  frame.apply(input, camera(), plan); input.mousePos.x = 500;
  assert.deepEqual(frame.physical(input), { x: 500, y: 300 });
  frame.restore(); assert.deepEqual(input.mousePos, { x: 500, y: 300 });
  frame.apply(input, camera(), plan); const old = input.mousePos;
  input.mousePos = { x: 700, y: 600 };
  const native = {}; assert.equal(frame.intent(input, camera(), native), native);
  frame.restore(); assert.deepEqual(input.mousePos, { x: 700, y: 600 }); assert.deepEqual(old, { x: 500, y: 300 });
});

test('unsupported input descriptor and invalid projection fail without partial mutation', () => {
  const frame = new MouseInputFrame(), input = { mousePos: { x: 440, y: 300 } };
  Object.defineProperty(input.mousePos, 'y', { value: 300, writable: false });
  assert.equal(frame.apply(input, camera(), plan), false); assert.equal(input.mousePos.x, 440);
  const c = camera(); c.camera.zoom = NaN;
  assert.equal(frame.apply({ mousePos: { x: 440, y: 300 } }, c, plan), false);
  assert.deepEqual(frame.snapshot(), { active: false, appliedFrames: 0, skippedFrames: 2 });
});

test('direct mouse config defaults on, accepts a persisted opt-out, rejects non-boolean', () => {
  assert.equal(normalizeConfig({}).directMouseInput, true);
  assert.equal(normalizeConfig({ directMouseInput: false }).directMouseInput, false);
  assert.equal(normalizeConfig({ directMouseInput: 'false' }).directMouseInput, true);
});
