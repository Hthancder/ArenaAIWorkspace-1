import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import { ast, captureApplication, captureDefinitions, discover, discoverCamera, discoverPlayerSchema,
  discoverSender, discoverVisualPosition, discoverLootSource, aimPoint, overlayPosition, Disposables, entries, intercept, patchMethod, project, read, segmentBlocked,
  teamOf, Tracker } from '../src/core.mjs';
import { Features, grenadeZone, inputShape, localDataSchema, modifyMessage, Overrides, VERIFIED_PROTOCOL } from '../src/features.mjs';
import { createMenu, DEFAULTS, loadConfig, normalizeConfig, STORAGE_KEY } from '../src/menu.mjs';
import { start } from '../src/main.mjs';

// Inert fixtures mirror audited public-source semantics with deliberately renamed internals.
// They are NOT captured from, or integration tests against, the live website.
class Camera {
  constructor() { this.p = { x: 10, y: 20 }; this.unit = 16; this.zoom = 2; this.target = 2; this.w = 800; this.h = 600; this.extra = [1, 2]; }
  scale() { return this.unit * this.zoom; }
  forward(p) { return { x: this.w * .5 + (p.x - this.p.x) * this.scale(), y: this.h * .5 - (p.y - this.p.y) * this.scale() }; }
  inverse(p) { return { x: this.p.x + (p.x - this.w * .5) / this.scale(), y: this.p.y + (this.h * .5 - p.y) / this.scale() }; }
}
class Player {
  constructor(id, pos = { x: 10, y: 20 }) {
    this.__id = id; this.__type = 1; this.active = true; this.layer = 0;
    this.container = {}; this.nameText = { visible: false, style: { fill: 65535 } }; this.p = pos; this.d = { x: 1, y: 0 };
    this.n = { weapon: 'mp5', dead: false, downed: false };
    this.l = { zoom: 48, index: 0, weapons: [{ type: 'mp5', ammo: 20 }, { type: 'mp5', ammo: 20 }, { type: 'fists', ammo: 0 }, { type: 'frag', ammo: 1 }] };
  }
  selectIdlePose() { const def = globalThis.fixtureDefs.typeToDefSafe(this.n.weapon); return def.type; }
  canInteract(map) { return !this.n.dead && (!map.perkMode || this.n.role); }
  getMeleeCollider() { const angle = Math.atan2(this.d.y, this.d.x); return globalThis.fixtureCollider(this.p, angle); }
  getZoom() { let zoom = this.l.zoom; if ([48, 68].indexOf(zoom) >= 0) zoom = this.l.zoom; return zoom; }
}
class Touch { getAimMovement(player, camera) { const throwable = player.l.index === 3; return this.getAim(throwable, camera); } }
class Binds {
  constructor(input) { this.input = input; }
  isBindDown(code) { return code === 4 && !!this.input.mouseButtons[0]; }
  isBindPressed(code) { return code === 4 && !!this.input.mouseButtons[0] && !this.input.mouseButtonsOld[0]; }
}
class Game {
  constructor(input) {
    this.initialized = true; this.connected = true; this.camera = new Camera(); this.hero = new Player(1);
    this.enemy = undefined; // Only one direct game-owned player reference, as in the source.
    this.barn = { playerIds: [1, 2], teamInfo: { 10: { playerIds: [1] }, 20: { playerIds: [2] } }, playerPool: { list: [this.hero, new Player(2, { x: 12, y: 20 })] } };
    this.ui = { spectating: false, setSpectating(value) { this.spectating = value; } };
    this.timeout = 1; this.touch = new Touch(); this.binds = new Binds(input); this.sent = [];
  }
  update(dt) { this.camera.zoom = lerp(dt, this.camera.zoom, this.camera.target); this.timeout -= dt; if (this.timeout < 0) this.timeout = 1; }
  transmit(type, data, size = 128) { const stream = { serializeMsg() {} }; stream.serializeMsg(type, data); this.sent.push({ type, data, size }); return 'forwarded'; }
  unrelated(a, b, c) { return a; }
}
class InputMsg {
  constructor() { Object.assign(this, { shootStart: false, shootHold: false, moveLeft: false, moveRight: true, moveUp: true, moveDown: false, touchMoveActive: false, touchMoveDir: { x: 1, y: 0 }, toMouseDir: { x: 1, y: 0 }, toMouseLen: 10, inputs: [] }); }
  serialize() {}
  addInput(value) { if (this.inputs.length < 7 && !this.inputs.includes(value)) this.inputs.push(value); }
}
class JoinMsg {
  constructor(protocol = VERIFIED_PROTOCOL) { Object.assign(this, { protocol, name: 'fixture', joinToken: 'fixture-only', isMobile: false, useTouch: false }); }
  serialize() {}
}
const defs = { mp5: { type: 'gun', bulletType: 'bullet_mp5', fireMode: 'single', fireDelay: .1 }, bullet_mp5: { type: 'bullet', speed: 100, distance: 80 }, frag: { type: 'throwable' }, explosion_frag: { type: 'explosion' } };
function fixture() {
  const input = { mousePos: { x: 440, y: 300 }, mouseButtons: { 0: false }, mouseButtonsOld: { 0: false }, keys: {}, keysOld: {}, flush() { this.mouseButtonsOld = { ...this.mouseButtons }; this.keysOld = { ...this.keys }; } };
  const callbacks = [];
  const ticker = { add(fn, context, priority = 0) { callbacks.push({ fn, context, priority }); }, remove(fn, context) { const i = callbacks.findIndex(x => x.fn === fn && x.context === context); if (i >= 0) callbacks.splice(i, 1); } };
  return { input, game: new Game(input), pixi: { ticker, stage: {} }, callbacks };
}
function env() {
  const dom = new JSDOM('<!doctype html><body></body>', { url: 'https://survev.io/', pretendToBeVisual: true, runScripts: 'outside-only' });
  dom.window.HTMLCanvasElement.prototype.getContext = () => ({ save() {}, restore() {}, setTransform() {}, setLineDash() {}, fillRect() {}, fillText() {}, measureText(text) { return { width: text.length * 6 }; }, clearRect() {}, beginPath() {}, arc() {}, stroke() {}, fill() {}, moveTo() {}, lineTo() {}, closePath() {} });
  return dom;
}

test('source discovery ignores throwing accessors and parses methods without invoking them', () => {
  let reads = 0;
  const o = { data: 2 }; Object.defineProperty(o, 'evil', { get() { reads++; throw Error(); } });
  assert.deepEqual(entries(o), [['data', 2]]); assert.equal(read(o, 'evil'), undefined); assert.equal(reads, 0);
  assert.ok(ast(Player.prototype.getMeleeCollider));
  assert.equal(ast(Math.max), null);
});

test('camera maps renamed roles and computes the audited forward transform', () => {
  const app = fixture(), camera = discoverCamera(app.game);
  assert.ok(camera); assert.equal(camera.gameKey, 'camera'); assert.equal(camera.posKey, 'p');
  assert.equal(camera.zoomKey, 'zoom');
  assert.deepEqual(project(camera, { x: 12, y: 21 }), { x: 464, y: 268 });
  assert.equal(project(camera, { x: NaN, y: 1 }), null);
});

test('ambiguous cameras and unsupported projection equations fail closed', () => {
  const app = fixture(); app.game.secondCamera = new Camera(); assert.equal(discoverCamera(app.game), null);
  class Wrong extends Camera { forward(p) { return { x: this.w * .5 + (p.x + this.p.x) * this.scale(), y: this.h * .5 - (p.y - this.p.y) * this.scale() }; } }
  assert.equal(discoverCamera({ camera: new Wrong() }), null);
});

test('camera accepts static bracket property access rather than key order', () => {
  const camera = { h: 100, p: { x: 0, y: 0 }, z: 3, u: 16, w: 200,
    s() { return this['u'] * this['z']; },
    f(p) { return { x: this['w'] * .5 + (p.x - this['p'].x) * this['s'](), y: this['h'] * .5 - (p.y - this['p'].y) * this['s']() }; } };
  const mapped = discoverCamera({ camera }); assert.ok(mapped);
  assert.deepEqual(project(mapped, { x: 1, y: 1 }), { x: 148, y: 2 });
});

test('player semantic anchors find roles despite extra fields and unrelated arrays', () => {
  const player = new Player(9); player.addedField = {}; player.randomIds = [7];
  const s = discoverPlayerSchema(player);
  assert.deepEqual(s, { netKey: 'n', weaponKey: 'weapon', deadKey: 'dead', posKey: 'p', dirKey: 'd' });
  assert.equal(discoverPlayerSchema({ ...player, selectIdlePose: null }), null);
});

test('pool discovery uses entities, rejects ambiguity, rereads compacted arrays', () => {
  const app = fixture(), m = discover(app.game); assert.equal(m.active, app.game.hero);
  assert.equal(m.poolKey, 'list'); assert.equal(m.players().length, 2);
  app.game.barn.playerPool.list = [app.game.hero]; assert.equal(m.players().length, 1);
  app.game.barn.playerPool.duplicate = [app.game.hero]; assert.equal(discover(app.game).poolKey, null);
  assert.equal(teamOf(app.game.barn, 999), null);
});

test('sender recognized by serializeMsg rather than arity; ambiguous sender rejected', () => {
  const app = fixture(); assert.equal(discoverSender(app.game), 'transmit');
  app.game.other = function (type, msg) { const s = {}; s.serializeMsg(type, msg); };
  assert.equal(discoverSender(app.game), null);
});

test('local slot and zoom roles come from touch/getZoom semantics', () => {
  const app = fixture(), local = localDataSchema(app.game, app.game.hero);
  assert.ok(local); assert.equal(local.slotKey, 'index'); assert.equal(local.zoomKey, 'zoom');
});

test('typed config validation, clamps, and storage failures', () => {
  const config = normalizeConfig({ aim: 'true', fov: 999, smooth: NaN, smokeOpacity: -1, menuKey: '<script>', unknown: true });
  assert.equal(config.aim, false); assert.equal(config.fov, 400); assert.equal(config.smokeOpacity, 0);
  assert.equal(config.smooth, 50); assert.equal(config.menuKey, 'ShiftRight'); assert.ok(!('unknown' in config));
  assert.deepEqual(loadConfig({ getItem() { throw Error(); } }), { ...DEFAULTS });
});

test('intercept handles stationary, impossible, linear, invalid and zero-distance cases', () => {
  assert.equal(intercept({ x: 10, y: 0 }, { x: 0, y: 0 }, 10), 1);
  assert.equal(intercept({ x: 10, y: 0 }, { x: 20, y: 0 }, 10), null);
  assert.equal(intercept({ x: 10, y: 0 }, { x: -10, y: 0 }, 10), .5);
  assert.equal(intercept({ x: 10, y: 0 }, { x: 0, y: 0 }, 0), null);
  assert.equal(intercept({ x: 0, y: 0 }, { x: 0, y: 0 }, 10), 0);
});

test('velocity history resets on pool reuse and long gap; turn tracking is time-aware', () => {
  const tracker = new Tracker(), p = new Player(1);
  tracker.update(p, { x: 0, y: 0 }, 100);
  const moving = tracker.update(p, { x: .2, y: 0 }, 120); assert.ok(moving.vx > 0);
  assert.ok(tracker.update(p, { x: 0, y: 0 }, 140).vx < 0);
  p.__id = 2; assert.equal(tracker.update(p, { x: 10, y: 10 }, 160).vx, 0);
  assert.equal(tracker.update(p, { x: 40, y: 40 }, 2000).vy, 0);
});

test('segment collision: parallel AABB edge cases, circle, unknown shape', () => {
  const box = { type: 1, min: { x: 1, y: 1 }, max: { x: 3, y: 3 } };
  assert.equal(segmentBlocked({ x: 0, y: 2 }, { x: 5, y: 2 }, box), true);
  assert.equal(segmentBlocked({ x: 0, y: 0 }, { x: 5, y: 0 }, box), false);
  assert.equal(segmentBlocked({ x: 0, y: 2 }, { x: 5, y: 2 }, { type: 0, pos: { x: 2, y: 2 }, rad: 1 }), true);
  assert.equal(segmentBlocked({ x: 0, y: 0 }, { x: 1, y: 1 }, { type: 99 }), true);
});

test('override cleanup restores latest game-written value and exact flags', () => {
  const state = { alpha: .8 }, overrides = new Overrides();
  const before = Object.getOwnPropertyDescriptor(state, 'alpha');
  overrides.set(state, 'alpha', raw => raw * .5); assert.equal(state.alpha, .4);
  state.alpha = .6; assert.equal(state.alpha, .3);
  overrides.clear(); assert.deepEqual(Object.getOwnPropertyDescriptor(state, 'alpha'), { ...before, value: .6 });
  overrides.clear(); assert.equal(overrides.records.size, 0);
});

test('method and property cleanup never stomp a later owner', () => {
  const object = { fn() { return 1; }, alpha: 1 }, bag = new Disposables();
  patchMethod(object, 'fn', original => () => original() + 1, bag); assert.equal(object.fn(), 2);
  const later = () => 3; object.fn = later; bag.clear(); assert.equal(object.fn, later);
  const overrides = new Overrides(); overrides.set(object, 'alpha', () => 0);
  Object.defineProperty(object, 'alpha', { value: .9, configurable: true, writable: true });
  overrides.clear(); assert.equal(object.alpha, .9);
});

test('message edits preserve prototype, isolate input arrays and require verified protocol', () => {
  const data = new InputMsg(); assert.equal(inputShape(data), true);
  const modified = modifyMessage(data, { mobileMovement: true }, { protocol: VERIFIED_PROTOCOL, switchSlot: 1 });
  assert.equal(Object.getPrototypeOf(modified), InputMsg.prototype);
  assert.equal(modified.touchMoveLen, 255); assert.ok(Math.abs(modified.touchMoveDir.x - Math.SQRT1_2) < 1e-12);
  assert.deepEqual(modified.inputs, [12]); assert.deepEqual(data.inputs, []); assert.equal(data.touchMoveActive, false);
  assert.equal(modifyMessage(data, { mobileMovement: true }, { protocol: 9999 }), data);
});

test('bounded capture restores call, forwards return and captures only once in isolated realm', async () => {
  const context = vm.createContext({ setTimeout, clearTimeout, queueMicrotask });
  const win = vm.runInContext('({ Function, Reflect, setTimeout, clearTimeout, queueMicrotask })', context);
  const original = win.Function.prototype.call; const found = [];
  const cancel = captureApplication(win, app => found.push(app), { timeout: 100 });
  const app = fixture(); context.app = app;
  assert.equal(vm.runInContext('(function(){return 42}).call(app)', context), 42);
  await new Promise(resolve => queueMicrotask(resolve));
  assert.equal(found.length, 1); assert.equal(found[0], app); assert.equal(win.Function.prototype.call, original);
  cancel();
});

test('capture timeout restores only own wrapper and executes timeout callback', async () => {
  const context = vm.createContext({ setTimeout, clearTimeout, queueMicrotask });
  const win = vm.runInContext('({ Function, Reflect, setTimeout, clearTimeout, queueMicrotask })', context);
  const original = win.Function.prototype.call; let timeouts = 0;
  captureApplication(win, () => assert.fail(), { timeout: 5, onTimeout: () => timeouts++ });
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(timeouts, 1); assert.equal(win.Function.prototype.call, original);
});

test('definition capture restores Object.keys and forwards invalid input errors', async () => {
  const context = vm.createContext({ setTimeout, clearTimeout, queueMicrotask });
  const win = vm.runInContext('({ Object, Reflect, setTimeout, clearTimeout, queueMicrotask })', context);
  const original = win.Object.keys; let captured;
  const stop = captureDefinitions(win, db => captured = db, 100);
  assert.throws(() => win.Object.keys(null)); assert.deepEqual([...win.Object.keys(defs)], Object.keys(defs));
  await new Promise(resolve => queueMicrotask(resolve));
  assert.equal(captured, defs); assert.equal(win.Object.keys, original); stop();
});

test('features capture protocol, clone join, and dispose all ticker/method ownership', () => {
  const dom = env(), win = dom.window, app = fixture();
  const originalSender = app.game.transmit, originalFlush = app.input.flush;
  const engine = new Features(win, app, { ...DEFAULTS, autoLoot: true, lootMode: 'mobile' }, () => {}, defs);
  const join = new JoinMsg(); assert.equal(app.game.transmit(1, join), 'forwarded');
  assert.equal(app.game.sent[0].data.isMobile, true); assert.equal(join.isMobile, false);
  assert.equal(engine.protocol, VERIFIED_PROTOCOL); assert.equal(app.callbacks.length, 2);
  engine.dispose(); engine.dispose(); assert.equal(app.callbacks.length, 0);
  assert.equal(app.game.transmit, originalSender); assert.equal(app.input.flush, originalFlush); dom.window.close();
});

test('aim transaction restores physical mouse before flush and resets on match exit', () => {
  const dom = env(), win = dom.window, app = fixture(), errors = [];
  app.input.mouseButtons[0] = true;
  const originalPos = { ...app.input.mousePos };
  const engine = new Features(win, app, { ...DEFAULTS, aim: true, predict: false, wallcheck: false, smoothEnabled: false }, (level, message) => { if (level === 'error') errors.push(message); }, defs);
  app.game.transmit(1, new JoinMsg());
  engine.pre(); assert.equal(app.input.mousePos.x, 440); assert.ok(engine.target);
  app.input.flush(); assert.deepEqual(app.input.mousePos, originalPos); assert.equal(app.input.mouseButtonsOld[0], true);
  app.game.initialized = false; engine.pre(); assert.equal(engine.mapping, null); assert.equal(engine.target, null);
  assert.deepEqual(errors, []); engine.dispose(); dom.window.close();
});

test('mapping preserves local zoom schema during accessor override; rejoin installs new pool', () => {
  const dom = env(), app = fixture(), engine = new Features(dom.window, app, { ...DEFAULTS, zoom: true }, () => {}, defs);
  engine.post(); assert.equal(app.game.hero.l.zoom, 72);
  engine.reconcile(true); assert.equal(engine.local.zoomKey, 'zoom');
  const old = app.game.barn.playerPool; app.game.barn.playerPool = { list: [...old.list] };
  engine.reconcile(true); assert.equal(engine.mapping.pool, app.game.barn.playerPool);
  engine.dispose(); assert.equal(app.game.hero.l.zoom, 48); dom.window.close();
});

test('semi-auto supports held single-fire input without changing current/old physical state', () => {
  const dom = env(), app = fixture(), engine = new Features(dom.window, app, { ...DEFAULTS, semi: true }, () => {}, defs);
  app.game.transmit(1, new JoinMsg()); engine.reconcile(true);
  app.input.mouseButtons[0] = app.input.mouseButtonsOld[0] = true;
  assert.equal(app.game.binds.isBindPressed(4), true);
  assert.equal(app.game.binds.isBindPressed(4), true); // All consumers see the same frame edge.
  engine.pre();
  assert.equal(app.game.binds.isBindPressed(4), false);
  assert.equal(app.input.mouseButtons[0], true); assert.equal(app.input.mouseButtonsOld[0], true);
  engine.dispose(); dom.window.close();
});

test('menu preserves tabs, settings, actual key rebind and removes listeners on dispose', async () => {
  const dom = env(), win = dom.window, config = { ...DEFAULTS }; let retries = 0;
  const menu = createMenu(win, config, { onChange() {}, retry() { retries++; }, stop() {}, diagnostics: () => ({ fixture: true }) });
  assert.deepEqual([...menu.root.querySelectorAll('nav button')].map(b => b.textContent), ['Main', 'Visuals', 'Misc', 'Keybinds', 'Help']);
  [...menu.root.querySelectorAll('nav button')].find(b => b.textContent === 'Keybinds').click();
  const keyButton = [...menu.root.querySelectorAll('main button')].find(b => b.textContent === 'ShiftRight'); keyButton.click();
  win.dispatchEvent(new win.KeyboardEvent('keydown', { code: 'KeyM', bubbles: true, cancelable: true }));
  assert.equal(config.menuKey, 'KeyM');
  await new Promise(resolve => win.setTimeout(resolve, 240)); assert.equal(JSON.parse(win.localStorage.getItem(STORAGE_KEY)).menuKey, 'KeyM');
  [...menu.root.querySelectorAll('button')].find(b => b.textContent === 'Retry capture').click(); assert.equal(retries, 1);
  const shell = menu.root.querySelector('#ui'); win.dispatchEvent(new win.KeyboardEvent('keydown', { code: 'KeyM' })); assert.equal(shell.hidden, true);
  menu.dispose(); win.dispatchEvent(new win.KeyboardEvent('keydown', { code: 'KeyM' })); assert.equal(shell.hidden, true); assert.equal(menu.host.isConnected, false); dom.window.close();
});

test('bundled userscript starts, prevents duplicate instances and fully cleans up in jsdom', () => {
  const dom = env(), win = dom.window;
  const script = readFileSync(new URL('../userscripts/duality-reborn.user.js', import.meta.url), 'utf8');
  const originalCall = win.Function.prototype.call, originalKeys = win.Object.keys;
  win.eval(script); const key = win.Symbol.for('duality.reborn.controller.v1'); assert.ok(win[key]);
  win.eval(script); assert.equal(win.document.querySelectorAll('#duality-reborn-host').length, 1);
  win[key].dispose(); assert.equal(win.document.querySelectorAll('#duality-reborn-host').length, 0);
  assert.equal(win.Function.prototype.call, originalCall); assert.equal(win.Object.keys, originalKeys); assert.equal(win[key], undefined);
  dom.window.close();
});

test('minifier/property-renaming mutation preserves semantic player and camera discovery', async () => {
  const { transformSync } = await import('esbuild');
  const code = `
    class Cam {
      constructor(){ this.added = true; this.m_height=600; this.m_pos={x:0,y:0}; this.m_ppu=16; this.m_zoom=2; this.m_width=800; }
      m_z(){return this.m_ppu*this.m_zoom}
      m_project(p){return {x:this.m_width*.5+(p.x-this.m_pos.x)*this.m_z(),y:this.m_height*.5-(p.y-this.m_pos.y)*this.m_z()}}
    }
    class Entity {
      constructor(){this.__id=1;this.active=true;this.container={};this.nameText={};this.m_net={m_dead:false,m_weapon:'mp5'};this.m_pos={x:3,y:4};this.m_dir={x:1,y:0};this.newField=123}
      selectIdlePose(){return database.typeToDefSafe(this.m_net.m_weapon)}
      canInteract(map){return !this.m_net.m_dead&&(!map.perkMode||this.m_net.m_role)}
      getMeleeCollider(){const a=Math.atan2(this.m_dir.y,this.m_dir.x);return collider(this.m_pos,a)}
    }
    globalThis.result={camera:new Cam,player:new Entity};
  `;
  for (const prefix of ['alpha', 'beta']) {
    const mangleCache = Object.fromEntries(['m_height','m_pos','m_ppu','m_zoom','m_width','m_z','m_project','m_net','m_dead','m_weapon','m_dir','m_role'].map((key, i) => [key, prefix + i]));
    const output = transformSync(code, { minify: true, mangleProps: /^m_/, mangleCache }).code;
    const context = vm.createContext({}); vm.runInContext(output, context);
    const mapped = discoverCamera({ camera: context.result.camera }); assert.ok(mapped);
    assert.deepEqual(project(mapped, { x: 1, y: 1 }), { x: 432, y: 268 });
    const schema = discoverPlayerSchema(context.result.player); assert.ok(schema);
    assert.equal(read(context.result.player, schema.posKey).x, 3);
    assert.equal(schema.deadKey, mangleCache.m_dead);
  }
});

test('bundled bootstrap captures an application, observes Join, and reports capabilities without exposing state', async () => {
  const dom = env(), win = dom.window, app = fixture();
  const script = readFileSync(new URL('../userscripts/duality-reborn.user.js', import.meta.url), 'utf8');
  win.eval(script); win.fixtureApp = app;
  win.eval('(function(){return 7}).call(window.fixtureApp)');
  await new Promise(resolve => win.queueMicrotask(resolve));
  const key = win.Symbol.for('duality.reborn.controller.v1');
  app.game.transmit(1, new JoinMsg());
  const d = win[key].diagnostics(); assert.equal(d.protocol, VERIFIED_PROTOCOL); assert.equal(d.capabilities.visuals, true);
  assert.equal(d.game, undefined); assert.equal(d.players, undefined);
  win[key].dispose(); assert.equal(app.callbacks.length, 0); dom.window.close();
});

test('hold aim releases on blur and ignores shortcuts from a text input', () => {
  const dom = env(), win = dom.window, config = { ...DEFAULTS, holdAim: true };
  const menu = createMenu(win, config, { onChange() {}, retry() {}, stop() {}, diagnostics: () => ({}) });
  win.dispatchEvent(new win.KeyboardEvent('keydown', { code: 'KeyB' })); assert.equal(config.aim, true);
  win.dispatchEvent(new win.Event('blur')); assert.equal(config.aim, false);
  const text = win.document.createElement('input'); win.document.body.append(text);
  text.dispatchEvent(new win.KeyboardEvent('keydown', { code: 'KeyB', bubbles: true, composed: true })); assert.equal(config.aim, false);
  menu.dispose(); dom.window.close();
});

test('visual effects use reversible properties and promptly prune disabled keys', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, esp: true, nametags: true, xray: true };
  const tree = { active: true, type: 'tree_01', sprite: { alpha: 1 } };
  const img = { isCeiling: true, sprite: { visible: true } };
  app.game.map = { mapTexture: null, getGroundSurface() {}, pool: { list: [tree, { imgs: [img] }] } };
  const engine = new Features(dom.window, app, config, () => {}, defs); engine.post();
  assert.equal(tree.sprite.alpha, .5); assert.equal(img.sprite.visible, false);
  assert.equal(app.game.barn.playerPool.list[1].nameText.visible, true);
  tree.sprite.alpha = .8; assert.equal(tree.sprite.alpha, .5);
  config.xray = false; config.esp = false; engine.lastVisual = -Infinity; engine.post();
  assert.equal(tree.sprite.alpha, .8); assert.equal(img.sprite.visible, true);
  assert.equal(app.game.barn.playerPool.list[1].nameText.visible, false);
  assert.equal(engine.overrides.records.size, 0); engine.dispose(); dom.window.close();
});

test('pool/active reference replacement is detected without waiting for the one-second discovery interval', () => {
  const dom = env(), app = fixture(), engine = new Features(dom.window, app, { ...DEFAULTS }, () => {}, defs);
  const old = app.game.hero, replacement = new Player(3);
  app.game.hero = replacement;
  app.game.barn = { playerIds: [3], teamInfo: { 30: { playerIds: [3] } }, playerPool: { list: [replacement] } };
  engine.pre(); assert.equal(engine.mapping.active, replacement); assert.notEqual(engine.mapping.active, old);
  assert.equal(engine.local.data, replacement.l); engine.dispose(); dom.window.close();
});

test('unknown Join protocol does not change mobile flag or activate enum-dependent input features', () => {
  const dom = env(), app = fixture(), engine = new Features(dom.window, app, { ...DEFAULTS, autoLoot: true, lootMode: 'mobile', mobileMovement: true, semi: true }, () => {}, defs);
  const join = new JoinMsg(9999); app.game.transmit(1, join); engine.reconcile(true);
  assert.equal(app.game.sent[0].data, join); assert.equal(join.isMobile, false);
  assert.equal(engine.capabilities.mobile, false); assert.equal(engine.capabilities.semi, false);
  const input = new InputMsg(); app.game.transmit(3, input); assert.equal(app.game.sent[1].data, input);
  engine.dispose(); dom.window.close();
});


// Source-backed refinements: public snapshot 3edee7e8, not live client captures.
test('render-position discovery follows camera projection into container position without running render', () => {
  const player = new Player(1); player.v = { x: 7, y: 9 }; player.decoy = { x: 88, y: 99 };
  player.render = function (camera) {
    const unrelated = camera.forward(this.decoy);
    globalThis.mustNotExecute();
    const screen = camera.forward(this.v);
    this.container.position.set(screen.x, screen.y);
  };
  assert.equal(discoverVisualPosition(player, 'forward'), 'v');
  assert.equal(discoverVisualPosition(player, 'other'), null);
  player.render = function (camera) {
    const screen = camera.forward(this.v); this.container.position.set(screen.y, screen.x);
  };
  assert.equal(discoverVisualPosition(player, 'forward'), null);
});

test('ambiguous render flows are rejected rather than selecting the first vector', () => {
  const player = new Player(1); player.a = { x: 1, y: 2 }; player.b = { x: 3, y: 4 };
  player.render = function (camera) {
    const first = camera.forward(this.a); this.container.position.set(first.x, first.y);
    const second = camera.forward(this.b); this.container.position.set(second.x, second.y);
  };
  assert.equal(discoverVisualPosition(player, 'forward'), null);
});

test('ESP uses interpolated visual positions while the tracker retains network-position semantics', () => {
  const dom = env(), app = fixture(), players = app.game.barn.playerPool.list;
  for (const p of players) {
    p.v = { x: p.p.x - 1, y: p.p.y - 2 };
    p.render = function (camera) { const screen = camera.forward(this.v); this.container.position.set(screen.x, screen.y); };
  }
  const engine = new Features(dom.window, app, { ...DEFAULTS, esp: true, lines: true, aim: true, espLabels: false, espMarkers: false, espLegend: false }, () => {}, defs);
  assert.equal(engine.mapping.visualPosKey, 'v'); assert.equal(engine.capabilities.interpolatedOverlay, true);
  const lines = [], ctx = { save() {}, restore() {}, setTransform() {}, setLineDash() {}, beginPath() {}, arc() {}, stroke() {}, moveTo(x, y) { lines.push({ x, y }); }, lineTo(x, y) { lines.push({ x, y }); } };
  engine.canvas = { width: dom.window.innerWidth, height: dom.window.innerHeight, remove() {} }; engine.ctx = ctx;
  engine.draw(players);
  assert.deepEqual(lines, players.map(p => project(engine.mapping.camera, p.v)));
  engine.pre(); assert.equal(engine.tracker.states.get(players[1]), undefined, 'Render/pre frames never fabricate network samples');
  engine.ctx = null; engine.dispose(); dom.window.close();
});

test('missing or invalid render contract falls back to network position without inventing vectors', () => {
  const app = fixture(), m = discover(app.game), player = app.game.hero;
  assert.equal(m.visualPosKey, null); assert.equal(overlayPosition(player, m), player.p);
  m.visualPosKey = 'v'; player.v = { x: NaN, y: 0 }; assert.equal(overlayPosition(player, m), player.p);
  player.v = { x: 2, y: 3 }; assert.equal(overlayPosition(player, m), player.v);
});

test('grenade radius excludes loot, inactive pooled entities, unknown protocols and invalid defs', () => {
  const definitions = { frag: { type: 'throwable', explosionType: 'boom' }, boom: { type: 'explosion', rad: { max: 12 } } };
  const e = { __type: 9, active: true, type: 'frag', layer: 0, pos: { x: 3, y: 4 } };
  assert.deepEqual(grenadeZone(e, definitions, 0, VERIFIED_PROTOCOL), { pos: e.pos, radius: 12 });
  for (const patch of [{ __type: 3 }, { active: false }, { active: undefined }, { layer: 1 }, { pos: { x: Infinity, y: 0 } }, { type: 'missing' }]) {
    assert.equal(grenadeZone({ ...e, ...patch }, definitions, 0, VERIFIED_PROTOCOL), null);
  }
  assert.equal(grenadeZone(e, definitions, 0, 9999), null);
  assert.equal(grenadeZone(e, { frag: { type: 'throwable', explosionType: 'explosion_smoke' }, explosion_smoke: definitions.boom }, 0, VERIFIED_PROTOCOL), null);
  for (const radius of [-1, 0, NaN, Infinity]) {
    assert.equal(grenadeZone(e, { ...definitions, boom: { type: 'explosion', rad: { max: radius } } }, 0, VERIFIED_PROTOCOL), null);
  }
  assert.equal(grenadeZone(e, { ...definitions, boom: { type: 'smoke', rad: { max: 12 } } }, 0, VERIFIED_PROTOCOL), null);
});

test('grenade overlay capability requires observed matching Join protocol and entity registry', () => {
  const dom = env(), app = fixture();
  app.game.creator = { registry: { 8: { __id: 8, __type: 9, active: true } } };
  const engine = new Features(dom.window, app, { ...DEFAULTS }, () => {}, defs);
  assert.equal(engine.capabilities.grenadeZones, false);
  app.game.transmit(1, new JoinMsg()); engine.reconcile(true);
  assert.equal(engine.capabilities.grenadeZones, true);
  app.game.transmit(1, new JoinMsg(9999)); engine.reconcile(true);
  assert.equal(engine.capabilities.grenadeZones, false);
  engine.dispose(); dom.window.close();
});

test('wallcheck ignores verified low obstacles but unknown height/layer/protocol stays conservative', () => {
  const dom = env(), app = fixture();
  const obstacle = { __id: 9, __type: 2, active: true, dead: false, collidable: true, height: .2, layer: 0,
    collider: { type: 0, pos: { x: 1, y: 0 }, rad: .5 } };
  app.game.creator = { registry: { 9: obstacle } };
  const engine = new Features(dom.window, app, { ...DEFAULTS, wallcheck: true }, () => {}, defs);
  const from = { pos: { x: 0, y: 0 }, layer: 0 }, to = { pos: { x: 2, y: 0 } };
  assert.equal(engine.blocked(from, to), true);
  app.game.transmit(1, new JoinMsg()); assert.equal(engine.blocked(from, to), false);
  assert.equal(engine.blocked(from, to, false), true); // Bullet-height exception must not apply to melee.
  obstacle.height = .25; assert.equal(engine.blocked(from, to), true);
  obstacle.height = undefined; assert.equal(engine.blocked(from, to), true);
  obstacle.layer = 1; assert.equal(engine.blocked(from, to), false);
  obstacle.layer = undefined; assert.equal(engine.blocked(from, to), true);
  engine.dispose(); dom.window.close();
});


test('cancelling capture invalidates a queued Application callback', async () => {
  const dom = env(), win = dom.window; let deliveries = 0;
  const cancel = captureApplication(win, () => { deliveries++; });
  win.fixtureApp = fixture();
  win.eval('(function(){}).call(window.fixtureApp)');
  cancel();
  await new Promise(resolve => win.queueMicrotask(resolve));
  assert.equal(deliveries, 0);
  dom.window.close();
});

test('Retry keeps the menu-owned canvas mounted and attaches the new engine to it', async () => {
  const dom = env(), win = dom.window, app = fixture();
  const controller = start(win); win.fixtureApp = app;
  win.eval('(function(){}).call(window.fixtureApp)');
  await new Promise(resolve => win.queueMicrotask(resolve));
  const canvas = win.document.querySelector('#duality-reborn-host').shadowRoot.querySelector('canvas');
  assert.equal(canvas.isConnected, true); assert.equal(app.callbacks.length, 2);
  controller.retry();
  assert.equal(canvas.isConnected, true); assert.equal(app.callbacks.length, 0);
  assert.equal(controller.diagnostics().captureState, 'waiting');
  win.eval('(function(){}).call(window.fixtureApp)');
  await new Promise(resolve => win.queueMicrotask(resolve));
  assert.equal(canvas.isConnected, true); assert.equal(app.callbacks.length, 2);
  assert.equal(controller.diagnostics().captureState, 'captured');
  controller.dispose(); assert.equal(canvas.isConnected, false); assert.equal(app.callbacks.length, 0);
  dom.window.close();
});

test('diagnostics distinguish capture, mapping and protocol without leaking game or Join data', async () => {
  const dom = env(), win = dom.window, app = fixture(), controller = start(win);
  assert.equal(controller.diagnostics().captureState, 'waiting');
  win.fixtureApp = app; win.eval('(function(){}).call(window.fixtureApp)');
  await new Promise(resolve => win.queueMicrotask(resolve));
  const d = controller.diagnostics();
  assert.equal(d.captured, true); assert.equal(d.menuMounted, true); assert.equal(d.definitionsCaptured, false);
  assert.equal(d.checks.camera, true); assert.equal(d.checks.playerSchema, true);
  assert.equal(d.checks.protocolObserved, false); assert.ok(d.missingContracts.includes('definitions'));
  assert.equal(d.game, undefined); assert.equal(d.players, undefined); assert.equal(d.joinToken, undefined);
  app.game.transmit(1, new JoinMsg());
  assert.equal(controller.diagnostics().checks.protocolMatches, true);
  controller.dispose(); dom.window.close();
});

test('distributed userscript retains readable function names and source-module sections', () => {
  const script = readFileSync(new URL('../userscripts/duality-reborn.user.js', import.meta.url), 'utf8');
  const version = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version;
  assert.ok(script.includes(`// @version      ${version}`));
  assert.match(script, /function captureApplication\(/);
  assert.match(script, /function start\(win\)/);
  assert.match(script, /\/\/ src\/main\.mjs/);
  assert.ok(script.split('\n').length > 500);
});

test('desktop Join accepts an undefined mobile flag and forwards a prototype-preserving mobile clone', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, autoLoot: true, lootMode: 'mobile' };
  const engine = new Features(dom.window, app, config, () => {}, defs), join = new JoinMsg();
  join.isMobile = undefined;
  app.game.transmit(1, join);
  const sent = app.game.sent[0].data;
  assert.equal(engine.protocol, VERIFIED_PROTOCOL); assert.equal(sent.isMobile, true);
  assert.equal(join.isMobile, undefined); assert.equal(Object.getPrototypeOf(sent), JoinMsg.prototype);
  assert.equal(engine.autoLootStatus(), 'mobile-join-forwarded');
  engine.dispose(); dom.window.close();
});

test('mobile mode reports pending / forwarded / off-next-join instead of implying immediate pickup', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, lootMode: 'mobile' };
  const engine = new Features(dom.window, app, config, () => {}, defs);
  app.game.transmit(1, new JoinMsg()); config.autoLoot = true;
  assert.equal(engine.autoLootStatus(), 'pending-next-join');
  app.game.transmit(1, new JoinMsg()); assert.equal(engine.autoLootStatus(), 'mobile-join-forwarded');
  config.autoLoot = false; assert.equal(engine.autoLootStatus(), 'off-next-join');
  app.game.transmit(1, new JoinMsg()); assert.equal(engine.autoLootStatus(), 'disabled');
  engine.dispose(); dom.window.close();
});

test('aim input stays player-relative when the visual/shaken camera center differs from network position', () => {
  const dom = env(), app = fixture(); app.game.camera.p = { x: 9, y: 18 };
  app.input.mouseButtons[0] = true;
  const engine = new Features(dom.window, app, { ...DEFAULTS, aim: true, predict: false, wallcheck: false, smoothEnabled: false }, () => {}, defs);
  const camera = engine.mapping.camera;
  assert.deepEqual(project(camera, { x: 12, y: 20 }), { x: 496, y: 236 });
  assert.deepEqual(aimPoint(camera, { x: 12, y: 20 }, { x: 10, y: 20 }), { x: 464, y: 300 });
  app.game.transmit(1, new JoinMsg());
  engine.pre(); assert.deepEqual(app.input.mousePos, { x: 440, y: 300 });
  const native = new InputMsg(); native.toMouseLen = 1.25;
  app.game.transmit(3, native); assert.equal(engine.stats.aimState, 'input-applied');
  assert.deepEqual(app.game.sent.at(-1).data.toMouseDir, { x: 1, y: 0 });
  app.input.flush(); assert.deepEqual(app.input.mousePos, { x: 440, y: 300 });
  engine.dispose(); dom.window.close();
});

test('direct native mouse route advances Lock once per frame and keeps the real cursor radius', () => {
  const f = coordinated({ smooth: 90 });
  const originalStep = f.engine.aimController.step.bind(f.engine.aimController);
  let steps = 0; f.engine.aimController.step = (...args) => { steps++; return originalStep(...args); };
  try {
    f.app.game.transmit(1, new JoinMsg());
    f.app.game.barn.playerPool.list[1].p = { x: 12, y: 20.4 };
    f.engine.pre();
    assert.equal(steps, 1);
    assert.notDeepEqual(f.app.input.mousePos, { x: 440, y: 300 });
    assert.ok(Math.abs(Math.hypot(f.app.input.mousePos.x - 400, 300 - f.app.input.mousePos.y) - 40) < 1e-9);
    f.app.game.transmit(3, (() => { const m = new InputMsg(); m.shootHold = true; m.toMouseLen = 1.25; return m; })());
    assert.equal(steps, 1, 'Sender reuses the direct-frame plan instead of advancing Lock twice');
    assert.equal(f.engine.stats.aimState, 'input-applied');
    assert.equal(f.engine.diagnostics().mouseInput.enabled, true);
    assert.ok(f.engine.diagnostics().mouseInput.appliedFrames >= 1);
    f.app.input.flush(); assert.deepEqual(f.app.input.mousePos, { x: 440, y: 300 });
    const d = f.engine.diagnostics().mouseInput; assert.equal(d.active, false);
  } finally { f.close(); }
});

test('Direct native mouse input can be opted out without disabling sender correction', () => {
  const f = coordinated({ directMouseInput: false });
  try {
    f.app.game.transmit(1, new JoinMsg());
    f.engine.pre(); assert.deepEqual(f.app.input.mousePos, { x: 440, y: 300 }); assert.equal(f.engine.stats.aimState, 'ready-to-send');
    f.app.game.transmit(3, (() => { const m = new InputMsg(); m.shootHold = true; m.toMouseLen = 1.25; return m; })());
    assert.equal(f.engine.stats.aimState, 'input-applied'); assert.deepEqual(f.app.input.mousePos, { x: 440, y: 300 });
    assert.equal(f.engine.diagnostics().mouseInput.enabled, false);
  } finally { f.close(); }
});

test('aim uses physical Fire fallback only if binds are missing, not to override an explicit released bind', () => {
  const dom = env(), app = fixture(); app.input.mouseButtons[0] = true; app.game.binds = null;
  const engine = new Features(dom.window, app, { ...DEFAULTS, aim: true, predict: false, wallcheck: false }, () => {}, defs);
  app.game.transmit(1, new JoinMsg()); engine.pre(); assert.equal(engine.stats.aimState, 'input-applied');
  app.game.binds = new Binds(app.input); app.game.binds.isBindDown = () => false;
  engine.reconcile(true); engine.pre(); assert.equal(engine.stats.aimState, 'waiting-activation');
  engine.dispose(); dom.window.close();
});

test('aim explains wallcheck, unknown teams and FOV rejection without exposing player identity or positions', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, aim: true, predict: false, wallcheck: true };
  app.input.mouseButtons[0] = true;
  const engine = new Features(dom.window, app, config, () => {}, defs);
  app.game.transmit(1, new JoinMsg()); engine.pre(); assert.equal(engine.stats.aimState, 'wallcheck-unavailable');
  config.wallcheck = false; delete app.game.barn.teamInfo[20]; engine.pre();
  assert.equal(engine.stats.aimState, 'no-candidate'); assert.equal(engine.stats.aimRejections.unknownTeam, 1);
  app.game.barn.teamInfo[20] = { playerIds: [2] }; app.game.barn.playerPool.list[1].p = { x: 100, y: 100 }; engine.pre();
  assert.equal(engine.stats.aimRejections.outsideFov, 1);
  const text = JSON.stringify(engine.diagnostics()); assert.ok(!text.includes('playerIds')); assert.ok(!text.includes('mousePos'));
  engine.dispose(); dom.window.close();
});

function pickupFixture() {
  const dom = env(), app = fixture();
  const loot = { __id: 9, __type: 3, active: true, type: '9mm', count: 30, pos: { x: 10, y: 20 }, rad: 2, ownerId: 0, layer: 0 };
  app.game.lootBarn = { closestLoot: loot, getClosestLoot() { return this.closestLoot; } };
  const config = { ...DEFAULTS, autoLoot: true, lootMode: 'nearby' }, definitions = { ...defs, '9mm': { type: 'ammo' } };
  const engine = new Features(dom.window, app, config, () => {}, definitions);
  return { dom, app, loot, config, engine };
}

test('loot source discovery rejects ambiguity and does not execute candidate methods', () => {
  const app = fixture();
  app.game.lootBarn = { candidate: null, getClosestLoot() { return this.candidate; } };
  assert.deepEqual(discoverLootSource(app.game), { owner: app.game.lootBarn, key: 'candidate' });
  app.game.otherLoot = { candidate: null, getClosestLoot() { return this.candidate; } };
  assert.equal(discoverLootSource(app.game), null);
  delete app.game.otherLoot;
  app.game.lootBarn.getClosestLoot = function () { throw Error('must not run'); };
  assert.equal(discoverLootSource(app.game), null);
});

test('nearby supplies work in the current match through native Loot binds without changing Join mobile mode', () => {
  const { dom, app, engine } = pickupFixture();
  app.game.transmit(1, new JoinMsg()); engine.pre();
  assert.equal(app.game.sent[0].data.isMobile, false); assert.equal(engine.capabilities.autoPickup, true);
  assert.equal(app.game.binds.isBindPressed(10), true); assert.equal(app.game.binds.isBindPressed(10), true);
  assert.equal(engine.autoLootStatus(), 'loot-input-ready');
  const msg = new InputMsg(); if (app.game.binds.isBindPressed(10)) msg.addInput(10);
  app.game.transmit(3, msg); assert.deepEqual(app.game.sent[1].data.inputs, [10]);
  engine.pre(); assert.equal(app.game.binds.isBindPressed(10), false); assert.equal(engine.stats.lootState, 'pickup-backoff');
  engine.dispose(); assert.equal(app.game.binds.isBindPressed(10), false); dom.window.close();
});

test('nearby pickup skips weapons, gear, inactive/foreign/out-of-range loot and pauses when downed', () => {
  const { dom, app, loot, engine } = pickupFixture(); app.game.transmit(1, new JoinMsg());
  for (const patch of [{ type: 'mp5' }, { type: 'unknown' }, { active: false }, { ownerId: 555 }, { layer: 1 }, { pos: { x: 20, y: 20 } }, { __type: 9 }]) {
    const original = { ...loot }; Object.assign(loot, patch); engine.pre();
    assert.equal(app.game.binds.isBindPressed(10), false, JSON.stringify(patch)); Object.assign(loot, original);
  }
  app.game.hero.downed = true; engine.pre(); assert.equal(engine.stats.lootState, 'paused');
  app.game.hero.downed = false; app.game.ui.spectating = true; engine.pre(); assert.equal(engine.stats.lootState, 'paused');
  engine.dispose(); dom.window.close();
});

test('unchanged loot backs off, count/id changes reset retry and unknown Join never enables native pickup', () => {
  const { dom, app, loot, engine } = pickupFixture();
  app.game.transmit(1, new JoinMsg(9999)); engine.pre(); assert.equal(engine.pickupPulse, false);
  app.game.transmit(1, new JoinMsg()); engine.pre(); assert.equal(engine.pickupAttempt.attempts, 1);
  engine.nextPickup = -Infinity; engine.pre(); assert.equal(engine.pickupAttempt.attempts, 2);
  loot.count--; engine.pre(); assert.equal(engine.pickupAttempt.attempts, 1); assert.equal(engine.pickupPulse, true);
  loot.__id++; engine.pre(); assert.equal(engine.pickupAttempt.attempts, 1);
  engine.dispose(); dom.window.close();
});

test('replacement bind instances get a fresh native pickup hook and old instance is restored', () => {
  const { dom, app, engine } = pickupFixture(); app.game.transmit(1, new JoinMsg()); engine.pre();
  const old = app.game.binds; app.game.binds = new Binds(app.input); engine.nextPickup = -Infinity;
  engine.reconcile(true); engine.pre();
  assert.equal(old.isBindPressed(10), false); assert.equal(app.game.binds.isBindPressed(10), true);
  engine.dispose(); dom.window.close();
});

test('pickup-mode select validates storage and updates config through the existing Misc tab', () => {
  assert.equal(normalizeConfig({ lootMode: 'invalid' }).lootMode, 'nearby');
  assert.equal(normalizeConfig({ lootMode: 'mobile' }).lootMode, 'mobile');
  const dom = env(), config = { ...DEFAULTS }, menu = createMenu(dom.window, config, { onChange() {}, retry() {}, stop() {}, diagnostics: () => ({}) });
  menu.capabilities({ sender: true });
  [...menu.root.querySelectorAll('.nav button')].find(b => b.textContent === 'Misc').click();
  const select = menu.root.querySelector('select'); assert.equal(select.value, 'nearby');
  select.value = 'mobile'; select.dispatchEvent(new dom.window.Event('change')); assert.equal(config.lootMode, 'mobile');
  menu.dispose(); dom.window.close();
});

test('Help offers a local selectable JSON fallback when clipboard access is unavailable', async () => {
  const dom = env(), menu = createMenu(dom.window, { ...DEFAULTS }, {
    onChange() {}, retry() {}, stop() {}, diagnostics: () => ({ captureState: 'captured', stats: { aimState: 'fire-not-held' } }),
  });
  [...menu.root.querySelectorAll('.nav button')].find(b => b.textContent === 'Help').click();
  [...menu.root.querySelectorAll('button')].find(b => b.textContent === 'Copy diagnostics').click();
  await Promise.resolve();
  const field = menu.root.querySelector('textarea'); assert.ok(field.readOnly);
  assert.equal(JSON.parse(field.value).stats.aimState, 'fire-not-held');
  assert.equal(field.selectionEnd, field.value.length);
  menu.dispose(); dom.window.close();
});

test('ESP native name colors honors filters and restores latest game writes when disabled', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, esp: true };
  const enemy = app.game.barn.playerPool.list[1]; enemy.nameText.text = 'fixture'; enemy.nameText.visible = true;
  const engine = new Features(dom.window, app, config, () => {}, defs);
  engine.attachCanvas(dom.window.document.createElement('canvas')); engine.post();
  assert.equal(enemy.nameText.visible, true); assert.equal(engine.stats.esp.enemy, 1);
  assert.equal(typeof Object.getOwnPropertyDescriptor(enemy.nameText, 'visible').get, 'function');
  enemy.nameText.visible = false; assert.equal(enemy.nameText.visible, true);
  assert.equal(enemy.nameText.style.fill, '#ff6262');
  enemy.nameText.visible = true; config.espShowEnemies = false; engine.lastVisual = -Infinity; engine.post();
  assert.equal(enemy.nameText.visible, true); assert.equal(engine.stats.esp.enemy, 0);
  config.espShowEnemies = true; engine.lastVisual = -Infinity; engine.post(); assert.equal(enemy.nameText.visible, true);
  config.esp = false; engine.lastVisual = -Infinity; engine.post();
  assert.equal(enemy.nameText.visible, true); assert.equal(engine.stats.esp.state, 'disabled');
  engine.dispose(); dom.window.close();
});

test('ESP rendering failures isolate Canvas error state without hiding native names', () => {
  const dom = env(), app = fixture(), engine = new Features(dom.window, app, { ...DEFAULTS, esp: true, lines: true }, () => {}, defs);
  const enemy = app.game.barn.playerPool.list[1]; enemy.nameText.visible = true;
  engine.attachCanvas(dom.window.document.createElement('canvas')); engine.ctx.stroke = () => { throw Error('canvas test'); };
  engine.guard('visual-frame', () => engine.post());
  assert.equal(enemy.nameText.visible, true); assert.equal(engine.stats.esp.state, 'error'); assert.equal(engine.overrides.records.size, 0);
  engine.dispose(); dom.window.close();
});

test('missing Canvas2D does not break input features or native colored names', () => {
  const dom = env(), app = fixture(), reports = [];
  app.input.mouseButtons[0] = true;
  const engine = new Features(dom.window, app, { ...DEFAULTS, esp: true, aim: true, predict: false, wallcheck: false }, (level, message) => reports.push({ level, message }), defs);
  engine.attachCanvas({ getContext() { throw Error('unsupported'); } });
  app.game.transmit(1, new JoinMsg()); engine.pre(); engine.post(); assert.equal(engine.stats.aimState, 'input-applied'); assert.equal(engine.stats.esp.state, 'no-canvas');
  assert.equal(app.game.barn.playerPool.list[1].nameText.visible, true);
  assert.ok(reports.some(r => r.level === 'warning')); engine.dispose(); dom.window.close();
});

test('ESP controls persist team filters and validated colors without changing tab layout', () => {
  const dom = env(), config = { ...DEFAULTS }, changes = [];
  const menu = createMenu(dom.window, config, { onChange(key) { changes.push(key); }, retry() {}, stop() {}, diagnostics: () => ({}) });
  menu.capabilities({ visuals: true, names: true });
  [...menu.root.querySelectorAll('.nav button')].find(b => b.textContent === 'Visuals').click();
  const row = [...menu.root.querySelectorAll('label')].find(n => n.textContent.includes('Allies (blue)'));
  row.querySelector('input').click(); assert.equal(config.espShowAllies, false);
  assert.equal(menu.root.querySelector('input[type=color]'), null, 'Names have fixed blue/red identity, no selected color');
  assert.ok(changes.includes('espShowAllies'));
  assert.deepEqual([...menu.root.querySelectorAll('.nav button')].map(b => b.textContent), ['Main', 'Visuals', 'Misc', 'Keybinds', 'Help']);
  menu.dispose(); const saved = JSON.parse(dom.window.localStorage.getItem(STORAGE_KEY));
  assert.equal(saved.espShowAllies, false); assert.equal(saved.espEnemyColor, DEFAULTS.espEnemyColor); dom.window.close();
});

test('ESP diagnostics contain aggregate counts only and reset on match exit', () => {
  const dom = env(), app = fixture(), engine = new Features(dom.window, app, { ...DEFAULTS, esp: true }, () => {}, defs);
  app.game.barn.playerPool.list[1].nameText.text = 'private-fixture-name';
  engine.attachCanvas(dom.window.document.createElement('canvas')); engine.post();
  const snapshot = engine.diagnostics(); assert.equal(snapshot.stats.esp.enemy, 1);
  assert.ok(!JSON.stringify(snapshot).includes('private-fixture-name')); assert.equal(snapshot.stats.esp.rows, undefined);
  app.game.initialized = false; engine.pre(); assert.equal(engine.stats.esp.enemy, 0);
  engine.dispose(); assert.equal(engine.espRenderer.widths.size, 0); dom.window.close();
});

test('held layer preview tracks native writes and restores on key release, blur, disable and dispose', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, layerSpoofer: true }, engine = new Features(dom.window, app, config, () => {}, defs);
  const hero = app.game.hero; hero.container.alpha = .8;
  dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', { code: 'KeyT' })); engine.pre();
  assert.equal(hero.layer, 1); assert.equal(hero.container.alpha, .5);
  hero.layer = 1; hero.container.alpha = .6; assert.equal(hero.layer, 0);
  dom.window.dispatchEvent(new dom.window.KeyboardEvent('keyup', { code: 'KeyT' })); assert.equal(hero.layer, 1); assert.equal(hero.container.alpha, .6);
  hero.layer = 0; dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', { code: 'KeyT' })); engine.pre();
  dom.window.dispatchEvent(new dom.window.Event('blur')); assert.equal(hero.layer, 0);
  dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', { code: 'KeyT' })); engine.pre(); config.layerSpoofer = false; engine.pre(); assert.equal(hero.layer, 0);
  config.layerSpoofer = true; engine.pre(); engine.dispose(); assert.equal(hero.layer, 0); assert.equal(hero.container.alpha, .6); dom.window.close();
});
test('layer key ignores typing and refuses unsupported layer descriptors', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, layerSpoofer: true }, engine = new Features(dom.window, app, config, () => {}, defs);
  const input = dom.window.document.createElement('input'); dom.window.document.body.append(input);
  input.dispatchEvent(new dom.window.KeyboardEvent('keydown', { code: 'KeyT', bubbles: true })); engine.pre(); assert.equal(app.game.hero.layer, 0);
  Object.defineProperty(app.game.hero, 'layer', { value: 0, writable: true, configurable: false });
  dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', { code: 'KeyT' })); engine.pre(); assert.equal(app.game.hero.layer, 0);
  engine.dispose(); dom.window.close();
});
test('Auto Melee selects melee slot only for a nearby enemy while Fire is held', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, melee: true, autoMelee: true, wallcheck: false, smoothEnabled: false };
  const localDefs = { ...defs, fists: { type: 'melee', attack: { cooldownTime: .25, offset: { x: 1.35, y: 0 }, rad: .9 } } };
  const engine = new Features(dom.window, app, config, () => {}, localDefs); app.game.transmit(1, new JoinMsg());
  engine.pre(); assert.equal(engine.switchSlot, null);
  app.input.mouseButtons[0] = true; engine.pre(); assert.equal(engine.switchSlot, 2); assert.ok(engine.meleeDirection);
  const native = new InputMsg(); app.game.transmit(3, native);
  assert.ok(app.game.sent.at(-1).data.inputs.includes(13)); assert.equal(native.inputs.length, 0);
  app.game.barn.playerPool.list[1].p = { x: 30, y: 20 }; engine.pre(); assert.equal(engine.switchSlot, null);
  engine.dispose(); dom.window.close();
});
test('all preview controls execute through Canvas with enemy filtering and source weapon direction', () => {
  const dom = env(), app = fixture(), config = { ...DEFAULTS, ownFlashlight: true, othersFlashlight: true, bulletTrajectory: true, grenadeTrajectory: true };
  const localDefs = { ...defs, frag: { type: 'throwable', throwPhysics: { speed: 20, velZ: 5 }, explosionType: 'explosion_frag' }, explosion_frag: { type: 'explosion', rad: { max: 13 } } };
  const engine = new Features(dom.window, app, config, () => {}, localDefs); engine.attachCanvas(dom.window.document.createElement('canvas')); app.game.transmit(1, new JoinMsg());
  engine.post(); assert.equal(engine.stats.previews.cones, 2); assert.equal(engine.stats.previews.bulletPaths, 1);
  app.game.hero.n.weapon = 'frag'; app.game.hero.l.index = 3; engine.lastVisual = -Infinity; engine.post();
  assert.equal(engine.stats.previews.throwPaths, 1);
  engine.dispose(); dom.window.close();
});
test('captureDefinitions can collect game and map registers in either order and restores its global hook', async () => {
  const dom = env(), win = dom.window, original = win.Object.keys, game = { mp5: { type: 'gun' }, bullet_mp5: { type: 'bullet' }, frag: { type: 'throwable' }, explosion_frag: { type: 'explosion' } };
  const map = { tree_01: { type: 'obstacle', collision: {}, reflectBullets: false }, stone_01: { type: 'obstacle', collision: {}, reflectBullets: true } };
  let foundGame, foundMap; const cancel = captureDefinitions(win, v => { foundGame = v; }, 1000, v => { foundMap = v; });
  win.Object.keys(map); assert.notEqual(win.Object.keys, original); win.Object.keys(game);
  await Promise.resolve(); assert.equal(foundGame, game); assert.equal(foundMap, map); assert.equal(win.Object.keys, original); cancel(); dom.window.close();
});

test('all restored feature settings are exposed as real validated controls, not placeholder hints', () => {
  const dom = env(), config = { ...DEFAULTS }, menu = createMenu(dom.window, config, {});
  const root = menu.host.shadowRoot, seen = new Set();
  for (const title of ['Main', 'Visuals', 'Misc']) {
    [...root.querySelectorAll('button')].find(button => button.textContent === title).click();
    for (const node of root.querySelectorAll('[data-config]')) seen.add(node.dataset.config);
  }
  for (const key of ['autoMelee', 'useOneGun', 'darkerSmokes', 'layerSpoofer', 'mapHighlights', 'smallerTrees', 'ownFlashlight', 'othersFlashlight', 'bulletTrajectory', 'grenadeZones', 'grenadeTrajectory', 'mobileMovement', 'movementSmooth', 'semi']) assert.ok(seen.has(key), key);
  const normalized = normalizeConfig({ layerKey: 'KeyY', movementSmooth: 1000, autoMelee: true, darkerSmokes: false, useOneGun: true });
  assert.equal(normalized.layerKey, 'KeyY'); assert.equal(normalized.movementSmooth, 100); assert.equal(normalized.useOneGun, true); assert.equal(normalized.darkerSmokes, false);
  menu.dispose(); dom.window.close();
});

// Final-output arbitration checks. Native scheduling/wire quantization is tested
// separately by scripts/check-upstream.mjs using extracted upstream methods.
function coordinated(config = {}) {
  const dom = env(), app = fixture(); let clock = 1000;
  Object.defineProperty(dom.window.performance, 'now', { value: () => clock, configurable: true });
  const cfg = { ...DEFAULTS, aim: true, predict: false, wallcheck: false, smoothEnabled: false, ...config };
  const engine = new Features(dom.window, app, cfg, () => {}, { ...defs, fists: { type: 'melee', attack: { offset: { x: 1.35, y: 0 }, rad: .9, cooldownTime: .25 } } });
  app.game.transmit(1, new JoinMsg()); app.input.mouseButtons[0] = true;
  const send = (inputs = []) => { engine.pre(); const native = new InputMsg(); native.toMouseLen = 1.25; native.shootHold = app.input.mouseButtons[0]; native.inputs = inputs; app.game.transmit(3, native); return { native, wire: app.game.sent.at(-1).data }; };
  return { dom, app, cfg, engine, send, advance(ms = 17) { clock += ms; }, close() { engine.dispose(); dom.window.close(); } };
}

test('Aim+Semi+Switch preserve physical Fire/movement and consume one equip; manual scopes do not cancel, slot swaps do', () => {
  const f = coordinated({ semi: true, autoSwitch: true });
  try {
    f.send(); f.app.input.flush(); f.advance(120);
    f.app.game.hero.l.weapons[0].ammo--;
    const { native, wire } = f.send([10]);
    assert.equal(wire.shootHold, true); assert.equal(wire.shootStart, native.shootStart);
    assert.equal(wire.moveRight, native.moveRight); assert.equal(wire.moveUp, native.moveUp);
    assert.ok(wire.inputs.includes(10)); assert.ok(wire.inputs.includes(12)); assert.deepEqual(native.inputs, [10]);
    f.advance(300); f.app.game.hero.l.weapons[0].ammo--; f.send([21]);
    assert.equal(f.engine.manualEquipHeld, false, 'Scope selection is not a weapon change');
    f.advance(300); f.app.game.hero.l.weapons[0].ammo--; const manual = f.send([28]);
    assert.deepEqual(manual.wire.inputs, [28]); assert.equal(f.engine.weaponSwitch.pending, null);
    assert.equal(f.engine.manualEquipHeld, true);
  } finally { f.close(); }
});

test('Melee wins equip/movement over Switch+Mobile, no repeated equip while awaiting confirmation, manual equip holds authority', () => {
  const f = coordinated({ melee: true, autoMelee: true, autoSwitch: true, mobileMovement: true });
  try {
    f.send(); f.app.game.hero.l.weapons[0].ammo--; f.advance();
    const { wire } = f.send();
    assert.ok(!wire.inputs.includes(12)); assert.equal(wire.touchMoveActive, true); assert.deepEqual(wire.touchMoveDir, { x: 1, y: 0 });
    assert.ok(!wire.inputs.includes(13), 'Already requested melee equip, await actual confirmation');
    assert.equal(f.engine.weaponSwitch.pending, null);
    f.advance(); const manual = f.send([12]); assert.deepEqual(manual.wire.inputs, [12]);
    f.advance(); const next = f.send(); assert.ok(!next.wire.inputs.includes(13), 'Do not fight manual equip while same Fire hold continues');
    f.app.input.mouseButtons[0] = false; f.send(); assert.equal(f.engine.manualEquipHeld, false);
    f.app.input.mouseButtons[0] = true; f.advance(); assert.ok(f.send().wire.inputs.includes(13));
  } finally { f.close(); }
});

test('Aim+Zoom+ESP+XRay share source layer and input; visual exception never blocks subsequent sender', () => {
  const f = coordinated({ zoom: true, esp: true, lines: true, xray: true, layerSpoofer: true });
  try {
    f.engine.attachCanvas(f.dom.window.document.createElement('canvas')); f.engine.post();
    assert.equal(f.app.game.hero.l.zoom, 72);
    f.dom.window.dispatchEvent(new f.dom.window.KeyboardEvent('keydown', { code: 'KeyT' }));
    const { wire } = f.send(); assert.deepEqual(wire.toMouseDir, { x: 1, y: 0 });
    assert.equal(f.app.game.hero.layer, 1); assert.equal(f.engine.sourceLayer(f.app.game.hero), 0);
    f.engine.ctx.stroke = () => { throw Error('preview only'); }; f.engine.lastVisual = -Infinity;
    f.engine.guard('visual-frame', () => f.engine.post()); assert.ok(f.engine.failed.has('overlay-render'));
    assert.equal(f.app.game.hero.l.zoom,72,'Canvas fault does not revoke zoom');
    assert.equal(f.app.game.barn.playerPool.list[1].nameText.style.fill,'#ff6262','Names independent of Canvas');
    f.advance(); assert.deepEqual(f.send().wire.toMouseDir, { x: 1, y: 0 }); assert.equal(f.engine.stats.aimState, 'input-applied');
    assert.ok(!f.engine.failed.has('input-frame'));
  } finally { f.close(); }
});

test('Fire/key/both activation, blur/typing/emote/death pause automation without rewriting native Fire', () => {
  const f = coordinated({ aimActivation: 'both', semi: true, mobileMovement: true });
  try {
    f.send(); assert.equal(f.engine.stats.aimState, 'waiting-activation');
    f.engine.holdAim = true; f.send(); assert.equal(f.engine.stats.aimState, 'input-applied');
    f.dom.window.dispatchEvent(new f.dom.window.Event('blur')); f.advance();
    let result = f.send(); assert.equal(result.wire, result.native); assert.equal(result.wire.shootHold, true);
    f.dom.window.dispatchEvent(new f.dom.window.Event('focus')); f.engine.holdAim = true;
    const input = f.dom.window.document.createElement('input'); f.dom.window.document.body.append(input); input.focus();
    f.advance(); result = f.send(); assert.equal(result.wire, result.native); input.blur();
    f.app.game.emotes = { wheelDisplayed: true }; f.advance(); result = f.send(); assert.equal(result.wire, result.native);
    f.app.game.emotes.wheelDisplayed = false; f.app.game.hero.n.dead = true; f.advance(); result = f.send(); assert.equal(result.wire, result.native);
    assert.equal(f.engine.aimController.time, null); assert.equal(f.engine.weaponSwitch.pending, null);
  } finally { f.close(); }
});

test('Snapshot boundary samples only position-bearing updated IDs, invalidates delete/reuse and never samples render frames', () => {
  const f = coordinated();
  try {
    f.engine.pre(); const enemy = f.app.game.barn.playerPool.list[1]; enemy.n.sourcePos = { ...enemy.p };
    f.engine.sourceFields = { pos: 'sourcePos' };
    f.engine.observeUpdate({ ack: 0, fullObjects: [], partObjects: [{ __id: 2, dir: { x: 1, y: 0 } }], delObjIds: [] });
    assert.equal(f.engine.tracker.states.get(enemy), undefined);
    f.engine.observeUpdate({ ack: 0, fullObjects: [], partObjects: [{ __id: 2, pos: enemy.n.sourcePos }], delObjIds: [] });
    assert.deepEqual(f.engine.tracker.states.get(enemy).pos, enemy.p);
    const time = f.engine.tracker.states.get(enemy).time; f.advance(); f.engine.pre();
    assert.equal(f.engine.tracker.states.get(enemy).time, time);
    f.engine.observeUpdate({ ack: 0, fullObjects: [], partObjects: [], delObjIds: [2] });
    assert.equal(f.engine.tracker.states.get(enemy), undefined);
    enemy.__id = 99; assert.equal(f.engine.tracker.estimate(enemy, time), null);
  } finally { f.close(); }
});

test('Mode groups are conditional; range adjustment keeps focus/DOM and open state, legacy tags never surface', () => {
  const dom = env(), config = { ...DEFAULTS, aim: true, aimMode: 'assist' };
  const menu = createMenu(dom.window, config, { retry() {}, stop() {}, diagnostics: () => ({}) });
  try {
    menu.capabilities({ aim: true, prediction: true });
    assert.ok(menu.root.querySelector('[data-config=assistStrength]')); assert.equal(menu.root.querySelector('[data-config=smooth]'), null);
    const slider = menu.root.querySelector('[data-config=assistStrength]'); slider.focus(); slider.value = 55; slider.dispatchEvent(new dom.window.Event('input'));
    assert.equal(menu.root.activeElement, slider); assert.equal(menu.root.querySelector('[data-config=assistStrength]'), slider); assert.equal(config.assistStrength, 55);
    const details = slider.closest('details'); details.open = true; details.dispatchEvent(new dom.window.Event('toggle'));
    const mode = menu.root.querySelector('[data-config=aimMode]'); mode.value = 'lock'; mode.dispatchEvent(new dom.window.Event('change'));
    assert.equal(menu.root.querySelector('[data-config=assistStrength]'), null); assert.ok(menu.root.querySelector('[data-config=smooth]')); assert.equal(menu.root.querySelector('details').open, true);
    mode.value = 'off'; // old disconnected control must not be used after rerender
    const currentMode = menu.root.querySelector('[data-config=aimMode]'); currentMode.value = 'off'; currentMode.dispatchEvent(new dom.window.Event('change')); assert.equal(config.aim, false);
    assert.ok(!/SQUAD|ENEMY|legend/.test(menu.root.querySelector('#ui').textContent));
  } finally { menu.dispose(); dom.window.close(); }
});

test('Final configuration is equivalent across unrelated visual toggle orders; sticky survives nearest-target crossover', () => {
  const outputs = [];
  for (const order of [['esp', 'xray', 'zoom'], ['zoom', 'esp', 'xray']]) {
    const f = coordinated({ sticky: true });
    try {
      f.engine.attachCanvas(f.dom.window.document.createElement('canvas'));
      const second = new Player(3, { x: 12, y: 20.2 });
      f.app.game.barn.playerPool.list.push(second); f.app.game.barn.teamInfo[20].playerIds.push(3);
      for (const key of order) { f.cfg[key] = true; f.engine.configurationChanged(key); f.engine.post(); }
      f.send(); const target = f.engine.target;
      second.p = { x: 11.25, y: 20 }; f.advance();
      const result = f.send(); assert.equal(f.engine.target, target, 'Sticky does not churn merely because another enemy becomes nearer to physical cursor');
      outputs.push({ dir: result.wire.toMouseDir, zoom: f.app.game.hero.l.zoom, name: target.nameText.style.fill, targetId: target.__id });
      f.cfg.esp = false; f.engine.lastVisual = -Infinity; f.engine.post();
      assert.equal(f.app.game.hero.l.zoom, 72, 'Disabling names does not clear unrelated zoom');
    } finally { f.close(); }
  }
  assert.deepEqual(outputs[0], outputs[1]);
});

test('native ESP survives missing aim/camera schema and legacy hidden name setting, with observable applied counts', () => {
  const f = coordinated({ esp: true, nametags: false });
  try {
    f.app.game.hero.selectIdlePose = function () { return 1; }; f.app.game.camera.forward = function () { return null; }; f.engine.reconcile(true);
    assert.equal(f.engine.capabilities.visuals, false); assert.equal(f.engine.capabilities.names, true);
    f.engine.post();
    const enemy = f.app.game.barn.playerPool.list[1];
    assert.equal(enemy.nameText.visible, true); assert.equal(enemy.nameText.style.fill, '#ff6262');
    assert.equal(f.engine.diagnostics().nativeNames.colored, 1); assert.equal(f.engine.diagnostics().nativeNames.state, 'native-names-active');
  } finally { f.close(); }
});

test('basic aim still reaches outgoing clone without optional prediction contract/definitions; non-gun and protocol guards remain', () => {
  const f = coordinated({ predict: true });
  try {
    f.engine.definitions = null; f.engine.reconcile(true);
    const enemy = f.app.game.barn.playerPool.list[1]; enemy.p = { x: 12, y: 20.4 };
    let result = f.send();
    assert.equal(f.engine.stats.aimState, 'input-applied'); assert.equal(f.engine.stats.predictionState, 'direct-missing-definitions');
    assert.ok(result.wire.toMouseDir.y > .19); assert.equal(result.native.toMouseDir.y, 0);
    assert.equal(result.wire.shootHold, true); assert.equal(result.wire.moveRight, result.native.moveRight);
    f.engine.definitions = defs; f.engine.reconcile(true); f.advance(); result = f.send();
    assert.equal(f.engine.stats.predictionState, 'direct-prediction-unavailable'); assert.ok(result.wire.toMouseDir.y > .19);
    f.app.game.hero.l.index = 3; f.app.game.hero.n.weapon = 'frag'; f.advance(); result = f.send();
    assert.equal(f.engine.stats.aimState, 'unsupported-weapon-profile'); assert.deepEqual(result.wire.toMouseDir, result.native.toMouseDir);
    f.engine.protocol = VERIFIED_PROTOCOL + 1; f.advance(); result = f.send();
    assert.equal(f.engine.stats.aimState, 'unsupported-protocol'); assert.equal(result.wire, result.native);
  } finally { f.close(); }
});

test('Aim helpers live in Main; menu key closes focused settings and gameplay aim resumes after hide', () => {
  const f = coordinated({ aimMode: 'assist', assistStrength: 35 });
  const menu = createMenu(f.dom.window, f.cfg, { onChange: key => f.engine.configurationChanged(key), retry() {}, stop() {}, diagnostics: () => ({}) });
  try {
    menu.capabilities({ aim: true, names: true });
    assert.ok(menu.root.querySelector('[data-config=showFov]')); assert.ok(menu.root.querySelector('[data-config=showDot]'));
    const slider = menu.root.querySelector('[data-config=assistStrength]'); slider.focus(); f.send();
    assert.equal(f.engine.stats.aimState, 'menu-open');
    slider.dispatchEvent(new f.dom.window.KeyboardEvent('keydown', { code: f.cfg.menuKey, bubbles: true, composed: true }));
    assert.equal(menu.root.querySelector('#ui').hidden, true); assert.notEqual(menu.root.activeElement, slider);
    f.advance(); f.send(); assert.equal(f.engine.stats.aimState, 'input-applied');
    [...menu.root.querySelectorAll('.nav button')].find(b => b.textContent === 'Visuals').click();
    assert.equal(menu.root.querySelector('[data-config=assistStrength]'), null); assert.equal(menu.root.querySelector('[data-config=showFov]'), null);
    assert.ok(menu.root.querySelector('[data-config=esp]'));
  } finally { menu.dispose(); f.close(); }
});

test('missing wallcheck contract cannot trap saved enabled control: user can turn it off without disabling native guards', () => {
  const dom = env(), config = { ...DEFAULTS, aim: true, wallcheck: true };
  const menu = createMenu(dom.window, config, { retry() {}, stop() {}, diagnostics: () => ({}) });
  try {
    menu.capabilities({ aim: true, wallcheck: false });
    const wall = menu.root.querySelector('[data-config=wallcheck]');
    assert.equal(wall.checked, true); assert.equal(wall.disabled, false);
    wall.click(); assert.equal(config.wallcheck, false); assert.equal(wall.disabled, true);
  } finally { menu.dispose(); dom.window.close(); }
});

test('diagnostics distinguish current dead/menu state from live Lock forwards, including wallcheck block before registry recovery', () => {
  const f = coordinated({ wallcheck: true });
  try {
    f.send(); assert.equal(f.engine.stats.aimState, 'wallcheck-unavailable');
    f.app.game.hero.n.dead = true; f.advance(); f.send();
    let d = f.engine.diagnostics(); assert.equal(d.inputBlockReason, 'dead');
    assert.equal(d.aimEvidence.lastLiveAttempt.state, 'wallcheck-unavailable');
    assert.equal(d.aimEvidence.lastLiveAttempt.wallcheckRequested, true); assert.equal(d.aimEvidence.lastCorrection, null);
    const enemy = f.app.game.barn.playerPool.list[1]; enemy.p = { x: 12, y: 20.4 };
    f.app.game.creator = { table: { 1: f.app.game.hero, 2: enemy }, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } };
    f.app.game.mirror = { cache: { 2: enemy } };
    f.app.game.hero.n.dead = false; f.engine.reconcile(true); f.advance(); f.send();
    d = f.engine.diagnostics(); assert.equal(d.capabilities.wallcheck, true); assert.equal(d.checks.objectRegistry, true);
    assert.equal(d.registry.state, 'native-id-table'); assert.equal(d.aimEvidence.lastLiveAttempt.state, 'input-applied');
    assert.ok(d.aimEvidence.lastCorrection.correctionDegrees > 10); assert.equal(d.aimEvidence.lastCorrection.firePreserved, true);
    f.app.game.hero.n.dead = true; f.advance(100); f.send(); d = f.engine.diagnostics();
    assert.equal(d.stats.aimState, 'dead'); assert.equal(d.aimEvidence.lastLiveAttempt.state, 'input-applied');
    assert.ok(d.aimEvidence.lastCorrection.correctionDegrees > 10); assert.ok(d.aimEvidence.lastCorrection.ageMs >= 100);
    assert.equal(d.checks.objectRegistry, true);
  } finally { f.close(); }
});

test('far map objects cannot exhaust wallcheck or hide a nearby blocker beyond the old first-1024 slice', () => {
  const f = coordinated({ wallcheck: true });
  try {
    const table = {};
    for (let i = 0; i < 1100; i++) table[i + 10] = { __id: i + 10, __type: 2, active: true, collidable: true, dead: false, layer: 0, height: 1,
      collider: { type: 0, pos: { x: 500 + i, y: 500 }, rad: 1 } };
    f.app.game.creator = { table, get(id) { return this.table[id]; }, remove(id) { delete this.table[id]; } };
    f.engine.reconcile(true); f.send(); assert.equal(f.engine.stats.aimState, 'input-applied');
    table[9999] = { __id: 9999, __type: 2, active: true, collidable: true, dead: false, layer: 0, height: 1,
      collider: { type: 0, pos: { x: 11, y: 20 }, rad: .3 } };
    f.advance(); f.send(); assert.equal(f.engine.stats.aimRejections.wall, 1);
  } finally { f.close(); }
});
