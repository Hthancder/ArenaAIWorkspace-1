// Compare a single central pellet's muzzle against exact pinned source
// fireWeapon clipping branches and collision methods. No server is started.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { clippedMuzzle } from '../src/aim-geometry.mjs';

const root = resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), '3edee7e8bd07fda8a63905aab4c45b595b684a80');
const js = file => transformSync(readFileSync(resolve(root, file), 'utf8'), { loader: 'ts' }).code;
function properties(code, name, names) {
  const tree = parse(code, { ecmaVersion: 'latest', sourceType: 'module' });
  const node = tree.body.map(n => n.declaration || n).find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === name).declarations[0].init;
  return names.map(key => { const p = node.properties.find(p => p.key.name === key); assert.ok(p, `${name}.${key}`); return code.slice(p.start, p.end); }).join(',');
}
const weapon = js('server/src/game/weaponManager.ts'), coldet = js('shared/utils/coldet.ts'), collider = js('shared/utils/collider.ts');
const a = weapon.indexOf('const direction = this.player.dir;'), b = weapon.indexOf('const hasExplosive =', a);
const c = weapon.indexOf('let bltStart =', b), d = weapon.indexOf('let distance = Number.MAX_VALUE;', c);
assert.ok(a >= 0 && b > a && c > b && d > c, 'source fireWeapon clipping branches');
const context = vm.createContext({});
vm.runInContext(`
const math={min:Math.min,max:Math.max,clamp:(v,a,b)=>Math.max(a,Math.min(b,v))};
const v2={create:(x=0,y=x)=>({x,y}),sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),add:(a,b)=>({x:a.x+b.x,y:a.y+b.y}),mul:(a,n)=>({x:a.x*n,y:a.y*n}),div:(a,n)=>({x:a.x/n,y:a.y/n}),perp:a=>({x:-a.y,y:a.x}),dot:(a,b)=>a.x*b.x+a.y*b.y,length:a=>Math.hypot(a.x,a.y),lengthSqr:a=>a.x*a.x+a.y*a.y,normalize:a=>{const n=Math.hypot(a.x,a.y);return n?{x:a.x/n,y:a.y/n}:{x:1,y:0}},normalizeSafe:(a,f)=>{const n=Math.hypot(a.x,a.y);return n?{x:a.x/n,y:a.y/n}:f}};
const coldet={${properties(coldet,'coldet',['intersectCircleCircle','intersectAabbCircle','intersectSegmentCircle','intersectSegmentAabb'])}};
const collider={Type:{Aabb:1},createAabbExtents:()=>({}),${properties(collider,'collider',['intersectCircle','intersectSegment'])}};
const util={toGroundLayer:a=>a&1,sameLayer:(a,b)=>(a&1)===(b&1)||!!((a&2)&&(b&2))};
const ObjectType={Obstacle:2},GameConfig={player:{radius:1},bullet:{height:.25}};
class WeaponManager { test(itemDef,weapon,offHand) { ${weapon.slice(a,b)} const i=0; ${weapon.slice(c,d)} return shotPos; } }
globalThis.WeaponManager=WeaponManager;
`, context);
let cases = 0;
for (const scale of [.3, 1, 2]) for (const layer of [0, 1]) for (const bulletLayer of [0, 1]) for (const x of [-.5, .1, .8, 1.2, 1.5, 2.205, 2.5, 4]) for (const angle of [0, .35, 1.2, 2.4]) for (const lateral of [0, .1, .25]) {
  const profile = { offset: 0, barrel: 2 }, start = { x: 0, y: 0 }, dir = { x: Math.cos(angle), y: Math.sin(angle) };
  const obstacle = { __type: 2, active: true, dead: false, collidable: true, layer: bulletLayer, height: 1, collider: { type: 0, pos: { x: dir.x * x - dir.y * lateral, y: dir.y * x + dir.x * lateral }, rad: .2 } };
  const player = { pos: start, dir, layer, aimLayer: bulletLayer, rad: scale, toMouseLen: 1, cancelAction() {}, game: { grid: { intersectCollider() { return [obstacle]; } } } };
  const manager = Object.assign(new context.WeaponManager(), { player });
  const expected = manager.test({ isDual: false, barrelOffset: 0, barrelLength: 2, fireDelay: .1 }, { ammo: 10 }, false);
  const actual = clippedMuzzle(start, dir, profile, [obstacle], bulletLayer, layer & 1, scale);
  assert.ok(Math.hypot(actual.x - expected.x, actual.y - expected.y) < 1e-8, `scale=${scale}, layer=${layer}, bullet=${bulletLayer}, x=${x} angle=${angle} lateral=${lateral}: ${JSON.stringify({actual,expected})}`);
  cases++;
}
console.log(`PASS ${cases} source central-pellet muzzle comparisons across scales and layers; inert grid, no live gameplay`);
