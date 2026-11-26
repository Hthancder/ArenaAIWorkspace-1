// Event-window synthetic comparison. Not a game hit rate or independent validation.
// Run: node scripts/benchmark-aim-events.mjs
import { SnapshotTracker, predictShot } from '../src/aim.mjs';

const quant = n => Math.round(n * 65535 / 1024) * 1024 / 65535;
const percentile = (a, p) => [...a].sort((x, y) => x - y)[Math.floor((a.length - 1) * p)];
const origin = { x: 0, y: 0 }, radius = 1;
// Events occur at t=2; acquisition deliberately discards all prior history.
const scenarios = {
  acquisition: t => ({ x: 60, y: 12 * (t - 2) }),
  reverse: t => ({ x: 60, y: 12 * (t < 2 ? t - 2 : 2 - t) }),
  stop: t => ({ x: 60, y: 12 * Math.min(t - 2, 0) }),
  'ad-escape-inline': t => ({ x: 60, y: t < 2 ? 1.5 * (2 / Math.PI) * Math.asin(Math.sin(2 * Math.PI * t)) : 12 * (t - 2) }),
  'ad-escape-side': t => ({ x: 60 + (t < 2 ? 0 : 12 * (t - 2)), y: t < 2 ? 1.5 * (2 / Math.PI) * Math.asin(Math.sin(2 * Math.PI * t)) : 0 }),
  straight: t => ({ x: 60, y: 12 * (t - 2) }),
  ad: t => ({ x: 60, y: 1.5 * (2 / Math.PI) * Math.asin(Math.sin(2 * Math.PI * t)) }),
};
const variants = {
  current: { lead: 1, stabilize: true },
  'half-lead': { lead: .5, stabilize: true },
  'no-midpoint': { lead: 1, stabilize: false },
  direct: null,
};
const results = new Map();
for (const [name, truth] of Object.entries(scenarios)) for (const speed of [66, 100, 182]) for (const hz of [30, 60, 144]) for (const phase of [0, .007, .019]) for (const delay of [.03, .08]) {
  const profile = { speed, range: 1000, barrel: 0, offset: 0 }, tracker = new SnapshotTracker(), entity = { __id: 1 };
  const packets = [];
  for (let t = name === 'acquisition' ? 2 : 0; t < 3.5; t += 1 / 33) {
    const p = truth(t); packets.push({ arrival: t + delay, p: { x: quant(p.x), y: quant(p.y) } });
  }
  let index = 0, current = null;
  for (let now = (name === 'acquisition' ? 2 : 0) + phase; now < 2.8; now += 1 / hz) {
    while (index < packets.length && packets[index].arrival <= now) {
      const packet = packets[index++]; current = packet.p; tracker.observe(entity, current, packet.arrival * 1000);
    }
    if (!current || now < 2) continue;
    const elapsed = now - 2, window = elapsed < .15 ? '0-150ms' : elapsed < .4 ? '150-400ms' : '400-800ms';
    const track = tracker.estimate(entity, now * 1000);
    for (const [variant, config] of Object.entries(variants)) {
      const shot = config ? predictShot({ origin, target: current, track, profile, radius, latency: delay, compensateSnapshot: true, ...config }) : null;
      const norm = Math.hypot(current.x, current.y), dir = shot?.dir || { x: current.x / norm, y: current.y / norm };
      // Compare perpendicular error at each model's estimated flight time. This
      // does not simulate collision, recoil, network scheduling or controller.
      const flight = shot?.time ?? norm / speed, actual = truth(now + delay + flight);
      const error = Math.abs(dir.x * actual.y - dir.y * actual.x);
      const key = `${name}\t${window}\t${variant}`, result = results.get(key) || { errors: [], fallback: 0, midpoint: 0 };
      result.errors.push(error); result.fallback += config && !shot?.dir ? 1 : 0; result.midpoint += shot?.state === 'bounded-oscillation' ? 1 : 0; results.set(key, result);
    }
  }
}
console.log('# Synthetic cross-track error in world units; not hit rate. Event windows use ground-truth event time, not observation time.');
console.log('# 33Hz snapshots; one-way up/down 30 or 80ms; 30/60/144 FPS; bullet speed 66/100/182; no spread, obstacles or aim controller.');
console.log('scenario\twindow\tvariant\tn\tmedian\tp95\toutside-radius%\tfallback%\tmidpoint%');
for (const [key, r] of results) console.log(`${key}\t${r.errors.length}\t${percentile(r.errors, .5).toFixed(3)}\t${percentile(r.errors, .95).toFixed(3)}\t${(100 * r.errors.filter(x => x > radius).length / r.errors.length).toFixed(1)}\t${(100 * r.fallback / r.errors.length).toFixed(1)}\t${(100 * r.midpoint / r.errors.length).toFixed(1)}`);
