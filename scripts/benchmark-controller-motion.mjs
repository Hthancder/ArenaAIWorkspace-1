// Deterministic synthetic controller + predictor benchmark; not live hit rate.
const { SnapshotTracker, predictShot, AimController } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const quant = x => Math.round(x * 65535 / 1024) * 1024 / 65535;
const triangle = t => 2 / Math.PI * Math.asin(Math.sin(Math.PI * t));
const motions = {
  stationary: t => 0,
  straight: t => 12 * t,
  reverse: t => 6 * triangle(t),
  'fast-reverse': t => 10 * triangle(t),
  'start-stop': t => 12 * (Math.floor(t / 1.4) * .7 + Math.min(t % 1.4, .7)),
  'small-ad': t => .6 * triangle(3 * t),
  'wide-ad': t => 1.5 * triangle(2 * t),
};
console.log('# Perpendicular plane error, equal real-time frame weight within each FPS; no spread, obstacles or server. Not hit rate.');
for (const [name, motion] of Object.entries(motions)) {
  const errors = [];
  for (const hz of [30,60,144]) for (const bullet of [66,100,182]) for (const phase of [0,.007,.019]) for (const down of [.03,.08]) {
    const tracker=new SnapshotTracker(), controller=new AimController(), target={__id:1}, profile={speed:bullet,range:1000,barrel:0,offset:0};
    const packets=[]; for(let t=0;t<10;t+=1/33) packets.push({at:t+down,pos:{x:60,y:quant(motion(t))}});
    let idx=0,pos=null;
    for(let now=phase;now<8;now+=1/hz) {
      while(idx<packets.length&&packets[idx].at<=now) { const p=packets[idx++]; pos=p.pos; tracker.observe(target,pos,p.at*1000); }
      if(!pos) continue;
      const track=tracker.estimate(target,now*1000), shot=predictShot({origin:{x:0,y:0},target:pos,track,profile,latency:down,radius:1,stabilize:true,compensateSnapshot:true});
      const len=Math.hypot(pos.x,pos.y), direct={x:pos.x/len,y:pos.y/len};
      if(!shot.dir) controller.reset();
      const dir=shot.dir ? controller.step(direct,shot.dir,{mode:'lock',smooth:50,humanLike:true,profile:'responsive',target,now:now*1000}) : direct;
      if(now<1) continue;
      const flight=dir.x > 0 ? 60/(bullet*dir.x) : Infinity;
      const miss=Number.isFinite(flight) ? Math.abs(60*dir.y/dir.x-motion(now+down+flight)) : 10000;
      // Weight 30/60/144Hz equally rather than giving more samples to high FPS.
      errors.push({miss,weight:1/hz});
    }
  }
  errors.sort((a,b)=>a.miss-b.miss); const sum=errors.reduce((s,x)=>s+x.weight,0);
  const percentile=p=>{let a=0;for(const x of errors){a+=x.weight;if(a>=p*sum)return x.miss;}return errors.at(-1).miss;};
  const outside=errors.reduce((s,x)=>s+(x.miss>1?x.weight:0),0)/sum;
  console.log(`${name}\tn=${errors.length}\tmedian=${percentile(.5).toFixed(3)}\tp95=${percentile(.95).toFixed(3)}\toutside-radius=${(100*outside).toFixed(2)}%`);
}
