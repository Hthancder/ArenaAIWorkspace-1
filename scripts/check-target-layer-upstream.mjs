// Compare source bullet and melee player-layer predicates across all layers.
// Inert predicates only; does not simulate damage or live gameplay.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { walk } from '../src/core.mjs';
import { targetLayerEligible } from '../src/aim-geometry.mjs';

const root = resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), '3edee7e8bd07fda8a63905aab4c45b595b684a80');
function source(file) { return transformSync(readFileSync(resolve(root, file), 'utf8'), { loader: 'ts' }).code; }
const bullet = source('server/src/game/objects/bullet.ts'), melee = source('server/src/game/weaponManager.ts');
let bulletNode, meleeNode;
walk(parse(bullet, { ecmaVersion: 'latest', sourceType: 'module' }), n => {
  if (n.type === 'LogicalExpression' && n.operator === '||' && bullet.slice(n.start, n.end) === 'util.sameLayer(obj.layer, this.layer) || 2 & obj.layer') bulletNode = n;
});
walk(parse(melee, { ecmaVersion: 'latest', sourceType: 'module' }), n => {
  if (n.type === 'CallExpression' && melee.slice(n.start, n.end) === 'util.sameLayer(playerCol.layer, this.player.layer)') meleeNode = n;
});
assert.ok(bulletNode && meleeNode, 'source player-layer predicates');
const context = vm.createContext({});
vm.runInContext(`const util={sameLayer:(a,b)=>(a&1)===(b&1)||!!((a&2)&&(b&2))};
globalThis.bullet=function(obj){return !!(${bullet.slice(bulletNode.start,bulletNode.end)})};
globalThis.melee=function(playerCol){return !!(${melee.slice(meleeNode.start,meleeNode.end)})};`, context);
let cases = 0;
for (let target = 0; target < 4; target++) for (let attack = 0; attack < 4; attack++) {
  assert.equal(targetLayerEligible(target, attack, false), context.bullet.call({ layer: attack }, { layer: target }));
  assert.equal(targetLayerEligible(target, attack, true), context.melee.call({ player: { layer: attack } }, { layer: target }));
  cases += 2;
}
assert.equal(targetLayerEligible(null, 1), false); assert.equal(targetLayerEligible(2, null), false);
console.log(`PASS ${cases} source bullet/melee player-layer predicates; inert fixture, no live gameplay`);
