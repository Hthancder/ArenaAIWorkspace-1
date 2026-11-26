// Audited Projectile/Bullet source is deterministic, but tick timing and future
// target input are not known to the client. This is a bounded model experiment.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { intercept } from '../src/core.mjs';
const root=resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),'3edee7e8bd07fda8a63905aab4c45b595b684a80');
const js=transformSync(readFileSync(resolve(root,'server/src/game/objects/bullet.ts'),'utf8'),{loader:'ts',target:'es2022'}).code;
const tree=parse(js,{ecmaVersion:'latest',sourceType:'module'});
const cls=tree.body.map(n=>n.declaration||n).find(n=>n.type==='ClassDeclaration'&&n.id.name==='Bullet');
const method=cls.body.body.find(n=>n.key?.name==='update'); assert.ok(method);
const ctx=vm.createContext({});
vm.runInContext(`
const math={min:Math.min,eqAbs:(a,b,e)=>Math.abs(a-b)<=e};
const v2={copy:a=>({...a}),sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),length:a=>Math.hypot(a.x,a.y),add:(a,b)=>({x:a.x+b.x,y:a.y+b.y}),mul:(a,n)=>({x:a.x*n,y:a.y*n}),set:(a,b)=>{a.x=b.x;a.y=b.y}};
const coldet={testPointAabb:()=>true};
class Bullet { ${js.slice(method.start,method.end)} }
globalThis.make=(dir,speed)=>Object.assign(new Bullet(),{pos:{x:0,y:0},startPos:{x:0,y:0},dir,speed,distance:300,distanceTraveled:0,alive:true,reflected:false,onHitFx:'',hit:false,target:{x:0,y:0},radius:1,bulletManager:{game:{map:{bounds:{min:{x:-10000,y:-10000},max:{x:10000,y:10000}}}}},checkForCollisions(old){ const dx=this.pos.x-old.x,dy=this.pos.y-old.y,tx=this.target.x-old.x,ty=this.target.y-old.y; const d=dx*dx+dy*dy, f=d?Math.max(0,Math.min(1,(tx*dx+ty*dy)/d)):0; if(Math.hypot(old.x+f*dx-this.target.x,old.y+f*dy-this.target.y)<=this.radius){this.hit=true;this.alive=false;} }});
`,ctx);
// Same observed past and next 150ms; later inputs are different. Even with
// exact past, one radius-1 aim point cannot cover both at 1.5 seconds.
const a = t => t, b = t => t <= .15 ? t : .3 - t;
for (const t of [-.5, -.2, 0, .05, .15]) assert.equal(a(t), b(t));
assert.ok(Math.abs(a(1.5) - b(1.5)) > 2);
const behaviors={
  slow1: t=>({y:1*t,velocity:1}), slow2:t=>({y:2*t,velocity:2}), straight12:t=>({y:12*t,velocity:12}),
  reverse1:t=>({y:t<=.15?t:.3-t,velocity:1}), reverse4:t=>({y:t<=.15?4*t:1.2-4*t,velocity:4}),
  stop2:t=>({y:2*Math.min(t,.15),velocity:2}),
};
for(const [kind,truth] of Object.entries(behaviors)) {
 const rows=Object.fromEntries(['baseline','plus-half-tick','minus-half-tick'].map(k=>[k,{n:0,hits:0}]));
 for(const dt of [1/30,1/60]) for(const speed of [66,100,182]) for(const dist of [20,50,100]) for(const radius of [.5,1]) for(let phase=0;phase<10;phase++) {
  const start=truth(0), vx=0, vy=start.velocity;
  for(const [model,row] of Object.entries(rows)) {
   const bias=model==='plus-half-tick'?dt/2:model==='minus-half-tick'?-dt/2:0;
   const target={x:dist,y:start.y+vy*bias}, time=intercept(target,{x:vx,y:vy},speed,Infinity);
   const v={x:target.x,y:target.y+vy*time}, n=Math.hypot(v.x,v.y), bullet=ctx.make({x:v.x/n,y:v.y/n},speed);
   bullet.radius=radius;
   const delay=phase/10*dt;
   for(let tick=0;tick<100 && bullet.alive;tick++) {const now=delay+tick*dt; const real=truth(now); bullet.target={x:dist,y:real.y}; bullet.update(dt);}
   row.n++; if(bullet.hit) row.hits++;
  }
 }
 console.log(kind+'\t'+Object.entries(rows).map(([k,r])=>`${k}=${r.hits}/${r.n} (${(100*r.hits/r.n).toFixed(2)}%)`).join('\t'));
}
console.log('Collision callback uses a segment/circle model with a fake grid; true target velocity is deliberately supplied. No network, spread, obstruction, server load or live measurement.');
