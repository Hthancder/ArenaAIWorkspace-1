// Deterministic held-out synthetic motion, not gameplay/hitrate or FPS evidence.
// Predictor sees only arrived quantized snapshots. Ground truth used only by scoring.
import { performance } from 'node:perf_hooks';
import { writeFileSync } from 'node:fs';
import { SnapshotTracker, predictShot } from '../src/aim.mjs';
import { Tracker, intercept } from '../src/core.mjs';

const rng = seed => () => { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 2 ** 32; };
const quant = p => ({ x: Math.round(p.x * 65535 / 1024) * 1024 / 65535, y: Math.round(p.y * 65535 / 1024) * 1024 / 65535 });
const q = (a, f) => a.length ? [...a].sort((a, b) => a - b)[Math.min(a.length - 1, Math.floor(a.length * f))] : 0;
const names = ['stationary', 'straight', 'diagonal', 'approach-retreat', 'start-stop', 'curve', 'turn90', 'reverse180', 'speed-change', 'zigzag-irregular', 'mixed', 'wall-stop'];
function trajectory(kind, random) {
  const dt = .005, points = [{ x: 45, y: 15 }]; let heading = .4, speed = 10, next = .2, turn = 1;
  for (let i = 1; i <= 2400; i++) {
    const t = i * dt;
    if (kind === 'stationary') speed = 0;
    if (kind === 'straight') heading = Math.PI / 2;
    if (kind === 'diagonal') heading = .7;
    if (kind === 'approach-retreat') heading = Math.floor(t / 1.3) % 2 ? Math.PI : 0;
    if (kind === 'start-stop') speed = Math.floor(t / .75) % 2 ? 0 : 10;
    if (kind === 'wall-stop') { const phase = t % 2.5; speed = phase < .9 ? 10 : phase < 1.5 ? 0 : 6; heading = phase < 1.5 ? 0 : Math.PI / 2; }
    if (kind === 'curve') heading = .4 + t * .75;
    if (kind === 'turn90') heading = Math.floor(t / .85) * Math.PI / 2;
    if (kind === 'reverse180') heading = Math.floor(t / .9) % 2 ? .4 : .4 + Math.PI;
    if (kind === 'speed-change') speed = [4, 12, 7, 16][Math.floor(t / .8) % 4];
    if ((kind === 'mixed' || kind === 'zigzag-irregular') && t >= next) {
      next = t + .15 + random() * .8;
      if (kind === 'mixed') { heading = random() * Math.PI * 2; speed = random() < .2 ? 0 : 4 + random() * 12; }
      else { turn *= -1; heading = turn * (.4 + random() * .9); }
    }
    const prev = points.at(-1); points.push({ x: prev.x + Math.cos(heading) * speed * dt, y: prev.y + Math.sin(heading) * speed * dt });
  }
  return t => { const index = Math.max(0, Math.min(points.length - 2, t / dt)), i = Math.floor(index), f = index - i; return { x: points[i].x * (1 - f) + points[i + 1].x * f, y: points[i].y * (1 - f) + points[i + 1].y * f }; };
}
const result = [], seeds = [1847, 82031, 517991]; // held out from diagnostic seeds 7301/99173/441019
for (const kind of names) {
  const rows = Object.fromEntries(['no-predict', 'legacy-render', 'simple-CV', 'snapshot'].map(key => [key, { miss: [], collider: [], overshoot: [], recovery: [], fallbacks: 0, limited: 0, cost: [] }]));
  for (const seed of seeds) for (const hz of [30, 60, 144]) for (const cadence of ['33Hz', 'jitter+gap']) {
    const random = rng(seed), truth = trajectory(kind, rng(seed + 7)), packets = [];
    for (let time = 0, n = 0; time < 10; n++) {
      time += 1 / 33;
      // Position receive clock has jitter, a 240ms gap and periodic bunching.
      const delay = .035 + (cadence === '33Hz' ? 0 : (random() - .5) * .025 + (n % 67 === 60 ? .24 : 0));
      packets.push({ arrival: Math.max(time + delay, (packets.at(-1)?.arrival || 0) + .0001), pos: quant(truth(time)) });
    }
    // WebSocket preserves order; gap causes subsequent snapshots to bunch, never reorder.
    const tracker = new SnapshotTracker(), legacy = new Tracker(), entity = { __id: 1 };
    let cursor = 0, current = packets[0].pos, previous = null, velocity = { x: 0, y: 0 }, packetTime = 0, previousVelocity = null, sinceTurn = null;
    for (let now = .07; now < 9; now += 1 / hz) {
      while (cursor < packets.length && packets[cursor].arrival <= now) {
        const packet = packets[cursor++];
        if (previous && packet.arrival - packetTime > .008) velocity = { x: (packet.pos.x - previous.x) / (packet.arrival - packetTime), y: (packet.pos.y - previous.y) / (packet.arrival - packetTime) };
        previous = packet.pos; current = packet.pos; packetTime = packet.arrival;
        tracker.observe(entity, current, packet.arrival * 1000);
      }
      const old = legacy.update(entity, current, now * 1000), track = tracker.estimate(entity, now * 1000);
      const vTruth = { x: (truth(now).x - truth(now - .01).x) / .01, y: (truth(now).y - truth(now - .01).y) / .01 };
      if (previousVelocity && Math.hypot(vTruth.x - previousVelocity.x, vTruth.y - previousVelocity.y) > 4) sinceTurn = now;
      previousVelocity = vTruth;
      // Vary source-supported speed/range and distances; no future observations fed back.
      const speed = [66, 85, 100, 182][(seed + Math.floor(hz / 30) + Number(cadence !== '33Hz')) % 4], origin = { x: seed % 2 ? -15 : 0, y: 0 }, profile = { speed, range: 300, barrel: 2, offset: .25 };
      const before = performance.now();
      const shot = predictShot({ origin, target: current, track, profile, latency: .035 });
      const cost = performance.now() - before;
      for (const [model, row] of Object.entries(rows)) {
        let world = current, flight = Math.hypot(current.x - origin.x, current.y) / speed;
        if (model === 'snapshot') {
          row.cost.push(cost); if (shot.state === 'reduced-lead-uncertainty') row.limited++; if (shot.world && track) { world = shot.world; flight = shot.time; } else row.fallbacks++;
        } else if (model !== 'no-predict') {
          const v = model === 'legacy-render' ? old : velocity;
          flight = intercept({ x: current.x - origin.x, y: current.y }, { x: v.vx ?? v.x, y: v.vy ?? v.y }, speed) ?? flight;
          world = { x: current.x + (v.vx ?? v.x) * flight, y: current.y + (v.vy ?? v.y) * flight };
        }
        const actual = truth(now + .035 + flight), dx = world.x - actual.x, dy = world.y - actual.y;
        const miss = Math.hypot(dx, dy); row.miss.push(miss); row.collider.push(Math.max(0, miss - 1));
        const n = Math.hypot(vTruth.x, vTruth.y); if (n > 1) row.overshoot.push(Math.max(0, (dx * vTruth.x + dy * vTruth.y) / n));
        if (sinceTurn !== null && miss < 1) row.recovery.push((now - sinceTurn) * 1000);
      }
    }
  }
  for (const [model, row] of Object.entries(rows)) result.push({ category: kind, model, n: row.miss.length, median: q(row.miss, .5), p95: q(row.miss, .95), colliderP95: q(row.collider, .95), overshootP95: q(row.overshoot, .95), recoveryMedian: q(row.recovery, .5), fallback: row.fallbacks / row.miss.length, limited: row.limited / row.miss.length, costP95us: q(row.cost, .95) * 1000 });
}
const fmt = x => x.toFixed(3);
const text = `# Movement-general prediction benchmark\n\nDeterministic synthetic held-out seeds: ${seeds.join(', ')}. Frozen solver evaluated on these seeds once; diagnostic/calibration seeds were 7301, 99173, 441019.\n12 motion families × 3 seeds × 30/60/144Hz render × regular/jitter-gap 33Hz snapshots. WebSocket packet order preserved, backlog produces bunching. Quantization 16-bit/1024; fixed 35ms one-way age + 35ms estimated input transit.\nModel only sees arrived samples. Weapon nominal speeds 66/85/100/182; origin/muzzle/range are explicit. No spread, body physics, obstructions or player skill. **Not live hitrate/FPS.**\n\nMiss is future-position error at model flight time; collider miss=max(0, miss−1). Rejected/stale snapshot predictions are scored as direct/native fallback, not removed. Legacy baseline uses former render-sampled Tracker/intercept, without old controller blend (isolates estimator/solver). CV uses last arrival interval, no filtering.\n\n| Motion | Model | n | Median miss wu | p95 miss | p95 collider miss | p95 overshoot | Recovery proxy median ms | Native fallback % | Reduced lead % | Solver p95 µs |\n|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n` + result.map(r => `| ${r.category} | ${r.model} | ${r.n} | ${fmt(r.median)} | ${fmt(r.p95)} | ${fmt(r.colliderP95)} | ${fmt(r.overshootP95)} | ${fmt(r.recoveryMedian)} | ${fmt(r.fallback * 100)} | ${fmt(r.limited * 100)} | ${fmt(r.costP95us)} |`).join('\n') + '\n\nRecovery column is the elapsed time since the most recent detected ground-truth velocity discontinuity **for frames already within radius** (not a guarantee of sustained recovery). Smooth curves have no discrete turn marker. Selection churn is not measured in this single-target solver benchmark; separate combination tests cover target ownership/lifecycle. CPU column measures only this solver call in Node, not frame work or browser FPS.\n\n## Interpretation / limits\n\nFit residual (wu) and slope uncertainty (wu/s) are separate. Excess slope uncertainty uses an explicit reduced-lead fallback, recalculating physical flight time; stale age >150ms relinquishes aim. Native fallback is scored using current-position direct aim as a proxy because physical user intent is not available in this synthetic dataset.\n\nShort weighted regression is movement-agnostic: no maneuver classifier or future-pattern fit. Turns/stops can be intrinsically unpredictable across flight time. The uncertainty guard may relinquish aim instead of claiming an accurate intercept; fallback misses remain in this table. Per-category results, including regressions, must be reviewed rather than hidden in a grand average.\n';
if (process.argv.includes('--write')) writeFileSync('docs/aim-benchmark.vi.md', text);
else console.log(text);
