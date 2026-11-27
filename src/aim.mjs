import { clamp, finite, intercept, point, vec } from './core.mjs';

export const unit = v => { const n = Math.hypot(v?.x, v?.y); return finite(n) && n > 1e-8 ? { x: v.x / n, y: v.y / n } : null; };
export const angleDelta = (a, b) => Math.atan2(Math.sin(b - a), Math.cos(b - a));

// Andrew I. Game Programming Gems-style critically damped SmoothDamp, adapted
// to one scalar. It eases in and out, never overshoots and is frame-rate
// independent. Human-like here is immediate game-feel, not a detection layer.
export function smoothDamp(current, target, velocity, smoothTime, maxSpeed, dt) {
  smoothTime = Math.max(.001, finite(smoothTime) ? smoothTime : .001);
  maxSpeed = Number.isFinite(maxSpeed) ? Math.max(0, maxSpeed) : Infinity;
  dt = clamp(finite(dt) ? dt : 0, 0, .05);
  const omega = 2 / smoothTime;
  const x = omega * dt;
  const exp = 1 / (1 + x + .48 * x * x + .235 * x * x * x);
  let delta = clamp(current - target, -maxSpeed * smoothTime, maxSpeed * smoothTime);
  const originalTo = target;
  target = current - delta;
  const temp = (velocity + omega * delta) * dt;
  velocity = (velocity - omega * temp) * exp;
  let result = target + (delta + temp) * exp;
  // Floating point fall-through is invisible in gameplay; still clamp the sign.
  if ((originalTo - current > 0) === (result > originalTo)) { result = originalTo; velocity = 0; }
  return { value: result, velocity };
}
export const modeOf = cfg => cfg.aim === false ? 'off' : cfg.aimMode === 'assist' ? 'assist' : cfg.aimMode === 'off' ? 'off' : 'lock';

function rememberMotion(s, pos, now) {
  const motion = s.motion || (s.motion = []);
  if (motion.length && now - motion.at(-1).t < 8) motion.pop();
  motion.push({ p: point(pos), t: now });
  s.motion = motion.filter(o => now - o.t <= 900).slice(-32);
}

// Only infer a bounded weave after observing a complete reversal cycle within
// a small region. A long snapshot gap or missing history disables this model.
export function boundedOscillation(track, radius) {
  const samples = track?.motion;
  if (!Array.isArray(samples) || samples.length < 8 || !finite(track.age) || track.age > .15 || !finite(radius) || radius <= 0) return null;
  if (samples.at(-1).t - samples[0].t < 550) return null;
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  let prevMinX = Infinity, prevMaxX = -Infinity, prevMinY = Infinity, prevMaxY = -Infinity;
  for (let i = 0; i < samples.length; i++) {
    const { p, t } = samples[i];
    if (!vec(p) || !finite(t) || i && (t <= samples[i - 1].t || t - samples[i - 1].t > 150)) return null;
    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
    if (i < samples.length - 1) {
      prevMinX = Math.min(prevMinX, p.x); prevMaxX = Math.max(prevMaxX, p.x);
      prevMinY = Math.min(prevMinY, p.y); prevMaxY = Math.max(prevMaxY, p.y);
    }
  }
  const last = samples.at(-1);
  // Reversals can happen at full strafe speed: speed alone is not evidence of
  // escape. Detect a departure from the previously observed region instead.
  const margin = .06;
  if (last.p.x < prevMinX - margin || last.p.x > prevMaxX + margin || last.p.y < prevMinY - margin || last.p.y > prevMaxY + margin) return null;
  const dx = maxX - minX, dy = maxY - minY, diameter = Math.hypot(dx, dy);
  // A wider bounded strafe can still favor its midpoint; cap it by hitbox
  // size and world distance. Beyond one diameter the midpoint may still miss.
  if (diameter < .2 || diameter > Math.min(3.5 * radius, 3.5)) return null;
  const axis = dx >= dy ? 'x' : 'y';
  let sign = 0, turns = 0;
  for (let i = 1; i < samples.length; i++) {
    const delta = samples[i].p[axis] - samples[i - 1].p[axis];
    if (Math.abs(delta) < .035) continue;
    const next = Math.sign(delta);
    if (sign && sign !== next) turns++;
    sign = next;
  }
  return turns >= 2 ? { x: (minX + maxX) / 2, y: (minY + maxY) / 2, diameter } : null;
}

// Observations only: never add a synthetic zero-velocity sample on render frames.
export class SnapshotTracker {
  states = new WeakMap();
  reset() { this.states = new WeakMap(); }
  forget(entity) { this.states.delete(entity); }
  observe(entity, pos, now, layer = null) {
    if (!vec(pos) || !finite(now)) return null;
    let s = this.states.get(entity);
    if (!s || s.id !== entity.__id || s.layer !== layer || now - s.time > 500 || now < s.time || Math.hypot(pos.x - s.pos.x, pos.y - s.pos.y) > 20) {
      s = { id: entity.__id, layer, pos: point(pos), time: now, vx: 0, vy: 0, error: 0, velocityError: 0, samples: [{ p: point(pos), t: now }] };
      rememberMotion(s, pos, now);
      this.states.set(entity, s); return s;
    }
    // A websocket backlog can deliver many ordered samples in one local tick.
    // Replace the coalesced endpoint, never manufacture tiny-dt velocity spikes.
    if (now - s.time < 8) {
      if (s.samples.length < 2) {
        s.pos = point(pos); s.time = now; s.samples = [{ p: point(pos), t: now }]; rememberMotion(s, pos, now); return s;
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
    s.pos = point(pos); s.time = now; rememberMotion(s, pos, now); return s;
  }
  estimate(entity, now) {
    const s = this.states.get(entity);
    return s && s.id === entity.__id && finite(now) && now >= s.time && now - s.time <= 250 ? { ...s, age: (now - s.time) / 1000 } : null;
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
// A short, nearly linear history can justify compensating snapshot transit in
// addition to the estimated outgoing transit. It cannot predict future turns.
function linearHistory(track) {
  const samples = track?.motion;
  if (!Array.isArray(samples) || samples.length < 12 || !finite(track.age) || track.age > .1) return false;
  const first = samples[0], last = samples.at(-1), span = last.t - first.t;
  if (!finite(first.t) || !finite(last.t) || span < 650 || !vec(first.p) || !vec(last.p)) return false;
  const dx = last.p.x - first.p.x, dy = last.p.y - first.p.y;
  if (Math.hypot(dx, dy) / (span / 1000) < 2) return false;
  for (let i = 1; i < samples.length; i++) {
    const sample = samples[i];
    if (!vec(sample.p) || !finite(sample.t) || sample.t <= samples[i - 1].t || sample.t - samples[i - 1].t > 100) return false;
    const f = (sample.t - first.t) / span;
    if (Math.hypot(sample.p.x - first.p.x - dx * f, sample.p.y - first.p.y - dy * f) > .12) return false;
  }
  return true;
}
export function predictShot({ origin, target, track, profile, latency = 0, lead = 1, radius = 1, muzzleFor = muzzleAt, stabilize = false, compensateSnapshot = false }) {
  if (!vec(origin) || !vec(target) || !profile) return { state: 'missing-profile' };
  const bounded = stabilize ? boundedOscillation(track, radius) : null;
  target = bounded || track?.pos || target;
  const age = track?.age || 0, vx = bounded ? 0 : track?.vx || 0, vy = bounded ? 0 : track?.vy || 0;
  const transit = clamp(latency * (compensateSnapshot && !bounded && linearHistory(track) ? 2 : 1), 0, .1), ahead = age + transit;
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
  const error = (track?.error || 0) + (bounded ? bounded.diameter / 2 : (track?.velocityError || 0) * (ahead + time));
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
  return { mouseLen, state: confidence < 1 ? 'reduced-lead-uncertainty' : bounded ? 'bounded-oscillation' : track ? 'predicted' : 'direct-no-history', world, dir, distance, muzzle: finalMuzzle, time, error, confidence, approximate: profile.approximate || confidence < 1 };
}
export class AimController {
  reset() { this.angle = null; this.time = null; this.target = null; this.mode = null; this.angularVelocity = 0; this.cubic = null; this.profile = null; }
  constructor() { this.reset(); }
  step(native, wanted, { mode, strength, smooth, now, target, humanLike = smooth > 0, profile = 'natural', cursorRadius = 100, targetRadius = 100 }) {
    const n = unit(native), d = unit(wanted); if (!n || !d || mode === 'off') { this.reset(); return n; }
    const a = Math.atan2(n.y, n.x), b = Math.atan2(d.y, d.x);
    if (mode === 'assist') { this.reset(); const out = a + angleDelta(a, b) * clamp(strength / 100, 0, 1); return { x: Math.cos(out), y: Math.sin(out) }; }
    if (this.target !== target || this.mode !== mode || this.profile !== null && this.profile !== profile || this.time === null || now - this.time > 250 || now < this.time) {
      this.angle = a; this.angularVelocity = 0; this.cubic = null;
    }
    const dt = this.time === null ? 1 / 60 : clamp((now - this.time) / 1000, 0, .05);
    // smooth: 0 is fast but humanLike callers normally treat 0 as direct.
    if (!humanLike || smooth <= 0) {
      this.angle = b; this.angularVelocity = 0; this.cubic = null;
    } else if (profile === 'duality') {
      // Inspired by Duality's screen-space cubic ease-out. Retarget from the
      // current point, never pause/replay Fire. Coordinates are viewport-relative.
      const nr = clamp(finite(cursorRadius) ? cursorRadius : 100, .001, 4096);
      const tr = clamp(finite(targetRadius) ? targetRadius : nr, .001, 4096);
      const desired = { x: d.x * tr, y: d.y * tr };
      let cur = { x: n.x * nr, y: n.y * nr };
      if (this.cubic) {
        const c = this.cubic, t = clamp((now - c.startTime) / c.duration, 0, 1), eased = 1 - (1 - t) ** 3;
        if (c.angularPath) {
          const startAngle = Math.atan2(c.start.y, c.start.x), endAngle = Math.atan2(c.end.y, c.end.x);
          const angle = startAngle + angleDelta(startAngle, endAngle) * eased;
          const radius = Math.hypot(c.start.x, c.start.y) + (Math.hypot(c.end.x, c.end.y) - Math.hypot(c.start.x, c.start.y)) * eased;
          cur = { x: radius * Math.cos(angle), y: radius * Math.sin(angle) };
        } else cur = { x: c.start.x + (c.end.x - c.start.x) * eased, y: c.start.y + (c.end.y - c.start.y) * eased };
      }
      if (!this.cubic || Math.abs(desired.x - this.cubic.end.x) > .001 || Math.abs(desired.y - this.cubic.end.y) > .001) {
        const distance = Math.hypot(desired.x - cur.x, desired.y - cur.y);
        const angular = Math.abs(angleDelta(Math.atan2(cur.y, cur.x), b));
        const immediate = distance <= 6 && angular <= Math.PI / 90;
        const duration = immediate ? 0 : 45 + 360 * Math.max(clamp(angular / Math.PI, 0, 1), clamp(distance / 450, 0, 1)) * clamp(smooth / 100, 0, 1);
        this.cubic = { start: cur, end: desired, startTime: now, duration: Math.max(duration, .001), angularPath: angular > Math.PI * .9 };
        if (immediate) cur = desired;
      }
      const normalized = unit(cur) || d;
      this.angle = Math.atan2(normalized.y, normalized.x); this.angularVelocity = 0;
    } else {
      this.cubic = null;
      const profiles = { responsive: { time: .78, rate: 12 }, natural: { time: 1, rate: 8.5 }, precise: { time: 1.32, rate: 6.25 } };
      const selectedProfile = profiles[profile] || profiles.natural;
      const amount = clamp(finite(smooth) ? smooth : 50, 1, 100);
      const targetAngle = this.angle + angleDelta(this.angle, b);
      const baseTime = (.065 + (amount / 100) * .24) * selectedProfile.time;
      // Responsive Lock brakes sooner only when the observed wanted direction is
      // behind the controller's current angular motion. This uses no future
      // target input and does not snap or affect Assist / other profiles.
      const braking = profile === 'responsive' && this.angularVelocity * angleDelta(this.angle, b) < -.001;
      const smoothTime = baseTime * (braking ? .7 : 1);
      const solved = smoothDamp(this.angle, targetAngle, this.angularVelocity, smoothTime, selectedProfile.rate, dt);
      this.angularVelocity = solved.velocity;
      this.angle = Math.atan2(Math.sin(solved.value), Math.cos(solved.value));
    }
    this.time = now; this.target = target; this.mode = mode; this.profile = profile;
    return { x: Math.cos(this.angle), y: Math.sin(this.angle) };
  }
}
