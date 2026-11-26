// Compare bounded-weave availability under deterministic synthetic normal A-D.
// AIM_MODULE permits an isolated experimental module; no runtime code is modified.
const { SnapshotTracker, boundedOscillation } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const quant = n => Math.round(n * 65535 / 1024) * 1024 / 65535;
const triangle = t => 2 / Math.PI * Math.asin(Math.sin(2 * Math.PI * t));
for (const width of [.6, 1.2, 3]) for (const hz of [1, 1.5, 2]) for (const noise of [0, .015, .04]) {
  let on = 0, count = 0, exit = 0;
  for (let phase = 0; phase < 30; phase++) {
    const tracker = new SnapshotTracker(), entity = { __id: 1 }; let wasOn = false;
    for (let i = 0; i < 200; i++) {
      const t = (i + phase / 30) / 33;
      // Deterministic measurement noise; neither random nor a real packet trace.
      const y = width / 2 * triangle(t * hz) + noise * Math.sin(i * 2.37 + phase);
      tracker.observe(entity, { x: 60, y: quant(y) }, t * 1000);
      const stable = !!boundedOscillation(tracker.estimate(entity, t * 1000), 1);
      if (t >= 1) { count++; on += stable; if (wasOn && !stable) exit++; }
      wasOn = stable;
    }
  }
  console.log(`width=${width}\thz=${hz}\tnoise=${noise}\tn=${count}\tmidpoint%=${(100 * on / count).toFixed(2)}\texits=${exit}`);
}
