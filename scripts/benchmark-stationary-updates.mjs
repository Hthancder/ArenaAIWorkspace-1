// Microbenchmark of isolated stationary snapshot work. Not browser FPS or live gameplay.
import { performance } from 'node:perf_hooks';
import { SnapshotTracker } from '../src/aim.mjs';
const count = 64, ticks = 10000, players = Array.from({ length: count }, (_, i) => ({ __id: i+1 }));
function run(gated) {
  const tr = new SnapshotTracker(), pos = { x: 42, y: 15 }; let fits=0;
  const start=performance.now();
  for (let tick=0;tick<ticks;tick++) {
    const now=tick*33;
    for (const p of players) {
      const s=tr.states.get(p);
      const settled = gated && s?.id === p.__id && s.layer === 0 && now > s.time && now-s.time < 50
        && Math.hypot(s.vx,s.vy)<.1 && s.samples?.length>=3
        && s.samples.every(o=>Math.hypot(o.p.x-pos.x,o.p.y-pos.y)<.02);
      if (!settled) { tr.observe(p,pos,now,0); fits++; }
    }
  }
  return { ms: performance.now()-start, fits, track:tr.estimate(players[0],(ticks-1)*33) };
}
// Warm runtime before measurement.
run(false); run(true);
for(const mode of [false,true]) { const r=run(mode); console.log(`${mode?'gated':'baseline'}: ${r.ms.toFixed(1)}ms / ${ticks*count} checks; fits=${r.fits}; age=${r.track.age.toFixed(3)}s, speed=${Math.hypot(r.track.vx,r.track.vy).toFixed(6)}`); }
