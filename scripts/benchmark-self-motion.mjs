// Combined target and shooter motion experiment: synthetic only, not gameplay.
// Tests shooter origin projection without editing runtime code. Received samples
// are quantized and delayed; actual future positions are used only for scoring.
import { SnapshotTracker, predictShot, muzzleAt } from '../src/aim.mjs';
const q=(a,p)=>[...a].sort((a,b)=>a-b)[Math.floor((a.length-1)*p)];
const quant=n=>Math.round(n*65535/1024)*1024/65535;
const paths={
  still:t=>({x:0,y:0}),
  slow:t=>({x:0,y:2*t}),
  straight:t=>({x:0,y:10*t}),
  reverse:t=>({x:0,y:6*Math.asin(Math.sin(Math.PI*t))}),
  sidestep:t=>({x:0,y:Math.max(-.6,Math.min(.6,2*Math.sin(Math.PI*2*t)))}),
  stop:t=>({x:0,y:10*(Math.floor(t/1.8)*.9+Math.min(t%1.8,.9))}),
};
const shooters={
  still:paths.still,
  straight:t=>({x:0,y:8*t}),
  reverse:t=>({x:0,y:4*Math.asin(Math.sin(Math.PI*t))}),
  stop:paths.stop,
};
for (const [ownName,ownTruth] of Object.entries(shooters)) for (const [targetName,targetTruth] of Object.entries(paths)) {
  const rows={baseline:[],project:[]}, rejected={baseline:0,project:0};
  for (const [down,up] of [[.03,.03],[.08,.08],[.15,.15],[.03,.15],[.15,.03]]) for(const fps of [30,60,144]) for(const bulletSpeed of [66,100,182]) for(const phase of [0,.009,.019]) for (const cadence of ['regular', 'jitter-gap']) {
    const own=new SnapshotTracker(), enemy=new SnapshotTracker(), me={__id:1}, target={__id:2};
    const packets=[]; let lastArrival=-Infinity;
    for (let t=0,i=0; t<6; t+=1/33,i++) {
      const jitter=cadence==='regular'?0:.012*Math.sin(i*2.3)+(i%83===75?.16:0);
      const arrival=Math.max(t+down+jitter,lastArrival+.0001); lastArrival=arrival;
      packets.push({t,arrival});
    }
    let packet=0;
    const profile={speed:bulletSpeed,range:400,barrel:2,offset:.25};
    for(let now=.8+phase;now<5;now+=1/fps) {
      while(packet<packets.length && packets[packet].arrival<=now) {
        const {t,arrival}=packets[packet++], op=ownTruth(t),tp=targetTruth(t);
        own.observe(me,{x:quant(op.x),y:quant(op.y)},arrival*1000);
        enemy.observe(target,{x:quant(60+tp.x),y:quant(tp.y)},arrival*1000);
      }
      const o=own.estimate(me,now*1000), e=enemy.estimate(target,now*1000); if(!o||!e)continue;
      const latency=Math.min(.1,(down+up)/2);
      for(const model of Object.keys(rows)) {
        const delta=model==='project'?Math.min(.2,o.age+Math.min(.1,latency*2)):0;
        const origin={x:o.pos.x+o.vx*delta,y:o.pos.y+o.vy*delta};
        const shot=predictShot({origin,target:e.pos,track:e,profile,latency,stabilize:true,compensateSnapshot:true});
        // Score rejects as an approximate direct/native fallback rather than
        // discarding difficult frames; actual user mouse direction is unknown.
        const dx0=e.pos.x-o.pos.x,dy0=e.pos.y-o.pos.y,n=Math.hypot(dx0,dy0);
        const dir=shot.dir||{x:dx0/n,y:dy0/n}, flight=shot.dir?shot.time:n/profile.speed;
        if(!shot.dir) rejected[model]++;
        const realOrigin=ownTruth(now+up),realTarget=targetTruth(now+up+flight);
        const realMuzzle = muzzleAt(realOrigin,dir,profile);
        const dx=60+realTarget.x-realMuzzle.x,dy=realTarget.y-realMuzzle.y;
        rows[model].push(Math.abs(dir.x*dy-dir.y*dx));
      }
    }
  }
  const fmt=a=>`n=${a.length},median=${q(a,.5).toFixed(3)},p95=${q(a,.95).toFixed(3)},over1=${(100*a.filter(x=>x>1).length/a.length).toFixed(1)}%`;
  console.log(`${ownName}/${targetName}\tbaseline:${fmt(rows.baseline)},reject=${rejected.baseline}\tproject:${fmt(rows.project)},reject=${rejected.project}`);
}
console.log('Synthetic proxy only: target/shooter model, no wall, spread, acceleration, server ticks or player input. True future used for scoring only.');
