import { aimPoint, ast, at, clamp, discover, discoverLootSource, discoverSender, Disposables, entries, finite, intercept, isPlayer,
  localWeapon, methods, object, overlayPosition, patchMethod, paths, point, project, read, readMethod, sameLayer,
  segmentBlocked, teamRelations, Tracker, unique, vec, walk } from './core.mjs';

import { buildEspFrame, emptyEspStats, EspRenderer, prepareOverlay } from './esp.mjs';
import { fadeObjectKind } from './xray.mjs';
import { discoverSmokeSources, emptyXrayStats, smokeAlpha, smokeParticles } from './effects.mjs';
import { RepeatFire } from './repeat-fire.mjs';
import { MapHighlights } from './map-highlights.mjs';
import { WeaponSwitch } from './weapon-switch.mjs';
import { MovementSmoother, previewAim, throwPreview, traceShot } from './previews.mjs';
import { AimController, SnapshotTracker, modeOf, predictShot, unit, weaponProfile, angleDelta } from './aim.mjs';
import { discoverInputTimeout, discoverUpdateReceiver, discoverSourceFields, NetworkTiming } from './aim-adapters.mjs';
import { clippedMuzzle, shotLayer, segmentCandidates, pathToTarget, pathAlongAim, geometryObjects, targetLayerEligible } from './aim-geometry.mjs';
import { AimEvidence } from './aim-evidence.mjs';
import { MouseInputFrame } from './mouse-input.mjs';
import { NativeNames } from './native-names.mjs';
import { drawTargetIndicator } from './target-indicator.mjs';
import { LootBackoff } from './loot-backoff.mjs';
import { nearbyLootSafety } from './loot-safety.mjs';
import { GrenadeTimer, drawGrenadeTimer } from './grenade-timer.mjs';
import { simulateOpenThrow, solveMovingOpenThrow, validateOpenThrow } from './grenade-aim.mjs';
import { assessAutoThrow } from './grenade-release.mjs';
import { GrenadeAutoRelease } from './grenade-auto-release.mjs';
import { RuntimePerf } from './runtime-perf.mjs';

export const VERIFIED_PROTOCOL = 1028;
export const isManualEquip = code => code >= 11 && code <= 20 || code === 27 || code === 28;
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
  if (context.aimOutput && vec(context.aimOutput.dir)) {
    copy.toMouseDir = point(context.aimOutput.dir);
    if (context.aimOutput.toMouseHit) copy.toMouseLen = clamp(context.aimOutput.distance, 0, 64);
  }
  const manualEquip = data.inputs.some(isManualEquip);
  const equip = manualEquip ? null : equipInput(context.switchSlot);
  if (equip !== null) copy.addInput(equip);
  return copy;
}

export class Features {
  constructor(win, app, config, report, definitions = null) {
    this.win = win; this.app = app; this.config = config; this.report = report; this.definitions = definitions;
    this.runtimePerf = new RuntimePerf();
    this.hooks = new Disposables(); this.matchHooks = new Disposables(); this.overrides = new Overrides();
    this.grenadeAuto = new GrenadeAutoRelease(); this.grenadeAutoPlan = null; this.lastGrenadeAutoEvidence = null; this.lastGrenadeAutoSent = -Infinity;
    this.grenadeTracker = new SnapshotTracker(); this.grenadeUpdateAt = null;
    this.tracker = new SnapshotTracker(); this.aimController = new AimController(); this.grenadeAimTimer = new GrenadeTimer(); this.grenadePlan = null; this.grenadeState = 'off'; this.grenadeManualOverride = false; this.lastGrenadeEvidence = null; this.timing = new NetworkTiming(); this.grenadeTimer = new GrenadeTimer(); this.names = new NativeNames(); this.aimEvidence = new AimEvidence(); this.lastAimSent = null; this.aimOutput = null; this.sourceFields = null; this.observedEntities = new Map(); this.focusBlocked = false; this.protocol = null; this.mapping = null; this.local = null;
    this.meleeEquip = null; this.manualEquipHeld = false; this.actualWeapon = null; this.lastPredictionEvidence = null;
    this.target = null; this.targetId = null; this.dot = null; this.mouseInput = new MouseInputFrame(); this.aimFrame = 0; this.aimPlanFrame = -1; this.aimOutputFrame = -1; this.aimPlanDirect = false; this.lastMap = -Infinity;
    this.lastVisual = -Infinity; this.lastInput = -Infinity; this.lastScan = -Infinity;
    this.effects = []; this.lastGame = null; this.lastPool = null; this.lastActive = null; this.lastActiveId = null;
    this.stopped = false; this.keys = new Set(); this.holdAim = false;
    this.movement = new MovementSmoother(); this.weaponSwitch = new WeaponSwitch(); this.layerOverrides = new Overrides(); this.layerHeld = false;
    this.repeatFire = new RepeatFire(); this.frameId = 0; this.switchSlot = null; this.meleeDirection = null;
    this.stats = { frames: 0, mappingRuns: 0, featureMs: 0, lastError: null, aimState: 'disabled', aimRejections: {} };
    this.joinState = { observed: false, forwarded: false, mobile: null, requested: false };
    this.capabilities = {}; this.failed = new Set();
    this.lootSource = null; this.pickupPulse = false; this.pickupAttempt = null; this.pickupPauseUntil = 0; this.lootBackoff = new LootBackoff();
    this.stats.lootState = 'disabled'; this.stats.pickupPulses = 0;
    this.espRenderer = new EspRenderer(); this.stats.esp = emptyEspStats();
    this.smokeSources = []; this.stats.xray = emptyXrayStats(); this.stats.semi = { state: 'disabled', pulses: 0 };
    this.mapHighlights = new MapHighlights(config, report);
    this.installFlush();
    const ticker = app.pixi.ticker;
    const measure = (key, operation) => { const start = win.performance.now(); try { operation(); } finally { this.runtimePerf.add(key, win.performance.now() - start); } };
    const pre = () => measure('inputFrame', () => this.guard('input-frame', () => this.pre()));
    const post = () => measure('visualFrame', () => this.guard('visual-frame', () => this.post()));
    ticker.add(pre, null, 10); ticker.add(post, null, -20);
    this.hooks.add(() => ticker.remove(pre, null)); this.hooks.add(() => ticker.remove(post, null));
    const controller = new win.AbortController(); this.hooks.add(() => controller.abort());
    const releaseLayer = () => { this.layerHeld = false; this.layerOverrides.clear(); };
    win.addEventListener('keydown', event => {
      if (event.repeat || event.defaultPrevented || event.composedPath().some(n => ['INPUT', 'TEXTAREA', 'SELECT'].includes(n.tagName) || n.isContentEditable)) return;
      // Do not consume the key or synthesize Fire. Cancel remains latched
      // until the user's native release has actually been forwarded.
      const firing = this.binds ? !!this.binds.isBindDown(4) : !!this.app.input.mouseButtons?.[0];
      if (event.code === this.config.grenadeCancelKey && firing && this.local?.data?.[this.local.slotKey] === 3 && ['preview', 'assist', 'lock'].includes(this.config.grenadeAimMode)) {
        this.grenadeManualOverride = true; this.grenadePlan = null; this.aimPlan = null; this.aimPlanFrame = -1; this.aimOutput = null;
        this.restoreInput(); this.grenadeState = 'manual-override'; this.lastGrenadeEvidence = { state: 'manual-override', recordedAt: this.win.performance.now() };
        if (this.lastAimSent && this.timeoutKey && this.app.game?.initialized) this.app.game[this.timeoutKey] = 0;
        return;
      }
      if (event.code === this.config.layerKey && this.config.layerSpoofer) this.layerHeld = true;
      if (event.code === this.config.aimKey) this.holdAim = true;
    }, { signal: controller.signal });
    win.addEventListener('keyup', event => { if (event.code === this.config.layerKey) releaseLayer(); if (event.code === this.config.aimKey) { this.holdAim = false; if (this.config.aimActivation !== 'fire') this.restoreInput(); } }, { signal: controller.signal });
    // Yield immediately on the ordinary mouse release; never consume or synthesize it.
    win.addEventListener('mouseup', event => { if (event.button === 0 && (this.config.aimActivation !== 'key' || this.meleeDirection)) this.restoreInput(); }, { signal: controller.signal });
    win.addEventListener('blur', () => { releaseLayer(); this.restoreInput(); this.focusBlocked = true; this.holdAim = false; this.aimController.reset(); this.grenadeTimer.reset(); this.grenadeAimTimer.reset(); this.grenadePlan = null; }, { signal: controller.signal });
    win.addEventListener('focus', () => { this.focusBlocked = false; }, { signal: controller.signal });
    win.document.addEventListener('visibilitychange', () => { if (win.document.hidden) { releaseLayer(); this.restoreInput(); this.grenadeTimer.reset(); this.grenadeAimTimer.reset(); this.grenadePlan = null; } }, { signal: controller.signal });
    this.reconcile(true);
  }
  guard(name, fn) {
    if (this.stopped || this.failed.has(name)) return;
    try { fn(); }
    catch (e) {
      this.failed.add(name); this.stats.lastError = `${name}: ${e.message}`;
      if (name === 'visual-frame' || name === 'overlay-render') this.stats.esp = emptyEspStats('error');
      if (name === 'overlay-render') this.clearCanvas();
      if (name === 'visual-frame') { this.overrides.clear(); this.names.clear(); this.clearCanvas(); }
      if (name === 'input-frame') { this.restoreInput(); this.aimController.reset(); this.aimOutput = null; this.layerOverrides.clear(); }
      this.report('error', this.stats.lastError);
    }
  }
  installFlush() {
    if (!this.app.input || !patchMethod(this.app.input, 'flush', original => {
      const self = this;
      return function () {
        // Captured Lock keeps physical writes separate until the next frame;
        // ordinary transactions are restored before native flush as before.
        if (!self.mouseInput.record?.captured) self.restoreInput();
        return Reflect.apply(original, this, arguments);
      };
    }, this.hooks)) this.report('warning', 'Không có flush contract: aim input bị khóa.');
    else this.flushReady = true;
  }
  restoreInput() { this.mouseInput.restore(); }
  releaseMatch() {
    // Do not re-arm across a match transition while the button is still held;
    // preserve post-release suppression until a physical button-up packet.
    if (this.grenadeAuto.phase === 'armed') this.grenadeAuto.phase = 'manual';
    // Keep only anonymous timestamped evidence across a match transition so
    // post-death diagnostics can explain the prior attempt. Never retain targets.
    this.grenadeAuto.target = null; this.grenadeAutoPlan = null;
    this.grenadeTracker.reset(); this.grenadeUpdateAt = null;
    this.restoreInput(); this.matchHooks.clear(); this.overrides.clear(); this.names.clear(); this.tracker.reset(); this.aimController.reset(); this.grenadeTimer.reset(); this.grenadeAimTimer.reset(); this.grenadePlan = null; this.grenadeState = 'off'; this.grenadeManualOverride = false; this.lastAimSent = null; this.aimOutput = null; this.aimPlan = null; this.aimPlanFrame = -1; this.aimOutputFrame = -1; this.previewAimPlan = null; this.aimPlanDirect = false; this.sourceFields = null; this.observedEntities.clear(); this.timing.reset(); this.lastPredictionEvidence = null;
    this.target = null; this.targetId = null; this.dot = null; this.meleeDirection = null; this.switchSlot = null; this.meleeEquip = null; this.manualEquipHeld = false; this.actualWeapon = null;
    this.local = null; this.mapping = null; this.effects = [];
    this.lootSource = null; this.pickupPulse = false; this.pickupAttempt = null; this.pickupPauseUntil = 0; this.lootBackoff.reset();
    this.binds = null; this.bindsInstalled = false; this.stickyId = null; this.lastInput = -Infinity;
    this.repeatFire.reset(); this.movement.reset(); this.weaponSwitch.reset(); this.layerOverrides.clear(); this.layerHeld = false; this.mapHighlights.dispose(); this.smokeSources = []; this.stats.xray = emptyXrayStats('waiting-contract');
    this.espRenderer.reset(); this.stats.esp = emptyEspStats('waiting-mapping'); this.stats.semi = { state: 'waiting-contract', pulses: this.repeatFire.pulses }; this.stats.switchState = 'waiting-contract'; this.stats.layerState = 'disabled'; this.stats.previews = { cones: 0, bulletPaths: 0, throwPaths: 0, unsupportedColliders: 0 };
    this.clearCanvas();
  }
  installSender(game) {
    const key = discoverSender(game);
    this.timeoutKey = discoverInputTimeout(game); this.receiverKey = discoverUpdateReceiver(game);
    if (this.receiverKey) {
      const self = this;
      patchMethod(game, this.receiverKey, original => function (msg) {
        // Capture arrival before native processing; main-thread work is not network latency.
        const arrivedAt = self.win.performance.now();
        const result = Reflect.apply(original, this, arguments);
        const start = self.win.performance.now();
        try { self.observeUpdate(msg, arrivedAt); } finally { self.runtimePerf.add('snapshotHook', self.win.performance.now() - start); }
        return result;
      }, this.gameHooks);
    }
    this.senderReady = false;
    if (!key) return;
    const self = this;
    this.senderReady = patchMethod(game, key, original => function (type, data, ...rest) {
      let outgoing = data, joinRecord = null, intent = data, inputBypassed = false;
      if (type === 3) self.aimEvidence.inputCalls++;
      try {
        if (type === 1 && Number.isInteger(data?.protocol) && typeof data.name === 'string'
          && typeof data.joinToken === 'string' && (typeof data.isMobile === 'boolean' || data.isMobile === undefined)
          && typeof data.useTouch === 'boolean' && typeof data.serialize === 'function') {
          self.aimEvidence.reset(); self.grenadeTimer.reset(); self.grenadeAimTimer.reset(); self.protocol = data.protocol; self.lastMap = -Infinity;
          if (self.protocol === VERIFIED_PROTOCOL && self.config.autoLoot && self.config.lootMode === 'mobile') {
            outgoing = Object.assign(Object.create(Object.getPrototypeOf(data)), data, { isMobile: true });
          }
          joinRecord = { observed: true, forwarded: false, mobile: !!outgoing.isMobile, requested: !!self.config.autoLoot && self.config.lootMode === 'mobile' };
          self.joinState = joinRecord;
          self.report('protocol', `Join protocol ${self.protocol}; mobile loot ${self.config.autoLoot && self.config.lootMode === 'mobile' ? 'yêu cầu bật' : 'tắt'}.`);
        }
        // Source protocol 1028 DropItem is message 12; pause before forwarding,
        // including a Loot pulse already prepared earlier in this same frame.
        if (type === 12 && self.protocol === VERIFIED_PROTOCOL && typeof data?.item === 'string' && data.item.length > 0
          && Number.isInteger(data.weapIdx) && typeof data.serialize === 'function') {
          self.pickupPauseUntil = self.win.performance.now() + 3500;
          self.pickupPulse = false;
          self.stats.lootState = 'paused-after-drop';
        }
        if (type === 3 && !self.stopped && self.mapping?.ui?.spectating === false) {
          if (!inputShape(data)) { self.aimEvidence.invalidInputs++; return Reflect.apply(original, this, arguments); }
          intent = self.mouseInput.intent(self.app.input, self.mapping?.camera, data);
          const manualEquip = data.inputs.some(isManualEquip);
          if (manualEquip) { self.weaponSwitch.reset(); self.switchSlot = null; self.manualEquipHeld = true; }
          if (!self.inputReady()) { self.stats.aimState = self.inputBlockReason(); self.aimOutput = null; self.aimController.reset(); self.weaponSwitch.reset(); self.movement.reset(); self.switchSlot = null; self.meleeDirection = null; }
          else if (manualEquip) {
            // The server applies this packet's aim/movement and equip together.
            // A pre-frame melee or gun plan belongs to the previous weapon; do
            // not reuse it or move toward its target during a manual switch.
            self.aimOutput = null; self.aimPlan = null; self.aimPlanFrame = -1;
            self.meleeDirection = null; self.switchSlot = null; self.target = null; self.targetId = null; self.dot = null;
            self.aimController.reset(); self.stats.aimState = 'manual-equip';
            self.grenadePlan = null; self.grenadeState = 'manual-equip';
          }
          else {
            // A physical mouse update can arrive after the frame plan but before
            // native serialization. Revalidate instead of sending stale intent.
            const cursor = self.mouseInput.physical(self.app.input), planned = self.aimPlanCursor;
            const sameCursor = vec(cursor) && vec(planned) && cursor.x === planned.x && cursor.y === planned.y;
            const grenade = self.local?.data?.[self.local.slotKey] === 3 && ['preview', 'assist', 'lock'].includes(self.config.grenadeAimMode);
            const reusable = !data.shootStart && sameCursor && self.aimPlanFrame === self.aimFrame && self.aimPlanDirect
                && (!self.aimPlan || modeOf(self.config) !== 'lock' && !self.meleeDirection || grenade || self.mouseInput.owns(self.app.input))
                && self.aimPlanFiring === (self.binds ? !!self.binds.isBindDown(4) : !!self.app.input.mouseButtons?.[0])
                && self.aimPlanHoldAim === self.holdAim;
            const direct = !!self.mouseInput.record?.captured || (modeOf(self.config) === 'lock' || self.config.melee)
              && self.local?.data?.[self.local.slotKey] !== 3 && !!self.flushReady;
            if (grenade && (self.config.grenadeAutoThrow || reusable && self.aimPlan)) {
              self.aimOutput = self.timedProcessAim(intent, true); // Grenade geometry/fuse must be current at sender.
            } else if (reusable && self.aimPlan && self.config.wallcheck) {
              // Recheck world state but keep this frame's controller output. A
              // second smoothing step or a new target can cause a visible jump.
              self.aimOutput = self.timedProcessAim(intent, true, direct, { target: self.target, dir: self.aimPlan.dir });
            } else self.aimOutput = reusable ? self.aimPlan : self.timedProcessAim(intent, true, direct);
          }
          if (manualEquip) { self.weaponSwitch.reset(); self.switchSlot = null; self.manualEquipHeld = true; }
          self.aimOutputFrame = self.frameId;
          self.moveDirection = self.config.mobileMovement && inputShape(data) ? self.movement.sample(data, self.config.movementSmooth, self.win.performance.now()) : null;
          if (!self.config.mobileMovement) self.movement.reset();
          const physicalHeld = self.binds ? !!self.binds.isBindDown(4) : !!self.app.input.mouseButtons?.[0];
          // Fire can be released after pre() scheduled a switch but before the
          // native packet is sent. Never send that stale equip after release.
          if (!physicalHeld && self.switchSlot !== null) { self.switchSlot = null; self.weaponSwitch.reset(); }
          outgoing = self.inputReady() ? modifyMessage(intent, self.config, self) : intent;
          // The anti-recook gate belongs to the throwable hold, not all future
          // weapons or an explicit manual equip. Yield it permanently for this
          // hold when the player switches or input safety is unavailable.
          if (self.grenadeAuto.phase === 'released' && (manualEquip || !self.inputReady() || self.local?.data?.[self.local.slotKey] !== 3)) {
            self.grenadeAuto.phase = 'manual';
          }
          if (physicalHeld && data.shootStart && self.grenadeAuto.phase === 'idle') self.lastGrenadeAutoEvidence = null;
          const auto = self.grenadeAuto.observe({ held: physicalHeld, edge: data.shootStart && data.shootHold,
            enabled: self.config.grenadeAutoThrow && self.config.grenadeAimMode === 'lock' && self.local?.data?.[self.local.slotKey] === 3,
            ready: self.inputReady() && !!self.timeoutKey && Object.getOwnPropertyDescriptor(self.app.game, self.timeoutKey)?.writable === true
              && !manualEquip && !self.manualEquipHeld && !self.grenadeManualOverride && data.shootHold,
            target: self.grenadeAutoPlan?.target ?? null, viable: !!self.grenadeAutoPlan?.viable && !!self.aimOutput,
            now: self.win.performance.now() });
          if (self.config.grenadeAutoThrow && self.local?.data?.[self.local.slotKey] === 3 && physicalHeld
              && !(self.grenadeAuto.phase === 'manual' && self.lastGrenadeAutoEvidence?.phase === 'manual') && auto !== 'suppress') {
            const reason = !self.inputReady() ? self.inputBlockReason() : manualEquip || self.manualEquipHeld ? 'manual-equip'
              : self.grenadeManualOverride ? 'manual-override' : !self.timeoutKey ? 'missing-scheduler'
              : self.config.grenadeAimMode !== 'lock' ? 'requires-lock' : self.grenadeAutoPlan?.reason ?? self.grenadeState;
            const measuredAt = self.win.performance.now();
            self.lastGrenadeAutoEvidence = { phase: self.grenadeAuto.phase, action: auto, reason,
              rttMs: finite(self.timing.rtt) ? Math.round(self.timing.rtt) : null,
              lastRttMs: finite(self.timing.lastRtt) ? Math.round(self.timing.lastRtt) : null,
              rttAgeMs: finite(self.timing.rttAt) ? Math.max(0, Math.round(measuredAt - self.timing.rttAt)) : null,
              recordedAt: measuredAt };
          }
          if (auto === 'cancel') {
            self.grenadeManualOverride = true; self.aimOutput = null; self.grenadePlan = null;
            outgoing = self.inputReady() ? modifyMessage(intent, self.config, self) : intent;
          }
          if (auto === 'release' || auto === 'suppress') {
            // Clone native message: never mutate the game's input. Suppress both
            // held and start until physical release, so it cannot recook.
            outgoing = Object.assign(Object.create(Object.getPrototypeOf(outgoing)), outgoing, { shootStart: false, shootHold: false });
            self.grenadeManualOverride = true;
          }
          if (!self.aimOutput || auto === 'suppress') self.restoreInput();
          if (self.meleeDirection && self.switchSlot === 2 && outgoing !== data && outgoing.inputs.includes(13)) self.meleeEquip = { id: self.target?.__id, until: self.win.performance.now() + 1000 };
          self.switchSlot = null;
        }
      } catch (e) { if (type === 3) { self.aimEvidence.inputErrors++; inputBypassed = true; } self.report('warning', `Input bypassed: ${e.message}`); self.aimOutput = null; self.restoreInput(); outgoing = intent; }
      const result = Reflect.apply(original, this, [type, outgoing, ...rest]);
      if (type === 3 && inputShape(outgoing)) {
        const now = self.win.performance.now();
        if (self.grenadeAuto.phase === 'armed') self.lastGrenadeAutoSent = now;
        self.aimEvidence.sent(intent, outgoing, !!self.aimOutput, now, self.inputReady(), {
          physicalHeld: self.binds ? !!self.binds.isBindDown(4) : !!self.app.input.mouseButtons?.[0], aimKeyHeld: self.holdAim,
          aimState: inputBypassed ? 'input-bypassed-error' : self.stats.aimState, rejections: inputBypassed ? {} : self.stats.aimRejections,
          directMouseEnabled: self.config.directMouseInput !== false, directMouseActive: !!self.mouseInput.record,
        });
        self.lastAimSent = self.aimOutput ? point(outgoing.toMouseDir) : null; self.timing.sent(outgoing, now);
        if (self.config.grenadeTimer || self.grenadeTimer.active) self.guard('grenade-timer', () => self.grenadeTimer.forwarded(self.grenadeContext(), outgoing, now, outgoing.inputs.some(isManualEquip)));
        if (self.config.grenadeAimMode !== 'off' && self.config.grenadeAimMode) self.grenadeAimTimer.forwarded({ ...self.grenadeContext(), enabled: true }, outgoing, now, outgoing.inputs.some(isManualEquip));
        if (self.grenadeManualOverride && intent.shootHold === false && !(self.binds ? self.binds.isBindDown(4) : self.app.input.mouseButtons?.[0])) self.grenadeManualOverride = false;
      }
      if (joinRecord) joinRecord.forwarded = true; // Forwarded to native sender; not a server acknowledgement.
      return result;
    }, this.gameHooks);
  }
  configurationChanged(key) {
    this.restoreInput(); this.aimPlanFrame = -1; this.aimOutputFrame = -1; this.aimPlanDirect = false;
    this.lastVisual = -Infinity;
    if (key === 'layerKey' || key === 'layerSpoofer') { this.layerHeld = false; this.layerOverrides.clear(); }
    if (['aim', 'aimMode', 'aimActivation'].includes(key)) { this.aimController.reset(); this.stickyId = null; }
    if (key === 'grenadeTimer') this.grenadeTimer.reset();
    if (key === 'grenadeAimMode' || key === 'grenadeAimActivation') { this.grenadeAimTimer.reset(); this.grenadePlan = null; }
    if (['autoSwitch', 'useOneGun', 'autoMelee', 'melee'].includes(key)) { this.weaponSwitch.reset(); this.meleeEquip = null; }
    if (key === 'autoLoot' || key === 'lootMode') this.pickupPulse = false;
    if (['mapHighlights', 'smallerTrees'].includes(key)) this.mapHighlights.sync(this.app.game, this.mapping?.map);
    // A slider changes policy, not source contracts: do not force AST discovery.
  }
  reconcile(force = false) {
    const now = this.win.performance.now(), game = this.app.game;
    if (game !== this.lastGame) {
      this.releaseMatch(); this.gameHooks?.clear(); this.gameHooks = new Disposables();
      this.lastGame = game; this.aimEvidence.reset(); this.protocol = null; this.lastPool = null; this.lastActive = null;
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
    const discoveryStart = this.win.performance.now();
    const next = discover(game);
    this.runtimePerf.add('discovery', this.win.performance.now() - discoveryStart);
    if (next.pool !== this.lastPool || next.active !== this.lastActive || next.active?.__id !== this.lastActiveId) {
      this.releaseMatch(); this.failed.clear();
      this.lastPool = next.pool; this.lastActive = next.active; this.lastActiveId = next.active?.__id;
    }
    this.mapping = next;
    this.mapHighlights.sync(game, next.map);
    if (next.active && next.schema) this.sourceFields = discoverSourceFields(next.active, next.schema);
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
      names: !!(next.barn && next.pool && next.active?.active),
      visuals: ready, interpolatedOverlay: ready && !!next.visualPosKey,
      grenadeZones: ready && !!this.definitions && !!next.registryKey && this.protocol === VERIFIED_PROTOCOL,
      grenadeTimer: ready && !!this.local && !!this.definitions && this.senderReady && !!next.ui && this.protocol === VERIFIED_PROTOCOL,
      aim: ready && this.senderReady && !!this.timeoutKey && !!next.ui && this.protocol === VERIFIED_PROTOCOL,
      autoPickup: ready && !!next.ui && !!this.lootSource && !!this.binds && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
      previews: ready && !!this.definitions && this.protocol === VERIFIED_PROTOCOL, prediction: ready && !!this.definitions && !!this.receiverKey && !!this.sourceFields?.pos, wallcheck: !!next.creator && !!next.registryKey,
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
        && self.inputReady() && self.pickupStillValid()) return true;
      if (code !== 4) return actual;
      const m = self.mapping, weapon = localWeapon(m), def = self.definitions?.[weapon];
      const pulse = self.repeatFire.sample({ frame: self.frameId, now: self.win.performance.now(), weapon, def,
        held: !!this.isBindDown(4), enabled: self.config.semi, protocolMatches: self.protocol === VERIFIED_PROTOCOL,
        paused: !self.inputReady() || self.emoteOpen() || !m?.active?.active
          || !m.schema || m.ui?.spectating !== false || m.active.downed === true || !!at(m.active, [m.schema.netKey, m.schema.deadKey]),
      });
      self.stats.semi = { state: self.repeatFire.state, pulses: self.repeatFire.pulses };
      return actual || pulse;
    }, this.matchHooks);
    if (this.bindsInstalled) this.matchHooks.add(() => { this.bindsInstalled = false; });
  }
  blocked(from, to, bulletPath = true, source = null) {
    if (!this.config.wallcheck) return false;
    if (!this.capabilities.wallcheck) return true;
    // Cheap spatial rejection first; keep the eligibility and budget semantics
    // unchanged, including unsupported shapes which must still fail closed.
    const nearby = segmentCandidates(source || this.mapping.obstacles(), from.pos, to.pos);
    const relevant = nearby.filter(o => read(o, 'active') !== false && !read(o, 'dead') && read(o, 'collidable') !== false
      && !(bulletPath && this.protocol === VERIFIED_PROTOCOL && finite(read(o, 'height')) && read(o, 'height') < BULLET_HEIGHT)
      && (!finite(read(o, 'layer')) || sameLayer(read(o, 'layer'), from.layer)));
    if (relevant.length > 1024) return true;
    return relevant.some(o => segmentBlocked(from.pos, to.pos, read(o, 'collider')));
  }
  blockedByPlayer(from, to, target, players) {
    if (!this.config.wallcheck) return false;
    const m = this.mapping;
    return players.some(p => {
      if (p === target || p === m.active || read(p, 'active') !== true || at(p, [m.schema.netKey, m.schema.deadKey])) return false;
      const layer = this.sourceLayer(p);
      if (finite(layer) && !sameLayer(layer, from.layer) && !(layer & 2)) return false;
      const pos = this.sourcePos(p), scale = at(p, [m.schema.netKey, this.sourceFields?.scale]);
      if (!vec(pos)) return false; // Unknown remote player positions cannot be reconstructed.
      return segmentBlocked(from.pos, to.pos, { type: 0, pos, rad: finite(scale) && scale > 0 ? scale : 1 });
    });
  }
  grenadeContext() {
    const slot = this.local?.data?.[this.local.slotKey], type = this.local?.data?.[this.local.weaponsKey]?.[3]?.type;
    return { enabled: !!this.config.grenadeTimer, ready: this.inputReady(), owner: this.mapping?.active, slot, type,
      activeType: this.mapping ? localWeapon(this.mapping) : null, definitions: this.definitions };
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
    if (this.config.grenadeTimer || this.grenadeTimer.active) this.guard('grenade-timer', () => this.grenadeTimer.validate(this.grenadeContext()));
    this.updateLayer();
    this.switchSlot = null;
    if (this.inputReady()) this.updateSwitch(); else this.weaponSwitch.reset();
    const aimFrame = ++this.aimFrame, directMouse = this.config.directMouseInput !== false && !!this.flushReady;
    const plan = this.timedProcessAim(null, directMouse, directMouse);
    this.aimPlan = plan; this.aimPlanFrame = aimFrame; this.aimPlanDirect = directMouse;
    this.aimPlanCursor = this.mouseInput.physical(this.app.input);
    this.aimPlanFiring = this.binds ? !!this.binds.isBindDown(4) : !!this.app.input.mouseButtons?.[0]; this.aimPlanHoldAim = this.holdAim;
    const needsRestore = !plan && this.lastAimSent;
    const needsAim = plan && (!this.lastAimSent || Math.abs(angleDelta(Math.atan2(this.lastAimSent.y, this.lastAimSent.x), Math.atan2(plan.dir.y, plan.dir.x))) > Math.PI / 1800 || plan.toMouseHit && Math.abs((this.lastAimDistance || 0) - plan.distance) > .5);
    const autoTick = this.grenadeAuto.phase === 'armed' && this.config.grenadeAutoThrow && this.inputReady()
      && this.win.performance.now() - this.lastGrenadeAutoSent >= 33;
    if (this.timeoutKey && (needsAim || needsRestore || this.switchSlot !== null || autoTick) && this.app.game?.initialized && this.mapping?.ui?.spectating === false) {
      const d = Object.getOwnPropertyDescriptor(this.app.game, this.timeoutKey);
      if (d && 'value' in d && d.writable) { this.app.game[this.timeoutKey] = 0; this.aimEvidence.requests++; }
    }
    // Loot is not needed for aim or aim scheduling; process it afterwards.
    this.updateLoot();
  }
  observeUpdate(msg, arrivedAt = this.win.performance.now()) {
    this.guard('snapshot-update', () => {
      // Native processing may replace the active-player reference before the
      // next frame; do not wait for the normal one-second discovery throttle.
      this.reconcile(msg.activePlayerIdDirty === true);
      const m = this.mapping, fields = this.sourceFields, now = arrivedAt;
      this.timing.received(msg, now);
      // Team info and local weapon changes can arrive without world objects.
      // They invalidate selection just like position, death and cover updates.
      // Do not send an extra packet or recompute inside the receiver.
      if ((msg.fullObjects || []).length || (msg.partObjects || []).length || (msg.delObjIds || []).length
        || (msg.playerInfos || []).length || (msg.deletedPlayerIds || []).length
        || msg.activePlayerIdDirty === true || msg.activePlayerData?.weapsDirty === true) {
        this.aimPlanFrame = -1; this.grenadePlan = null;
      }
      if (!m?.schema || !fields?.pos) return;
      for (const id of msg.delObjIds || []) {
        const old = this.observedEntities.get(id); if (old) { this.tracker.forget(old); this.grenadeTracker.forget(old); }
        this.observedEntities.delete(id);
      }
      const ids = new Set(), mentioned = new Set();
      for (const list of [msg.fullObjects || [], msg.partObjects || []]) for (const o of list) { mentioned.add(o.__id); if (vec(o.pos)) ids.add(o.__id); }
      // Source sends a visible player's position whenever that player's position
      // changes; absence from consecutive complete updates is a bounded
      // stationary inference, not a new observed position or server ACK. Keep it
      // separate from observed gun velocity and reset on missing/stalled updates.
      const needsInference = this.config.grenadeAimMode && this.config.grenadeAimMode !== 'off'
        || this.config.aim && this.config.aimMode !== 'off' && this.config.predict;
      const complete = needsInference && this.protocol === VERIFIED_PROTOCOL
        && Array.isArray(msg.fullObjects) && Array.isArray(msg.partObjects) && Array.isArray(msg.delObjIds);
      const sameTick = complete && this.grenadeUpdateAt !== null && now === this.grenadeUpdateAt;
      const cadence = complete && this.grenadeUpdateAt !== null && now > this.grenadeUpdateAt && now - this.grenadeUpdateAt <= 150;
      // Ordered updates may arrive in the same local clock tick. Preserve the
      // history, but do not infer a new stationary sample without elapsed time.
      if (!cadence && !sameTick) this.grenadeTracker.reset();
      this.grenadeUpdateAt = complete ? now : null;
      const players = complete || ids.size ? m.players() : null;
      const visible = complete ? new Set(players) : null;
      if (complete) for (const [id, p] of this.observedEntities) {
        if (!visible.has(p) || p.__id !== id || !p.active || mentioned.has(id) && !ids.has(id)) { this.grenadeTracker.forget(p); continue; }
        if (!mentioned.has(id) && cadence) {
          const pos = at(p, [m.schema.netKey, fields.pos]), layer = this.sourceLayer(p);
          if (vec(pos) && Number.isInteger(layer)) {
            const s = this.grenadeTracker.states.get(p);
            // Already-stable omitted players do not need another regression on
            // every packet. Real position updates always bypass this fast path.
            const settled = s?.id === id && s.layer === layer && now > s.time && now - s.time < 50
              && Math.hypot(s.vx, s.vy) < .1 && s.samples?.length >= 3
              && s.samples.every(o => Math.hypot(o.p.x - pos.x, o.p.y - pos.y) < .02);
            if (!settled) this.grenadeTracker.observe(p, pos, now, layer);
          }
        }
      }
      // Most control-only updates do not change positions: avoid a full player scan for gun prediction.
      if (!ids.size) return;
      const live = visible || new Set(players);
      for (const [id, p] of this.observedEntities) if (!live.has(p) || p.__id !== id) { this.tracker.forget(p); this.observedEntities.delete(id); }
      for (const p of players) if (ids.has(p.__id)) {
        const old = this.observedEntities.get(p.__id); if (old && old !== p) { this.tracker.forget(old); this.grenadeTracker.forget(old); }
        this.observedEntities.set(p.__id, p);
        this.tracker.observe(p, at(p, [m.schema.netKey, fields.pos]), now, this.sourceLayer(p));
        if (complete && Number.isInteger(this.sourceLayer(p))) this.grenadeTracker.observe(p, at(p, [m.schema.netKey, fields.pos]), now, this.sourceLayer(p));
      }
    });
  }
  sourcePos(p) { return at(p, [this.mapping?.schema?.netKey, this.sourceFields?.pos]) || read(p, this.mapping?.schema?.posKey); }
  sourceLayer(p) { return at(p, [this.mapping?.schema?.netKey, this.sourceFields?.layer]) ?? this.layerOverrides.getRaw(p, 'layer'); }
  inputBlockReason() {
    const m = this.mapping, doc = this.win.document; let el = doc.activeElement;
    const menuFocused = el?.id === 'duality-reborn-host' && !el.shadowRoot?.querySelector('#ui')?.hidden;
    while (el?.shadowRoot?.activeElement) el = el.shadowRoot.activeElement;
    if (!this.app.game?.initialized) return 'not-in-game';
    if (!m?.schema || !m.active?.active) return 'missing-player-mapping';
    if (!m.ui) return 'missing-spectator-contract';
    if (m.ui.spectating !== false) return 'spectating';
    if (m.active.downed) return 'downed';
    if (at(m.active, [m.schema.netKey, m.schema.deadKey])) return 'dead';
    if (doc.hidden) return 'page-hidden';
    if (this.focusBlocked) return 'blurred';
    if (menuFocused) return 'menu-open';
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes(el?.tagName) || el?.isContentEditable) return 'typing';
    if (this.binds?.menuHovered) return 'native-menu-hovered';
    if (this.emoteOpen()) return 'emote-open';
    if (this.failed.has('input-frame')) return 'input-frame-error';
    if (this.protocol === null) return 'awaiting-join-protocol';
    if (this.protocol !== VERIFIED_PROTOCOL) return 'unsupported-protocol';
    return null;
  }
  inputReady() { return this.inputBlockReason() === null; }
  emoteOpen() { return entries(this.app.game).some(([, child]) => read(child, 'wheelDisplayed') === true); }
  processGrenadeAim({ native, applyDirect, pos, mouse, camera, physical, firing, now }) {
    const m = this.mapping, cfg = this.config, mode = cfg.grenadeAimMode;
    // Preserve only anonymous status so opening Help does not erase the last
    // live failure; menu focus intentionally blocks input before reaching here.
    const record = state => { this.grenadeState = state; this.lastGrenadeEvidence = { state, recordedAt: now }; };
    const fail = reason => {
      record(reason); this.grenadePlan = null;
      if (firing && this.grenadeAuto.phase === 'armed' && this.grenadeAuto.target !== null) {
        this.grenadeAuto.phase = 'manual'; this.grenadeManualOverride = true; this.restoreInput();
        this.lastGrenadeAutoEvidence = { phase: 'manual', action: 'cancel', reason, recordedAt: now };
      }
      return null;
    };
    if (this.grenadeManualOverride) { this.grenadeState = 'manual-override'; this.grenadePlan = null; return null; }
    if (!this.capabilities.aim || !this.capabilities.prediction || !this.capabilities.wallcheck || !this.local || this.manualEquipHeld) return fail('missing-contract');
    const ctx = { ...this.grenadeContext(), enabled: true }, def = this.definitions?.[ctx.type];
    if (!def || ctx.type !== ctx.activeType) return fail('missing-throwable');
    const perks = at(m.active, [m.schema.netKey, this.sourceFields?.perks]);
    if (!Array.isArray(perks) || perks.some(p => p?.type === 'amped_explosives')) return fail('unknown-or-amped-perks');
    const map = m.map, surface = readMethod(map, 'getGroundSurface');
    if (!surface) return fail('missing-terrain');
    const playerTrack = this.grenadeTracker.estimate(m.active, now);
    if (!playerTrack || playerTrack.age > .15 || playerTrack.samples?.length < 2 || !finite(playerTrack.vx) || !finite(playerTrack.vy)) return fail('missing-own-velocity');
    const myVelocity = { x: playerTrack.vx, y: playerTrack.vy }, layer = this.sourceLayer(m.active);
    // Retain the observed fuse for the native release packet as well: the
    // server consumes direction and shootHold together when throwing. Do not
    // revert to a full fuse between physical release and sender forwarding.
    const timer = this.grenadeAimTimer.sample(ctx, now);
    if (firing && !timer) return fail('waiting-for-forwarded-fire');
    const fuse = timer ? timer.seconds : def.fuseTime;
    if (!finite(fuse) || fuse < .15 || fuse > 10) return fail('invalid-fuse');
    const relations = teamRelations(m.barn, m.active.__id);
    if (!relations.ready) return fail('missing-team');
    const scale = read(camera.camera, camera.scaleKeys[0]) * read(camera.camera, camera.scaleKeys[1]);
    if (!finite(scale) || scale <= 0) return fail('missing-camera');
    const cursor = native ? { x: read(camera.camera, camera.widthKey) / 2 + physical.x * native.toMouseLen * scale, y: read(camera.camera, camera.heightKey) / 2 - physical.y * native.toMouseLen * scale } : mouse;
    const candidates = [];
    for (const p of m.players().slice(0, 256)) {
      const relation = relations.classify(p.__id).kind;
      if (p === m.active || !p.active || at(p, [m.schema.netKey, m.schema.deadKey]) || (!cfg.knocked && p.downed)
          || !(relation === 'enemy' || cfg.grenadeAimAllies && relation === 'ally') || !sameLayer(layer, this.sourceLayer(p))) continue;
      const target = this.sourcePos(p), screen = aimPoint(camera, target, pos), track = this.grenadeTracker.estimate(p, now);
      if (!screen || !track || track.age > .15 || track.samples?.length < 2 || !finite(track.vx) || !finite(track.vy)) continue;
      const distance = Math.hypot(screen.x - cursor.x, screen.y - cursor.y);
      if (distance <= (cfg.grenadeFov ?? cfg.fov)) candidates.push({ p, target, track, distance });
    }
    candidates.sort((a, b) => a.distance - b.distance);
    if (!candidates.length) return fail('no-target-or-fresh-track');
    const geometry = geometryObjects(read(m.creator, m.registryKey));
    if (!geometry.valid) return fail('missing-geometry');
    const obstacles = geometry.obstacles;
    // Only accept surface types present in the pinned upstream contract. An
    // unknown future surface must not silently be treated as dry ground.
    const drySurfaces = new Set(['asphalt', 'brick', 'bunker', 'carpet', 'container', 'grass', 'shack', 'snow', 'stone', 'tile', 'warehouse', 'house', 'sand']);
    const groundAt = (point, floor) => { const result = Reflect.apply(surface, map, [point, floor]); return drySurfaces.has(result?.type) ? 'ground' : 'unknown'; };
    for (const c of candidates.slice(0, 3)) {
      if (firing && this.grenadeAuto.phase === 'armed' && this.grenadeAuto.target !== null && c.p !== this.grenadeAuto.target)
        return fail('auto-target-changed');
      const transit = this.timing.transit(now);
      const solution = solveMovingOpenThrow({ def, origin: pos, target: c.target, playerVelocity: myVelocity, targetVelocity: { x: c.track.vx, y: c.track.vy }, fuseRemaining: fuse, releaseDelay: transit + c.track.age });
      if (!solution) continue;
      const checked = validateOpenThrow({ solution, origin: pos, def, layer, obstacles, groundAt });
      if (!checked.ok) { this.grenadeState = checked.reason; continue; }
      this.grenadePlan = { points: solution.points, end: solution.end, type: ctx.type };
      if (native && cfg.grenadeAutoThrow && mode === 'lock' && firing && timer) {
        // Unknown or high RTT, recently changed movement, and missing target
        // identity are not sufficient evidence for an automatic release.
        const stable = c.track.samples?.length >= 3 && playerTrack.samples?.length >= 3;
        const timingKnown = finite(this.timing.rtt) && this.timing.rtt <= 160 && finite(this.timing.lastRtt)
          && this.timing.lastRtt <= 160 && finite(this.timing.rttAt) && now >= this.timing.rttAt && now - this.timing.rttAt <= 1500;
        const result = stable && timingKnown ? assessAutoThrow({ def, explosion: this.definitions?.[def.explosionType],
          selfRadius: at(m.active, [m.schema.netKey, this.sourceFields?.scale]), origin: pos, direction: solution.direction,
          mouseDistance: solution.mouseDistance, playerVelocity: myVelocity, target: c.target,
          targetVelocity: { x: c.track.vx, y: c.track.vy }, fuseRemaining: fuse,
          releaseDelay: transit + c.track.age, layer, obstacles, groundAt, bounds: { width: read(map, 'width'), height: read(map, 'height') } })
          : { ok: false, reason: !stable ? 'insufficient-track-samples' : 'latency-unavailable-or-high' };
        this.grenadeAutoPlan = { target: c.p, viable: result.ok, reason: result.reason };
      }
      record(timer ? 'estimate-unconfirmed' : 'estimate-before-throw');
      if (mode === 'preview' || cfg.grenadeAimActivation !== 'equip' && !firing && !timer) return null;
      const strength = mode === 'assist' ? clamp((cfg.grenadeAssistStrength ?? 35) / 100, 0, 1) : 1;
      if (strength === 0) return null;
      const a = Math.atan2(physical.y, physical.x), b = Math.atan2(solution.direction.y, solution.direction.x), angle = a + angleDelta(a, b) * strength;
      const dir = { x: Math.cos(angle), y: Math.sin(angle) };
      const nativeLength = native?.toMouseLen ?? Math.hypot(mouse.x - read(camera.camera, camera.widthKey) / 2, mouse.y - read(camera.camera, camera.heightKey) / 2) / scale;
      const distance = clamp(nativeLength + (solution.mouseDistance - nativeLength) * strength, 0, 64);
      if (applyDirect && this.config.directMouseInput !== false && this.flushReady) this.mouseInput.apply(this.app.input, camera, { dir, distance, toMouseHit: true });
      return { dir, distance, toMouseHit: true };
    }
    return fail(this.grenadeState === 'off' ? 'no-clear-solution' : this.grenadeState);
  }
  timedProcessAim(native, advance, applyDirect = false, recheck = null) {
    const start = this.win.performance.now();
    try { return this.processAim(native, advance, applyDirect, recheck); }
    finally { this.runtimePerf.add(native ? 'aimSender' : 'aimFrame', this.win.performance.now() - start); }
  }
  processAim(native, advance, applyDirect = false, recheck = null) {
    const m = this.mapping, cfg = this.config, mode = modeOf(cfg), now = this.win.performance.now();
    this.grenadePlan = null; this.grenadeAutoPlan = null; this.grenadeState = 'off';
    this.aimPreparation = null;
    this.target = null; this.targetId = null; this.dot = null; this.meleeDirection = null; this.stats.aimRejections = {}; this.stats.predictionState = null; this.stats.aimApproximate = false;
    const blockedInput = this.inputBlockReason();
    const note = state => this.aimEvidence.attempt(state, { mode, activation: cfg.aimActivation, wallcheckRequested: !!cfg.wallcheck,
      wallcheckAvailable: !!this.capabilities.wallcheck, predictionRequested: !!cfg.predict }, this.stats.aimRejections, now, !blockedInput);
    const fail = state => {
      this.stats.aimState = state; this.aimController.reset(); if (state !== 'wall-blocked' || !cfg.sticky) this.stickyId = null; this.target = null; this.targetId = null; this.dot = null; note(state); return null;
    };
    if (blockedInput) return fail(blockedInput);
    const pos = this.sourcePos(m.active), mouse = this.mouseInput.physical(this.app.input), camera = m.camera;
    if (!vec(pos) || !vec(mouse) || !camera) return fail('invalid-input-position');
    const physical = native?.toMouseDir || unit({ x: mouse.x - read(camera.camera, camera.widthKey) / 2, y: read(camera.camera, camera.heightKey) / 2 - mouse.y }) || { x: 1, y: 0 };
    if (!unit(physical)) return fail('invalid-direction');
    const actualWeapon = localWeapon(m);
    if (actualWeapon !== this.actualWeapon) { this.aimController.reset(); this.actualWeapon = actualWeapon; }
    const firing = this.binds ? !!this.binds.isBindDown(4) : !!this.app.input.mouseButtons?.[0];
    if (!firing) { this.manualEquipHeld = false; this.meleeEquip = null; }
    if (this.local?.data?.[this.local.slotKey] === 3 && ['preview', 'assist', 'lock'].includes(cfg.grenadeAimMode)) {
      this.aimController.reset(); return this.processGrenadeAim({ native, applyDirect, pos, mouse, camera, physical, firing, now });
    }
    const trigger = cfg.aimActivation === 'key' ? this.holdAim : cfg.aimActivation === 'both' ? this.holdAim && firing : firing;
    const gun = this.definitions?.[localWeapon(m)], slot = this.local?.data[this.local.slotKey];
    const meleeDef = gun?.type === 'melee' ? gun : cfg.autoMelee && [0, 1].includes(slot) ? this.definitions?.[this.local?.data[this.local.weaponsKey]?.[2]?.type] : null;
    const reach = meleeReach(meleeDef), melee = !!(cfg.melee && !this.manualEquipHeld && this.capabilities.mobile && firing && reach);
    if ((mode === 'off' || !this.capabilities.aim) && !melee) return fail(mode === 'off' ? 'disabled' : 'missing-input-scheduler');
    if ((melee || mode === 'lock') && (cfg.directMouseInput === false || !this.flushReady)) return fail('lock-mouse-unavailable');
    // Do not preselect or solve within FOV until explicitly activated.
    if (!trigger && !melee) return fail('waiting-activation');
    if (mode === 'assist' && cfg.assistStrength === 0 && !melee) return fail('assist-zero');
    const relations = teamRelations(m.barn, m.active.__id);
    if (!relations.ready) return fail('missing-own-team');
    if (cfg.wallcheck && !this.capabilities.wallcheck) return fail('wallcheck-unavailable');
    const scale = read(camera.camera, camera.scaleKeys[0]) * read(camera.camera, camera.scaleKeys[1]);
    const inputCursor = native ? { x: read(camera.camera, camera.widthKey) / 2 + physical.x * native.toMouseLen * scale,
      y: read(camera.camera, camera.heightKey) / 2 - physical.y * native.toMouseLen * scale } : mouse;
    const rawLayer = this.sourceLayer(m.active), selfRadius = at(m.active, [m.schema.netKey, this.sourceFields?.scale]) || 1;
    // Defer the registry and obstacle scans until a plausible target needs them.
    let geometry;
    const world = () => geometry ||= geometryObjects(read(m.creator, m.registryKey));
    const layerFor = dir => shotLayer(pos, dir, rawLayer, selfRadius, world().structures);
    // Source bullet collision admits a player on either stair layer even when
    // the ground parity differs. Melee instead uses sameLayer(player.layer).
    const targetOnLayer = (targetLayer, attackLayer) => targetLayerEligible(targetLayer, attackLayer, melee);
    let possibleLayers;
    const layersForAnyDirection = () => possibleLayers ||= [
      { x: 1, y: 0 }, { x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 },
    ].map(layerFor);
    const candidates = [], reject = key => { this.stats.aimRejections[key] = (this.stats.aimRejections[key] || 0) + 1; };
    const players = m.players();
    for (const p of players.slice(0, 256)) {
      if (p === m.active || at(p, [m.schema.netKey, m.schema.deadKey])) continue;
      if (!cfg.knocked && p.downed) { reject('downed'); continue; }
      const relation = relations.classify(p.__id).kind;
      if (!(relation === 'enemy' || cfg.aimAllies && relation === 'ally')) { reject(relation === 'unknown' ? 'unknownTeam' : 'teammate'); continue; }
      const target = this.sourcePos(p), screen = aimPoint(camera, target, pos); if (!screen) continue;
      const distance = melee ? Math.hypot(target.x - pos.x, target.y - pos.y) : Math.hypot(screen.x - inputCursor.x, screen.y - inputCursor.y);
      const stickyCurrent = !!cfg.sticky && p.__id === this.stickyId;
      // Lock + Keep target retains the already-selected player for the active
      // hold, even when physical cursor motion crosses the acquisition FOV.
      // All live/team/layer, prediction and wall checks below still apply.
      // Assist and initial acquisition continue to use the normal FOV.
      const retainLock = !melee && mode === 'lock' && trigger && stickyCurrent;
      const radius = melee ? reach : cfg.fov * (stickyCurrent ? 1.25 : 1);
      if (!retainLock && distance > radius) { reject('outsideFov'); continue; }
      // The discovered registry can disappear or become unreadable between
      // reconciliations. An empty failed scan is not evidence of clear cover.
      if (cfg.wallcheck && !world().valid) return fail('wallcheck-unavailable');
      const targetLayer = this.sourceLayer(p), directLayer = melee ? rawLayer : layerFor(unit({ x: target.x - pos.x, y: target.y - pos.y }) || physical);
      // On stairs, lead or barrel offset can put the final shot in a different
      // cardinal direction and therefore a different aimLayer. Only reject here
      // if no possible cardinal direction reaches the target's layer; the
      // actual solved direction is checked again below before output.
      if (!targetOnLayer(targetLayer, directLayer) && (melee || !layersForAnyDirection().some(layer => targetOnLayer(targetLayer, layer)))) { reject('otherLayer'); continue; }
      // A real switch margin prevents two enemies on opposite sides of the FOV from
      // trading ownership every frame. The current target needs to be meaningfully
      // better before Lock/Assist changes targets.
      const score = distance * (stickyCurrent ? 0.65 : 1);
      candidates.push({ p, pos: target, distance, score, stickyCurrent });
    }
    candidates.sort((a, b) => a.score - b.score || a.distance - b.distance);
    const sticky = cfg.sticky && candidates.find(c => c.stickyCurrent);
    const ordered = recheck ? candidates.filter(c => c.p === recheck.target)
      : sticky ? [sticky, ...candidates.filter(c => c !== sticky)] : candidates;
    if (!ordered.length) return fail(recheck ? 'aim-state-changed' : 'no-candidate');
    const perks = at(m.active, [m.schema.netKey, this.sourceFields?.perks]) || [];
    const profile = weaponProfile(this.definitions, localWeapon(m), perks);
    const obstacles = profile || cfg.wallcheck ? world().obstacles : [];
    const muzzleObstacles = profile ? segmentCandidates(obstacles, pos, pos, Math.abs(profile.offset) + profile.barrel + 1.5) : [];
    if (profile && muzzleObstacles.length > 1024) return fail('muzzle-obstacle-budget');
    for (const candidate of ordered.slice(0, 6)) {
      if (recheck && (!recheck.target || candidate.p !== recheck.target || !vec(recheck.dir))) return fail('aim-state-changed');
      let shot, track = null;
      if (melee) shot = { dir: unit({ x: candidate.pos.x - pos.x, y: candidate.pos.y - pos.y }), world: candidate.pos, muzzle: pos, distance: Math.hypot(candidate.pos.x - pos.x, candidate.pos.y - pos.y), state: 'melee' };
      else {
        // Prediction is an enhancement, not a second hidden master switch for
        // basic aim. Never fabricate velocity, bullet speed or gun identity.
        if (!profile && !([0, 1].includes(slot) && !gun)) return fail('unsupported-weapon-profile');
        const predictionReady = !!(cfg.predict && profile && this.capabilities.prediction);
        track = predictionReady ? this.tracker.estimate(candidate.p, now) : null;
        let inferredStationary = false;
        if (predictionReady && (!track || track.age > .15) && this.tracker.states.has(candidate.p)) {
          // A visible player omitted by a continuous source-shaped update stream
          // may be stationary. Do not fabricate velocity for moving targets or
          // use this fallback in strict prediction; real updates always win.
          const stationary = this.grenadeTracker.estimate(candidate.p, now);
          const recent = stationary && stationary.age <= .15 && stationary.samples?.length >= 2
            && Math.hypot(stationary.vx, stationary.vy) < .2 && stationary.samples.every(s => Math.hypot(s.p.x - stationary.pos.x, s.p.y - stationary.pos.y) < .02);
          if (!cfg.predictionStrict && recent) {
            track = { ...stationary, vx: 0, vy: 0, error: 0, velocityError: 0, motion: [] }; inferredStationary = true;
          } else { reject('staleSnapshot'); continue; }
        }
        if (!profile) {
          shot = { dir: unit({ x: candidate.pos.x - pos.x, y: candidate.pos.y - pos.y }), world: candidate.pos, muzzle: pos,
            distance: Math.hypot(candidate.pos.x - pos.x, candidate.pos.y - pos.y), state: 'direct-missing-definitions', approximate: true };
        } else {
          shot = predictShot({ origin: pos, target: candidate.pos, track, profile,
            latency: track && cfg.latencyCompensation ? this.timing.transit(now) : 0, compensateSnapshot: mode === 'lock', lead: (cfg.leadAdjustment ?? 100) / 100,
            radius: at(candidate.p, [m.schema.netKey, this.sourceFields?.scale]) || 1, stabilize: mode === 'lock' && cfg.stabilizeStrafe !== false,
            muzzleFor: (origin, dir, model) => clippedMuzzle(origin, dir, model, muzzleObstacles, layerFor(dir), rawLayer & 1) });
          if (shot.dir && cfg.predict && !track) { shot.state = predictionReady ? 'direct-awaiting-snapshot' : 'direct-prediction-unavailable'; shot.approximate = true; }
          if (shot.dir && inferredStationary) { shot.state = 'inferred-stationary'; shot.approximate = true; }
          // Strict prediction is an accuracy-first fallback policy: do not invent a
          // confident solution from stale/missing snapshots or large slope uncertainty.
          if (cfg.predictionStrict && (shot.approximate || shot.confidence < .85 || shot.state === 'uncertain')) { reject('predictionUncertain'); continue; }
        }
      }
      if (!shot.dir) { reject(shot.state); continue; }
      const shotAimLayer = melee ? rawLayer : layerFor(shot.dir);
      if (!targetOnLayer(this.sourceLayer(candidate.p), shotAimLayer)) { reject('aimLayer'); continue; }
      const hitRadius = melee ? 0 : at(candidate.p, [m.schema.netKey, this.sourceFields?.scale]) || 1;
      const rayFrom = { pos: shot.muzzle, layer: shotAimLayer };
      const rayTo = { pos: pathToTarget(shot.muzzle, shot.world, hitRadius) };
      if (this.blocked(rayFrom, rayTo, !melee, obstacles) || !melee && this.blockedByPlayer(rayFrom, rayTo, candidate.p, players)) {
        reject('wall');
        // Keep-target intentionally waits for its selected target. Without it,
        // try the other already-filtered candidates, but a sender recheck must
        // never change the target of a cached direction in the same frame.
        if (cfg.sticky) this.stickyId = candidate.p.__id;
        if (cfg.sticky || recheck) return fail('wall-blocked');
        continue;
      }
      this.target = candidate.p; this.targetId = candidate.p.__id; this.stickyId = candidate.p.__id;
      this.stats.predictionState = shot.state;
      this.stats.aimApproximate = !!shot.approximate;
      const dir = recheck ? recheck.dir : advance ? this.aimController.step(physical, shot.dir, { mode: melee ? 'lock' : mode, strength: cfg.assistStrength ?? 35,
        smooth: melee || !cfg.humanLikeAim ? 0 : cfg.smooth, now, target: candidate.p, humanLike: !!cfg.humanLikeAim, profile: cfg.smoothProfile || 'responsive',
        cursorRadius: Math.hypot(mouse.x - read(camera.camera, camera.widthKey) / 2, mouse.y - read(camera.camera, camera.heightKey) / 2),
        targetRadius: shot.distance * scale }) : !melee && mode === 'assist' ? this.aimController.step(physical, shot.dir, { mode, strength: cfg.assistStrength ?? 35, now, target: candidate.p }) : shot.dir;
      if (recheck && melee && (Math.abs(dir.x - shot.dir.x) > 1e-6 || Math.abs(dir.y - shot.dir.y) > 1e-6)) return fail('aim-state-changed');
      if (cfg.wallcheck && !melee && dir && (Math.abs(dir.x - shot.dir.x) > 1e-6 || Math.abs(dir.y - shot.dir.y) > 1e-6)) {
        const actualLayer = layerFor(dir);
        if (actualLayer === null) { reject('aimLayer'); return fail('wall-blocked'); }
        const actualMuzzle = profile ? clippedMuzzle(pos, dir, profile, muzzleObstacles, actualLayer, rawLayer & 1) : pos;
        if (!vec(actualMuzzle)) { reject('uncertainMuzzle'); return fail('uncertain-muzzle'); }
        // Truncate only if this exact direction intersects the predicted hitbox;
        // otherwise inspect the entire conservative segment for cover.
        const actualFrom = { pos: actualMuzzle, layer: actualLayer }, actualTo = { pos: pathAlongAim(actualMuzzle, dir, shot.world, hitRadius) };
        if (this.blocked(actualFrom, actualTo, true, obstacles) || this.blockedByPlayer(actualFrom, actualTo, candidate.p, players)) { reject('wall'); return fail('wall-blocked'); }
      }
      // Retain the last accepted solution after Fire is released; this is not a
      // server hit record. No target ID, coordinates, or player name is kept.
      if (advance) {
        // Anonymous local-only evidence: the solver currently starts at the
        // last observed own position, not an extrapolated future muzzle.
        const ownTrack = this.tracker.estimate(m.active, now);
        const visualOwn = read(m.active, m.visualPosKey), visualTarget = read(candidate.p, m.visualPosKey);
        const visualCrossTrack = vec(visualOwn) && vec(visualTarget) && vec(dir)
          ? Math.abs((visualTarget.x - visualOwn.x) * dir.y - (visualTarget.y - visualOwn.y) * dir.x) : null;
        this.lastPredictionEvidence = {
          recordedAt: now, weapon: typeof actualWeapon === 'string' ? actualWeapon : null, mode,
          state: shot.state, approximate: !!shot.approximate,
          controllerErrorDeg: vec(dir) && vec(shot.dir) ? Math.round(Math.abs(angleDelta(Math.atan2(dir.y, dir.x), Math.atan2(shot.dir.y, shot.dir.x))) * 180000 / Math.PI) / 1000 : null,
          visualCrossTrack: finite(visualCrossTrack) ? Math.round(visualCrossTrack * 1000) / 1000 : null,
          snapshotAgeMs: finite(track?.age) ? Math.round(track.age * 1000) : null,
          estimatedSpeed: finite(track?.vx) && finite(track?.vy) ? Math.round(Math.hypot(track.vx, track.vy) * 100) / 100 : null,
          ownSnapshotAgeMs: finite(ownTrack?.age) ? Math.round(ownTrack.age * 1000) : null,
          ownEstimatedSpeed: finite(ownTrack?.vx) && finite(ownTrack?.vy) ? Math.round(Math.hypot(ownTrack.vx, ownTrack.vy) * 100) / 100 : null,
          historySamples: Array.isArray(track?.motion) ? track.motion.length : 0,
          confidence: finite(shot.confidence) ? Math.round(shot.confidence * 1000) / 1000 : null,
          rttMs: finite(this.timing.rtt) ? Math.round(this.timing.rtt) : null,
        };
      }
      this.dot = project(camera, shot.world);
      if (melee) {
        this.meleeDirection = shot.dir; this.weaponSwitch.reset(); this.switchSlot = null;
        if (slot !== 2 && cfg.autoMelee && (!this.meleeEquip || this.meleeEquip.id !== candidate.p.__id || now > this.meleeEquip.until)) this.switchSlot = 2;
      } else this.meleeEquip = null;
      const outputDistance = profile?.toMouseHit && !melee ? shot.mouseLen : shot.distance;
      const directInput = applyDirect && this.config.directMouseInput !== false && !!this.flushReady;
      const lockOwnership = mode === 'lock' || melee;
      const directApplied = directInput ? this.mouseInput.apply(this.app.input, camera, { dir, distance: outputDistance, toMouseHit: !!profile?.toMouseHit && !melee }, lockOwnership, lockOwnership) : false;
      // Never send a forced gun Lock direction while local rotation is reading
      // an unowned native mouse vector. Yield both paths instead of fighting.
      if (lockOwnership && applyDirect && !directApplied) {
        this.meleeDirection = null; this.switchSlot = null;
        return fail('lock-mouse-unavailable');
      }
      this.stats.aimState = directInput && !directApplied ? 'ready-to-send' : advance ? 'input-applied' : 'ready-to-send';
      if (advance) this.lastAimDistance = outputDistance;
      note(this.stats.aimState);
      return { dir, distance: outputDistance, toMouseHit: !!profile?.toMouseHit && !melee };
    }
    return fail(this.stats.aimRejections.wall ? 'wall-blocked' : 'no-candidate');
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
    // Manual equip owns the remainder of the physical Fire hold. Otherwise a
    // later ammo update can restart Auto Switch and undo the user's choice.
    if (this.config.autoSwitch && this.manualEquipHeld) {
      this.weaponSwitch.reset(); this.switchSlot = null; this.stats.switchState = 'manual-equip'; return;
    }
    this.switchSlot = this.weaponSwitch.sample({ enabled: this.config.autoSwitch, ready: !!(this.capabilities.switch && local),
      slot: local?.data[local.slotKey], weapons: local?.data[local.weaponsKey], definitions: this.definitions,
      held: !!this.binds?.isBindDown(4), oneGun: this.config.useOneGun, now: this.win.performance.now() });
    this.stats.switchState = this.weaponSwitch.state;
  }
  scanEffects() {
    const m = this.mapping, out = [], seen = new Set();
    if (!m) return;
    // Bounded shallow traversal of known map/barn owners, not arbitrary window/DOM graphs.
    let budget = 12000;
    const visit = (o, depth, building = null) => {
      if (!object(o) || depth < 0 || seen.has(o) || --budget < 0) return;
      seen.add(o);
      const sprite = read(o, 'sprite'), type = read(o, 'type');
      const kind = fadeObjectKind(type, this.mapDefinitions) || (read(o, 'isBush') === true ? 'vegetation' : null);
      if (sprite && kind) out.push({ owner: sprite, kind, entity: o, type });
      if (read(o, 'isCeiling') === true && sprite) out.push({ owner: sprite, kind: 'ceiling', entity: o, building });
      // Building.imgs entries have no active flag; their owning pooled building does.
      const imgs = read(o, 'imgs');
      if (Array.isArray(imgs)) {
        for (const img of imgs) { if (budget <= 0) break; visit(img, depth - 1, o); }
        return;
      }
      // Pooled obstacles and building image records are leaves for this feature.
      if (sprite) return;
      const parent = building;
      for (const [k, v] of entries(o)) {
        if (['parent', 'children', 'container', 'sprite', 'texture', '_texture', 'game', 'renderer'].includes(k)) continue;
        if (Array.isArray(v)) { for (const child of v) { if (budget <= 0) break; visit(child, depth - 1, parent); } }
        else if (depth > 0 && object(v)) visit(v, depth - 1, parent);
      }
    };
    // The current client stores obstacles and buildings in map pool arrays.
    // Traverse those first so unrelated map metadata cannot consume the budget,
    // and don't silently discard entries after index 2048.
    for (const [, pool] of entries(m.map)) {
      for (const [, values] of entries(pool)) {
        if (Array.isArray(values) && values.some(v => object(v) && typeof read(v, 'active') === 'boolean' && (object(read(v, 'sprite')) || Array.isArray(read(v, 'imgs'))))) {
          for (const value of values) { if (budget <= 0) break; if (read(value, 'active') !== false) visit(value, 2); }
        }
      }
    }
    visit(m.map, 4);
    this.effects = out;
  }
  // Native localRotation may be off; Duality also updates the active body's
  // visual rotation after native update for both gun aim and melee lock.
  syncLockRotation() {
    const m = this.mapping, record = this.mouseInput.record;
    if (!this.inputReady() || this.local?.data?.[this.local.slotKey] === 3 || !this.mouseInput.owns(this.app.input)) return;
    const firing = this.binds ? !!this.binds.isBindDown(4) : !!this.app.input.mouseButtons?.[0];
    const meleeActive = !!this.config.melee && !!this.meleeDirection && firing;
    const active = this.config.aimActivation === 'key' ? this.holdAim : this.config.aimActivation === 'both' ? this.holdAim && firing : firing;
    if (!m?.camera || !meleeActive && !(this.config.aim && modeOf(this.config) === 'lock' && active)) return;
    const body = read(m.active, 'bodyContainer'), width = read(m.camera.camera, m.camera.widthKey), height = read(m.camera.camera, m.camera.heightKey);
    if (!body || !finite(width) || !finite(height) || !vec(record?.applied)) return;
    const dx = record.applied.x - width / 2, dy = record.applied.y - height / 2;
    if (!finite(dx) || !finite(dy) || Math.hypot(dx, dy) < 1e-8) return;
    try { if (finite(body.rotation)) body.rotation = Math.atan2(dy, dx); } catch { /* Unsupported PIXI body: never affect input. */ }
  }
  post() {
    if (!this.mouseInput.record?.captured) this.restoreInput();
    this.syncLockRotation();
    // The last send in this frame can revalidate and replace the frame plan.
    // Never use last frame's unit direction as a distance for grenade preview.
    this.previewAimPlan = this.aimOutputFrame === this.frameId ? this.aimOutput
      : this.aimPlanFrame === this.aimFrame ? this.aimPlan : null;
    this.aimPlanFrame = -1; this.aimPlanDirect = false;
    const now = this.win.performance.now(); this.stats.frames++;
    if (now - this.lastVisual < 1000 / 30) return;
    this.lastVisual = now;
    const start = now, m = this.mapping, cfg = this.config;
    this.clearCanvas();
    this.stats.esp = emptyEspStats(cfg.esp ? this.win.document.hidden ? 'page-hidden' : this.ctx ? 'waiting-mapping' : 'no-canvas' : 'disabled');
    this.stats.xray = emptyXrayStats(cfg.xray ? 'waiting-contract' : 'disabled');
    if (!this.app.game?.initialized || this.win.document.hidden) { this.overrides.clear(); this.names.clear(); return; }
    const playerReady = !!(m?.schema && m.active?.active && this.capabilities.visuals);
    if (!(cfg.esp || cfg.lines || cfg.xray || cfg.zoom || cfg.aim || cfg.melee || cfg.ownFlashlight || cfg.othersFlashlight || cfg.bulletTrajectory || cfg.grenadeTrajectory || cfg.grenadeZones || cfg.grenadeTimer || cfg.grenadeAimMode !== 'off' && !!cfg.grenadeAimMode)) {
      if (this.overrides.records.size) this.overrides.clear();
      this.names.clear(); return;
    }
    const namePlayers = m?.barn && m.active?.active ? m.players() : [];
    const players = playerReady ? namePlayers : [];
    const espFrame = playerReady && (cfg.esp || cfg.lines) && this.ctx ? buildEspFrame(m, players, cfg, this.win.innerWidth, this.win.innerHeight, this.target) : null;
    this.names.sync(m, namePlayers, cfg);
    const keep = new Map();
    const want = (owner, key) => { if (!keep.has(owner)) keep.set(owner, new Set()); keep.get(owner).add(key); };
    if (cfg.xray && now - this.lastScan > 500) {
      const scanStart = this.win.performance.now(); this.scanEffects();
      this.runtimePerf.add('xrayScan', this.win.performance.now() - scanStart); this.lastScan = now;
    }
    for (const effect of cfg.xray ? this.effects : []) {
      const { owner, kind, entity, building, type } = effect;
      if (read(entity, 'active') === false || read(building, 'active') === false || owner.destroyed || read(entity, 'sprite') !== owner) continue;
      if (kind === 'ceiling' && cfg.ceilings && read(entity, 'isCeiling') === true && (!building || read(building, 'imgs')?.includes(entity))) { if (this.overrides.set(owner, 'visible', () => false)) { want(owner, 'visible'); this.stats.xray.ceilings++; } }
      if ((kind === 'vegetation' || kind === 'furniture') && read(entity, 'type') === type) { if (this.overrides.set(owner, 'alpha', raw => Math.min(raw, cfg.treeOpacity / 100))) { want(owner, 'alpha'); this.stats.xray.vegetation++; } }
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
    if (playerReady) this.guard('overlay-render', () => this.draw(players, espFrame));
    if (this.failed.has('overlay-render')) this.stats.esp = emptyEspStats('error');
    this.stats.featureMs = this.win.performance.now() - start;
  }
  attachCanvas(canvas) {
    this.canvas = canvas;
    try { this.ctx = canvas.getContext('2d'); } catch { this.ctx = null; }
    if (!this.ctx) this.report('warning', 'Canvas 2D không khả dụng: overlay bị khóa, input features không bị dừng.');
  }
  clearCanvas() { try { if (this.ctx && this.canvas) this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height); } catch { /* Lost canvas must not revoke names, zoom or input authority. */ } }
  draw(players, espFrame = null) {
    const ctx = this.ctx, canvas = this.canvas, m = this.mapping, cfg = this.config;
    if (!ctx || !canvas) return;
    const width = this.win.innerWidth, height = this.win.innerHeight;
    if (!prepareOverlay(canvas, ctx, width, height, this.win.devicePixelRatio)) return;
    ctx.globalAlpha = 1; ctx.setLineDash([]);
    const mouse = this.mouseInput.physical(this.app.input);
    if (cfg.aim && cfg.showFov && vec(mouse)) {
      ctx.strokeStyle = '#ffffff44'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(mouse.x, mouse.y, cfg.fov, 0, Math.PI * 2); ctx.stroke();
    }
    if (cfg.showDot && this.dot) { ctx.fillStyle = '#f95353'; ctx.beginPath(); ctx.arc(this.dot.x, this.dot.y, 4, 0, Math.PI * 2); ctx.fill(); }
    const target = this.target;
    if (cfg.aim && cfg.showTarget && target && read(target, 'active') === true && read(target, '__id') === this.targetId && !at(target, [m.schema?.netKey, m.schema?.deadKey])) {
      const screen = project(m.camera, overlayPosition(target, m));
      const scale = read(m.camera?.camera, m.camera?.scaleKeys?.[0]) * read(m.camera?.camera, m.camera?.scaleKeys?.[1]);
      const radius = at(target, [m.schema?.netKey, this.sourceFields?.scale]) || 1;
      if (screen && finite(scale)) drawTargetIndicator(ctx, screen, scale * radius + 5, cfg.targetStyle);
    }
    const selfPos = overlayPosition(m.active, m), origin = project(m.camera, selfPos);
    if (!origin) { if (cfg.esp) this.stats.esp = emptyEspStats('invalid-projection'); return; }
    if (cfg.grenadeTimer && this.capabilities.grenadeTimer) {
      const timer = this.grenadeTimer.sample(this.grenadeContext(), this.win.performance.now());
      if (timer) drawGrenadeTimer(ctx, origin, timer.seconds);
    }
    if (this.grenadePlan && ['preview', 'assist', 'lock'].includes(cfg.grenadeAimMode)) {
      const projected = this.grenadePlan.points.filter((_, i) => i % 3 === 0 || i === this.grenadePlan.points.length - 1).map(p => project(m.camera, p));
      if (projected.length > 1 && projected.every(Boolean)) {
        ctx.save(); ctx.strokeStyle = '#80ffb5cc'; ctx.lineWidth = 2; ctx.setLineDash([5, 4]); ctx.beginPath();
        projected.forEach((p, i) => i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)); ctx.stroke();
        const end = projected.at(-1), def = this.definitions?.[this.grenadePlan.type], radius = this.definitions?.[def?.explosionType]?.rad?.max;
        const scale = read(m.camera?.camera, m.camera?.scaleKeys?.[0]) * read(m.camera?.camera, m.camera?.scaleKeys?.[1]);
        if (finite(radius) && radius > 0 && finite(scale)) { ctx.beginPath(); ctx.arc(end.x, end.y, radius * scale, 0, Math.PI * 2); ctx.stroke(); }
        ctx.setLineDash([]); ctx.fillStyle = '#ffffff'; ctx.font = '11px system-ui'; ctx.fillText('ước lượng / chưa xác nhận', end.x + 4, end.y - 8); ctx.restore();
      }
    }
    if (cfg.esp || cfg.lines) {
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
    const selfPos = this.sourcePos(m.active), inputOrigin = aimPoint(m.camera, selfPos, selfPos);
    const scale = read(m.camera.camera, m.camera.scaleKeys[0]) * read(m.camera.camera, m.camera.scaleKeys[1]);
    const input = previewAim(this.mouseInput.physical(this.app.input), inputOrigin, scale, this.previewAimPlan);
    if (!input) return;
    const ownDirection = input.direction;
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
      if (!player.active || at(player, [schema.netKey, schema.deadKey]) || !sameLayer(player.layer, this.sourceLayer(m.active))) continue;
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
      const preview = throwPreview(def, selfPos, ownDirection, input.distance);
      if (preview) {
        line(preview.points, '#80ffb5aa', true); this.stats.previews.throwPaths++;
        const center = project(m.camera, preview.end), explosion = this.definitions[def.explosionType];
        if (center && explosion?.rad?.max > 0) { ctx.strokeStyle = '#80ffb577'; ctx.setLineDash([5, 4]); ctx.beginPath(); ctx.arc(center.x, center.y, explosion.rad.max * scale, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]); }
      }
    }
  }
  pickupEligible(loot) {
    const m = this.mapping, pos = m?.active && this.sourcePos(m.active), lootPos = read(loot, 'pos');
    return !!(m?.active && read(loot, '__type') === 3 && read(loot, 'active') === true && vec(lootPos) && vec(pos)
      && sameLayer(read(loot, 'layer'), this.sourceLayer(m.active)) && finite(read(loot, 'rad')) && loot.rad > 0
      && (loot.ownerId === 0 || loot.ownerId === m.active.__id)
      && Math.hypot(lootPos.x - pos.x, lootPos.y - pos.y) < loot.rad
      && ['ammo', 'heal', 'boost', 'throwable'].includes(this.definitions?.[read(loot, 'type')]?.type));
  }
  pickupSafety(loot) {
    const m = this.mapping;
    if (!['snapshot-id-table', 'native-id-table'].includes(m?.registryState)) return 'missing-registry';
    return nearbyLootSafety(read(m?.creator, m?.registryKey), loot, m?.active && this.sourcePos(m.active),
      m?.active && this.sourceLayer(m.active), read(m?.active, '__id'));
  }
  pickupStillValid() {
    const attempt = this.pickupAttempt, loot = this.lootSource && read(this.lootSource.owner, this.lootSource.key);
    if (!(attempt && loot === attempt.entity && loot.__id === attempt.id && loot.type === attempt.type
      && loot.count === attempt.count && this.pickupEligible(loot))) return false;
    const safety = this.pickupSafety(loot);
    if (safety !== 'clear-observed') { this.stats.lootState = safety; return false; }
    return true;
  }
  updateLoot() {
    this.pickupPulse = false;
    if (!this.config.autoLoot || this.config.lootMode === 'mobile') return;
    const now = this.win.performance.now();
    if (!this.capabilities.autoPickup || !this.bindsInstalled) { this.stats.lootState = 'missing-pickup-contract'; return; }
    if (now < this.pickupPauseUntil) { this.stats.lootState = 'paused-after-drop'; return; }
    if (!this.inputReady()) { this.stats.lootState = 'paused'; return; }
    const loot = read(this.lootSource.owner, this.lootSource.key);
    if (!this.pickupEligible(loot)) { this.stats.lootState = 'no-eligible-loot'; return; }
    // Never synthesize Interact/Use: they can open doors or revive. Native Loot
    // goes through normal InputMsg diff detection and the server's pickup checks.
    const attempt = this.lootBackoff.attempt(loot, now);
    if (!attempt) { this.stats.lootState = 'pickup-backoff'; return; }
    const safety = this.pickupSafety(loot);
    if (safety !== 'clear-observed') { this.stats.lootState = safety; return; }
    this.pickupAttempt = { entity: loot, ...attempt };
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
      objectRegistry: !!m?.creator && !!m?.registryKey,
      playerSchema: !!m?.schema, camera: !!m?.camera, spectatorUI: !!m?.ui,
      snapshotReceiver: !!this.receiverKey, inputScheduler: !!this.timeoutKey, inputFlush: !!this.flushReady, sender: !!this.senderReady,
      canvasRenderer: !!this.ctx, mapDefinitions: !!this.mapDefinitions, smokeSource: this.smokeSources.length > 0, definitions: !!this.definitions, lootSource: !!this.lootSource, localData: !!this.local, binds: !!this.binds,
      protocolObserved: this.protocol !== null, protocolMatches: this.protocol === VERIFIED_PROTOCOL,
    };
    return { version: '0.5.0-preview.8', protocol: this.protocol, sourceProtocol: VERIFIED_PROTOCOL,
      initialized: checks.initialized, checks,
      autoLoot: { state: this.autoLootStatus(), mode: this.config.lootMode, ...this.joinState },
      grenadeTimer: { enabled: !!this.config.grenadeTimer, state: this.grenadeTimer.active ? 'forwarded-edge-unconfirmed' : this.config.grenadeTimer ? 'waiting-for-edge' : 'disabled' },
      grenadeAim: { mode: this.config.grenadeAimMode || 'off', targetAllies: !!this.config.grenadeAimAllies, state: this.grenadeState,
        autoThrow: { enabled: !!this.config.grenadeAutoThrow, phase: this.grenadeAuto.phase,
          last: this.lastGrenadeAutoEvidence ? (({ recordedAt, ...rest }) => ({ ...rest, ageMs: Math.max(0, Math.round(this.win.performance.now() - recordedAt)) }))(this.lastGrenadeAutoEvidence) : null },
        last: this.lastGrenadeEvidence ? { state: this.lastGrenadeEvidence.state, ageMs: Math.max(0, Math.round(this.win.performance.now() - this.lastGrenadeEvidence.recordedAt)) } : null },
      mapHighlights: { ...this.mapHighlights.stats },
      nativeNames: { ...this.names.stats },
      inputBlockReason: this.inputBlockReason(),
      mouseInput: { enabled: this.config.directMouseInput !== false, flushReady: !!this.flushReady, capturingWrites: !!this.mouseInput.record?.captured, ...this.mouseInput.snapshot() },
      registry: { state: m?.registryState ?? 'waiting-mapping', ...m?.registryEvidence },
      aimControls: { mode: modeOf(this.config), activation: this.config.aimActivation, targetAllies: !!this.config.aimAllies, wallcheckRequested: !!this.config.wallcheck, predictionRequested: !!this.config.predict, stabilizeStrafe: this.config.stabilizeStrafe !== false, latencyCompensation: !!this.config.latencyCompensation, leadAdjustment: this.config.leadAdjustment ?? 100, predictionStrict: !!this.config.predictionStrict, humanLikeAim: !!this.config.humanLikeAim, smooth: this.config.smooth, smoothProfile: this.config.smoothProfile || 'responsive' },
      aimPreparation: this.aimPreparation,
      runtimePerformance: { ...this.runtimePerf.snapshot(), meaning: 'Script-local hook durations only; not game FPS, GPU time, network delay or hit rate.' },
      aimEvidence: this.aimEvidence.snapshot(this.win.performance.now()),
      lastPrediction: this.lastPredictionEvidence ? (() => {
        const { recordedAt, ...evidence } = this.lastPredictionEvidence;
        return { ...evidence, ageMs: Math.max(0, Math.round(this.win.performance.now() - recordedAt)) };
      })() : null,
      missingContracts: Object.keys(checks).filter(key => !checks[key]),
      capabilities: { ...this.capabilities },
      stats: { ...this.stats }, failed: [...this.failed], overrides: this.overrides.records.size + this.layerOverrides.records.size };
  }
  dispose() {
    if (this.stopped) return;
    if (this.lastAimSent && this.timeoutKey && this.app.game?.initialized) this.app.game[this.timeoutKey] = 0;
    this.stopped = true; this.releaseMatch(); this.gameHooks?.clear(); this.hooks.clear();
    // The menu owns this canvas. Retry replaces the engine, not the menu DOM.
    // releaseMatch() already cleared it; only menu.dispose() should remove it.
    this.canvas = this.ctx = null;
  }
}
