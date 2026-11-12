import { aimPoint, ast, at, clamp, discover, discoverLootSource, discoverSender, Disposables, entries, finite, intercept, isPlayer,
  localWeapon, methods, object, overlayPosition, patchMethod, paths, point, project, read, readMethod, sameLayer,
  segmentBlocked, teamRelations, Tracker, unique, vec, walk } from './core.mjs';

import { buildEspFrame, emptyEspStats, EspRenderer, prepareOverlay } from './esp.mjs';
import { discoverSmokeSources, emptyXrayStats, smokeAlpha, smokeParticles } from './effects.mjs';
import { RepeatFire } from './repeat-fire.mjs';
import { MapHighlights } from './map-highlights.mjs';
import { WeaponSwitch } from './weapon-switch.mjs';
import { MovementSmoother, throwPreview, traceShot } from './previews.mjs';

export const VERIFIED_PROTOCOL = 1028;
export const equipInput = slot => Number.isInteger(slot) && slot >= 0 && slot <= 3 ? 11 + slot : null;
export function meleeReach(def) {
  const attack = def?.attack;
  return def?.type === 'melee' && vec(attack?.offset) && finite(attack?.rad) && attack.rad > 0
    ? Math.hypot(attack.offset.x, attack.offset.y) + attack.rad + 1 : null;
}
// Constants tied to the audited protocol; never apply enum/height assumptions to unknown Join versions.
const PROJECTILE_TYPE = 9;
const BULLET_HEIGHT = .25;
export function grenadeZone(entity, definitions, layer, protocol) {
  if (protocol !== VERIFIED_PROTOCOL || read(entity, '__type') !== PROJECTILE_TYPE || read(entity, 'active') !== true) return null;
  const def = definitions?.[read(entity, 'type')];
  if (def?.type !== 'throwable' || !def.explosionType || def.explosionType === 'explosion_smoke') return null;
  const explosion = definitions[def.explosionType], pos = read(entity, 'pos');
  if (explosion?.type !== 'explosion' || !finite(explosion?.rad?.max) || explosion.rad.max <= 0
    || !vec(pos) || !sameLayer(read(entity, 'layer'), layer)) return null;
  // Nominal radial preview only: no remaining fuse, future landing point, occlusion or shrapnel claim.
  return { pos, radius: explosion.rad.max };
}

export function localDataSchema(game, player) {
  const candidates = [];
  for (const [, child] of entries(game)) {
    const tree = ast(readMethod(child, 'getAimMovement'));
    const root = tree?.params?.[0]?.name;
    if (!root) continue;
    for (const p of paths(tree, root)) {
      if (p.length !== 2 || !Number.isInteger(at(player, p)) || at(player, p) < 0 || at(player, p) > 3) continue;
      const data = read(player, p[0]);
      const weapons = entries(data).filter(([, v]) => Array.isArray(v) && v.length >= 4 && v.every(w => typeof read(w, 'type') === 'string' && finite(read(w, 'ammo'))));
      if (weapons.length !== 1) continue;
      const zoomKeys = [];
      for (const [, fn] of methods(player)) {
        const tree = ast(fn);
        let indexOf = false;
        walk(tree, n => { if (n.type === 'MemberExpression' && n.property?.name === 'indexOf') indexOf = true; });
        if (indexOf) for (const q of paths(tree)) if (q.length === 2 && q[0] === p[0] && finite(at(player, q))) zoomKeys.push(q[1]);
      }
      candidates.push({ data, dataKey: p[0], slotKey: p[1], weaponsKey: weapons[0][0], zoomKey: unique(zoomKeys) });
    }
  }
  return candidates.length === 1 ? candidates[0] : null;
}

// Own data descriptors only. Game setters keep updating raw state while a visual override is active.
// Cleanup restores the latest game value, not a stale first-frame snapshot.
export class Overrides {
  records = new Map();
  owned = new WeakMap();
  getRaw(owner, key) { return this.owned.get(owner)?.get(key)?.raw ?? read(owner, key); }
  set(owner, key, transform) {
    let keys = this.owned.get(owner);
    if (keys?.has(key)) { keys.get(key).transform = transform; return true; }
    const d = Object.getOwnPropertyDescriptor(owner, key);
    if (!d || !('value' in d) || !d.configurable || !d.writable) return false;
    const record = { owner, key, descriptor: d, raw: d.value, transform };
    record.get = () => record.transform(record.raw);
    record.set = value => { record.raw = value; };
    try { Object.defineProperty(owner, key, { configurable: true, enumerable: d.enumerable, get: record.get, set: record.set }); }
    catch { return false; }
    if (!keys) this.owned.set(owner, keys = new Map());
    keys.set(key, record); this.records.set(record, record); return true;
  }
  release(owner, key) {
    const r = this.owned.get(owner)?.get(key);
    if (!r) return;
    const now = Object.getOwnPropertyDescriptor(owner, key);
    if (now?.get === r.get && now?.set === r.set) Object.defineProperty(owner, key, { ...r.descriptor, value: r.raw });
    this.owned.get(owner).delete(key); this.records.delete(r);
  }
  prune(keep) { for (const r of this.records.values()) if (!keep(r.owner, r.key)) this.release(r.owner, r.key); }
  clear() { this.prune(() => false); }
}

export function inputShape(data) {
  return object(data) && typeof data.shootStart === 'boolean' && typeof data.shootHold === 'boolean'
    && ['moveLeft', 'moveRight', 'moveUp', 'moveDown', 'touchMoveActive'].every(k => typeof data[k] === 'boolean')
    && vec(data.toMouseDir) && vec(data.touchMoveDir) && finite(data.toMouseLen)
    && Array.isArray(data.inputs) && data.inputs.length <= 7 && data.inputs.every(Number.isInteger)
    && typeof data.serialize === 'function' && typeof data.addInput === 'function';
}
export function modifyMessage(data, config, context) {
  if (!inputShape(data) || context.protocol !== VERIFIED_PROTOCOL) return data;
  const copy = Object.assign(Object.create(Object.getPrototypeOf(data)), data, {
    inputs: [...data.inputs], touchMoveDir: point(data.touchMoveDir), toMouseDir: point(data.toMouseDir),
  });
  if (config.mobileMovement) {
    const x = Number(data.moveRight) - Number(data.moveLeft), y = Number(data.moveUp) - Number(data.moveDown);
    const len = Math.hypot(x, y);
    if (len) { copy.touchMoveActive = true; copy.touchMoveLen = 255; copy.touchMoveDir = vec(context.moveDirection) ? point(context.moveDirection) : { x: x / len, y: y / len }; }
  }
  if (config.melee && context.meleeDirection && vec(context.meleeDirection)) {
    copy.touchMoveActive = true; copy.touchMoveLen = 255; copy.touchMoveDir = point(context.meleeDirection);
  }
  const equip = equipInput(context.switchSlot);
  if (equip !== null) copy.addInput(equip);
  return copy;
}

export class Features {
  constructor(win, app, config, report, definitions = null) {
    this.win = win; this.app = app; this.config = config; this.report = report; this.definitions = definitions;
    this.hooks = new Disposables(); this.matchHooks = new Disposables(); this.overrides = new Overrides();
    this.tracker = new Tracker(); this.protocol = null; this.mapping = null; this.local = null;
    this.target = null; this.dot = null; this.restoreMouse = null; this.lastMap = -Infinity;
    this.lastVisual = -Infinity; this.lastInput = -Infinity; this.lastScan = -Infinity;
    this.effects = []; this.lastGame = null; this.lastPool = null; this.lastActive = null; this.lastActiveId = null;
    this.stopped = false; this.keys = new Set(); this.holdAim = false;
    this.movement = new MovementSmoother(); this.weaponSwitch = new WeaponSwitch(); this.layerOverrides = new Overrides(); this.layerHeld = false;
    this.repeatFire = new RepeatFire(); this.frameId = 0; this.switchSlot = null; this.meleeDirection = null;
    this.stats = { frames: 0, mappingRuns: 0, featureMs: 0, lastError: null, aimState: 'disabled', aimRejections: {} };
    this.joinState = { observed: false, forwarded: false, mobile: null, requested: false };
    this.capabilities = {}; this.failed = new Set();
    this.lootSource = null; this.pickupPulse = false; this.nextPickup = 0; this.pickupAttempt = null;
    this.stats.lootState = 'disabled'; this.stats.pickupPulses = 0;
    this.espRenderer = new EspRenderer(); this.stats.esp = emptyEspStats();
    this.smokeSources = []; this.stats.xray = emptyXrayStats(); this.stats.semi = { state: 'disabled', pulses: 0 };
    this.mapHighlights = new MapHighlights(config, report);
    this.installFlush();
    const ticker = app.pixi.ticker;
    const pre = () => this.guard('input-frame', () => this.pre());
    const post = () => this.guard('visual-frame', () => this.post());
    ticker.add(pre, null, 10); ticker.add(post, null, -20);
    this.hooks.add(() => ticker.remove(pre, null)); this.hooks.add(() => ticker.remove(post, null));
    const controller = new win.AbortController(); this.hooks.add(() => controller.abort());
    const releaseLayer = () => { this.layerHeld = false; this.layerOverrides.clear(); };
    win.addEventListener('keydown', event => {
      if (event.repeat || event.defaultPrevented || event.composedPath().some(n => ['INPUT', 'TEXTAREA', 'SELECT'].includes(n.tagName) || n.isContentEditable)) return;
      if (event.code === this.config.layerKey && this.config.layerSpoofer) this.layerHeld = true;
    }, { signal: controller.signal });
    win.addEventListener('keyup', event => { if (event.code === this.config.layerKey) releaseLayer(); }, { signal: controller.signal });
    win.addEventListener('blur', releaseLayer, { signal: controller.signal });
    win.document.addEventListener('visibilitychange', () => { if (win.document.hidden) releaseLayer(); }, { signal: controller.signal });
    this.reconcile(true);
  }
  guard(name, fn) {
    if (this.stopped || this.failed.has(name)) return;
    try { fn(); }
    catch (e) {
      this.failed.add(name); this.stats.lastError = `${name}: ${e.message}`;
      if (name === 'visual-frame') this.stats.esp = emptyEspStats('error');
      this.restoreInput(); this.overrides.clear(); this.layerOverrides.clear(); this.clearCanvas();
      this.report('error', this.stats.lastError);
    }
  }
  installFlush() {
    if (!this.app.input || !patchMethod(this.app.input, 'flush', original => {
      const self = this;
      return function () {
        self.restoreInput(); // Restore BEFORE native flush captures old state.
        return Reflect.apply(original, this, arguments);
      };
    }, this.hooks)) this.report('warning', 'Không có flush contract: aim input bị khóa.');
    else this.flushReady = true;
  }
  restoreInput() {
    if (this.restoreMouse) {
      const { owner, x, y } = this.restoreMouse;
      // Only undo values still owned by this frame; don't clobber a later writer.
      if (owner.x === this.restoreMouse.appliedX) owner.x = x;
      if (owner.y === this.restoreMouse.appliedY) owner.y = y;
      this.restoreMouse = null;
    }
  }
  releaseMatch() {
    this.restoreInput(); this.matchHooks.clear(); this.overrides.clear(); this.tracker.reset();
    this.target = null; this.dot = null; this.meleeDirection = null; this.switchSlot = null;
    this.local = null; this.mapping = null; this.effects = [];
    this.lootSource = null; this.pickupPulse = false; this.pickupAttempt = null; this.nextPickup = 0;
    this.binds = null; this.bindsInstalled = false; this.stickyId = null; this.lastInput = -Infinity;
    this.repeatFire.reset(); this.movement.reset(); this.weaponSwitch.reset(); this.layerOverrides.clear(); this.layerHeld = false; this.mapHighlights.dispose(); this.smokeSources = []; this.stats.xray = emptyXrayStats('waiting-contract');
    this.espRenderer.reset(); this.stats.esp = emptyEspStats('waiting-mapping'); this.stats.semi = { state: 'waiting-contract', pulses: this.repeatFire.pulses }; this.stats.switchState = 'waiting-contract'; this.stats.layerState = 'disabled'; this.stats.previews = { cones: 0, bulletPaths: 0, throwPaths: 0, unsupportedColliders: 0 };
    this.clearCanvas();
  }
  installSender(game) {
    const key = discoverSender(game);
    this.senderReady = false;
    if (!key) return;
    const self = this;
    this.senderReady = patchMethod(game, key, original => function (type, data, ...rest) {
      let outgoing = data, joinRecord = null;
      try {
        if (type === 1 && Number.isInteger(data?.protocol) && typeof data.name === 'string'
          && typeof data.joinToken === 'string' && (typeof data.isMobile === 'boolean' || data.isMobile === undefined)
          && typeof data.useTouch === 'boolean' && typeof data.serialize === 'function') {
          self.protocol = data.protocol; self.lastMap = -Infinity;
          if (self.protocol === VERIFIED_PROTOCOL && self.config.autoLoot && self.config.lootMode === 'mobile') {
            outgoing = Object.assign(Object.create(Object.getPrototypeOf(data)), data, { isMobile: true });
          }
          joinRecord = { observed: true, forwarded: false, mobile: !!outgoing.isMobile, requested: !!self.config.autoLoot && self.config.lootMode === 'mobile' };
          self.joinState = joinRecord;
          self.report('protocol', `Join protocol ${self.protocol}; mobile loot ${self.config.autoLoot && self.config.lootMode === 'mobile' ? 'yêu cầu bật' : 'tắt'}.`);
        }
        if (type === 3 && !self.stopped && self.mapping?.ui?.spectating === false) {
          self.moveDirection = self.config.mobileMovement && inputShape(data) ? self.movement.sample(data, self.config.movementSmooth, self.win.performance.now()) : null;
          if (!self.config.mobileMovement) self.movement.reset();
          outgoing = modifyMessage(data, self.config, self);
          self.switchSlot = null;
        }
      } catch (e) { self.report('warning', `Input bypassed: ${e.message}`); outgoing = data; }
      const result = Reflect.apply(original, this, [type, outgoing, ...rest]);
      if (joinRecord) joinRecord.forwarded = true; // Forwarded to native sender; not a server acknowledgement.
      return result;
    }, this.gameHooks);
  }
  reconcile(force = false) {
    const now = this.win.performance.now(), game = this.app.game;
    if (game !== this.lastGame) {
      this.releaseMatch(); this.gameHooks?.clear(); this.gameHooks = new Disposables();
      this.lastGame = game; this.protocol = null; this.lastPool = null; this.lastActive = null;
      this.joinState = { observed: false, forwarded: false, mobile: null, requested: false };
      if (game) this.installSender(game);
    }
    if (!game?.initialized) {
      if (this.mapping) this.releaseMatch();
      this.capabilities = { sender: this.senderReady, visuals: false };
      return;
    }
    // Boot/rejoin is immediate; stable discovery is throttled, never per player/per frame.
    if (!force && now - this.lastMap < 1000 && this.mapping) return;
    this.lastMap = now; this.stats.mappingRuns++;
    const next = discover(game);
    if (next.pool !== this.lastPool || next.active !== this.lastActive || next.active?.__id !== this.lastActiveId) {
      this.releaseMatch(); this.failed.clear();
      this.lastPool = next.pool; this.lastActive = next.active; this.lastActiveId = next.active?.__id;
    }
    this.mapping = next;
    this.mapHighlights.sync(game, next.map);
    if (next.active && !this.local) this.local = localDataSchema(game, next.active);
    const nextBinds = this.findBinds();
    if (this.binds && this.binds !== nextBinds) {
      this.matchHooks.clear(); this.bindsInstalled = false;
      this.repeatFire.reset();
    }
    this.binds = nextBinds;
    this.lootSource = discoverLootSource(game);
    this.smokeSources = discoverSmokeSources(game);
    const ready = !!(next.schema && next.camera && next.barn && next.pool && next.active?.active);
    this.capabilities = {
      visuals: ready, interpolatedOverlay: ready && !!next.visualPosKey,
      grenadeZones: ready && !!this.definitions && !!next.registryKey && this.protocol === VERIFIED_PROTOCOL, aim: ready && this.flushReady && !!next.ui,
      autoPickup: ready && !!next.ui && !!this.lootSource && !!this.binds && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
      previews: ready && !!this.definitions && this.protocol === VERIFIED_PROTOCOL, prediction: ready && !!this.definitions, wallcheck: !!next.creator && !!next.registryKey,
      xray: !!next.map || this.smokeSources.length > 0, mapHighlights: this.mapHighlights.available, layer: ready && [0, 1].includes(this.layerOverrides.getRaw(next.active, 'layer')),
      zoom: !!this.local?.zoomKey, semi: !!this.binds && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
      sender: this.senderReady, mobile: this.senderReady && this.protocol === VERIFIED_PROTOCOL,
      switch: !!this.local && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
    };
    if (!this.bindsInstalled && this.capabilities.semi) this.installSemi();
    this.report('mapping', ready ? 'Mapping hợp lệ; tính năng thiếu contract sẽ bị khóa.' : 'Chờ player/camera contract hoặc build chưa tương thích.');
  }
  findBinds() {
    return unique(entries(this.app.game).filter(([, o]) => typeof readMethod(o, 'isBindDown') === 'function'
      && typeof readMethod(o, 'isBindPressed') === 'function' && object(read(o, 'input'))).map(([, o]) => o));
  }
  installSemi() {
    const binds = this.binds;
    if (!binds) return;
    const self = this;
    this.bindsInstalled = patchMethod(binds, 'isBindPressed', original => function (code) {
      const actual = Reflect.apply(original, this, arguments);
      if (code === 10 && self.pickupPulse && !self.stopped && !self.failed.has('input-frame')
        && self.config.autoLoot && self.config.lootMode === 'nearby' && self.protocol === VERIFIED_PROTOCOL
        && self.mapping?.ui?.spectating === false && !self.win.document.hidden) return true;
      if (self.protocol === VERIFIED_PROTOCOL && (self.config.autoSwitch || self.config.melee && self.config.autoMelee) && self.switchSlot !== null
        && self.mapping?.ui?.spectating === false && code === equipInput(self.switchSlot)) return true;
      if (code !== 4) return actual;
      const m = self.mapping, weapon = localWeapon(m), def = self.definitions?.[weapon];
      const pulse = self.repeatFire.sample({ frame: self.frameId, now: self.win.performance.now(), weapon, def,
        held: !!this.isBindDown(4), enabled: self.config.semi, protocolMatches: self.protocol === VERIFIED_PROTOCOL,
        paused: self.stopped || self.failed.has('input-frame') || self.win.document.hidden || !m?.active?.active
          || !m.schema || m.ui?.spectating !== false || m.active.downed === true || !!at(m.active, [m.schema.netKey, m.schema.deadKey]),
      });
      self.stats.semi = { state: self.repeatFire.state, pulses: self.repeatFire.pulses };
      return actual || pulse;
    }, this.matchHooks);
    if (this.bindsInstalled) this.matchHooks.add(() => { this.bindsInstalled = false; });
  }
  blocked(from, to, bulletPath = true) {
    if (!this.config.wallcheck) return false;
    if (!this.capabilities.wallcheck) return true;
    return this.mapping.obstacles().some(o => !read(o, 'dead') && read(o, 'collidable')
      && !(bulletPath && this.protocol === VERIFIED_PROTOCOL && finite(read(o, 'height')) && read(o, 'height') < BULLET_HEIGHT)
      && (!finite(read(o, 'layer')) || sameLayer(read(o, 'layer'), from.layer)) && segmentBlocked(from.pos, to.pos, read(o, 'collider')));
  }
  pre() {
    this.frameId++;
    this.restoreInput();
    const staleIdentity = this.mapping && (read(this.app.game, this.mapping.barnKey) !== this.mapping.barn
      || read(this.mapping.barn, 'playerPool') !== this.mapping.pool
      || (this.mapping.activeKey && read(this.app.game, this.mapping.activeKey) !== this.mapping.active)
      || (this.mapping.active && this.mapping.active.__id !== this.lastActiveId)
      || (this.local && this.mapping.active[this.local.dataKey] !== this.local.data));
    if (staleIdentity) { this.releaseMatch(); this.lastActive = null; }
    this.reconcile(!!staleIdentity);
    this.updateLayer();
    this.updateLoot();
    const m = this.mapping, cfg = this.config;
    this.target = null; this.dot = null; this.meleeDirection = null; this.switchSlot = null;
    this.stats.aimRejections = {};
    this.stats.aimState = cfg.aim || cfg.melee ? 'waiting-mapping' : 'disabled';
    if (!cfg.aim && !cfg.melee && !cfg.autoSwitch) return;
    if (!m?.schema || !m.active?.active) return;
    if (m.ui?.spectating !== false) { this.stats.aimState = m.ui ? 'spectating' : 'missing-spectator-contract'; return; }
    if (this.win.document.hidden) { this.stats.aimState = 'page-hidden'; return; }
    const now = this.win.performance.now(), self = m.active, schema = m.schema;
    const pos = read(self, schema.posKey), mouse = this.app.input?.mousePos;
    if (!vec(pos) || !vec(mouse)) { this.stats.aimState = 'invalid-input-position'; return; }
    if (at(self, [schema.netKey, schema.deadKey])) { this.stats.aimState = 'dead'; return; }
    this.updateSwitch();
    if (!cfg.aim && !cfg.melee) return;
    const relations = teamRelations(m.barn, self.__id);
    if (!relations.ready) { this.stats.aimState = 'missing-own-team'; return; }
    const players = m.players();
    for (const p of players) {
      const v = read(p, schema.posKey);
      if (vec(v)) this.tracker.update(p, v, now);
    }
    const bindDown = this.protocol === VERIFIED_PROTOCOL && this.binds
      ? this.binds.isBindDown(4) : !!this.app.input.mouseButtons?.[0];
    const firing = !!bindDown;
    const currentDef = this.definitions?.[localWeapon(m)], localSlot = this.local?.data?.[this.local.slotKey];
    const meleeSlot = this.local?.data?.[this.local.weaponsKey]?.[2];
    const autoMelee = cfg.autoMelee && [0, 1].includes(localSlot) && currentDef?.type === 'gun';
    const meleeDef = currentDef?.type === 'melee' ? currentDef : autoMelee ? this.definitions?.[meleeSlot?.type] : null;
    const reach = meleeReach(meleeDef);
    const wantMelee = cfg.melee && this.capabilities.mobile && firing && reach !== null;
    if ((!cfg.aim || !this.capabilities.aim || !firing) && !wantMelee) {
      this.stats.aimState = !firing ? 'fire-not-held' : 'missing-aim-contract'; return;
    }
    if (cfg.wallcheck && !this.capabilities.wallcheck) { this.stats.aimState = 'wallcheck-unavailable'; return; }
    const candidates = [], rejected = this.stats.aimRejections;
    const reject = reason => { rejected[reason] = (rejected[reason] || 0) + 1; };
    for (const p of players) {
      if (p === self) continue;
      if (at(p, [schema.netKey, schema.deadKey])) { reject('dead'); continue; }
      if (!cfg.knocked && p.downed) { reject('downed'); continue; }
      if (!sameLayer(p.layer, self.layer)) { reject('otherLayer'); continue; }
      const relation = relations.classify(p.__id), targetPos = read(p, schema.posKey);
      if (relation.kind === 'unknown') { reject('unknownTeam'); continue; }
      if (relation.kind !== 'enemy') { reject('teammate'); continue; }
      if (!vec(targetPos)) { reject('invalidPosition'); continue; }
      const screen = project(m.camera, targetPos);
      if (!screen) { reject('invalidProjection'); continue; }
      const distance = wantMelee ? Math.hypot(pos.x - targetPos.x, pos.y - targetPos.y) : Math.hypot(screen.x - mouse.x, screen.y - mouse.y);
      if (distance > (wantMelee ? reach : cfg.fov)) { reject('outsideFov'); continue; }
      if (this.blocked({ pos, layer: self.layer }, { pos: targetPos }, !wantMelee)) { reject('wall'); continue; }
      candidates.push({ p, pos: targetPos, screen, distance });
    }
    candidates.sort((a, b) => a.distance - b.distance);
    let target = cfg.sticky && this.stickyId !== null ? candidates.find(c => c.p.__id === this.stickyId) : null;
    target ||= candidates[0];
    if (!target) { this.stickyId = null; this.stats.aimState = 'no-candidate'; return; }
    this.stickyId = target.p.__id;
    let world = point(target.pos);
    if (cfg.predict && this.capabilities.prediction && !wantMelee) {
      const gun = this.definitions[localWeapon(m)], bullet = this.definitions[gun?.bulletType];
      const track = this.tracker.states.get(target.p);
      if (track && bullet?.speed > 0) {
        const relative = { x: target.pos.x - pos.x, y: target.pos.y - pos.y };
        const time = intercept(relative, { x: track.vx, y: track.vy }, bullet.speed);
        // No arbitrary multiplicative coefficients or mixed world/screen units.
        if (time !== null) world = { x: world.x + track.vx * time, y: world.y + track.vy * time };
      }
    }
    const screen = aimPoint(m.camera, world, pos);
    if (!screen || !this.flushReady) { this.stats.aimState = 'missing-input-contract'; return; }
    const dt = clamp((now - this.lastInput) / 1000, .001, .05); this.lastInput = now;
    const gain = cfg.smoothEnabled ? 1 - Math.exp(-dt / (.015 + cfg.smooth / 500)) : 1;
    const x = mouse.x + (screen.x - mouse.x) * gain, y = mouse.y + (screen.y - mouse.y) * gain;
    this.restoreMouse = { owner: mouse, x: mouse.x, y: mouse.y, appliedX: x, appliedY: y };
    mouse.x = x; mouse.y = y;
    this.target = target.p; this.dot = { x, y }; this.stats.aimState = 'applied';
    if (wantMelee) {
      if (autoMelee) this.switchSlot = 2;
      const dx = target.pos.x - pos.x, dy = target.pos.y - pos.y, len = Math.hypot(dx, dy);
      if (len > .1) this.meleeDirection = { x: dx / len, y: dy / len };
    }
  }
  updateLayer() {
    const m = this.mapping, active = m?.active;
    const desired = new Map();
    const raw = active && this.layerOverrides.getRaw(active, 'layer');
    const ready = this.config.layerSpoofer && this.layerHeld && !this.win.document.hidden && active?.active
      && m.ui?.spectating === false && !active.downed && !at(active, [m.schema?.netKey, m.schema?.deadKey]);
    if (ready && [0, 1].includes(raw) && this.layerOverrides.set(active, 'layer', value => value === 0 ? 1 : value === 1 ? 0 : value)) {
      desired.set(active, new Set(['layer']));
      if (active.container && this.layerOverrides.set(active.container, 'alpha', value => Math.min(value, .5))) desired.set(active.container, new Set(['alpha']));
      this.stats.layerState = 'local-render-spoof';
    } else this.stats.layerState = !this.config.layerSpoofer ? 'disabled' : !this.layerHeld ? 'key-not-held' : 'unsupported-layer';
    this.layerOverrides.prune((owner, key) => desired.get(owner)?.has(key));
  }
  updateSwitch() {
    const local = this.local;
    this.switchSlot = this.weaponSwitch.sample({ enabled: this.config.autoSwitch, ready: !!(this.capabilities.switch && local),
      slot: local?.data[local.slotKey], weapons: local?.data[local.weaponsKey], definitions: this.definitions,
      held: !!this.binds?.isBindDown(4), oneGun: this.config.useOneGun, now: this.win.performance.now() });
    this.stats.switchState = this.weaponSwitch.state;
  }
  scanEffects() {
    const m = this.mapping, out = [], seen = new Set();
    if (!m) return;
    // Bounded shallow traversal of known map/barn owners, not arbitrary window/DOM graphs.
    const roots = [m.map];
    let budget = 12000;
    const visit = (o, depth) => {
      if (!object(o) || depth < 0 || seen.has(o) || --budget < 0) return;
      seen.add(o);
      const sprite = read(o, 'sprite');
      if (sprite && typeof read(o, 'type') === 'string' && /^(tree|bush|table|stairs)[_-]/.test(read(o, 'type'))) out.push({ owner: sprite, kind: 'tree', entity: o });
      if (read(o, 'isCeiling') === true && sprite) out.push({ owner: sprite, kind: 'ceiling', entity: o });
      for (const [k, v] of entries(o)) {
        if (['parent', 'children', 'container', 'sprite', 'texture', '_texture', 'game', 'renderer'].includes(k)) continue;
        if (Array.isArray(v)) { for (const child of v.slice(0, 2048)) visit(child, depth - 1); }
        else if (depth > 0 && object(v)) visit(v, depth - 1);
      }
    };
    roots.forEach(root => visit(root, 4));
    this.effects = out;
  }
  post() {
    this.restoreInput();
    const now = this.win.performance.now(); this.stats.frames++;
    if (now - this.lastVisual < 1000 / 30) return;
    this.lastVisual = now;
    const start = now, m = this.mapping, cfg = this.config;
    this.clearCanvas();
    this.stats.esp = emptyEspStats(cfg.esp ? this.win.document.hidden ? 'page-hidden' : this.ctx ? 'waiting-mapping' : 'no-canvas' : 'disabled');
    this.stats.xray = emptyXrayStats(cfg.xray ? 'waiting-contract' : 'disabled');
    if (!this.app.game?.initialized || this.win.document.hidden) { this.overrides.clear(); return; }
    const playerReady = !!(m?.schema && m.active?.active && this.capabilities.visuals);
    if (!(cfg.esp || cfg.xray || cfg.zoom || cfg.aim || cfg.melee || cfg.ownFlashlight || cfg.othersFlashlight || cfg.bulletTrajectory || cfg.grenadeTrajectory || cfg.grenadeZones)) {
      if (this.overrides.records.size) this.overrides.clear();
      return;
    }
    const players = playerReady ? m.players() : [];
    const espFrame = playerReady && cfg.esp && this.ctx ? buildEspFrame(m, players, cfg, this.win.innerWidth, this.win.innerHeight, this.target) : null;
    const espPlayers = new Set(espFrame?.rows.filter(row => !row.offscreen).map(row => row.player));
    const keep = new Map();
    const want = (owner, key) => { if (!keep.has(owner)) keep.set(owner, new Set()); keep.get(owner).add(key); };
    for (const p of players) {
      if (!p.nameText || p === m.active || at(p, [m.schema.netKey, m.schema.deadKey])) continue;
      if (cfg.esp && cfg.nametags && espPlayers.has(p)) {
        // Canvas labels carry relation colors; suppress duplicate native text only
        // while the corresponding overlay is rendered. Legacy label-only mode stays reversible.
        this.overrides.set(p.nameText, 'visible', () => !cfg.espLabels); want(p.nameText, 'visible');
      }
    }
    if (cfg.xray && now - this.lastScan > 500) { this.scanEffects(); this.lastScan = now; }
    for (const effect of cfg.xray ? this.effects : []) {
      const { owner, kind, entity } = effect;
      if (read(entity, 'active') === false || owner.destroyed) continue;
      if (kind === 'ceiling' && cfg.ceilings && read(entity, 'isCeiling') === true) { if (this.overrides.set(owner, 'visible', () => false)) { want(owner, 'visible'); this.stats.xray.ceilings++; } }
      if (kind === 'tree' && /^(tree|bush|table|stairs)[_-]/.test(read(entity, 'type') || '')) { if (this.overrides.set(owner, 'alpha', raw => Math.min(raw, cfg.treeOpacity / 100))) { want(owner, 'alpha'); this.stats.xray.vegetation++; } }
    }
    if (cfg.xray) {
      const smoke = smokeParticles(this.smokeSources), stats = this.stats.xray;
      stats.smokeSources = this.smokeSources.length; stats.smokeActive = smoke.length;
      for (const particle of smoke) {
        if (this.overrides.set(particle.sprite, 'alpha', raw => smokeAlpha(raw, cfg.smokeOpacity))) {
          want(particle.sprite, 'alpha'); stats.smokeModified++;
        } else stats.smokeUnsupported++;
        if (cfg.darkerSmokes && this.overrides.set(particle, 'tint', () => 0x202020)) { want(particle, 'tint'); stats.darkened++; }
      }
      stats.state = stats.smokeModified || stats.ceilings || stats.vegetation ? 'overrides-active' : stats.smokeSources ? 'waiting-particles' : 'no-effect-contract';
    }
    if (playerReady && cfg.zoom && this.local?.zoomKey) {
      const { data, zoomKey } = this.local;
      this.overrides.set(data, zoomKey, raw => raw * cfg.zoomFactor); want(data, zoomKey);
    }
    this.overrides.prune((owner, key) => keep.get(owner)?.has(key));
    if (playerReady) this.draw(players, espFrame);
    this.stats.featureMs = this.win.performance.now() - start;
  }
  attachCanvas(canvas) {
    this.canvas = canvas;
    try { this.ctx = canvas.getContext('2d'); } catch { this.ctx = null; }
    if (!this.ctx) this.report('warning', 'Canvas 2D không khả dụng: overlay bị khóa, input features không bị dừng.');
  }
  clearCanvas() { if (this.ctx && this.canvas) this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height); }
  draw(players, espFrame = null) {
    const ctx = this.ctx, canvas = this.canvas, m = this.mapping, cfg = this.config;
    if (!ctx || !canvas) return;
    const width = this.win.innerWidth, height = this.win.innerHeight;
    if (!prepareOverlay(canvas, ctx, width, height, this.win.devicePixelRatio)) return;
    ctx.globalAlpha = 1; ctx.setLineDash([]);
    const mouse = this.app.input?.mousePos;
    if (cfg.aim && cfg.showFov && vec(mouse)) {
      ctx.strokeStyle = '#ffffff44'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(mouse.x, mouse.y, cfg.fov, 0, Math.PI * 2); ctx.stroke();
    }
    if (cfg.showDot && this.dot) { ctx.fillStyle = '#f95353'; ctx.beginPath(); ctx.arc(this.dot.x, this.dot.y, 4, 0, Math.PI * 2); ctx.fill(); }
    const selfPos = overlayPosition(m.active, m), origin = project(m.camera, selfPos);
    if (!origin) { if (cfg.esp) this.stats.esp = emptyEspStats('invalid-projection'); return; }
    if (cfg.esp) {
      espFrame ||= buildEspFrame(m, players, cfg, width, height, this.target);
      this.stats.esp = this.espRenderer.draw(ctx, espFrame, cfg, width, height);
    }
    this.drawPreviews(players);
    if (cfg.grenadeZones && this.capabilities.grenadeZones) {
      for (const [, entity] of entries(read(m.creator, m.registryKey))) {
        const zone = grenadeZone(entity, this.definitions, m.active.layer, this.protocol);
        if (!zone) continue;
        const { pos, radius } = zone;
        const center = project(m.camera, pos);
        if (!center) continue;
        const scale = read(m.camera.camera, m.camera.scaleKeys[0]) * read(m.camera.camera, m.camera.scaleKeys[1]);
        ctx.strokeStyle = '#ff744a99'; ctx.beginPath(); ctx.arc(center.x, center.y, radius * scale, 0, Math.PI * 2); ctx.stroke();
      }
    }
  }
  drawPreviews(players) {
    const cfg = this.config, m = this.mapping, ctx = this.ctx, schema = m.schema;
    this.stats.previews = { cones: 0, bulletPaths: 0, throwPaths: 0, unsupportedColliders: 0, ricochetDefinitions: !!this.mapDefinitions };
    if (this.protocol !== VERIFIED_PROTOCOL || !this.definitions || !(cfg.ownFlashlight || cfg.othersFlashlight || cfg.bulletTrajectory || cfg.grenadeTrajectory)) return;
    const selfPos = read(m.active, schema.posKey), inputOrigin = aimPoint(m.camera, selfPos, selfPos), aim = this.dot || this.app.input.mousePos;
    if (!inputOrigin || !vec(aim)) return;
    const scale = read(m.camera.camera, m.camera.scaleKeys[0]) * read(m.camera.camera, m.camera.scaleKeys[1]);
    if (!(scale > 0)) return;
    const ownDirection = { x: aim.x - inputOrigin.x, y: inputOrigin.y - aim.y };
    const allObstacles = m.obstacles(), truncated = allObstacles.length > 256;
    const obstacles = allObstacles.slice(0, 256), relations = teamRelations(m.barn, m.active.__id);
    this.stats.previews.truncatedObstacles = truncated;
    const line = (points, color, dashed = false) => {
      const projected = points.map(p => project(m.camera, p)); if (projected.some(p => !p)) return;
      ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.setLineDash(dashed ? [5, 4] : []); ctx.beginPath();
      projected.forEach((p, i) => i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)); ctx.stroke(); ctx.setLineDash([]);
    };
    let cones = 0;
    for (const player of [m.active, ...players.filter(p => p !== m.active)]) {
      const own = player === m.active;
      if (!player.active || at(player, [schema.netKey, schema.deadKey]) || !sameLayer(player.layer, m.active.layer)) continue;
      if (!own && (!cfg.othersFlashlight || relations.classify(player.__id).kind !== 'enemy')) continue;
      const gun = this.definitions[at(player, [schema.netKey, schema.weaponKey])], bullet = this.definitions[gun?.bulletType];
      const pos = overlayPosition(player, m), direction = own ? ownDirection : read(player, schema.dirKey);
      if (gun?.type !== 'gun' || !(bullet?.distance > 0) || !pos || !vec(direction) || Math.hypot(direction.x, direction.y) < .001) continue;
      const angle = Math.atan2(direction.y, direction.x), origin = project(m.camera, pos);
      if (!origin || origin.x < -100 || origin.x > this.win.innerWidth + 100 || origin.y < -100 || origin.y > this.win.innerHeight + 100) continue;
      if ((own && cfg.ownFlashlight || !own) && cones < 8) {
        const half = clamp(gun.shotSpread || 0, 1, 90) * Math.PI / 360, ends = [];
        for (let i = 0; i < 7; i++) {
          const a = angle - half + 2 * half * i / 6;
          const trace = traceShot(pos, { x: Math.cos(a), y: Math.sin(a) }, bullet.distance, obstacles, player.layer, this.mapDefinitions);
          if (!trace) continue;
          this.stats.previews.unsupportedColliders += trace.unsupported;
          ends.push(project(m.camera, trace.points.at(-1)));
        }
        if (ends.length && ends.every(Boolean)) {
          ctx.fillStyle = own ? '#88caff20' : '#ff626218'; ctx.beginPath(); ctx.moveTo(origin.x, origin.y);
          for (const end of ends) ctx.lineTo(end.x, end.y); ctx.closePath(); ctx.fill(); cones++; this.stats.previews.cones++;
        }
      }
      if (own && cfg.bulletTrajectory) {
        const trace = traceShot(pos, direction, bullet.distance, obstacles, player.layer, this.mapDefinitions, 3);
        if (trace) { line(trace.points, '#ffdf91bb', trace.unsupported > 0 || truncated || !this.mapDefinitions); this.stats.previews.bulletPaths++; this.stats.previews.unsupportedColliders += trace.unsupported; }
      }
    }
    if (cfg.grenadeTrajectory && this.protocol === VERIFIED_PROTOCOL && this.local?.data[this.local.slotKey] === 3) {
      const type = this.local.data[this.local.weaponsKey]?.[3]?.type, def = this.definitions[type];
      const preview = throwPreview(def, selfPos, ownDirection, Math.hypot(ownDirection.x, ownDirection.y) / scale);
      if (preview) {
        line(preview.points, '#80ffb5aa', true); this.stats.previews.throwPaths++;
        const center = project(m.camera, preview.end), explosion = this.definitions[def.explosionType];
        if (center && explosion?.rad?.max > 0) { ctx.strokeStyle = '#80ffb577'; ctx.setLineDash([5, 4]); ctx.beginPath(); ctx.arc(center.x, center.y, explosion.rad.max * scale, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]); }
      }
    }
  }
  updateLoot() {
    this.pickupPulse = false;
    if (!this.config.autoLoot || this.config.lootMode === 'mobile') return;
    const m = this.mapping, now = this.win.performance.now();
    if (!this.capabilities.autoPickup || !this.bindsInstalled) { this.stats.lootState = 'missing-pickup-contract'; return; }
    if (this.win.document.hidden || m.ui?.spectating !== false || !m.active?.active
      || m.active.downed || at(m.active, [m.schema.netKey, m.schema.deadKey])) { this.stats.lootState = 'paused'; return; }
    const loot = read(this.lootSource.owner, this.lootSource.key), pos = read(m.active, m.schema.posKey);
    if (read(loot, '__type') !== 3 || read(loot, 'active') !== true || !vec(read(loot, 'pos')) || !vec(pos)
      || !sameLayer(read(loot, 'layer'), m.active.layer) || !finite(read(loot, 'rad')) || loot.rad <= 0
      || !(loot.ownerId === 0 || loot.ownerId === m.active.__id)
      || Math.hypot(loot.pos.x - pos.x, loot.pos.y - pos.y) >= loot.rad) {
      this.stats.lootState = 'no-nearby-loot'; this.pickupAttempt = null; this.nextPickup = 0; return;
    }
    const def = this.definitions?.[read(loot, 'type')];
    if (!['ammo', 'heal', 'boost', 'throwable'].includes(def?.type)) { this.stats.lootState = 'skip-non-supply'; return; }
    // Never synthesize Interact/Use: they can open doors or revive. Native Loot
    // goes through normal InputMsg diff detection and the server's pickup checks.
    const previous = this.pickupAttempt;
    const unchanged = previous?.entity === loot && previous.id === loot.__id && previous.count === loot.count;
    if (!unchanged) this.nextPickup = 0;
    if (now < this.nextPickup) { this.stats.lootState = 'pickup-backoff'; return; }
    const attempts = unchanged ? previous.attempts + 1 : 1;
    this.pickupAttempt = { entity: loot, id: loot.__id, count: loot.count, attempts };
    this.nextPickup = now + Math.min(2000, 350 * 2 ** Math.min(attempts - 1, 3));
    this.pickupPulse = true; this.stats.pickupPulses++; this.stats.lootState = 'loot-input-ready';
  }
  autoLootStatus() {
    if (!this.config.autoLoot) return this.joinState.mobile && this.joinState.forwarded ? 'off-next-join' : 'disabled';
    if (this.config.lootMode === 'nearby') return this.stats.lootState;
    if (!this.senderReady) return 'missing-sender';
    if (this.protocol !== null && this.protocol !== VERIFIED_PROTOCOL) return 'unsupported-protocol';
    if (!this.joinState.observed || !this.joinState.mobile) return 'pending-next-join';
    return this.joinState.forwarded ? 'mobile-join-forwarded' : 'join-not-forwarded';
  }
  diagnostics() {
    const m = this.mapping;
    // Report contracts, never game references, player state or message contents.
    const checks = {
      initialized: !!this.app.game?.initialized,
      playerBarn: !!m?.barn, playerPool: !!m?.poolKey, activePlayer: !!m?.active,
      playerSchema: !!m?.schema, camera: !!m?.camera, spectatorUI: !!m?.ui,
      inputFlush: !!this.flushReady, sender: !!this.senderReady,
      canvasRenderer: !!this.ctx, mapDefinitions: !!this.mapDefinitions, smokeSource: this.smokeSources.length > 0, definitions: !!this.definitions, lootSource: !!this.lootSource, localData: !!this.local, binds: !!this.binds,
      protocolObserved: this.protocol !== null, protocolMatches: this.protocol === VERIFIED_PROTOCOL,
    };
    return { version: '0.4.0', protocol: this.protocol, sourceProtocol: VERIFIED_PROTOCOL,
      initialized: checks.initialized, checks,
      autoLoot: { state: this.autoLootStatus(), mode: this.config.lootMode, ...this.joinState },
      mapHighlights: { ...this.mapHighlights.stats },
      missingContracts: Object.keys(checks).filter(key => !checks[key]),
      capabilities: { ...this.capabilities },
      stats: { ...this.stats }, failed: [...this.failed], overrides: this.overrides.records.size + this.layerOverrides.records.size };
  }
  dispose() {
    if (this.stopped) return;
    this.stopped = true; this.releaseMatch(); this.gameHooks?.clear(); this.hooks.clear();
    // The menu owns this canvas. Retry replaces the engine, not the menu DOM.
    // releaseMatch() already cleared it; only menu.dispose() should remove it.
    this.canvas = this.ctx = null;
  }
}
