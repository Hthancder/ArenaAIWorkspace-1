// Build a local test-only adapter to the pinned Survev source. No network server
// is started. Only the movement block is extracted; Bullet, Grid, WeaponManager,
// collider and definitions are the actual source modules bundled by esbuild.
import { readFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build, transformSync } from 'esbuild';
import { parse } from 'acorn';
import assert from 'node:assert/strict';

export async function loadSource(root = '.cache/survev') {
  root = resolve(root);
  const rev = execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
  assert.equal(rev,'3edee7e8bd07fda8a63905aab4c45b595b684a80','source must be the audited pinned revision');
  assert.equal(execFileSync('git',['status','--porcelain'],{cwd:root,encoding:'utf8'}).trim(),'', 'source checkout must be clean');
  const source = transformSync(readFileSync(resolve(root,'server/src/game/objects/player.ts'),'utf8'),{loader:'ts',target:'es2022'}).code;
  const tree = parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const cls=tree.body.map(n=>n.declaration||n).find(n=>n.type==='ClassDeclaration'&&n.id.name==='Player');
  const update=cls?.body.body.find(n=>n.key?.name==='update'), recalc=cls?.body.body.find(n=>n.key?.name==='recalculateSpeed');
  assert.ok(update && recalc,'pinned Player methods');
  const from=source.indexOf('const movement = v2.create(0, 0);',update.start);
  const to=source.indexOf('this.mapIndicator?.updatePosition(this.pos);',from);
  assert.ok(from>update.start && to>from && to<update.end,'pinned movement block');
  const playerUpdate=source.slice(update.start,update.end);
  assert.match(playerUpdate,/if\s*\(!v2\.eq\(this\.pos, this\.posOld\)\)\s*\{\s*this\.setPartDirty\(\)/, 'source marks changed player position dirty');
  assert.match(playerUpdate,/if\s*\(!v2\.eq\(this\.dir, this\.dirNew\)\)\s*\{\s*this\.dir = this\.dirNew;\s*this\.setPartDirty\(\)/, 'source marks changed direction dirty');
  const client=readFileSync(resolve(root,'server/src/game/client.ts'),'utf8');
  assert.match(client,/game\.objectRegister\.dirtyPart\[obj\.__id\][\s\S]{0,100}updateMsg\.partObjects\.push\(obj\)/, 'source sends partial dirty objects');
  const movement=source.slice(from,to), method=source.slice(recalc.start,recalc.end);
  const entry=`
import { BulletBarn } from './server/src/game/objects/bullet.ts';
import { Grid } from './server/src/game/grid.ts';
import { WeaponManager } from './server/src/game/weaponManager.ts';
import { ObjectType, ObjectSerializeFns } from './shared/net/objectSerializeFns.ts';
import { BitStream } from './shared/net/net.ts';
import { InputMsg } from './shared/net/inputMsg.ts';
import { GameConfig } from './shared/gameConfig.ts';
import { GameObjectDefs, MapObjectDefs } from './shared/defs/register.ts';
import { PerkProperties } from './shared/defs/gameObjects/perkDefs.ts';
import { v2 } from './shared/utils/v2.ts';
import { collider } from './shared/utils/collider.ts';
import { math } from './shared/utils/math.ts';
import { util } from './shared/utils/util.ts';
class Movement { step(dt) { ${movement} } ${method} }
export { BulletBarn, Grid, WeaponManager, ObjectType, ObjectSerializeFns, BitStream, InputMsg, v2, GameConfig, GameObjectDefs, MapObjectDefs, collider, Movement };
`;
  mkdirSync('.cache',{recursive:true});
  const out=resolve(`.cache/source-duel-bundle-${process.pid}.mjs`);
  await build({stdin:{contents:entry,resolveDir:root,sourcefile:'arena-test-adapter.mjs'},outfile:out,bundle:true,platform:'node',format:'esm',target:'node22',logLevel:'silent'});
  return import(pathToFileURL(out).href+`?revision=${rev}`);
}
