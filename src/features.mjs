import { aimPoint, ast, at, clamp, discover, discoverLootSource, discoverSender, Disposables, entries, finite, intercept, isPlayer,
  localWeapon, methods, object, overlayPosition, patchMethod, paths, point, project, read, readMethod, sameLayer,
  segmentBlocked, teamRelations, Tracker, unique, vec, walk } from './core.mjs';

import { buildEspFrame, emptyEspStats, EspRenderer, prepareOverlay } from './esp.mjs';

export const VERIFIED_PROTOCOL = 1028;
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
    if (len) { copy.touchMoveActive = true; copy.touchMoveLen = 255; copy.touchMoveDir = { x: x / len, y: y / len }; }
  }
  if (config.melee && context.meleeDirection && vec(context.meleeDirection)) {
    copy.touchMoveActive = true; copy.touchMoveLen = 255; copy.touchMoveDir = point(context.meleeDirection);
  }
  if (context.switchSlot !== null && context.switchSlot !== undefined) copy.addInput(context.switchSlot === 0 ? 11 : 12);
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
    this.nextSemi = 0; this.frameId = 0; this.semiFrame = -1; this.semiValue = false; this.nextSwitch = 0; this.switchSlot = null; this.meleeDirection = null;
    this.lastAmmo = null; this.stats = { frames: 0, mappingRuns: 0, featureMs: 0, lastError: null, aimState: 'disabled', aimRejections: {} };
    this.joinState = { observed: false, forwarded: false, mobile: null, requested: false };
    this.capabilities = {}; this.failed = new Set();
    this.lootSource = null; this.pickupPulse = false; this.nextPickup = 0; this.pickupAttempt = null;
    this.stats.lootState = 'disabled'; this.stats.pickupPulses = 0;
    this.espRenderer = new EspRenderer(); this.stats.esp = emptyEspStats();
    this.installFlush();
    const ticker = app.pixi.ticker;
    const pre = () => this.guard('input-frame', () => this.pre());
    const post = () => this.guard('visual-frame', () => this.post());
    ticker.add(pre, null, 10); ticker.add(post, null, -20);
    this.hooks.add(() => ticker.remove(pre, null)); this.hooks.add(() => ticker.remove(post, null));
    this.reconcile(true);
  }
  guard(name, fn) {
    if (this.stopped || this.failed.has(name)) return;
    try { fn(); }
    catch (e) {
      this.failed.add(name); this.stats.lastError = `${name}: ${e.message}`;
      if (name === 'visual-frame') this.stats.esp = emptyEspStats('error');
      this.restoreInput(); this.overrides.clear(); this.clearCanvas();
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
    this.lastAmmo = null; this.local = null; this.mapping = null; this.effects = [];
    this.lootSource = null; this.pickupPulse = false; this.pickupAttempt = null; this.nextPickup = 0;
    this.binds = null; this.bindsInstalled = false; this.stickyId = null; this.lastInput = -Infinity;
    this.espRenderer.reset(); this.stats.esp = emptyEspStats('waiting-mapping');
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
    if (next.active && !this.local) this.local = localDataSchema(game, next.active);
    const nextBinds = this.findBinds();
    if (this.binds && this.binds !== nextBinds) {
      this.matchHooks.clear(); this.bindsInstalled = false;
      this.nextSemi = 0; this.semiFrame = -1;
    }
    this.binds = nextBinds;
    this.lootSource = discoverLootSource(game);
    const ready = !!(next.schema && next.camera && next.barn && next.pool && next.active?.active);
    this.capabilities = {
      visuals: ready, interpolatedOverlay: ready && !!next.visualPosKey,
      grenadeZones: ready && !!this.definitions && !!next.registryKey && this.protocol === VERIFIED_PROTOCOL, aim: ready && this.flushReady && !!next.ui,
      autoPickup: ready && !!next.ui && !!this.lootSource && !!this.binds && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
      prediction: ready && !!this.definitions, wallcheck: !!next.creator && !!next.registryKey,
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
      if (self.protocol === VERIFIED_PROTOCOL && self.config.autoSwitch && self.switchSlot !== null
        && self.mapping?.ui?.spectating === false && code === (self.switchSlot === 0 ? 11 : 12)) return true;
      if (code !== 4 || self.failed.has('input-frame') || !self.config.semi || self.protocol !== VERIFIED_PROTOCOL || !self.mapping?.active || self.mapping.ui?.spectating !== false) return actual;
      const gun = self.definitions?.[localWeapon(self.mapping)];
      if (gun?.type !== 'gun' || gun.fireMode !== 'single') return actual;
      if (!this.isBindDown(4)) { self.nextSemi = 0; self.semiFrame = -1; return actual; }
      if (self.semiFrame === self.frameId) return actual || self.semiValue;
      self.semiFrame = self.frameId; self.semiValue = false;
      const now = self.win.performance.now();
      if (now >= self.nextSemi) {
        self.nextSemi = now + Math.max(50, (gun.fireDelay || .1) * 1000);
        self.semiValue = true; return true;
      }
      return actual;
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
    this.updateLoot();
    const m = this.mapping, cfg = this.config;
    this.target = null; this.dot = null; this.meleeDirection = null;
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
    const wantMelee = cfg.melee && this.capabilities.mobile && firing && this.definitions?.[localWeapon(m)]?.type === 'melee';
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
      if (distance > (wantMelee ? 5.5 : cfg.fov)) { reject('outsideFov'); continue; }
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
      const dx = target.pos.x - pos.x, dy = target.pos.y - pos.y, len = Math.hypot(dx, dy);
      if (len > .1) this.meleeDirection = { x: dx / len, y: dy / len };
    }
  }
  updateSwitch() {
    if (!this.config.autoSwitch || !this.capabilities.switch || !this.local) return;
    const { data, slotKey, weaponsKey } = this.local;
    const slot = data[slotKey], weapons = data[weaponsKey], current = weapons?.[slot];
    if (![0, 1].includes(slot) || !current) { this.lastAmmo = null; return; }
    const def = this.definitions[current.type], now = this.win.performance.now();
    if (def?.type === 'gun' && def.fireMode === 'single' && this.lastAmmo?.slot === slot
      && this.lastAmmo.type === current.type && current.ammo < this.lastAmmo.ammo && now >= this.nextSwitch) {
      const other = weapons[1 - slot];
      if (other?.ammo > 0 && this.definitions[other.type]?.type === 'gun') {
        this.switchSlot = 1 - slot; this.nextSwitch = now + 200;
      }
    }
    this.lastAmmo = { slot, ammo: current.ammo, type: current.type };
  }
  scanEffects() {
    const m = this.mapping, out = [], seen = new Set();
    if (!m) return;
    // Bounded shallow traversal of known map/barn owners, not arbitrary window/DOM graphs.
    const roots = [m.map, ...entries(this.app.game).map(([, v]) => v).filter(v => typeof readMethod(v, 'm_allocParticle') === 'function')];
    // Particle allocator may be renamed: identify actual arrays of smoke particles by texture.
    roots.push(...entries(this.app.game).map(([, v]) => v).filter(v => entries(v).some(([, a]) => Array.isArray(a) && a.some(p => read(read(p, 'sprite'), 'texture') || read(p, 'fadeTicker') !== undefined))));
    let budget = 12000;
    const visit = (o, depth) => {
      if (!object(o) || depth < 0 || seen.has(o) || --budget < 0) return;
      seen.add(o);
      const sprite = read(o, 'sprite');
      if (sprite && typeof read(o, 'type') === 'string' && /^(tree|bush|table|stairs)[_-]/.test(read(o, 'type'))) out.push({ owner: sprite, kind: 'tree', entity: o });
      if (read(o, 'isCeiling') === true && sprite) out.push({ owner: sprite, kind: 'ceiling', entity: o });
      if (sprite && finite(read(o, 'fadeTicker')) && finite(read(o, 'fadeDuration')) && vec(read(o, 'posTarget'))) out.push({ owner: sprite, kind: 'smoke', entity: o });
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
    if (!this.app.game?.initialized || !m?.schema || !m.active?.active || !this.capabilities.visuals || this.win.document.hidden) { this.overrides.clear(); return; }
    if (!(cfg.esp || cfg.xray || cfg.zoom || cfg.aim || cfg.melee || cfg.ownFlashlight || cfg.grenadeZones)) {
      if (this.overrides.records.size) this.overrides.clear();
      return;
    }
    const players = m.players();
    const espFrame = cfg.esp && this.ctx ? buildEspFrame(m, players, cfg, this.win.innerWidth, this.win.innerHeight, this.target) : null;
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
      if (kind === 'ceiling' && cfg.ceilings && read(entity, 'isCeiling') === true) { this.overrides.set(owner, 'visible', () => false); want(owner, 'visible'); }
      if (kind === 'tree' && /^(tree|bush|table|stairs)[_-]/.test(read(entity, 'type') || '')) { this.overrides.set(owner, 'alpha', raw => Math.min(raw, cfg.treeOpacity / 100)); want(owner, 'alpha'); }
      if (kind === 'smoke') { this.overrides.set(owner, 'alpha', raw => raw * cfg.smokeOpacity / 100); want(owner, 'alpha'); }
    }
    if (cfg.zoom && this.local?.zoomKey) {
      const { data, zoomKey } = this.local;
      this.overrides.set(data, zoomKey, raw => raw * cfg.zoomFactor); want(data, zoomKey);
    }
    this.overrides.prune((owner, key) => keep.get(owner)?.has(key));
    this.draw(players, espFrame);
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
    if (cfg.ownFlashlight && this.definitions) {
      const gun = this.definitions[localWeapon(m)], bullet = this.definitions[gun?.bulletType];
      const aim = this.dot || mouse;
      if (gun?.type === 'gun' && bullet?.distance > 0 && vec(aim)) {
        const angle = Math.atan2(aim.y - origin.y, aim.x - origin.x);
        const scale = read(m.camera.camera, m.camera.scaleKeys[0]) * read(m.camera.camera, m.camera.scaleKeys[1]);
        ctx.fillStyle = '#88caff18'; ctx.beginPath(); ctx.moveTo(origin.x, origin.y);
        const spread = clamp(gun.shotSpread || 0, 1, 90) * Math.PI / 180;
        ctx.arc(origin.x, origin.y, bullet.distance * scale, angle - spread / 2, angle + spread / 2); ctx.closePath(); ctx.fill();
      }
    }
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
      canvasRenderer: !!this.ctx, definitions: !!this.definitions, lootSource: !!this.lootSource, localData: !!this.local, binds: !!this.binds,
      protocolObserved: this.protocol !== null, protocolMatches: this.protocol === VERIFIED_PROTOCOL,
    };
    return { version: '0.3.0', protocol: this.protocol, sourceProtocol: VERIFIED_PROTOCOL,
      initialized: checks.initialized, checks,
      autoLoot: { state: this.autoLootStatus(), mode: this.config.lootMode, ...this.joinState },
      missingContracts: Object.keys(checks).filter(key => !checks[key]),
      capabilities: { ...this.capabilities },
      stats: { ...this.stats }, failed: [...this.failed], overrides: this.overrides.records.size };
  }
  dispose() {
    if (this.stopped) return;
    this.stopped = true; this.releaseMatch(); this.gameHooks?.clear(); this.hooks.clear();
    // The menu owns this canvas. Retry replaces the engine, not the menu DOM.
    // releaseMatch() already cleared it; only menu.dispose() should remove it.
    this.canvas = this.ctx = null;
  }
}
