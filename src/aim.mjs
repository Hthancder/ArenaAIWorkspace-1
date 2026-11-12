import { clamp, finite, intercept, point, vec } from './core.mjs';

export const unit = v => { const n = Math.hypot(v?.x, v?.y); return finite(n) && n > 1e-8 ? { x: v.x / n, y: v.y / n } : null; };
export const angleDelta = (a, b) => Math.atan2(Math.sin(b - a), Math.cos(b - a));
export const modeOf = cfg => cfg.aim === false ? 'off' : cfg.aimMode === 'assist' ? 'assist' : cfg.aimMode === 'off' ? 'off' : 'lock';

// Observations only: never add a synthetic zero-velocity sample on render frames.
export class SnapshotTracker {
  states = new WeakMap();
  reset() { this.states = new WeakMap(); }
  forget(entity) { this.states.delete(entity); }
  observe(entity, pos, now, layer = null) {
    if (!vec(pos) || !finite(now)) return null;
    let s = this.states.get(entity);
    if (!s || s.id !== entity.__id || s.layer !== layer || now - s.time > 500 || now <= s.time || Math.hypot(pos.x - s.pos.x, pos.y - s.pos.y) > 20) {
      s = { id: entity.__id, layer, pos: point(pos), time: now, vx: 0, vy: 0, error: 0, velocityError: 0, samples: [{ p: point(pos), t: now }] };
      this.states.set(entity, s); return s;
    }
    // A websocket backlog can deliver many ordered samples in one local tick.
    // Replace the coalesced endpoint, never manufacture tiny-dt velocity spikes.
    if (now - s.time < 8) {
      if (s.samples.length < 2) {
        s.pos = point(pos); s.time = now; s.samples = [{ p: point(pos), t: now }]; return s;
      }
      s.samples.pop(); const previous = s.samples.at(-1); s.pos = point(previous.p); s.time = previous.t;
    }
    const dt = (now - s.time) / 1000;
    const raw = { x: (pos.x - s.pos.x) / dt, y: (pos.y - s.pos.y) / dt };
    if (Math.hypot(raw.x, raw.y) > 80) { this.states.delete(entity); return this.observe(entity, pos, now, layer); }
    const residual = Math.hypot(pos.x - s.pos.x - s.vx * dt, pos.y - s.pos.y - s.vy * dt);
    const n = Math.hypot(raw.x, raw.y) * Math.hypot(s.vx, s.vy);
    const turn = n > 4 && (raw.x * s.vx + raw.y * s.vy) / n < .5;
    const stop = Math.hypot(raw.x, raw.y) < .7 && Math.hypot(s.vx, s.vy) > 2;
    const start = Math.hypot(s.vx, s.vy) < .7 && Math.hypot(raw.x, raw.y) > 2;
    if (turn || stop || start || residual > .8) s.samples = [{ p: point(s.pos), t: s.time }];
    s.samples.push({ p: point(pos), t: now });
    s.samples = s.samples.filter(o => now - o.t <= 140).slice(-6);
    // Weighted linear fit in seconds, centered at now (bounded six observations).
    let w = 0, t = 0, tt = 0, x = 0, y = 0, tx = 0, ty = 0;
    for (const o of s.samples) {
      const a = (o.t - now) / 1000, weight = Math.exp(a / .08);
      w += weight; t += weight * a; tt += weight * a * a;
      x += weight * o.p.x; y += weight * o.p.y; tx += weight * a * o.p.x; ty += weight * a * o.p.y;
    }
    const den = w * tt - t * t;
    if (den > 1e-9) { s.vx = (w * tx - t * x) / den; s.vy = (w * ty - t * y) / den; }
    const ix = (x - s.vx * t) / w, iy = (y - s.vy * t) / w;
    let rss = 0;
    for (const o of s.samples) {
      const a = (o.t - now) / 1000, weight = Math.exp(a / .08);
      rss += weight * ((o.p.x - ix - s.vx * a) ** 2 + (o.p.y - iy - s.vy * a) ** 2);
    }
    // Fit residual and slope uncertainty have distinct units (wu vs wu/s).
    // Quantization floor follows 16-bit positions over 1024 world units.
    s.error = Math.sqrt(rss / Math.max(w, 1)) + 1024 / 65535;
    s.velocityError = Math.sqrt((rss / Math.max(1, s.samples.length - 2) + (1024 / 65535) ** 2) / Math.max(tt - t * t / w, .0001));
    s.pos = point(pos); s.time = now; return s;
  }
  estimate(entity, now) {
    const s = this.states.get(entity);
    return s && s.id === entity.__id && now - s.time <= 250 ? { ...s, age: Math.max(0, (now - s.time) / 1000) } : null;
  }
}

// Source WeaponManager.fireWeapon: bonus_9mm is ammo-conditional; the other
// two multipliers follow hasPerk branches, not gun-name heuristics.
export function weaponProfile(defs, type, perks = []) {
  const gun = defs?.[type], bullet = defs?.[gun?.bulletType];
  if (gun?.type !== 'gun' || bullet?.type !== 'bullet' || !(bullet.speed > 0) || !(bullet.distance > 0)) return null;
  const owned = new Set(perks.map(p => p?.type)); let mult = 1, rangeMult = 1;
  if (gun.ammo === '9mm' && owned.has('bonus_9mm')) { mult *= 1.2; rangeMult *= 1.2; }
  if (owned.has('high_velocity')) { mult *= 1.4; rangeMult *= 1.3; }
  if (owned.has('bonus_assault')) mult *= 1.1;
  const variance = 1 + (bullet.variance || 0), rangeJitter = bullet.noDistAdj ? 0 : 1;
  return { gun, variance, rangeJitter, speed: bullet.speed * mult * variance, range: Math.min(1024, Math.max(0, bullet.distance * rangeMult * variance - rangeJitter)),
    barrel: finite(gun.barrelLength) ? gun.barrelLength : 0, offset: gun.isDual ? 0 : finite(gun.barrelOffset) ? gun.barrelOffset : 0,
    approximate: !!gun.isDual || gun.ammo === '45acp' && owned.has('bonus_45'), toMouseHit: !!gun.toMouseHit };
}
export function muzzleAt(pos, dir, profile) {
  return { x: pos.x - dir.y * profile.offset + dir.x * profile.barrel, y: pos.y + dir.x * profile.offset + dir.y * profile.barrel };
}
export function predictShot({ origin, target, track, profile, latency = 0, lead = 1, radius = 1, muzzleFor = muzzleAt }) {
  if (!vec(origin) || !vec(target) || !profile) return { state: 'missing-profile' };
  target = track?.pos || target;
  const age = track?.age || 0, vx = track?.vx || 0, vy = track?.vy || 0;
  const transit = clamp(latency, 0, .1), ahead = age + transit;
  const current = { x: target.x + vx * ahead, y: target.y + vy * ahead };
  let dir = unit({ x: current.x - origin.x, y: current.y - origin.y });
  if (!dir) return { state: 'coincident' };
  let time = 0, world = current, muzzle;
  for (let i = 0; i < 3; i++) {
    muzzle = muzzleFor(origin, dir, profile);
    time = intercept({ x: current.x - muzzle.x, y: current.y - muzzle.y }, { x: vx * lead, y: vy * lead }, profile.speed, Infinity);
    if (time === null) return { state: 'no-intercept' };
    world = { x: current.x + vx * time * lead, y: current.y + vy * time * lead };
    dir = unit({ x: world.x - muzzle.x, y: world.y - muzzle.y }); if (!dir) return { state: 'coincident' };
  }
  if (profile.speed * time > profile.range) return { state: 'out-of-range-or-horizon' };
  const error = (track?.error || 0) + (track?.velocityError || 0) * (ahead + time);
  if (age > .15 || (track?.error || 0) > Math.max(.75, radius) * 2) return { state: 'uncertain' };
  // Continuous, explicit fallback for slope uncertainty: reduce speculative
  // flight lead, not physical flight time. No motion-pattern classification.
  const confidence = error > Math.max(.75, radius) * 2 ? Math.max(.75, radius) * 2 / error : 1;
  if (confidence < 1) for (let i = 0; i < 3; i++) {
    muzzle = muzzleFor(origin, dir, profile);
    time = intercept({ x: current.x - muzzle.x, y: current.y - muzzle.y }, { x: vx * lead * confidence, y: vy * lead * confidence }, profile.speed, Infinity);
    if (time === null) return { state: 'no-intercept' };
    world = { x: current.x + vx * time * lead * confidence, y: current.y + vy * time * lead * confidence };
    dir = unit({ x: world.x - muzzle.x, y: world.y - muzzle.y }); if (!dir) return { state: 'coincident' };
  }
  if (profile.speed * time > profile.range) return { state: 'out-of-range-or-horizon' };
  // Aim direction is the barrel orientation, including the lateral muzzle offset.
  const rel = { x: world.x - origin.x, y: world.y - origin.y }, distance = Math.hypot(rel.x, rel.y);
  if (distance > Math.abs(profile.offset) + .001) {
    const a = Math.atan2(rel.y, rel.x) - Math.asin(clamp(profile.offset / distance, -1, 1));
    dir = { x: Math.cos(a), y: Math.sin(a) };
  }
  const finalMuzzle = muzzleFor(origin, dir, profile);
  const mouseLen = Math.hypot(world.x - finalMuzzle.x, world.y - finalMuzzle.y) / (profile.variance || 1) + profile.barrel;
  return { mouseLen, state: confidence < 1 ? 'reduced-lead-uncertainty' : track ? 'predicted' : 'direct-no-history', world, dir, distance, muzzle: finalMuzzle, time, error, confidence, approximate: profile.approximate || confidence < 1 };
}
export class AimController {
  reset() { this.angle = null; this.time = null; this.target = null; this.mode = null; }
  constructor() { this.reset(); }
  step(native, wanted, { mode, strength, smooth, now, target }) {
    const n = unit(native), d = unit(wanted); if (!n || !d || mode === 'off') { this.reset(); return n; }
    const a = Math.atan2(n.y, n.x), b = Math.atan2(d.y, d.x);
    if (mode === 'assist') { this.reset(); const out = a + angleDelta(a, b) * clamp(strength / 100, 0, 1); return { x: Math.cos(out), y: Math.sin(out) }; }
    if (this.target !== target || this.mode !== mode || this.time === null || now - this.time > 250) this.angle = a;
    const dt = this.time === null ? 1 / 60 : clamp((now - this.time) / 1000, 0, .05);
    const gain = smooth <= 0 ? 1 : 1 - Math.exp(-dt / (.015 + smooth / 500));
    this.angle += angleDelta(this.angle, b) * gain;
    this.time = now; this.target = target; this.mode = mode;
    return { x: Math.cos(this.angle), y: Math.sin(this.angle) };
  }
}
