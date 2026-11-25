import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { transformSync } from 'esbuild';
import { discoverObjectRegistry, patchMethod, Disposables } from '../src/core.mjs';
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

test('snapshot delObjIds disambiguates native tables without mistaking deletedPlayerIds', () => {
  const make = () => ({ table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } });
  const game = { world: make(), metadata: make(), receive(msg) {
    for (let i = 0; i < msg.delObjIds.length; i++) this.world.remove(msg.delObjIds[i]);
    for (let i = 0; i < msg.deletedPlayerIds.length; i++) this.metadata.remove(msg.deletedPlayerIds[i]);
    void msg.fullObjects; void msg.partObjects; void msg.activePlayerData;
  } };
  const result = discoverObjectRegistry(game);
  assert.equal(result.creator, game.world); assert.equal(result.registryState, 'snapshot-id-table');
  assert.deepEqual(result.registryEvidence, { nativeCandidates: 2, receiverCandidates: 1 });
  // Do not execute unknown code while identifying a role.
  assert.deepEqual(game.world.table, {});
});

test('duplicate references to one owner are not independent registry candidates', () => {
  const owner = { table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } };
  const result = discoverObjectRegistry({ first: owner, alias: owner });
  assert.equal(result.creator, owner); assert.equal(result.registryState, 'native-id-table');
  assert.equal(result.registryEvidence.nativeCandidates, 1);
});

test('snapshot registry selection withstands rename/minification and refuses two true anchors', () => {
  const source = `const make=()=>({m_table:{},m_get(id){return this.m_table[id]},m_remove(id){delete this.m_table[id]}});
    globalThis.g={m_world:make(),m_metadata:make(),m_receive(msg){
      for(let i=0;i<msg.delObjIds.length;i++)this.m_world.m_remove(msg.delObjIds[i]);
      for(let i=0;i<msg.deletedPlayerIds.length;i++)this.m_metadata.m_remove(msg.deletedPlayerIds[i]);
      globalThis.refs=[msg.fullObjects,msg.partObjects,msg.activePlayerData];
    }};g.m_alias=g.m_world;`;
  for (const minify of [false, true]) {
    const code = transformSync(source, { minify, ...(minify ? { mangleProps: /^m_/, mangleQuoted: true } : {}) }).code;
    const context = vm.createContext({}); vm.runInContext(code, context);
    const result = discoverObjectRegistry(context.g);
    assert.equal(result.registryState, 'snapshot-id-table'); assert.equal(result.registryEvidence.nativeCandidates, 2);
  }
  const make = () => ({ table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } });
  const game = { a: make(), b: make(), receive(msg) {
    this.a.remove(msg.delObjIds[0]); this.b.remove(msg.delObjIds[0]);
    void msg.fullObjects; void msg.partObjects; void msg.activePlayerData;
  } };
  assert.equal(discoverObjectRegistry(game).registryState, 'ambiguous-snapshot-id-table');
  assert.equal(discoverObjectRegistry(game).creator, null);
});

test('a non-snapshot method using delObjIds does not override registry ambiguity', () => {
  const make = () => ({ table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } });
  const game = { a: make(), b: make(), fake(msg) { this.a.remove(msg.delObjIds[0]); } };
  assert.equal(discoverObjectRegistry(game).registryState, 'ambiguous-native-id-table');
});


test('owned receiver wrapper retains source role during remapping and cleanup', () => {
  const make = () => ({ table: {}, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } });
  const game = { a: make(), b: make(), receive(msg) {
    this.a.remove(msg.delObjIds[0]);
    void msg.fullObjects; void msg.partObjects; void msg.activePlayerData;
  } };
  const original = game.receive, bag = new Disposables();
  assert.ok(patchMethod(game, 'receive', original => function (msg) { return Reflect.apply(original, this, arguments); }, bag));
  assert.equal(discoverObjectRegistry(game).registryState, 'snapshot-id-table');
  assert.equal(discoverObjectRegistry(game).creator, game.a);
  bag.clear(); assert.equal(game.receive, original);
  assert.equal(discoverObjectRegistry(game).registryState, 'snapshot-id-table');
  // A public field on an unknown wrapper must never be treated as trusted source.
  game.receive = function () {}; game.receive.original = original;
  assert.equal(discoverObjectRegistry(game).registryState, 'ambiguous-native-id-table');
});
