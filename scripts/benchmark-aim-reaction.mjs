// Snapshot-level reaction benchmark. Deterministic synthetic trajectories, not live latency.
// AIM_MODULE permits testing an isolated experimental copy without modifying runtime.
const { SnapshotTracker, boundedOscillation } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const quant = n => Math.round(n * 65535 / 1024) * 1024 / 65535;
const pct = (a, p) => [...a].sort((x, y) => x - y)[Math.floor((a.length - 1) * p)];
const period = 1 / 33, event = 2;
const triangle = t => 0.6 * (2 / Math.PI) * Math.asin(Math.sin(2 * Math.PI * t * 1.5));
const scenarios = {
  reverse: t => ({ x: 60, y: 12 * (t < event ? t - event : event - t) }),
  stop: t => ({ x: 60, y: 12 * Math.min(t - event, 0) }),
  // Continuous departures; some start inside the old range rather than at its edge.
  'ad-depart-inline': t => ({ x: 60, y: t < event ? triangle(t) : triangle(event) + 12 * (t - event) }),
  'ad-depart-side': t => ({ x: 60 + (t < event ? 0 : 12 * (t - event)), y: t < event ? triangle(t) : triangle(event) }),
};
console.log('# Receive-to-classification proxy, no sender/controller or live networking. Event time is server truth; receive time includes configured downlink.');
console.log('scenario\tdown-ms\tn\tbaseline-eligible\tfirst-post-receive-ms median/p95\tclassification-after-first-ms median/p95\tmissed');
for (const [name, truth] of Object.entries(scenarios)) for (const down of [.03, .08, .15]) {
  const firsts = [], afters = []; let eligible = 0, missed = 0;
  for (let phase = 0; phase < 60; phase++) {
    const tracker = new SnapshotTracker(), target = { __id: 1 }; let first = null, detected = null, before = false;
    for (let t = phase * period / 60; t < event + .8; t += period) {
      const pos = truth(t), arrival = t + down;
      tracker.observe(target, { x: quant(pos.x), y: quant(pos.y) }, arrival * 1000);
      const track = tracker.estimate(target, arrival * 1000), midpoint = !!boundedOscillation(track, 1);
      if (t < event) { before = name.startsWith('ad-') ? midpoint : name === 'reverse' || name === 'stop' ? track.vy > 5 : false; continue; }
      if (first === null) { first = arrival; if (before) eligible++; }
      if (!before) break;
      const changed = name === 'reverse' ? track.vy < -2 : name === 'stop' ? Math.abs(track.vy) < .7 : !midpoint;
      if (changed) { detected = arrival; break; }
    }
    if (!before) continue;
    firsts.push((first - event) * 1000);
    if (detected === null) missed++; else afters.push((detected - first) * 1000);
  }
  const fmt = a => a.length ? `${pct(a, .5).toFixed(1)}/${pct(a, .95).toFixed(1)}` : 'n/a';
  console.log(`${name}\t${down * 1000}\t60\t${eligible}\t${fmt(firsts)}\t${fmt(afters)}\t${missed}`);
}
console.log('# Classification means tracker velocity sign/stop threshold or midpoint disabled, not confirmed aim or server hit. Phase, quantization and geometry matter.');
