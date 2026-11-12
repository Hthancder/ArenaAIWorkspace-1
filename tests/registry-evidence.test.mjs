import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { transformSync } from 'esbuild';
import { discoverObjectRegistry } from '../src/core.mjs';
import { AimEvidence } from '../src/aim-evidence.mjs';

test('native get/delete table beats unrelated entity dictionaries, including empty native registry', () => {
  const creator = { table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } };
  const game = { owner: creator, cache: { table: { 7: { __id: 7, __type: 1 } } } };
  const result = discoverObjectRegistry(game);
  assert.equal(result.creator, creator); assert.equal(result.registryKey, 'table'); assert.equal(result.registryState, 'native-id-table');
});

test('registry dataflow withstands native m_* rename/minify and still rejects genuine ambiguity', () => {
  const code = transformSync('globalThis.g={m_creator:{m_ids:{},m_get(id){return this.m_ids[id]},m_delete(id){delete this.m_ids[id]}},m_decoy:{ids:{7:{__id:7,__type:1}}}}', { minify: true, mangleProps: /^m_/, mangleQuoted: true }).code;
  const context = vm.createContext({}); vm.runInContext(code, context);
  const result = discoverObjectRegistry(context.g); assert.equal(result.registryState, 'native-id-table');
  context.g.second = { table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } };
  assert.equal(discoverObjectRegistry(context.g).registryState, 'ambiguous-native-id-table');
  assert.equal(discoverObjectRegistry(context.g).creator, null);
});

test('shape fallback remains explicit and ambiguous fallback never chooses first table', () => {
  const game = { owner: { table: { 1: { __id: 1, __type: 1 } } } };
  assert.equal(discoverObjectRegistry(game).registryState, 'entity-table-fallback');
  game.other = { table: { 2: { __id: 2, __type: 2 } } };
  assert.equal(discoverObjectRegistry(game).registryState, 'ambiguous-entity-tables');
  let reads = 0; Object.defineProperty(game, 'evil', { get() { reads++; throw Error('unsafe'); } });
  discoverObjectRegistry(game); assert.equal(reads, 0);
});

test('last live attempt/correction survive death/menu and exported history is bounded and immutable', () => {
  const evidence = new AimEvidence(), controls = { mode: 'lock', wallcheckRequested: true, wallcheckAvailable: false };
  evidence.attempt('wallcheck-unavailable', controls, {}, 1000, true);
  evidence.attempt('dead', controls, {}, 1100, false);
  assert.equal(evidence.snapshot(1200).lastLiveAttempt.state, 'wallcheck-unavailable');
  const native = { toMouseDir: { x: 1, y: 0 }, shootStart: true, shootHold: true };
  evidence.sent(native, { ...native, toMouseDir: { x: 0, y: 1 } }, true, 1300, true);
  evidence.sent(native, native, false, 1400, false);
  let snapshot = evidence.snapshot(1500);
  assert.equal(snapshot.lastCorrection.correctionDegrees, 90); assert.equal(snapshot.lastCorrection.ageMs, 200);
  assert.equal(snapshot.lastGameplayForward.firePreserved, true); assert.equal(snapshot.correctedGameplayInputs, 1);
  assert.equal(snapshot.forwardedInputs, 2);
  snapshot.lastLiveAttempt.rejections.injected = 9; snapshot.lastCorrection.correctionDegrees = 0;
  snapshot = evidence.snapshot(1500); assert.equal(snapshot.lastLiveAttempt.rejections.injected, undefined); assert.equal(snapshot.lastCorrection.correctionDegrees, 90);
  for (let i = 0; i < 100; i++) evidence.attempt(String(i), controls, {}, 1500 + i, true);
  assert.equal(evidence.snapshot(1700).transitions.length, 12);
  const json = JSON.stringify(evidence.snapshot(1700));
  for (const field of ['toMouseDir', 'playerId', 'joinToken', 'pos', 'shootHold']) assert.ok(!json.includes(`"${field}"`));
  evidence.reset(); assert.equal(evidence.snapshot(1800).lastCorrection, null);
});
