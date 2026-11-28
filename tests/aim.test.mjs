import test from 'node:test';
import assert from 'node:assert/strict';
import { AimController, SnapshotTracker, angleDelta, predictShot, weaponProfile, smoothDamp } from '../src/aim.mjs';
import { discoverInputTimeout, discoverSourceFields, discoverUpdateReceiver, NetworkTiming } from '../src/aim-adapters.mjs';
import { clippedMuzzle, shotLayer, pathToTarget, pathAlongAim } from '../src/aim-geometry.mjs';
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
    c.reset(); assert.equal(c.time, null); assert.equal(c.angularVelocity, 0);
  }
});

test('critically damped angular SmoothDamp eases in/out without overshoot and honors profiles', () => {
  const target = {};
  const steps = profile => {
    const c = new AimController(); let previous = Math.PI / 2, maximum = 0;
    for (let i = 0; i < 60; i++) {
      const now = i * 1000 / 60;
      const out = c.step({ x: 1, y: 0 }, { x: 0, y: 1 }, { mode: 'lock', smooth: 50, profile, target, now, humanLike: true });
      const error = Math.abs(Math.PI / 2 - angle(out));
      maximum = Math.max(maximum, Math.abs(error - previous)); previous = error;
    }
    return { error: previous, maximum };
  };
  const responsive = steps('responsive'), natural = steps('natural'), precise = steps('precise');
  assert.ok(responsive.error < natural.error); assert.ok(natural.error < precise.error);
  assert.ok([responsive, natural, precise].every(r => Number.isFinite(r.error) && r.error >= 0));
  let velocity = 0; const solved = smoothDamp(0, 1.2, velocity, .18, 9, 1 / 60);
  assert.ok(Number.isFinite(solved.value)); assert.ok(solved.velocity >= 0);
  const stay = smoothDamp(1.2, 1.2, 0, .1, 9, 1 / 60); assert.equal(stay.value, 1.2); assert.equal(stay.velocity, 0);
  const carried = smoothDamp(1.2, 1.2, 5, .1, 9, 1 / 60); assert.ok(Number.isFinite(carried.value)); assert.ok(Number.isFinite(carried.velocity));
});

test('responsive Lock brakes observed reversals without changing Assist or other profiles', () => {
  const target = {}, native = { x: 1, y: 0 }, wanted = { x: Math.cos(-.2), y: Math.sin(-.2) };
  const run = profile => {
    const c = new AimController(); Object.assign(c, { angle: .3, angularVelocity: 1, time: 0, target, mode: 'lock' });
    const out = c.step(native, wanted, { mode: 'lock', smooth: 50, profile, target, now: 1000 / 60, humanLike: true });
    return { c, out };
  };
  const base = (.065 + .5 * .24) * .78;
  const expected = smoothDamp(.3, -.2, 1, base * .7, 12, 1 / 60);
  const responsive = run('responsive');
  assert.ok(Math.abs(angle(responsive.out) - expected.value) < 1e-12);
  assert.ok(responsive.c.angularVelocity < smoothDamp(.3, -.2, 1, base, 12, 1 / 60).velocity);
  const natural = run('natural'), unchanged = smoothDamp(.3, -.2, 1, .065 + .5 * .24, 8.5, 1 / 60);
  assert.ok(Math.abs(angle(natural.out) - unchanged.value) < 1e-12);
  const direct = new AimController().step(native, wanted, { mode: 'lock', smooth: 50, profile: 'responsive', target, now: 0, humanLike: false });
  assert.ok(Math.abs(angle(direct) + .2) < 1e-12);
});

test('Duality-inspired cubic profile converges at 30/60/144 Hz and is isolated from instant Lock and Assist', () => {
  for (const hz of [30, 60, 144]) {
    const c = new AimController(), target = {}, errors = [];
    for (let i = 0; i < hz; i++) {
      const out = c.step({ x: 1, y: 0 }, { x: 0, y: 1 }, { mode: 'lock', humanLike: true, smooth: 50, profile: 'duality', cursorRadius: 120, targetRadius: 120, target, now: i * 1000 / hz });
      errors.push(Math.abs(Math.PI / 2 - angle(out)));
    }
    assert.ok(errors.at(-1) < .001); assert.ok(errors.every((e, i) => !i || e <= errors[i - 1] + 1e-9));
    const direct = c.step({ x: 1, y: 0 }, { x: 0, y: -1 }, { mode: 'lock', humanLike: false, smooth: 50, profile: 'duality', target, now: 1100 });
    assert.ok(Math.abs(angle(direct) + Math.PI / 2) < 1e-9);
    const assist = c.step({ x: 1, y: 0 }, { x: 0, y: 1 }, { mode: 'assist', strength: 35, profile: 'duality' });
    assert.ok(Math.abs(angle(assist) - Math.PI / 2 * .35) < 1e-9);
  }
  assert.equal(normalizeConfig({ smoothProfile: 'duality' }).smoothProfile, 'duality');
  const c = new AimController(), target = {}, angles = [];
  for (let i = 0; i <= 60; i++) angles.push(angle(c.step({x:1,y:0},{x:-1,y:0}, { mode:'lock', humanLike:true, smooth:50, profile:'duality', target, now:i*10 })));
  for (let i=1;i<angles.length;i++) assert.ok(Math.abs(angleDelta(angles[i-1],angles[i])) < .5, 'opposite direction avoids screen-center singularity');
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

test('Tracker coalesces equal-time ordered snapshots without discarding history or dividing by zero', () => {
  const tracker = new SnapshotTracker(), player = { __id: 1 };
  tracker.observe(player, { x: 0, y: 0 }, 0, 0);
  tracker.observe(player, { x: .3, y: 0 }, 30, 0);
  tracker.observe(player, { x: .59, y: 0 }, 60, 0);
  tracker.observe(player, { x: .6, y: 0 }, 60, 0);
  tracker.observe(player, { x: .61, y: 0 }, 60, 0);
  const estimate = tracker.estimate(player, 60);
  assert.ok(estimate.samples.length >= 2);
  assert.ok(Number.isFinite(estimate.vx) && estimate.vx > 9 && estimate.vx < 11);
  assert.equal(estimate.motion.filter(s => s.t === 60).length, 1);
  assert.equal(estimate.pos.x, .61);
  assert.equal(tracker.estimate(player, 59), null);
  assert.equal(tracker.estimate(player, NaN), null);
  tracker.observe(player, { x: 5, y: 0 }, 59, 0);
  assert.equal(tracker.estimate(player, 59).vx, 0, 'clock rollback resets history');
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

test('Solver reconciles flight time with its final barrel direction and labels unresolved close shots', () => {
  const origin = { x: 0, y: 0 }, target = { x: -1.695948062667297, y: 1.5536280664094095 };
  const track = { pos: target, vx: -10, vy: -13, age: .03, error: 0, velocityError: 0 };
  const model = { offset: -.8, barrel: 1.1, speed: 41, range: 1000, variance: 1 };
  const shot = predictShot({ origin, target, track, profile: model });
  assert.ok(shot.dir);
  const impact = { x: shot.muzzle.x + shot.dir.x * model.speed * shot.time, y: shot.muzzle.y + shot.dir.y * model.speed * shot.time };
  assert.ok(Math.hypot(impact.x - shot.world.x, impact.y - shot.world.y) <= .02);
  assert.ok(Math.hypot(shot.world.x - target.x - track.vx * (track.age + shot.time), shot.world.y - target.y - track.vy * (track.age + shot.time)) < 1e-8);
  const close = predictShot({ origin, target: { x: 1, y: 0 }, profile: { ...model, offset: 0, barrel: 2 } });
  assert.equal(close.state, 'unresolved-muzzle-solution'); assert.equal(close.approximate, true); assert.ok(close.dir);
});

test('Stair aim-layer uses source cardinal direction and real collision radius, not spoofed render layer', () => {
  const structures = [{ active: true, stairs: [{ collision: { min: { x: -1, y: -1 }, max: { x: 1, y: 1 } }, downDir: { x: -1, y: 0 } }] }];
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 1, y: 0 }, 0, 1, structures), 2);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: -1, y: 0 }, 0, 1, structures), 3);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 0, y: 1 }, 0, 1, structures), 0);
  assert.equal(shotLayer({ x: 10, y: 0 }, { x: -1, y: 0 }, 0, 1, structures), 0);
  assert.equal(shotLayer({ x: 2, y: 0 }, { x: -1, y: 0 }, 0, 1, structures), 0, 'external tangency is not collision');
  assert.equal(shotLayer({ x: 1.999, y: 0 }, { x: -1, y: 0 }, 0, 1, structures), 3);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 1, y: 0 }, 0, 1, Array(257).fill(structures[0])), null);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 1, y: 0 }, 0, 1, [{ active: true, stairs: Array(33).fill(structures[0].stairs[0]) }]), null);
  assert.equal(shotLayer({ x: 0, y: 0 }, { x: 1, y: 0 }, 0, 1, [{ active: true, stairs: [{ collision: null }] }]), null);
});

test('Muzzle clips against eligible bullet-height obstacles; below-height/dead/other floor do not clip', () => {
  const obstacle = { active: true, collidable: true, height: 1, layer: 0, collider: { type: 1, min: { x: 1, y: -1 }, max: { x: 1.5, y: 1 } } };
  const start = { x: 0, y: 0 }, dir = { x: 1, y: 0 };
  assert.ok(Math.abs(clippedMuzzle(start, dir, profile, [obstacle], 0, 0).x - .89) < 1e-9);
  for (const change of [{ dead: true }, { layer: 1 }, { height: .1 }]) assert.equal(clippedMuzzle(start, dir, profile, [{ ...obstacle, ...change }], 0, 0).x, 2);
});

test('cross-layer muzzle overlap uses the source base radius, independent of player scale', () => {
  const gun = { ...profile, offset: 0 }, origin = { x: 0, y: 0 }, dir = { x: 1, y: 0 };
  const wall = { active: true, collidable: true, dead: false, layer: 1, height: 1,
    collider: { type: 0, pos: { x: 1.5, y: 0 }, rad: .2 } };
  assert.ok(Math.abs(clippedMuzzle(origin, dir, gun, [wall], 1, 0, 2).x - 1.19) < 1e-9, 'large scale must not wrongly ignore wall');
  wall.collider.pos.x = .8;
  assert.equal(clippedMuzzle(origin, dir, gun, [wall], 1, 0, .3).x, 2, 'small scale must not clip a source-ignored wall');
  assert.ok(Math.abs(clippedMuzzle(origin, dir, gun, [wall], 1, 1).x - .49) < 1e-9, 'same-layer clip still applies');
  wall.collider = { type: 0, pos: { x: .1, y: 0 }, rad: .5 };
  assert.equal(clippedMuzzle(origin, dir, gun, [wall], 1, 1).x, 2, 'starting inside a circle intersects its exit; outward normal does not clip');
  wall.collider = { type: 0, pos: { x: 2.205, y: 0 }, rad: .2 };
  assert.ok(Math.abs(clippedMuzzle(origin, dir, gun, [wall], 1, 1).x - 1.895) < 1e-9, 'biased plane just beyond muzzle can still clip');
});

test('muzzle clipping reevaluates each obstacle against the previously shifted endpoint', () => {
  const dir = { x: -0.4751493527921102, y: 0.8799051611061495 };
  const make = (x, y, rad) => ({ active: true, collidable: true, dead: false, layer: 0, height: 1, collider: { type: 0, pos: { x, y }, rad } });
  const obstacles = [make(.024755407784434684, .1009292699472144, .36540001749526707),
    make(-.14120266565043407, .4839605890609974, .11964199682697654),
    make(-.3942117631835551, 1.2382072992418747, .148494633869268)];
  const muzzle = clippedMuzzle({ x: 0, y: 0 }, dir, { offset: 0, barrel: 2 }, obstacles, 0, 0);
  assert.ok(Math.hypot(muzzle.x - -.1491319449104743, muzzle.y - .2761699394967654) < 1e-8);
});

test('ambiguous muzzle inside an AABB relinquishes prediction rather than fabricating an origin', () => {
  const wall = { active: true, collidable: true, dead: false, layer: 0, height: 1,
    collider: { type: 1, min: { x: -.4, y: -.5 }, max: { x: .4, y: .5 } } };
  const origin = { x: 0, y: 0 }, dir = { x: 1, y: 0 }, gun = { ...profile, offset: 0 };
  assert.equal(clippedMuzzle(origin, dir, gun, [wall], 0, 0), null);
  const shot = predictShot({ origin, target: { x: 10, y: 0 }, profile: gun,
    muzzleFor: (pos, direction, p) => clippedMuzzle(pos, direction, p, [wall], 0, 0) });
  assert.deepEqual(shot, { state: 'uncertain-muzzle' });
  assert.equal(clippedMuzzle(origin, dir, gun, [wall], 0, 1).x, 2, 'cross-layer source skip is checked first');
});

test('AST adapters infer contracts by dataflow and reject ambiguous native schedulers', () => {
  const g = { tick(dt) { this.a -= dt; if (changed || this.a < 0) this.a = 1; }, receiver(msg) { for (const x of msg.fullObjects) {} for (const x of msg.partObjects) {} for (const x of msg.delObjIds) {} this.active = msg.activePlayerData; } };
  assert.equal(discoverInputTimeout(g), 'a'); assert.equal(discoverUpdateReceiver(g), 'receiver');
  g.other = function (dt) { this.b -= dt; if (this.b < 0) this.b = 1; }; assert.equal(discoverInputTimeout(g), null);
  const p = { net: {}, apply(data) { this.net.p = { x: data.pos.x, y: data.pos.y }; this.net.l = data.layer; this.net.s = data.scale; this.net.perks = data.perks; } };
  // Actual source uses v2.copy(data.pos), not pos.x/y expressions.
  p.apply = function (data) { this.net.p = copy(data.pos); this.net.l = data.layer; this.net.s = data.scale; this.net.perks = data.perks; };
  const first = discoverSourceFields(p, { netKey: 'net' });
  assert.deepEqual(first, { pos: 'p', layer: 'l', scale: 's', perks: 'perks' });
  first.pos = 'tampered';
  assert.equal(discoverSourceFields(p, { netKey: 'net' }).pos, 'p', 'cached results cannot be mutated by caller');
  p.apply = function (data) { this.net.newPos = copy(data.pos); this.net.l = data.layer; };
  assert.equal(discoverSourceFields(p, { netKey: 'net' }).pos, 'newPos', 'new implementation invalidates role cache');
  assert.equal(discoverSourceFields(p, { netKey: 'other' }).pos, null, 'different net key invalidates role cache');
});

test('ACK timing is local bounded RTT/2, duplicate ACK cannot be counted twice', () => {
  const t = new NetworkTiming(); t.sent({ seq: 4 }, 1000); t.sent({ seq: 4 }, 1020); t.received({ ack: 3 }, 1030);
  assert.equal(t.rtt, null); t.received({ ack: 4 }, 1080); assert.equal(t.transit(1080), .04);
  t.received({ ack: 4 }, 1300); assert.equal(t.rtt, 80); assert.equal(t.transit(2581), 0); assert.equal(t.transit(1079), 0);
  t.sent({ seq: 5 }, 3000); t.received({ ack: 5 }, 3020);
  assert.equal(t.rtt, 20, 'a fresh ACK after a long gap starts a new estimate');
  t.sent({ seq: 6 }, 3050); t.received({ ack: 6 }, 3090);
  assert.equal(t.rtt, 24, 'nearby ACKs still use the EWMA');
  t.reset(); assert.equal(t.transit(2600), 0);
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
  assert.equal(normalizeConfig({}).humanLikeAim, true);
  assert.equal(normalizeConfig({}).smoothProfile, 'responsive');
  assert.equal(normalizeConfig({ version: 2, smoothEnabled: true }).humanLikeAim, true, 'legacy Smooth Lock maps to the separated Human-like toggle');
  assert.equal(normalizeConfig({ humanLikeAim: true }).humanLikeAim, true);
  assert.equal(normalizeConfig({ smoothProfile: 'precise' }).smoothProfile, 'precise');
  assert.equal(normalizeConfig({ smoothProfile: 'cinematic' }).smoothProfile, 'responsive');
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

test('bounded small oscillation stabilizes Lock, not Assist or fast departure', () => {
  const tracker = new SnapshotTracker(), target = { __id: 52 }; let now = 0;
  for (let i = 0; i <= 29; i++) {
    now = i * 33;
    tracker.observe(target, { x: 50, y: .34 * Math.sin(now / 1000 * 2 * Math.PI * 1.4) }, now);
  }
  const track = tracker.estimate(target, now);
  const opts = { origin: { x: 0, y: 0 }, target: track.pos, track, profile, radius: 1 };
  const stable = predictShot({ ...opts, stabilize: true });
  assert.equal(stable.state, 'bounded-oscillation');
  assert.ok(Math.abs(stable.world.y) < .03);
  const assist = predictShot(opts);
  assert.notEqual(assist.state, 'bounded-oscillation');
  assert.deepEqual(assist, predictShot({ ...opts, stabilize: false }));
  now += 33; tracker.observe(target, { x: 50, y: track.pos.y + .4 }, now);
  const fastTrack = tracker.estimate(target, now);
  assert.notEqual(predictShot({ ...opts, target: fastTrack.pos, track: fastTrack, stabilize: true }).state, 'bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, track: { ...track, age: .16 }, stabilize: true }).state, 'bounded-oscillation');
});

test('small-oscillation hypothesis rejects straight motion, gaps and insufficient history', () => {
  const tracker = new SnapshotTracker(), p = { __id: 53 };
  for (let i = 0; i < 28; i++) tracker.observe(p, { x: 50, y: Math.round(i * .03 * 100) / 100 }, i * 33);
  const track = tracker.estimate(p, 27 * 33), opts = { origin: { x: 0, y: 0 }, target: track.pos, track, profile, stabilize: true };
  assert.notEqual(predictShot(opts).state, 'bounded-oscillation');
  const samples = Array.from({ length: 30 }, (_, i) => ({ t: i * 33, p: { x: 50, y: .3 * Math.sin(i * 33 / 1000 * 2 * Math.PI * 1.4) } }));
  const broken = samples.filter((_, i) => i < 10 || i > 15);
  assert.notEqual(predictShot({ ...opts, track: { ...track, motion: broken } }).state, 'bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, track: { ...track, motion: samples.slice(-5) } }).state, 'bounded-oscillation');
});

test('bullet wallcheck ends at first hitbox edge or the exit if spawned inside', () => {
  assert.deepEqual(pathToTarget({ x: 0, y: 0 }, { x: 10, y: 0 }, 1), { x: 9, y: 0 });
  assert.deepEqual(pathToTarget({ x: 9.5, y: 0 }, { x: 10, y: 0 }, 1), { x: 11, y: 0 });
});

test('smoothed wallcheck follows the actual ray and truncates only at a real circle intersection', () => {
  const from = { x: 0, y: 0 }, target = { x: 10, y: 0 };
  const direct = pathAlongAim(from, { x: 1, y: 0 }, target, 1);
  assert.deepEqual(direct, { x: 9, y: 0 });
  const angle = .05, dir = { x: Math.cos(angle), y: Math.sin(angle) };
  const hit = pathAlongAim(from, dir, target, 1);
  assert.ok(Math.abs(Math.hypot(hit.x - target.x, hit.y - target.y) - 1) < 1e-9);
  assert.ok(Math.hypot(hit.x, hit.y) < 10);
  const miss = pathAlongAim(from, { x: 0, y: 1 }, target, 1);
  assert.deepEqual(miss, { x: 0, y: 11 });
  assert.deepEqual(pathAlongAim({ x: 9.5, y: 0 }, { x: 1, y: 0 }, target, 1), { x: 11, y: 0 });
});

test('fast bounded strafes tolerate speed but not region departures or excessive diameter', () => {
  const tracker = new SnapshotTracker(), entity = { __id: 150 };
  const ys = [0, .4, .8, 1.2, .8, .4, 0, .4, .8, 1.2, .8, .4, 0, .4, .8, 1.2, .8, .4, 0, .4, .8];
  ys.forEach((y, i) => tracker.observe(entity, { x: 50, y }, i * 33));
  const track = tracker.estimate(entity, 20 * 33);
  const opts = { origin: { x: 0, y: 0 }, target: track.pos, track, profile, radius: .75, stabilize: true };
  assert.equal(predictShot(opts).state, 'bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, radius: .3 }).state, 'bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, stabilize: false }).state, 'bounded-oscillation');
  tracker.observe(entity, { x: 50, y: 1.4 }, 21 * 33);
  const departure = tracker.estimate(entity, 21 * 33);
  assert.notEqual(predictShot({ ...opts, target: departure.pos, track: departure }).state, 'bounded-oscillation');
  tracker.observe(entity, { x: 50.4, y: 1.4 }, 22 * 33);
  const side = tracker.estimate(entity, 22 * 33);
  assert.notEqual(predictShot({ ...opts, target: side.pos, track: side }).state, 'bounded-oscillation');
});

test('wide A-D midpoint is bounded, long-flight-only, approximate and yields on departure', () => {
  const tracker = new SnapshotTracker(), entity = { __id: 153 };
  for (let i = 0; i < 28; i++) {
    const t = i * 33, y = 2.4 * 2 / Math.PI * Math.asin(Math.sin(2 * Math.PI * t / 800));
    tracker.observe(entity, { x: 55, y }, t);
  }
  const track = tracker.estimate(entity, 27 * 33), gun = { speed: 66, range: 250, barrel: 2, offset: 0, variance: 1 };
  const opts = { origin: { x: 0, y: 0 }, target: track.pos, track, profile: gun, radius: 1, stabilize: true };
  const shot = predictShot(opts);
  assert.equal(shot.state, 'wide-bounded-oscillation'); assert.equal(shot.approximate, true); assert.ok(Math.abs(shot.world.y) < .08);
  assert.notEqual(predictShot({ ...opts, stabilize: false }).state, 'wide-bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, radius: .5 }).state, 'wide-bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, origin: { x: 45, y: 0 } }).state, 'wide-bounded-oscillation');
  const motion = track.motion.filter((_, i) => i < 8 || i > 15);
  assert.notEqual(predictShot({ ...opts, track: { ...track, motion } }).state, 'wide-bounded-oscillation');
  tracker.observe(entity, { x: 55.3, y: track.pos.y }, 28 * 33);
  const departure = tracker.estimate(entity, 28 * 33);
  assert.notEqual(predictShot({ ...opts, track: departure, target: departure.pos }).state, 'wide-bounded-oscillation');
});

test('strafe stabilization setting defaults on and preserves explicit opt-out', () => {
  assert.equal(normalizeConfig({}).stabilizeStrafe, true);
  assert.equal(normalizeConfig({ version: 3, stabilizeStrafe: false }).stabilizeStrafe, false);
  assert.equal(normalizeConfig({ stabilizeStrafe: 'false' }).stabilizeStrafe, true);
});

test('Lock linear snapshot compensation is bounded, history-gated and opt-in', () => {
  const tracker = new SnapshotTracker(), enemy = { __id: 151 };
  for (let i = 0; i < 28; i++) tracker.observe(enemy, { x: 50, y: i * .33 }, i * 33);
  const track = tracker.estimate(enemy, 27 * 33);
  const opts = { origin: { x: 0, y: 0 }, target: track.pos, track, profile, latency: .03 };
  const normal = predictShot(opts), adapted = predictShot({ ...opts, compensateSnapshot: true });
  assert.ok(adapted.world.y > normal.world.y + .25);
  assert.deepEqual(predictShot({ ...opts, latency: 0, compensateSnapshot: true }), predictShot({ ...opts, latency: 0 }));
  assert.deepEqual(predictShot({ ...opts, compensateSnapshot: true, latency: .1 }), predictShot({ ...opts, latency: .1 }));
  assert.deepEqual(predictShot({ ...opts, compensateSnapshot: true, track: { ...track, motion: track.motion.slice(-5) } }), predictShot({ ...opts, track: { ...track, motion: track.motion.slice(-5) } }));
  const motion = track.motion.map((s, i) => i === 10 ? { ...s, p: { ...s.p, x: s.p.x + .5 } } : s);
  assert.deepEqual(predictShot({ ...opts, compensateSnapshot: true, track: { ...track, motion } }), predictShot({ ...opts, track: { ...track, motion } }));
  const gap = track.motion.filter((_, i) => i < 10 || i > 14);
  assert.deepEqual(predictShot({ ...opts, compensateSnapshot: true, track: { ...track, motion: gap } }), predictShot({ ...opts, track: { ...track, motion: gap } }));
});

test('wider repeated A-D aims at the middle only while bounded; escape and Assist remain separate', () => {
  const tracker = new SnapshotTracker(), entity = { __id: 152 };
  const ys = [0,.4,.8,1.2,1.6,2,2.4,2.8,3,2.6,2.2,1.8,1.4,1,.6,.2,0,.4,.8,1.2,1.6,2,2.4,2.8,3,2.6,2.2,1.8];
  ys.forEach((y, i) => tracker.observe(entity, { x: 50, y }, i * 33));
  const track = tracker.estimate(entity, (ys.length - 1) * 33);
  const opts = { origin: { x: 0, y: 0 }, target: track.pos, track, profile, radius: 1 };
  const shot = predictShot({ ...opts, stabilize: true });
  assert.equal(shot.state, 'bounded-oscillation'); assert.ok(Math.abs(shot.world.y - 1.5) < .01);
  assert.notEqual(predictShot({ ...opts, stabilize: false }).state, 'bounded-oscillation');
  assert.notEqual(predictShot({ ...opts, radius: .75, stabilize: true }).state, 'bounded-oscillation');
  tracker.observe(entity, { x: 50, y: 3.2 }, ys.length * 33);
  const escape = tracker.estimate(entity, ys.length * 33);
  assert.notEqual(predictShot({ ...opts, target: escape.pos, track: escape, stabilize: true }).state, 'bounded-oscillation');
});
