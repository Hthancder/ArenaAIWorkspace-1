// Verify all base gun profiles against source Bullet.init with fake world.
// No spread, collision, networking, live server or player input is simulated.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { weaponProfile } from '../src/aim.mjs';
const root=resolve(process.argv[2]||'.cache/survev'), pin='3edee7e8bd07fda8a63905aab4c45b595b684a80';
assert.equal(execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),pin);
function transpile(file){ const js=transformSync(readFileSync(resolve(root,file),'utf8'),{loader:'ts',target:'es2022'}).code; return {js,tree:parse(js,{ecmaVersion:'latest',sourceType:'module'})}; }
function variable(tree,name){ return tree.body.map(n=>n.declaration||n).find(n=>n.type==='VariableDeclaration'&&n.declarations[0].id.name===name)?.declarations[0].init; }
const guns=transpile('shared/defs/gameObjects/gunDefs.ts'), bullets=transpile('shared/defs/gameObjects/bulletDefs.ts'), perks=transpile('shared/defs/gameObjects/perkDefs.ts'), source=transpile('server/src/game/objects/bullet.ts');
const g=variable(guns.tree,'BaseDefs'), b=variable(bullets.tree,'BaseDefs'), p=variable(perks.tree,'PerkProperties');
assert.ok(g&&b&&p);
const cls=source.tree.body.map(n=>n.declaration||n).find(n=>n.type==='ClassDeclaration'&&n.id.name==='Bullet');
const init=cls?.body.body.find(n=>n.key?.name==='init'); assert.ok(init);
const ctx=vm.createContext({});
vm.runInContext(`
const FactionTeam={Red:1,Blue:2};
const gunDefs=${guns.js.slice(g.start,g.end)};
const bulletDefs=${bullets.js.slice(b.start,b.end)};
const perks=${perks.js.slice(p.start,p.end)};
const Constants={MaxPosition:1024}; const ObjectType={Player:1,Obstacle:2};
const GameConfig={bullet:{reflectDistDecay:1,height:.25}};
const math={min:Math.min,clamp:(x,a,b)=>Math.max(a,Math.min(b,x)),remap:(n,a,b,c,d)=>c+(n-a)/(b-a)*(d-c)};
const v2={copy:p=>({...p}),normalize:p=>{let n=Math.hypot(p.x,p.y);return {x:p.x/n,y:p.y/n}},add:(a,b)=>({x:a.x+b.x,y:a.y+b.y}),mul:(a,n)=>({x:a.x*n,y:a.y*n})};
const util={randomInt:()=>0}; const coldet={intersectSegmentAabb2:()=>null};
const GameObjectDefs={typeToDef:(type)=>bulletDefs[type]};
class Bullet { ${source.js.slice(init.start,init.end)} }
globalThis.data={gunDefs,bulletDefs,perks};
globalThis.make=(bulletType,speedMult,distanceMult)=>{
 const x=Object.assign(new Bullet(),{bulletManager:{game:{objectRegister:{getById:()=>null},grid:{intersectLineSegment:()=>[]},map:{bounds:{min:{x:0,y:0},max:{x:1024,y:1024}}}}}});
 x.init({bulletType,speedMult,distanceMult,pos:{x:100,y:100},dir:{x:1,y:0},playerId:1,layer:0,gameSourceType:'test',damageMult:1});
 return {speed:x.speed,range:x.maxDistance};
};
`,ctx);
const {gunDefs,bulletDefs,perks:props}=ctx.data, defs={...gunDefs,...bulletDefs}; let checked=0; const missing=[];
for (const [id,gun] of Object.entries(gunDefs)) {
  if(!bulletDefs[gun.bulletType]) {missing.push(`${id}:${gun.bulletType}`); continue;}
  for(let bits=0;bits<8;bits++) {
    const types=[...(bits&1?['bonus_9mm']:[]),...(bits&2?['high_velocity']:[]),...(bits&4?['bonus_assault']:[])];
    let speed=1,range=1;
    if(types.includes('bonus_9mm')&&gun.ammo==='9mm') {speed*=props.bonus_9mm.speedMult;range*=props.bonus_9mm.distanceMult;}
    if(types.includes('high_velocity')) {speed*=props.high_velocity.speedMult;range*=props.high_velocity.distanceMult;}
    if(types.includes('bonus_assault')) speed*=props.bonus_assault.speedMult;
    const actual=ctx.make(gun.bulletType,speed,range), profile=weaponProfile(defs,id,types.map(type=>({type})));
    assert.ok(profile, id);
    assert.ok(Math.abs(profile.speed-actual.speed)<1e-8,`${id} speed`);
    assert.ok(Math.abs(profile.range-actual.range)<1e-8,`${id} range`);
    checked++;
  }
}
console.log(`PASS ${checked} source Bullet.init comparisons across ${checked/8} base guns and 8 perk combinations; omitted ${missing.length} guns with no captured bullet def.`);
if(missing.length)console.log('Omitted:',missing.join(', '));
console.log('Fake inert world, min distance jitter, no toMouseHit clipping, .45 random perk, skins, spread, projectile weapons, network or live game.');
