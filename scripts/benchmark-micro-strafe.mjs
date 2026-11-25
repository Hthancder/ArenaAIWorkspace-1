// Synthetic A/D movement and abrupt departure. Development-only, not live hit rate.
import { SnapshotTracker, predictShot } from '../src/aim.mjs';
const q = (xs, f) => [...xs].sort((a, b) => a - b)[Math.floor((xs.length - 1) * f)];
const quant = n => Math.round(n * 65535 / 1024) * 1024 / 65535;
const rng = seed => () => { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 2 ** 32; };

function run({ width, radius, escape, cadence, hz, seed, speed, drift = 0 }) {
  const random = rng(seed), dt = .002, states = [{ x: 60, y: 0 }]; let x = 60, y = 0, lo = 0, sign = 1, wasEscaping = false;
  for (let i = 1; i <= 6000; i++) {
    const t = i * dt, phase = t % 3, escaping = escape && phase >= 2.2 && phase < 2.8;
    if (escaping) {
      if (escape === 'inline') y += 12 * dt; else x += 12 * dt;
    } else {
      if (wasEscaping && escape === 'inline') { lo = y - width / 2; sign = -1; }
      lo += drift * dt;
      y += (sign * 12 + drift) * dt;
      if (y >= lo + width) { y = 2 * (lo + width) - y; sign = -1; }
      if (y <= lo) { y = 2 * lo - y; sign = 1; }
    }
    states.push({ x, y }); wasEscaping = escaping;
  }
  const truth = t => { const s = Math.max(0, Math.min(states.length - 2, t / dt)); const i = Math.floor(s), f = s - i; return { x: states[i].x * (1 - f) + states[i + 1].x * f, y: states[i].y * (1 - f) + states[i + 1].y * f }; };
  const packets = [];
  for (let t = 0, i = 0; t < 10; i++) {
    t += 1 / 33;
    const delay = .035 + (cadence === 'jitter' ? (random() - .5) * .02 + (i % 93 === 80 ? .18 : 0) : 0);
    const p = truth(t);
    packets.push({ t: Math.max(t + delay, (packets.at(-1)?.t || 0) + .0001), p: { x: quant(p.x), y: quant(p.y) } });
  }
  const tracker = new SnapshotTracker(), entity = { __id: 1 }, origin = { x: 0, y: 0 };
  const profile = { speed, range: 1000, barrel: 0, offset: 0 }, errors = [], misses = []; let i = 0, current = packets[0].p, stable = 0, rejected = 0, total = 0;
  for (let now = .07; now < 9; now += 1 / hz) {
    while (i < packets.length && packets[i].t <= now) { const p = packets[i++]; current = p.p; tracker.observe(entity, current, p.t * 1000); }
    const track = tracker.estimate(entity, now * 1000);
    const shot = predictShot({ origin, target: current, track, profile, radius, latency: .035, stabilize: true });
    const flight = shot.time ?? Math.hypot(current.x, current.y) / speed;
    const actual = truth(now + .035 + flight), d = shot.dir || { x: current.x / Math.hypot(current.x, current.y), y: current.y / Math.hypot(current.x, current.y) };
    const miss = Math.abs(d.x * actual.y - d.y * actual.x);
    errors.push(miss); misses.push(miss > radius ? 1 : 0); total++;
    if (shot.state === 'bounded-oscillation') stable++;
    if (!shot.dir) rejected++;
  }
  return { errors, misses, stable, rejected, total };
}

for (const [name, width, radius, escape, drift = 0] of [
  ['ad-small-035', .55, .35, false], ['ad-small-050', .8, .5, false],
  ['ad-wide-050', 1.2, .5, false], ['ad-min-source-075', 1.2, .75, false], ['ad-normal-100', 1.2, 1, false],
  ['escape-035', .55, .35, 'side'], ['escape-050', .8, .5, 'side'], ['escape-min-source-075', 1.2, .75, 'side'],
  ['escape-inline-035', .55, .35, 'inline'], ['escape-inline-050', .8, .5, 'inline'], ['escape-inline-min-source-075', 1.2, .75, 'inline'],
  ['drift-min-source-075', 1.2, .75, false, .4],
]) {
  const all = { errors: [], misses: [], stable: 0, rejected: 0, total: 0 };
  for (const cadence of ['regular', 'jitter']) for (const hz of [30, 60, 144]) for (const seed of [731, 7283, 51743]) for (const speed of [66, 100, 182]) {
    const r = run({ width, radius, escape, cadence, hz, seed, speed, drift });
    all.errors.push(...r.errors); all.misses.push(...r.misses); all.stable += r.stable; all.rejected += r.rejected; all.total += r.total;
  }
  console.log(`${name}\tn=${all.total}\tmedian=${q(all.errors, .5).toFixed(3)}\tp95=${q(all.errors, .95).toFixed(3)}\toutside-radius=${(100 * all.misses.reduce((a, b) => a + b, 0) / all.total).toFixed(2)}%\tstable=${(100 * all.stable / all.total).toFixed(2)}%\tfallback=${(100 * all.rejected / all.total).toFixed(2)}%`);
}
