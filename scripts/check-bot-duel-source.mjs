// Check only the source constants/branches cited by the simplified duel bot.
// This is NOT a replay of Player movement or bullet collision.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import { SIM } from './benchmark-bot-duel.mjs';
const root=resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),'3edee7e8bd07fda8a63905aab4c45b595b684a80');
const js=transformSync(readFileSync(resolve(root,'shared/gameConfig.ts'),'utf8'),{loader:'ts'}).code;
const tree=parse(js,{ecmaVersion:'latest',sourceType:'module'});
const declaration=tree.body.map(n=>n.declaration||n).find(n=>n.type==='VariableDeclaration'&&n.declarations.some(d=>d.id.name==='GameConfig'));
const obj=declaration.declarations.find(d=>d.id.name==='GameConfig').init;
const prop=(node,key)=>node.properties.find(p=>(p.key.name||p.key.value)===key)?.value;
const player=prop(obj,'player');
assert.equal(prop(player,'moveSpeed').value,SIM.baseSpeed);
assert.equal(prop(player,'boostMoveSpeed').value,SIM.boostBonus);
assert.equal(prop(player,'radius').value,SIM.radius);
const source=readFileSync(resolve(root,'server/src/game/objects/player.ts'),'utf8');
const part=source.slice(source.indexOf('recalculateSpeed(hasTreeClimbing: boolean)'),source.indexOf('\n    }',source.indexOf('recalculateSpeed(hasTreeClimbing: boolean)')));
assert.match(part,/this\.boost\s*>=\s*50/);
assert.match(part,/this\.speed\s*\+=\s*GameConfig\.player\.boostMoveSpeed/);
assert.match(part,/this\.shotSlowdownTimer\s*>\s*0/);
assert.match(part,/this\.speed\s*\*=\s*0\.5/);
assert.equal(SIM.fireMultiplier,.5);
console.log('PASS pinned base speed, boost bonus, radius and slowdown source branches; simplified bot is not a server replay.');
