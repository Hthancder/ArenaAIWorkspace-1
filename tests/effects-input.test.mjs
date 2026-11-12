import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { transformSync } from 'esbuild';
import { discoverSmokeSources, smokeAlpha, smokeParticles } from '../src/effects.mjs';
import { Overrides, equipInput, meleeReach } from '../src/features.mjs';
import { RepeatFire, repeatFirePolicy } from '../src/repeat-fire.mjs';
import { discoverMapRedraw, highlightMinimap, MapHighlights, mapHighlightCompatible } from '../src/map-highlights.mjs';
import { MovementSmoother, rayHit, throwPreview, traceShot } from '../src/previews.mjs';
import { WeaponSwitch } from '../src/weapon-switch.mjs';

const fists = { type: 'melee', autoAttack: false, attack: { cooldownTime: .25, offset: { x: 1.35, y: 0 }, rad: .9 } };
const single = { type: 'gun', fireMode: 'single', fireDelay: .1 };
const particle = () => ({ active: true, fadeTicker: 0, fadeDuration: 2, posTarget: { x: 0, y: 0 }, radTarget: 2, tint: 0xeeeeee, sprite: { alpha: .9, visible: true } });
const source = `class SmokeBarn { constructor() { this.m_pool=[];this.decoy=[]; } update() { for(let i=0;i<this.m_pool.length;i++){const p=this.m_pool[i]; if(p.active){p.sprite.alpha=1-p.fadeTicker/p.fadeDuration;p.sprite.tint=p.tint;p.sprite.visible=true;p.rad=p.radTarget;p.pos=p.posTarget;}} } } globalThis.barn=new SmokeBarn();`;
for (const minify of [false, true]) test(`smoke AST discovers an empty validated pool, minified=${minify}`, () => {
  const context = vm.createContext({}); vm.runInContext(transformSync(source, { minify, mangleProps: /^m_/, target: 'es2022' }).code, context);
  const sources = discoverSmokeSources({ renamedBarn: context.barn }); assert.equal(sources.length, 1);
  const p = particle(); context.barn[sources[0].key].push(p); assert.deepEqual(smokeParticles(sources), [p]);
  p.active = false; assert.equal(smokeParticles(sources).length, 0); p.active = true; p.sprite._destroyed = true;
  assert.equal(smokeParticles(sources).length, 0);
});
test('smoke pool rejects a data-only decoy and ambiguous update arrays', () => {
  assert.deepEqual(discoverSmokeSources({ decoy: { particles: [particle()] } }), []);
  const c = vm.createContext({}); vm.runInContext(source.replace('globalThis.barn=', 'globalThis.barn='), c);
  c.barn.second = []; c.barn.secondUpdate = function () { for (let i = 0; i < this.second.length; i++) { const p = this.second[i]; p.sprite.alpha = p.fadeTicker / p.fadeDuration; p.sprite.tint = p.tint; p.sprite.visible = true; p.pos = p.posTarget; p.rad = p.radTarget; } };
  assert.deepEqual(discoverSmokeSources({ barn: c.barn }), []);
});
test('legacy smoke opacity cap preserves native fade and restores latest PIXI own alpha', () => {
  assert.equal(smokeAlpha(.9, 50), .05); assert.equal(smokeAlpha(.02, 50), .02); assert.equal(smokeAlpha(.9, 0), 0); assert.equal(smokeAlpha(.9, 100), .1);
  const sprite = { alpha: .9 }, overrides = new Overrides();
  assert.ok(overrides.set(sprite, 'alpha', value => smokeAlpha(value, 50))); sprite.alpha = .8; assert.equal(sprite.alpha, .05);
  sprite.alpha = .01; assert.equal(sprite.alpha, .01); overrides.clear(); assert.equal(sprite.alpha, .01);
  assert.equal(Object.getOwnPropertyDescriptor(sprite, 'alpha').writable, true);
});
test('overrides reject unsupported descriptors and leave later writers alone', () => {
  const owner = {}; Object.defineProperty(owner, 'alpha', { value: .9, writable: true, configurable: false });
  const o = new Overrides(); assert.equal(o.set(owner, 'alpha', () => 0), false);
  const p = particle(); o.set(p, 'tint', () => 0); Object.defineProperty(p, 'tint', { configurable: true, writable: true, value: 123 }); o.clear(); assert.equal(p.tint, 123);
});
test('repeat policy includes non-auto melee and never repeats throwable/auto/burst', () => {
  assert.equal(repeatFirePolicy(fists).state, 'melee-repeat'); assert.equal(repeatFirePolicy(single).interval, 100);
  for (const def of [{ type: 'throwable' }, { ...single, fireMode: 'burst' }, { ...single, fireMode: 'auto' }, { ...fists, autoAttack: true }, { type: 'melee' }]) assert.equal(repeatFirePolicy(def).interval, null);
});
test('melee repeat stays frame-stable, bounded and resets on release/weapon change', () => {
  const repeat = new RepeatFire(), input = { weapon: 'fists', def: fists, held: true, enabled: true, paused: false, protocolMatches: true };
  assert.equal(repeat.sample({ ...input, frame: 0, now: 0 }), true); assert.equal(repeat.sample({ ...input, frame: 0, now: 40 }), true);
  assert.equal(repeat.sample({ ...input, frame: 1, now: 16 }), false); assert.equal(repeat.sample({ ...input, frame: 2, now: 50 }), true);
  assert.equal(repeat.sample({ ...input, frame: 3, now: 60, held: false }), false);
  assert.equal(repeat.sample({ ...input, frame: 4, now: 65 }), true);
  assert.equal(repeat.sample({ ...input, frame: 5, now: 66, paused: true }), false);
  assert.equal(repeat.sample({ ...input, frame: 6, now: 67, protocolMatches: false }), false);
  assert.equal(repeat.sample({ ...input, frame: 7, now: 68, weapon: 'knife' }), true);
});
test('melee reach comes from source attack dimensions and equip codes include melee', () => {
  assert.equal(meleeReach(fists), 3.25); assert.equal(meleeReach(single), null);
  assert.deepEqual([0, 1, 2, 3, -1, null].map(equipInput), [11, 12, 13, 14, null, null]);
});
const weapons = () => [{ type: 'a', ammo: 10 }, { type: 'b', ammo: 10 }, { type: 'fists', ammo: 0 }, { type: 'frag', ammo: 1 }];
const switchDefs = { a: single, b: { ...single, fireMode: 'burst' } };
test('weapon switch detects single and burst ammo changes without first-frame or release switching', () => {
  const manager = new WeaponSwitch(), ws = weapons(), input = { enabled: true, ready: true, definitions: switchDefs, held: true, oneGun: false, slot: 0, weapons: ws, now: 0 };
  assert.equal(manager.sample(input), null); ws[0].ammo--;
  assert.equal(manager.sample({ ...input, now: 10 }), 1);
  assert.equal(manager.sample({ ...input, slot: 1, now: 220 }), null); ws[1].ammo--;
  assert.equal(manager.sample({ ...input, slot: 1, now: 230 }), 0);
  ws[1].ammo--; assert.equal(manager.sample({ ...input, held: false, slot: 1, now: 500 }), null);
});
test('Use One Gun waits for observed equip before requesting return, cancels on release', () => {
  const manager = new WeaponSwitch(), ws = weapons(), input = { enabled: true, ready: true, definitions: switchDefs, held: true, oneGun: true, slot: 0, weapons: ws, now: 0 };
  manager.sample(input); ws[0].ammo--; assert.equal(manager.sample({ ...input, now: 10 }), 1);
  assert.equal(manager.sample({ ...input, now: 150 }), null, 'Do not assume equip succeeded');
  assert.equal(manager.sample({ ...input, slot: 1, now: 150 }), 0);
  manager.reset(); manager.sample(input); ws[0].ammo--; manager.sample({ ...input, now: 200 });
  assert.equal(manager.sample({ ...input, held: false, slot: 1, now: 400 }), null); assert.equal(manager.pending, null);
});
test('single gun cycles through melee when the other gun slot is empty', () => {
  const manager = new WeaponSwitch(), ws = weapons(); ws[1] = { type: '', ammo: 0 };
  const input = { enabled: true, ready: true, definitions: switchDefs, held: true, slot: 0, weapons: ws, now: 0 };
  manager.sample(input); ws[0].ammo--; assert.equal(manager.sample({ ...input, now: 10 }), 2);
  assert.equal(manager.sample({ ...input, slot: 2, now: 120 }), 0);
  manager.sample({ ...input, enabled: false }); assert.equal(manager.pending, null);
});
test('map highlight clones the shared shape array and preserves collider identity', () => {
  const raw = { obj: { type: 'stone_02' }, zIdx: 1, shapes: [{ scale: 1, color: 123, collider: { type: 0 } }] };
  const changed = highlightMinimap(raw, { mapHighlights: true }); assert.equal(changed.zIdx, 999); assert.equal(changed.shapes[0].scale, 6);
  assert.equal(changed.shapes[0].collider, raw.shapes[0].collider); assert.equal(raw.shapes[0].color, 123);
  assert.equal(highlightMinimap(raw, { mapHighlights: false }), raw);
  raw.obj.type = 'tree_01'; raw.shapes[0].scale = 4;
  assert.equal(highlightMinimap(raw, { mapHighlights: true, smallerTrees: true }).shapes[0].scale, 1.8);
});
class MapFixture {
  constructor() { this.mapLoaded = true; this.last = []; this.calls = 0; this.shape = { color: 123, scale: 1, collider: { type: 0 } }; }
  getMinimapRender(obj) { return { obj, zIdx: 1, shapes: [this.shape] }; }
  renderMap(renderer, mode) { this.calls++; const records = [this.getMinimapRender({ type: 'stone_02' })]; records.sort((a, b) => a.zIdx - b.zIdx); this.last = records; }
}
class GameFixture { constructor(map) { this.m_map = map; this.m_renderer = { renderer: { render() {} } }; this.m_canvas = false; } draw() { this.m_map.renderMap(this.m_renderer.renderer, this.m_canvas); } }
test('map wrapper validates the native contract and redraws once per config change, restores on dispose', () => {
  const map = new MapFixture(), game = new GameFixture(map), config = { mapHighlights: true, smallerTrees: true };
  assert.ok(mapHighlightCompatible(map)); assert.ok(discoverMapRedraw(game, map));
  const original = map.getMinimapRender, manager = new MapHighlights(config, () => {});
  manager.sync(game, map); assert.equal(map.calls, 1); assert.equal(map.last[0].shapes[0].scale, 6);
  manager.sync(game, map); assert.equal(map.calls, 1);
  config.mapHighlights = false; manager.sync(game, map); assert.equal(map.calls, 2); assert.equal(map.last[0].shapes[0].scale, 1);
  config.mapHighlights = true; manager.sync(game, map); manager.dispose(); assert.equal(map.last[0].shapes[0].scale, 1); assert.equal(map.getMinimapRender, original);
});
test('ray clips circle/AABB, misses nonintersecting objects and handles origins inside a collider', () => {
  const box = { type: 1, min: { x: 3, y: -1 }, max: { x: 4, y: 1 } };
  assert.equal(rayHit({ x: 0, y: 0 }, { x: 1, y: 0 }, 10, box).distance, 3);
  assert.equal(rayHit({ x: 0, y: 2 }, { x: 1, y: 0 }, 10, box), null);
  assert.equal(rayHit({ x: 0, y: 0 }, { x: 1, y: 0 }, 10, { type: 0, pos: { x: 5, y: 0 }, rad: 1 }).distance, 4);
  assert.equal(rayHit({ x: 3.5, y: 0 }, { x: 1, y: 0 }, 10, box).distance, 0);
});
test('shot preview respects layers, low/dead obstacles and bounds reflections', () => {
  const wall = { active: true, dead: false, collidable: true, type: 'metal', height: 1, layer: 0, collider: { type: 1, min: { x: 3, y: -1 }, max: { x: 4, y: 1 } } };
  const start = { x: 0, y: 0 }, dir = { x: 1, y: 0 };
  assert.equal(traceShot(start, dir, 10, [wall], 0, {}).points.at(-1).x, 3);
  assert.ok(traceShot(start, dir, 10, [wall], 0, { metal: { reflectBullets: true } }, 3).points.at(-1).x < 0);
  assert.equal(traceShot(start, dir, 10, [{ ...wall, layer: 1 }, { ...wall, dead: true }, { ...wall, height: .1 }], 0, {}).points.at(-1).x, 10);
  assert.equal(traceShot(start, dir, 10, [{ ...wall, collider: { type: 9 } }], 0, {}).unsupported, 1);
});
test('throw preview uses bounded source-strength/physics and is explicitly nominal', () => {
  const def = { type: 'throwable', throwPhysics: { speed: 20, velZ: 5 } };
  const near = throwPreview(def, { x: 0, y: 0 }, { x: 1, y: 0 }, 9), far = throwPreview(def, { x: 0, y: 0 }, { x: 1, y: 0 }, 18);
  assert.ok(far.end.x > near.end.x); assert.ok(far.points.length <= 31); assert.equal(far.nominal, true);
  assert.deepEqual(throwPreview(def, { x: 0, y: 0 }, { x: 1, y: 0 }, 999), far);
  assert.equal(throwPreview(single, { x: 0, y: 0 }, { x: 1, y: 0 }, 18), null);
});
test('movement smoothing interpolates turns, never coasts and accepts reversal', () => {
  const smooth = new MovementSmoother();
  assert.deepEqual(smooth.sample({ moveRight: true }, 100, 0), { x: 1, y: 0 });
  const turn = smooth.sample({ moveUp: true }, 100, 16); assert.ok(turn.x > 0 && turn.y > 0); assert.ok(Math.abs(Math.hypot(turn.x, turn.y) - 1) < 1e-9);
  assert.equal(smooth.sample({}, 100, 32), null);
  assert.deepEqual(smooth.sample({ moveLeft: true }, 0, 48), { x: -1, y: 0 });
  assert.deepEqual(smooth.sample({ moveRight: true }, 100, 64), { x: 1, y: 0 });
});
