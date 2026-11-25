// Synthetic predictor sensitivity, not game hitrate. Run after each tested implementation.
import { SnapshotTracker, predictShot } from '../src/aim.mjs';

const quant = n => Math.round(n * 65535 / 1024) * 1024 / 65535;
const percentile = (a, p) => [...a].sort((x, y) => x - y)[Math.floor((a.length - 1) * p)];
const trajectories = {
  straight: t => ({ x: 60, y: 12 * t }),
  reverse: t => ({ x: 60, y: 6 * Math.asin(Math.sin(Math.PI * t)) }),
  curve: t => ({ x: 60 + 12 * Math.sin(t), y: 12 * (1 - Math.cos(t)) }),
};
for (const [name, truth] of Object.entries(trajectories)) for (const [down, up] of [[.03, .03], [.08, .08], [.15, .15], [.25, .25], [.03, .15], [.15, .03]]) {
  const errors = [], rejected = { n: 0 }; let n = 0;
  for (const hz of [30, 60, 144]) for (const speed of [66, 100, 182]) for (const phase of [0, .007, .019]) {
    const packets = [];
    for (let t = 0; t < 12; t += 1 / 33) { const p = truth(t); packets.push({ t: t + down, p: { x: quant(p.x), y: quant(p.y) } }); }
    const tracker = new SnapshotTracker(), target = { __id: 1 }, profile = { speed, range: 1000, barrel: 0, offset: 0 };
    let i = 0, pos = packets[0].p;
    for (let now = 1 + phase; now < 9; now += 1 / hz) {
      while (i < packets.length && packets[i].t <= now) { const packet = packets[i++]; pos = packet.p; tracker.observe(target, pos, packet.t * 1000); }
      // Baseline approximates RTT/2; --adaptive enables conditional snapshot
      // transit compensation. Neither includes additional ACK scheduling.
      const track = tracker.estimate(target, now * 1000), latency = Math.min(.1, (down + up) / 2);
      const shot = predictShot({ origin: { x: 0, y: 0 }, target: pos, track, profile, latency, stabilize: true, compensateSnapshot: process.argv.includes('--adaptive') });
      const flight = shot.time ?? Math.hypot(pos.x, pos.y) / speed;
      const actual = truth(now + up + flight), dir = shot.dir ?? { x: pos.x / Math.hypot(pos.x, pos.y), y: pos.y / Math.hypot(pos.x, pos.y) };
      errors.push(Math.abs(dir.x * actual.y - dir.y * actual.x)); n++; if (!shot.dir) rejected.n++;
    }
  }
  console.log(`${name}\tdown=${down}\tup=${up}\tn=${n}\tmedian=${percentile(errors, .5).toFixed(3)}\tp95=${percentile(errors, .95).toFixed(3)}\tfallback=${(100 * rejected.n / n).toFixed(2)}%`);
}
