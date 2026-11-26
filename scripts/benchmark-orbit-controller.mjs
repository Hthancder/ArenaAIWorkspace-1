// Idealized controller-only benchmark; not hit rate or a network/server model.
import { AimController, angleDelta } from '../src/aim.mjs';
const cases = {
  'shooter-orbit/still': t => ({ own:{x:10*Math.cos(.8*t),y:10*Math.sin(.8*t)}, target:{x:0,y:0} }),
  'shooter-straight/still': t => ({ own:{x:20,y:8*t-30},target:{x:0,y:0} }),
  'shooter-stop/still': t => ({ own:{x:15,y:8*(Math.floor(t/2)+Math.min(t%2,1))-30},target:{x:0,y:0} }),
  'shooter-orbit/target-moves': t => ({ own:{x:15*Math.cos(.5*t),y:15*Math.sin(.5*t)},target:{x:3*Math.sin(.8*t),y:3*Math.cos(.8*t)} }),
  'shooter-still/target-reverse': t => ({ own:{x:15,y:0},target:{x:0,y:6*Math.asin(Math.sin(3*t))} }),
};
function quantile(a,p){a.sort((x,y)=>x-y); return a[Math.floor((a.length-1)*p)];}
console.log('Controller lag only: true instantaneous shooter/target positions; no muzzle, prediction, latency, spread, wall or server. Not gameplay hit rate.');
for(const [name,path] of Object.entries(cases)) {
 const samples={smooth0:[],smooth20:[],smooth50:[]};
 for(const hz of [30,60,144]) for(const phase of [0,.007,.019]) for(const [key,smooth] of Object.entries({smooth0:0,smooth20:20,smooth50:50})) {
  const c=new AimController(), targetId={};
  for(let now=phase;now<8;now+=1/hz) {
   const {own,target}=path(now),dx=target.x-own.x,dy=target.y-own.y,dist=Math.hypot(dx,dy),want=Math.atan2(dy,dx);
   const dir=c.step({x:Math.cos(want),y:Math.sin(want)},{x:Math.cos(want),y:Math.sin(want)},{mode:'lock',humanLike:true,profile:'responsive',smooth,now:now*1000,target:targetId});
   if(now<1)continue;
   // Subsample at 30Hz per run so 144Hz does not dominate the summary.
   if (Math.floor((now-phase)*30+1e-6) === Math.floor((now-phase-1/hz)*30+1e-6)) continue;
   samples[key].push(Math.abs(Math.sin(angleDelta(Math.atan2(dir.y,dir.x),want))*dist));
  }
 }
 const fields=Object.entries(samples).map(([key,a])=>`${key}:n=${a.length},median=${quantile(a,.5).toFixed(3)},p95=${quantile(a,.95).toFixed(3)},over1=${(100*a.filter(x=>x>1).length/a.length).toFixed(1)}%`);
 console.log(`${name}\t${fields.join('\t')}`);
}
