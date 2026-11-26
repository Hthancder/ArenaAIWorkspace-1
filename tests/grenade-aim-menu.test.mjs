import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULTS, normalizeConfig } from '../src/menu.mjs';

test('grenade aim modes are independent, exclusive and default off', () => {
  assert.equal(DEFAULTS.grenadeAimMode, 'off');
  assert.equal(DEFAULTS.grenadeAutoThrow, false);
  assert.equal(normalizeConfig({ grenadeAutoThrow: true }).grenadeAutoThrow, true);
  assert.equal(normalizeConfig({ grenadeAutoThrow: 'true' }).grenadeAutoThrow, false);
  assert.equal(DEFAULTS.grenadeAimActivation, 'hold');
  assert.equal(DEFAULTS.grenadeAssistStrength, 35);
  assert.equal(DEFAULTS.grenadeFov, 100); assert.equal(DEFAULTS.grenadeCancelKey, 'AltLeft');
  assert.equal(normalizeConfig({ fov: 225 }).grenadeFov, 225);
  assert.equal(normalizeConfig({ fov: 225, grenadeFov: 75 }).grenadeFov, 75);
  assert.equal(normalizeConfig({ grenadeAssistStrength: 999 }).grenadeAssistStrength, 100);
  for (const mode of ['off', 'preview', 'assist', 'lock']) assert.equal(normalizeConfig({ grenadeAimMode: mode }).grenadeAimMode, mode);
  assert.equal(normalizeConfig({ grenadeAimMode: 'automatic' }).grenadeAimMode, 'off');
  assert.equal(normalizeConfig({ grenadeAimActivation: 'equip' }).grenadeAimActivation, 'equip');
  assert.equal(normalizeConfig({ grenadeAimActivation: 'other' }).grenadeAimActivation, 'hold');
});
