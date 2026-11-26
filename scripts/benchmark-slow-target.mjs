// Synthetic single-shot proxy; no spread, cooldown, collisions or actual game.
import { SnapshotTracker, predictShot } from '../src/aim.mjs';
const q = (a,p) => [...a].sort((x,y)=>x-y)[Math.floor((a.length-1)*p)];
const quant = n => Math.round(n*65535/1024)*1024/65535;
const kinds = {
  straight1: t=>t, straight2: t=>2*t, straight4: t=>4*t,
  reverse1: t=>Math.asin(Math.sin(Math.PI*t))/Math.PI,
  reverse2: t=>2*Math.asin(Math.sin(Math.PI*t))/Math.PI,
  stop2: t=>2*(Math.floor(t/2)+Math.min(t%2,1)),
  fast: t=>12*t,
};
for (const [name, fn] of Object.entries(kinds)) {
  const scores = Object.fromEntries(['baseline','half-lead','uncertainty','slow-no-double'].map(x=>[x,[]]));
  for (const down of [.03,.08,.15]) for (const up of [.03,.08,.15]) for (const hz of [30,60,144]) for (const speed of [66,100,182]) {
    const tr = new SnapshotTracker(), p={__id:1}, profile={speed,range:1000,barrel:0,offset:0}; let next=0;
    for (let now=.5;now<6;now+=1/hz) {
      while(next+down<=now) { tr.observe(p,{x:60,y:quant(fn(next))},(next+down)*1000);next+=1/33; }
      const track=tr.estimate(p,now*1000); if(!track)continue;
      const oneWay=Math.min(.1,(down+up)/2), vel=Math.hypot(track.vx,track.vy);
      for (const [mode, value] of Object.entries(scores)) {
        const factor=mode==='half-lead' ? .5 : mode==='uncertainty' ? vel/(vel+(track.velocityError||0)) : 1;
        const t={...track, vx:track.vx*factor,vy:track.vy*factor};
        const s=predictShot({origin:{x:0,y:0},target:t.pos,track:t,profile,latency:oneWay,stabilize:true,compensateSnapshot:!(mode==='slow-no-double' && vel <= 4)});
        if (!s.dir)continue;
        const actual={x:60,y:fn(now+up+s.time)}, error=Math.abs(s.dir.x*actual.y-s.dir.y*actual.x);
        value.push(error);
      }
    }
  }
  console.log(name+'\t'+Object.entries(scores).map(([k,a])=>`${k}:median=${q(a,.5).toFixed(3)},p95=${q(a,.95).toFixed(3)},over1=${(a.filter(x=>x>1).length/a.length*100).toFixed(2)}%`).join('\t'));
}
