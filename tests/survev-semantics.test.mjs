// Offline, inert reproductions of JavaScript semantics and audited source layouts.
// These tests do not inject into a browser or contact a game server.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';

test('patching .call does not intercept direct calls; explicit .call is observed', () => {
  const result = vm.runInNewContext(`
    const original = Function.prototype.call;
    let observed = 0;
    Function.prototype.call = function () {
      observed++;
      return Reflect.apply(original, this, arguments);
    };
    const obj = { method() { return 42; } };
    obj.method();
    const direct = observed;
    obj.method.call(obj);
    Function.prototype.call = original;
    ({ direct, explicit: observed });
  `);
  assert.equal(result.direct, 0);
  assert.equal(result.explicit, 1);
});

test('audited Camera layout: index 2 is zoom, index 3 is targetZoom', () => {
  const camera = {
    m_pos: { x: 0, y: 0 }, m_ppu: 16, m_zoom: 1.5, m_targetZoom: 1.5,
    m_screenWidth: 1, m_screenHeight: 1, m_shakeEnabled: true, m_shakeInt: 0,
  };
  assert.equal(Object.keys(camera)[2], 'm_zoom');
  assert.equal(Object.keys(camera)[3], 'm_targetZoom');
});

test('audited Join layout: scanning first string skips token, then fixed name and useTouch lead to isMobile', () => {
  // A synthetic fixture, not an actual network packet. No bits are modified.
  const token = Buffer.from('synthetic-token\0', 'ascii');
  const name = Buffer.alloc(16);
  name.write('test');
  const bytes = Buffer.concat([Buffer.from([1]), Buffer.alloc(4), token, name, Buffer.alloc(1)]);
  let bitOffset = 8 + 32;
  while (bytes[bitOffset >> 3] !== 0) bitOffset += 8;
  bitOffset += 8;
  assert.equal(bitOffset / 8, 5 + token.length);
  bitOffset += 16 * 8 + 1;
  const flagStart = (5 + token.length + 16) * 8;
  assert.equal(bitOffset, flagStart + 1); // useTouch is flag 0; isMobile is flag 1.
});

test('restoring current buttons after flush does not restore old-state snapshot', () => {
  const input = { mouseButtons: { 0: false }, mouseButtonsOld: { 0: false } };
  input.mouseButtons[0] = true; // temporary pre-frame value
  input.mouseButtonsOld = { ...input.mouseButtons }; // Application.update -> flush
  input.mouseButtons[0] = false; // post-frame restoration
  assert.equal(input.mouseButtons[0], false);
  assert.equal(input.mouseButtonsOld[0], true);
});

test('first array discovery is ambiguous when an owner also contains playerIds', () => {
  const barn = { playerIds: [1, 2], actualEntities: [{ __id: 1 }] };
  const firstArray = Object.values(barn).find(Array.isArray);
  assert.equal(firstArray, barn.playerIds);
  assert.notEqual(firstArray, barn.actualEntities);
});

test('native-style toString output is not proof of original function identity', () => {
  const original = Math.max;
  const wrapped = new Proxy(original, {});
  assert.equal(wrapped(1, 2), 2);
  assert.notEqual(wrapped, original);
  assert.match(Function.prototype.toString.call(wrapped), /native code/);
});
