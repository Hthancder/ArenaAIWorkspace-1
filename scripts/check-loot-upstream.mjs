// Compare Nearby's guard with pinned source Player.getClosestLoot. No server is started.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { parse } from 'acorn';
import { transformSync } from 'esbuild';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { nearbyLootSafety } from '../src/loot-safety.mjs';

const root = resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), '3edee7e8bd07fda8a63905aab4c45b595b684a80');
const js = transformSync(readFileSync(resolve(root, 'server/src/game/objects/player.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const tree = parse(js, { ecmaVersion: 'latest', sourceType: 'module' });
const cls = tree.body.map(n => n.declaration || n).find(n => n.type === 'ClassDeclaration' && n.id.name === 'Player');
const method = cls?.body.body.find(n => n.key?.name === 'getClosestLoot'); assert.ok(method);
const code = `const ObjectType={Loot:3}, GameConfig={player:{touchLootRadMult:1}};
const collider={createCircle:(pos,rad)=>({pos,rad})},v2={sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),lengthSqr:v=>v.x*v.x+v.y*v.y};
const util={sameLayer:(a,b)=>(a&1)===(b&1)||!!((a&2)&&(b&2))};
class Player { ${js.slice(method.start, method.end)} }
globalThis.select=(objects,pos)=>Object.assign(new Player(),{__id:1,pos,rad:1,layer:0,isMobile:false,game:{grid:{intersectCollider(){return objects}}}}).getClosestLoot();`;
const context = vm.createContext({}); vm.runInContext(code, context);
const origin = { x: 10, y: 20 };
const candidate = { __id: 9, __type: 3, active: true, destroyed: false, type: '9mm', pos: { x: 11.5, y: 20 }, rad: 2, ownerId: 0, layer: 0 };
const weapon = { __id: 10, __type: 3, active: true, destroyed: false, type: 'mp5', pos: { x: 10.8, y: 20 }, rad: .2, ownerId: 0, layer: 0 };
assert.equal(context.select([candidate, weapon], origin), weapon, 'Server selects closer weapon despite its client pickup radius');
assert.equal(nearbyLootSafety({ 9: candidate, 10: weapon }, candidate, origin, 0, 1), 'competing-loot');
for (const patch of [{ layer: 1 }, { ownerId: 2 }, { pos: { x: 12.5, y: 20 } }]) {
  const other = { ...weapon, ...patch };
  assert.equal(context.select([candidate, other], origin), candidate);
  assert.equal(nearbyLootSafety({ 9: candidate, 10: other }, candidate, origin, 0, 1), 'clear-observed');
}
console.log('PASS source Player.getClosestLoot: nearer weapon mismatch and 3 clear cases; inert grid, no network or live server');
