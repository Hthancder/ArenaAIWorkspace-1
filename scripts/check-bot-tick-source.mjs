// Compare bot segment/circle predicate against the pinned source method.
// Does not reproduce server grid, movement, timing, hit processing or live gameplay.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { tickSegmentCircle } from './benchmark-bot-duel.mjs';
const root=resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),'3edee7e8bd07fda8a63905aab4c45b595b684a80');
const js=transformSync(readFileSync(resolve(root,'shared/utils/coldet.ts'),'utf8'),{loader:'ts'}).code;
const tree=parse(js,{ecmaVersion:'latest',sourceType:'module'});
const obj=tree.body.map(n=>n.declaration||n).find(n=>n.type==='VariableDeclaration'&&n.declarations[0].id.name==='coldet').declarations[0].init;
const method=obj.properties.find(p=>p.key.name==='intersectSegmentCircle'); assert.ok(method);
const ctx=vm.createContext({});
vm.runInContext(`const math={max:Math.max}; const v2={sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),add:(a,b)=>({x:a.x+b.x,y:a.y+b.y}),length:a=>Math.hypot(a.x,a.y),div:(a,n)=>({x:a.x/n,y:a.y/n}),mul:(a,n)=>({x:a.x*n,y:a.y*n}),dot:(a,b)=>a.x*b.x+a.y*b.y,normalize:a=>{const n=Math.hypot(a.x,a.y);return n?{x:a.x/n,y:a.y/n}:{x:1,y:0}}}; globalThis.coldet={${js.slice(method.start,method.end)}};`,ctx);
let seed=31827; const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
for(let i=0;i<12000;i++) {
  const center={x:(rand()-.5)*4,y:(rand()-.5)*4}, radius=.1+2*rand();
  const start={x:center.x+(rand()-.5)*6,y:center.y+(rand()-.5)*6};
  const angle=rand()*Math.PI*2, len=i%7===0 ? 0 : rand()*4;
  const end={x:start.x+len*Math.cos(angle),y:start.y+len*Math.sin(angle)};
  assert.equal(tickSegmentCircle(start,end,center,radius),!!ctx.coldet.intersectSegmentCircle(start,end,center,radius),`case ${i}`);
}
console.log('PASS 12000 segment/circle predicate comparisons with pinned coldet, including zero-length and overlapping cases; not a full server replay.');
