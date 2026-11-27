// Exercise pinned source explosion damage and split projectile methods in an
// inert fixture. This does not simulate collision rays, networking or gameplay.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';
import vm from 'node:vm';

const root = resolve(process.argv[2] || '.cache/survev');
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), '3edee7e8bd07fda8a63905aab4c45b595b684a80');
function js(file) { return transformSync(readFileSync(resolve(root, file), 'utf8'), { loader: 'ts' }).code; }
function declaration(code, name) {
  return parse(code, { ecmaVersion: 'latest', sourceType: 'module' }).body.map(n => n.declaration || n).find(n => n.id?.name === name || n.declarations?.[0]?.id.name === name);
}
function method(code, className, name) {
  const node = declaration(code, className)?.body.body.find(n => n.key?.name === name); assert.ok(node, `${className}.${name}`);
  return code.slice(node.start, node.end);
}
function property(code, variable, name) {
  const obj = declaration(code, variable)?.declarations[0].init, node = obj?.properties.find(p => p.key?.name === name)?.value;
  assert.ok(node, `${variable}.${name}`); return code.slice(node.start, node.end);
}
const player = js('server/src/game/objects/player.ts'), explosion = js('server/src/game/objects/explosion.ts'), projectile = js('server/src/game/objects/projectile.ts');
const throwable = js('shared/defs/gameObjects/throwableDefs.ts'), explDefs = js('shared/defs/gameObjects/explosionsDefs.ts');
const script = `
const ObjectType={Player:1,Obstacle:2,Loot:3}, GameConfig={DamageType:{Gas:1,Bleeding:2},player:{health:100}};
const PerkProperties={}, math={min:Math.min,remap:(x,a,b,c,d)=>c+(x-a)*(d-c)/(b-a)};
const v2={}, collider={createCircle:(pos,rad)=>({pos,rad})}, coldet={test:()=>false};
const defs={frag:${property(throwable, 'ThrowableDefs', 'frag')},mirv:${property(throwable, 'ThrowableDefs', 'mirv')},explosion_frag:${property(explDefs, 'ExplosionDefs', 'explosion_frag')}};
const GameObjectDefs={typeToDef:(name)=>defs[name],typeToDefSafe:(name)=>defs[name]};
class Player { ${method(player, 'Player', 'damage')} get health(){return this._health} set health(v){this._health=v} hasPerk(){return false} }
class ExplosionBarn { ${method(explosion, 'ExplosionBarn', 'damageObject')} }
class Projectile { ${method(projectile, 'Projectile', 'explode')} }
globalThis.result={Player,ExplosionBarn,Projectile,defs};`;
const context = vm.createContext({}); vm.runInContext(script, context);
const { Player, ExplosionBarn, Projectile, defs } = context.result;
function victim() { return Object.assign(new Player(), { __type: 1, debug: { godMode: false }, _health: 200, dead: false, downed: false, teamId: 7, groupId: 7, disconnected: false, damageTaken: 0, game: { map: { perkMode: false }, isTeamMode: false } }); }
const self = victim(), ally = victim(), barn = new ExplosionBarn();
const blast = { type: 'explosion_frag', pos: { x: 0, y: 0 }, damageParams: { source: self, gameSourceType: 'frag', damageType: 0 } };
const collision = obj => ({ obj, distance: 2, dir: { x: 1, y: 0 } });
barn.damageObject(blast, collision(ally)); assert.equal(ally.health, 200, 'source teammate damage guard');
barn.damageObject(blast, collision(self)); assert.ok(self.health < 200, 'source owner is not protected by teammate guard');
let split = null; const p = Object.assign(new Projectile(), { dead: false, type: 'mirv', playerId: 1, pos: { x: 0, y: 0 }, layer: 0, vel: { x: 0, y: 0 }, game: { projectileBarn: { addSplitProjectiles(...args) { split = args; } }, objectRegister: { getById() { return self; } }, explosionBarn: { addExplosion() {} } }, destroy() {} });
p.explode(); assert.equal(split?.[1], defs.mirv.splitType); assert.equal(split?.[5], defs.mirv.numSplit);
assert.equal(defs.frag.explosionType, 'explosion_frag'); assert.equal(defs.explosion_frag.rad.max, 12);
console.log('PASS source self vs ally explosion damage, frag blast radius and MIRV split; inert fixture, no live gameplay');
