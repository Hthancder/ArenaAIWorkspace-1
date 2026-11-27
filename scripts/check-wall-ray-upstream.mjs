// Compare the actual-direction wallcheck cutoff with source circle intersection.
// Inert geometry only; does not simulate bullet movement or server gameplay.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { pathAlongAim } from '../src/aim-geometry.mjs';

const root = resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), '3edee7e8bd07fda8a63905aab4c45b595b684a80');
const js = transformSync(readFileSync(resolve(root, 'shared/utils/coldet.ts'), 'utf8'), { loader: 'ts' }).code;
const tree = parse(js, { ecmaVersion: 'latest', sourceType: 'module' });
const obj = tree.body.map(n => n.declaration || n).find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === 'coldet').declarations[0].init;
const method = obj.properties.find(p => p.key.name === 'intersectSegmentCircle'); assert.ok(method);
const context = vm.createContext({});
vm.runInContext(`const math={max:Math.max}; const v2={sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),add:(a,b)=>({x:a.x+b.x,y:a.y+b.y}),length:a=>Math.hypot(a.x,a.y),div:(a,n)=>({x:a.x/n,y:a.y/n}),mul:(a,n)=>({x:a.x*n,y:a.y*n}),dot:(a,b)=>a.x*b.x+a.y*b.y,normalize:a=>{const n=Math.hypot(a.x,a.y);return n?{x:a.x/n,y:a.y/n}:{x:1,y:0}}}; globalThis.coldet={${js.slice(method.start,method.end)}};`, context);
let cases = 0;
for (const origin of [{ x: 0, y: 0 }, { x: 9.5, y: 0 }, { x: 10, y: 0 }, { x: 12, y: 3 }]) {
  const target = { x: 10, y: 0 };
  for (const radius of [.25, 1, 2]) for (let i = 0; i < 720; i++) {
    const angle = (i + .125) * 2 * Math.PI / 720, dir = { x: Math.cos(angle), y: Math.sin(angle) };
    const length = Math.hypot(target.x - origin.x, target.y - origin.y) + radius;
    const end = { x: origin.x + dir.x * length, y: origin.y + dir.y * length };
    const collision = context.coldet.intersectSegmentCircle(origin, end, target, radius);
    const expected = collision?.point || end, actual = pathAlongAim(origin, dir, target, radius);
    assert.ok(Math.hypot(actual.x - expected.x, actual.y - expected.y) < 1e-8, `case ${cases}`);
    cases++;
  }
}
console.log(`PASS ${cases} source coldet.intersectSegmentCircle comparisons; inert geometry, no live gameplay`);
