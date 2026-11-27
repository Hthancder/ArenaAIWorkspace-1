// Compare stair shot-layer selection against a pinned source Player.update
// branch and source math methods. Inert collaborators; no running server.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { shotLayer } from '../src/aim-geometry.mjs';

const root = resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), '3edee7e8bd07fda8a63905aab4c45b595b684a80');
const player = transformSync(readFileSync(resolve(root, 'server/src/game/objects/player.ts'), 'utf8'), { loader: 'ts' }).code;
const start = player.indexOf('const rot = Math.atan2(this.dir.y, this.dir.x);');
const end = player.indexOf('if (this.layer !== originalLayer)', start);
assert.ok(start >= 0 && end > start, 'source player stair branch');
const mathJS = transformSync(readFileSync(resolve(root, 'shared/utils/math.ts'), 'utf8'), { loader: 'ts' }).code;
const tree = parse(mathJS, { ecmaVersion: 'latest', sourceType: 'module' });
const mathObject = tree.body.map(n => n.declaration || n).find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === 'math').declarations[0].init;
const sourceMath = ['fmod', 'radToOri'].map(name => {
  const node = mathObject.properties.find(p => p.key.name === name);
  assert.ok(node, `source math.${name}`); return mathJS.slice(node.start, node.end);
}).join(',');
const context = vm.createContext({});
vm.runInContext(`const math={${sourceMath}}; class Player { select(objs) { ${player.slice(start, end)} return this.aimLayer; } } globalThis.Player=Player; globalThis.math=math;`, context);
let cases = 0;
for (const layer of [0, 1, 2, 3]) for (let down = 0; down < 4; down++) {
  const a = down * Math.PI / 2, downDir = { x: Math.cos(a), y: Math.sin(a) };
  const stair = { collision: { min: { x: -1, y: -1 }, max: { x: 1, y: 1 } }, downDir };
  const structures = [{ active: true, stairs: [stair] }];
  const downOri = context.math.radToOri(a);
  const source = new context.Player(); Object.assign(source, { layer, rad: 1, checkStairs: () => ({ downOri, upOri: (downOri + 2) % 4 }) });
  for (let i = 0; i < 720; i++) {
    // Offset from cardinal boundaries to avoid platform rounding ambiguities.
    const angle = (i + .125) * Math.PI * 2 / 720, dir = { x: Math.cos(angle), y: Math.sin(angle) };
    source.dir = dir;
    assert.equal(shotLayer({ x: 0, y: 0 }, dir, layer, 1, structures), source.select([]));
    cases++;
  }
}
console.log(`PASS ${cases} source Player.update stair-layer direction comparisons; inert stair collision, no network or live server`);
