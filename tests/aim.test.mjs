import test from 'node:test';
import assert from 'node:assert/strict';
import { AimController, SnapshotTracker, angleDelta, predictShot, weaponProfile } from '../src/aim.mjs';
import { discoverInputTimeout, discoverSourceFields, discoverUpdateReceiver, NetworkTiming } from '../src/aim-adapters.mjs';
import { clippedMuzzle, shotLayer } from '../src/aim-geometry.mjs';
import { NativeNames } from '../src/native-names.mjs';
import { DEFAULTS, normalizeConfig } from '../src/menu.mjs';

const defs = { gun: { type: 'gun', bulletType: 'b', ammo: '9mm', barrelLength: 2, barrelOffset: .3 }, b: { type: 'bullet', speed: 100, distance: 200, variance: .1 } };
const profile = weaponProfile(defs, 'gun');
const angle = v => Math.atan2(v.y, v.x);

test('Lock converges over time with unchanged physical intent at 30/60/144Hz; no fixed blend floor', () => {
  for (const hz of [30, 60, 144]) {
    const c = new AimController(), target = {}, errors = [];
    for (let i = 0; i < hz; i++) errors.push(Math.abs(Math.PI / 2 - angle(c.step({ x: 1, y: 0 }, { x: 0, y: 1 }, { mode: 'lock', smooth: 50, target, now: i * 1000 / hz }))));
    assert.ok(errors.at(-1) < .001); assert.ok(errors.every((e, i) => !i || e <= errors[i - 1]));
    c.reset(); assert.equal(c.time, null);
  }
});

test('Assist is monotonic, strength zero is native and moving intent escapes without controller memory', () => {
  const c = new AimController(); let last = -1;
  for (const strength of [0, 10, 35, 70, 100]) {
    const a = angle(c.step({ x: 1, y: 0 }, { x: 0, y: 1 }, { mode: 'assist', strength }));
    assert.ok(a >= last); if (!strength) assert.equal(a, 0); last = a;
  }
  const escaped = c.step({ x: 0, y: -1 }, { x: 1, y: 0 }, { mode: 'assist', strength: 35 });
  assert.ok(escaped.y < -.8); assert.equal(c.time, null);
});

test('Snapshot fit is stable between observations and recovers on stops/turns; quantization bounded', () => {
  const t = new SnapshotTracker(), p = { __id: 1 };
  for (let i = 0; i < 10; i++) t.observe(p, { x: i * .36, y: 0 }, i * 30);
  assert.ok(Math.abs(t.estimate(p, 280).vx - 12) < 1e-7);
  for (let now = 271; now < 299; now++) assert.equal(t.estimate(p, now).vx, t.estimate(p, 280).vx);
  t.observe(p, { x: 3.24, y: 0 }, 300); assert.ok(Math.abs(t.estimate(p, 300).vx) < .01);
  t.observe(p, { x: 2.88, y: 0 }, 330); assert.ok(t.estimate(p, 330).vx < -11.9);
  t.observe(p, { x: 2.88, y: .36 }, 360); assert.ok(Math.abs(t.estimate(p, 360).vx) < 1e-7); assert.ok(t.estimate(p, 360).vy > 11.9);
});

test('Tracker invalidates on gaps/teleports/layer/identity changes; delete and same-ID reuse cannot leak velocity', () => {
  const t = new SnapshotTracker(), p = { __id: 1 };
  t.observe(p, { x: 0, y: 0 }, 0, 0); t.observe(p, { x: .3, y: 0 }, 30, 0);
  assert.equal(t.estimate(p, 300), null);
  t.observe(p, { x: .6, y: 0 }, 60, 1); assert.equal(t.estimate(p, 60).vx, 0);
  p.__id = 2; assert.equal(t.estimate(p, 61), null);
  t.observe(p, { x: .9, y: 0 }, 90); assert.equal(t.estimate(p, 90).vx, 0);
  t.observe(p, { x: 80, y: 0 }, 120); assert.equal(t.estimate(p, 120).vx, 0);
  t.forget(p); assert.equal(t.estimate(p, 121), null);
  assert.equal(t.estimate({ __id: 2 }, 121), null);
});

test('Profiles follow actual bullet variance/perk multipliers, unknown weapon fails, dual hand is explicitly approximate', () => {
  assert.equal(profile.speed, 110.00000000000001);
  const p = weaponProfile(defs, 'gun', ['bonus_9mm', 'high_velocity', 'bonus_assault'].map(type => ({ type })));
  assert.ok(Math.abs(p.speed - 100 * 1.1 * 1.2 * 1.4 * 1.1) < 1e-9);
  assert.equal(p.range, 200 * 1.2 * 1.3 * 1.1 - 1); assert.equal(weaponProfile(defs, 'unknown'), null);
  const dual = weaponProfile({ ...defs, gun: { ...defs.gun, isDual: true, dualOffset: .8 } }, 'gun');
  assert.equal(dual.offset, 0); assert.equal(dual.approximate, true);
});

test('Solver includes muzzle lateral offset and does not clamp flight time to prediction trust horizon', () => {
  const target = { x: 45, y: 20 }, track = { pos: target, vx: 4, vy: 7, age: .02, error: 0 };
  const s = predictShot({ origin: { x: 0, y: 0 }, target, track, profile, latency: .04 });
  assert.equal(s.state, 'predicted');
  const impact = { x: s.muzzle.x + s.dir.x * profile.speed * s.time, y: s.muzzle.y + s.dir.y * profile.speed * s.time };
  assert.ok(Math.hypot(impact.x - s.world.x, impact.y - s.world.y) < .02);
  assert.ok(Math.hypot(s.world.x - (target.x + 4 * (.06 + s.time)), s.world.y - (target.y + 7 * (.06 + s.time))) < 1e-8);
  const slow = predictShot({ origin: { x: 0, y: 0 }, target: { x: 80, y: 0 }, profile: { ...profile, speed: 40 } });
  assert.ok(slow.time > 1.5 && slow.dir);
  assert.ok(Math.abs((s.mouseLen - profile.barrel) * profile.variance - Math.hypot(s.world.x - s.muzzle.x, s.world.y - s.muzzle.y)) < 1e-9, 'toMouseHit distance inverts source clipDistance variance');
  assert.equal(predictShot({ origin: { x: 0, y: 0 }, target, profile: { ...profile, range: 1 } }).state, 'out-of-range-or-horizon');
  assert.equal(predictShot({ origin: { x: 0, y: 0 }, target, track: { ...track, error: 10 }, profile }).state, 'uncertain');
});

test('Stair aim-layer uses source cardinal direction and real collision radius, not spoofed render layer', () => {
  const structures = [{ active: true, stairs: [{ collision: { min: { x: -1, y: -1 }, max: { x: 1, y: 1 } }, downDir: { x: -1, y: 0 } }] }];
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 1, y: 0 }, 0, 1, structures), 2);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: -1, y: 0 }, 0, 1, structures), 3);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 0, y: 1 }, 0, 1, structures), 0);
  assert.equal(shotLayer({ x: 10, y: 0 }, { x: -1, y: 0 }, 0, 1, structures), 0);
});

test('Muzzle clips against eligible bullet-height obstacles; below-height/dead/other floor do not clip', () => {
  const obstacle = { active: true, collidable: true, height: 1, layer: 0, collider: { type: 1, min: { x: 1, y: -1 }, max: { x: 1.5, y: 1 } } };
  const start = { x: 0, y: 0 }, dir = { x: 1, y: 0 };
  assert.ok(Math.abs(clippedMuzzle(start, dir, profile, [obstacle], 0, 0).x - .89) < 1e-9);
  for (const change of [{ dead: true }, { layer: 1 }, { height: .1 }]) assert.equal(clippedMuzzle(start, dir, profile, [{ ...obstacle, ...change }], 0, 0).x, 2);
});

test('AST adapters infer contracts by dataflow and reject ambiguous native schedulers', () => {
  const g = { tick(dt) { this.a -= dt; if (changed || this.a < 0) this.a = 1; }, receiver(msg) { for (const x of msg.fullObjects) {} for (const x of msg.partObjects) {} for (const x of msg.delObjIds) {} this.active = msg.activePlayerData; } };
  assert.equal(discoverInputTimeout(g), 'a'); assert.equal(discoverUpdateReceiver(g), 'receiver');
  g.other = function (dt) { this.b -= dt; if (this.b < 0) this.b = 1; }; assert.equal(discoverInputTimeout(g), null);
  const p = { net: {}, apply(data) { this.net.p = { x: data.pos.x, y: data.pos.y }; this.net.l = data.layer; this.net.s = data.scale; this.net.perks = data.perks; } };
  // Actual source uses v2.copy(data.pos), not pos.x/y expressions.
  p.apply = function (data) { this.net.p = copy(data.pos); this.net.l = data.layer; this.net.s = data.scale; this.net.perks = data.perks; };
  assert.deepEqual(discoverSourceFields(p, { netKey: 'net' }), { pos: 'p', layer: 'l', scale: 's', perks: 'perks' });
});

test('ACK timing is local bounded RTT/2, duplicate ACK cannot be counted twice', () => {
  const t = new NetworkTiming(); t.sent({ seq: 4 }, 1000); t.sent({ seq: 4 }, 1020); t.received({ ack: 3 }, 1030);
  assert.equal(t.rtt, null); t.received({ ack: 4 }, 1080); assert.equal(t.transit(), .04);
  t.received({ ack: 4 }, 1300); assert.equal(t.rtt, 80); t.reset(); assert.equal(t.transit(), 0);
});

test('Native TextStyle cyan is replaced not multiplied; unknown names untouched; restore obeys ownership and latest visibility', () => {
  const names = new NativeNames(), self = { __id: 1 }, enemy = { __id: 2, active: true, n: {}, nameText: { _style: { fill: 65535 }, _text: 'native', visible: false } }, ally = { ...enemy, __id: 3, nameText: { style: { fill: 'cyan' }, visible: true } }, unknown = { ...enemy, __id: 4, nameText: { style: { fill: 'cyan' }, visible: false } };
  const m = { active: self, schema: { netKey: 'n', deadKey: 'dead' }, barn: { teamInfo: { 1: { playerIds: [1, 3] }, 2: { playerIds: [2] } } } };
  names.sync(m, [self, enemy, ally, unknown], { ...DEFAULTS, esp: true });
  assert.equal(enemy.nameText._style.fill, '#ff6262'); assert.equal(ally.nameText.style.fill, '#56b6ff');
  assert.equal(enemy.nameText._text, 'native'); assert.equal(unknown.nameText.visible, false); assert.equal(enemy.nameText.visible, true);
  enemy.nameText.visible = false; names.sync(m, [self, enemy, ally, unknown], { ...DEFAULTS, esp: true });
  assert.equal(enemy.nameText._style.fill, '#ff6262');
  ally.nameText.style.fill = 'later-writer'; names.clear();
  assert.equal(enemy.nameText._style.fill, 65535); assert.equal(enemy.nameText.visible, false); assert.equal(ally.nameText.style.fill, 'later-writer');
});

test('Legacy migration removes clutter and exclusive Off cannot accidentally enable aim', () => {
  const c = normalizeConfig({ aim: true, esp: true, espLegend: true, espLabels: true, lines: true, showDot: true });
  assert.equal(c.aimMode, 'lock'); assert.equal(c.aim, true); assert.equal(c.lines, false); assert.equal(c.showDot, false); assert.equal(c.espLegend, false); assert.equal(c.espLabels, false);
  assert.equal(normalizeConfig({ version: 2, aim: true, aimMode: 'off' }).aim, false);
  assert.equal(normalizeConfig({ aim: false }).aim, false);
});

test('Slope uncertainty reduces flight lead explicitly, without clipping physical TOF; burst of coalesced samples stays finite', () => {
  const target = { x: 50, y: 0 }, origin = { x: 0, y: 0 };
  const shot = predictShot({ origin, target, track: { pos: target, vx: 0, vy: 10, age: 0, error: .01, velocityError: 20 }, profile });
  assert.equal(shot.state, 'reduced-lead-uncertainty'); assert.ok(shot.confidence > 0 && shot.confidence < 1);
  assert.ok(Math.abs(Math.hypot(shot.world.x - shot.muzzle.x, shot.world.y - shot.muzzle.y) / profile.speed - shot.time) < .001);
  const t = new SnapshotTracker(), p = { __id: 1 };
  for (let i = 0; i < 5; i++) t.observe(p, { x: i * .3, y: 0 }, i * 30);
  for (let i = 0; i < 12; i++) t.observe(p, { x: 1.5 + i * .3, y: 0 }, 400 + i * .1);
  const state = t.estimate(p, 402); assert.ok(Number.isFinite(state.vx)); assert.ok(Math.abs(state.vx) <= 80); assert.ok(state.samples.length <= 6);
});

test('production logical/comma scheduler and reversed zero comparison retain timeout discovery', async () => {
  const { transformSync } = await import('esbuild');
  const vm = await import('node:vm');
  const code = transformSync('globalThis.g={tick(dt){this.timer-=dt;if(diff||this.timer<0){this.send();this.timer=1;this.prev=msg}}}', { minify: true }).code;
  assert.ok(!code.includes('if('), 'Exercise the logical-expression shape actually emitted by minification');
  const context = vm.createContext({}); vm.runInContext(code, context);
  assert.equal(discoverInputTimeout(context.g), 'timer');
  const explicit = { tick(dt) { this.clock = this.clock - dt; (changed || 0 > this.clock) && (this.clock = 1); } };
  assert.equal(discoverInputTimeout(explicit), 'clock');
  explicit.unrelated = function (dt) { this.counter -= dt; if (this.counter < 0) this.counter = 1; };
  assert.equal(discoverInputTimeout(explicit), null, 'Ambiguity still fails closed');
});

test('ESP ignores obsolete nametags flag and does not require aim schema/camera', () => {
  const names = new NativeNames(), self = { __id: 1 }, enemy = { __id: 2, active: true, nameText: { visible: false, _style: { fill: 65535 }, _text: 'unchanged' } };
  const mapping = { active: self, barn: { teamInfo: { 1: { playerIds: [1] }, 2: { playerIds: [2] } } } };
  const config = normalizeConfig({ version: 2, esp: true, nametags: false });
  assert.equal(config.nametags, true);
  names.sync(mapping, [self, enemy], { ...config, nametags: false });
  assert.equal(enemy.nameText.visible, true); assert.equal(enemy.nameText._style.fill, '#ff6262');
  assert.equal(names.stats.state, 'native-names-active'); assert.equal(names.stats.colored, 1);
  assert.equal(enemy.nameText._text, 'unchanged');
  names.clear(); assert.equal(enemy.nameText.visible, false); assert.equal(enemy.nameText._style.fill, 65535);
});

test('ESP supports actual PIXI7 Container visibility and inherited TextStyle API without reconstructing styles', async () => {
  const { Container } = await import('@pixi/display');
  const { TextStyle } = await import('@pixi/text');
  class NativeText extends Container {
    constructor() { super(); this._style = new TextStyle({ fill: 65535 }); this._text = 'native'; this.visible = false; }
    get style() { return this._style; }
  }
  const text = new NativeText(), style = text.style, nativeFill = style.fill, names = new NativeNames();
  const self = { __id: 1 }, enemy = { __id: 2, active: true, nameText: text };
  const m = { active: self, barn: { teamInfo: { 1: { playerIds: [1] }, 2: { playerIds: [2] } } } };
  names.sync(m, [enemy], { ...DEFAULTS, esp: true });
  assert.equal(text.visible, true); assert.equal(text.style.fill, '#ff6262'); const styleID = style.styleID;
  text.visible = false; names.sync(m, [enemy], { ...DEFAULTS, esp: true });
  assert.equal(text.visible, true); assert.equal(text.style, style); assert.equal(style.styleID, styleID);
  names.clear(); assert.equal(text.style.fill, nativeFill); assert.equal(text.visible, false);
  text.destroy();
});
