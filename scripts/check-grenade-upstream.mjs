// Independent open-ground comparison against actual pinned Survev Projectile.update.
// No game server, networking, map collisions or live gameplay is started.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { parse } from 'acorn';
import { transformSync } from 'esbuild';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { simulateOpenThrow, solveOpenThrow } from '../src/grenade-aim.mjs';
import { throwPreview } from '../src/previews.mjs';

const root = resolve(process.argv[2] || '.cache/survev');
const pin = '3edee7e8bd07fda8a63905aab4c45b595b684a80';
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), pin, 'Use audited source commit');
const js = transformSync(readFileSync(resolve(root, 'server/src/game/objects/projectile.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const tree = parse(js, { ecmaVersion: 'latest', sourceType: 'module' });
const cls = tree.body.map(n => n.declaration || n).find(n => n.type === 'ClassDeclaration' && n.id.name === 'Projectile');
const update = cls?.body.body.find(n => n.key?.name === 'update');
assert.ok(update, 'source Projectile.update');
const weaponJs = transformSync(readFileSync(resolve(root, 'server/src/game/weaponManager.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const weaponTree = parse(weaponJs, { ecmaVersion: 'latest', sourceType: 'module' });
const weaponClass = weaponTree.body.map(n => n.declaration || n).find(n => n.type === 'ClassDeclaration' && n.id.name === 'WeaponManager');
const throwMethod = weaponClass?.body.body.find(n => n.key?.name === 'throwThrowable');
assert.ok(throwMethod, 'source WeaponManager.throwThrowable');
const defsJs = transformSync(readFileSync(resolve(root, 'shared/defs/gameObjects/throwableDefs.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const defsTree = parse(defsJs, { ecmaVersion: 'latest', sourceType: 'module' });
const defs = defsTree.body.map(n => n.declaration || n).find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === 'ThrowableDefs').declarations[0].init;
const frag = defs.properties.find(n => n.key.name === 'frag')?.value;
const snowball = defs.properties.find(n => n.key.name === 'snowball')?.value;
assert.ok(frag && snowball, 'source frag and snowball definitions');
const code = `
const gravity=10.5, math={max:Math.max,clamp:(n,a,b)=>Math.max(a,Math.min(b,n))};
const v2={mul:(a,n)=>({x:a.x*n,y:a.y*n}),add:(a,b)=>({x:a.x+b.x,y:a.y+b.y}),sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),normalizeSafe:(v,fallback={x:1,y:0})=>{const n=Math.hypot(v.x,v.y);return n>1e-6?{x:v.x/n,y:v.y/n}:fallback},copy:a=>({...a}),length:a=>Math.hypot(a.x,a.y),create:(x,y)=>({x,y}),rotate:(p,a)=>({x:p.x*Math.cos(a)-p.y*Math.sin(a),y:p.x*Math.sin(a)+p.y*Math.cos(a)})};
const GameConfig={projectile:{maxHeight:5},player:{cookTime:.1,throwableMaxMouseDist:18,throwTime:.3},WeaponSlot:{Throwable:3},Anim:{Throw:3},DamageType:{Player:1}}, frag=${defsJs.slice(frag.start, frag.end)}, snowball=${defsJs.slice(snowball.start, snowball.end)};
const GameObjectDefs={typeToDef(type){return type==='snowball'?snowball:frag}};
class Projectile { ${js.slice(update.start, update.end)} }
class WeaponManager { ${weaponJs.slice(throwMethod.start, throwMethod.end)} }
globalThis.make=(origin,dir,mouse,vel,fuse,type='frag')=>{
 let spawned=null; const def=GameObjectDefs.typeToDef(type);
 const game={map:{isOnWater:()=>false,clampToMapBounds(){}},grid:{intersectLineSegment:()=>[],intersectGameObject:()=>[],updateObject(){}},projectileBarn:{addProjectile(...args){spawned=args;return {}}}};
 const player={__id:1,layer:0,pos:origin,dir,moveVel:vel,toMouseLen:mouse,game,hasPerk:()=>false,playAnim(){},invManager:{get:()=>1,take(){}}};
 const manager=Object.assign(new WeaponManager(),{player,weapons:[{},{},{},{type}],curWeapIdx:3,cookingThrowable:true,cookTicker:def.fuseTime-fuse});
 manager.throwThrowable(); if(!spawned)throw Error('source throw did not spawn');
 const [id,spawnedType,pos,posZ,layer,throwVelocity,actualFuse]=spawned;
 return Object.assign(new Projectile(),{type:spawnedType,layer,pos,posZ,velZ:def.throwPhysics.velZ,rad:def.rad*.5,obstacleBellowHeight:0,vel:throwVelocity,fuseTime:actualFuse,dead:false,destroyed:false,game,checkStairs(){},setDirty(){},setPartDirty(){},explode(){this.dead=true;this.destroyed=true;}});
}; globalThis.frag=frag; globalThis.snowball=snowball;
`;
const ctx = vm.createContext({}); vm.runInContext(code, ctx);
let cases = 0;
for (const angle of [-3, -.7, 0, 1.4, 3]) for (const mouse of [0, 3, 9, 18])
  for (const vel of [{ x: 0, y: 0 }, { x: 4, y: -3 }]) for (const fuse of [.03, .4, 1.7, 3.4]) for (const dt of [1 / 30, 1 / 60]) {
    const origin = { x: 100, y: 100 }, dir = { x: Math.cos(angle), y: Math.sin(angle) };
    const src = ctx.make(origin, dir, mouse, vel, fuse);
    const remaining = src.fuseTime;
    const sim = simulateOpenThrow({ def: ctx.frag, origin, direction: dir, mouseDistance: mouse, playerVelocity: vel, fuseRemaining: remaining, dt });
    assert.ok(sim); let step = 0;
    while (!src.destroyed && step < 1000) {
      src.update(dt); step++;
      const point = sim.points[step]; assert.ok(point);
      assert.ok(Math.hypot(src.pos.x - point.x, src.pos.y - point.y) < 1e-9, `source XY mismatch step ${step}`);
      assert.ok(Math.abs(src.posZ - point.z) < 1e-9, `source Z mismatch step ${step}`);
    }
    assert.equal(step, sim.points.length - 1);
    const solved = solveOpenThrow({ def: ctx.frag, origin, target: sim.end, playerVelocity: vel, fuseRemaining: remaining, dt });
    assert.ok(solved); assert.ok(Math.hypot(solved.end.x-src.pos.x, solved.end.y-src.pos.y) < 1e-8);
    cases++;
  }
let impactCases = 0;
for (const angle of [-2, -.7, 0, 1.4, 3]) for (const mouse of [0, 3, 9, 18]) {
  const origin = { x: 100, y: 100 }, dir = { x: Math.cos(angle), y: Math.sin(angle) };
  const src = ctx.make(origin, dir, mouse, { x: 0, y: 0 }, ctx.snowball.fuseTime - .2, 'snowball');
  const preview = throwPreview(ctx.snowball, origin, dir, mouse);
  const sampled = [{ ...src.pos }]; let steps = 0;
  while (!src.destroyed && steps < 180) {
    src.update(1 / 60); steps++;
    if (steps % 6 === 0) sampled.push({ ...src.pos });
  }
  assert.ok(src.destroyed, 'source impact projectile explodes on the ground');
  if (steps % 6) sampled.push({ ...src.pos });
  assert.equal(preview.points.length, sampled.length);
  for (let i = 0; i < sampled.length; i++) assert.ok(Math.hypot(preview.points[i].x - sampled[i].x, preview.points[i].y - sampled[i].y) < 1e-8, `impact preview mismatch ${angle}, ${mouse}, point ${i}`);
  assert.ok(Math.hypot(preview.end.x - src.pos.x, preview.end.y - src.pos.y) < 1e-8);
  impactCases++;
}
console.log(`PASS ${cases} source WeaponManager.throwThrowable + Projectile.update flat-ground scenarios, plus ${impactCases} snowball preview comparisons; no terrain, obstacle/player collision, networking or live gameplay`);
