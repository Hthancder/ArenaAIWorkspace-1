// Optional integration checks against a local checkout of the pinned public source.
// No upstream code is vendored; input files are read/transpiled only for this run.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parse } from 'acorn';
import { transformSync } from 'esbuild';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { JSDOM } from 'jsdom';
import { Features, VERIFIED_PROTOCOL } from '../src/features.mjs';
import { discover, discoverSender } from '../src/core.mjs';
import { DEFAULTS } from '../src/menu.mjs';
import { buildEspFrame } from '../src/esp.mjs';
import { mapHighlightCompatible, highlightMinimap } from '../src/map-highlights.mjs';

const root = resolve(process.argv[2] || '../survev-reference');
const pin = '3edee7e8bd07fda8a63905aab4c45b595b684a80';
assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(), pin, 'Use the audited source commit');
function sourceClass(file, name, selected) {
  const js = transformSync(readFileSync(resolve(root, file), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
  const tree = parse(js, { ecmaVersion: 'latest', sourceType: 'module' });
  const cls = tree.body.map(n => n.declaration || n).find(n => n.type === 'ClassDeclaration' && n.id.name === name);
  assert.ok(cls, `class ${name}`);
  const members = selected ? cls.body.body.filter(n => selected.includes(n.key?.name)) : cls.body.body;
  if (selected) assert.equal(members.length, selected.length, `${name}: source members changed`);
  return `class ${name} {\n${members.map(n => js.slice(n.start, n.end)).join('\n')}\n}`;
}
// Use the exact desktop aim expressions from Game.update, up to InputMsg creation.
const gameJS = transformSync(readFileSync(resolve(root, 'client/src/game.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const gameTree = parse(gameJS, { ecmaVersion: 'latest', sourceType: 'module' });
const gameClass = gameTree.body.map(n => n.declaration || n).find(n => n.type === 'ClassDeclaration' && n.id.name === 'Game');
const update = gameClass.body.body.find(n => n.key?.name === 'update');
const statement = name => update.value.body.body.find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === name);
const aimExpressions = gameJS.slice(statement('playerPos').start, statement('inputMsg').start);
const meleeJS = transformSync(readFileSync(resolve(root, 'shared/defs/gameObjects/meleeDefs.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const meleeTree = parse(meleeJS, { ecmaVersion: 'latest', sourceType: 'module' });
const baseDefs = meleeTree.body.find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === 'BaseDefs').declarations[0].init;
const fistsNode = baseDefs.properties.find(n => n.key.name === 'fists').value;
const fistsSource = meleeJS.slice(fistsNode.start, fistsNode.end);
const classes = [
  sourceClass('client/src/camera.ts', 'Camera', ['m_z', 'm_pixels', 'm_pointToScreen', 'm_screenToPoint']),
  sourceClass('client/src/objects/player.ts', 'Player', ['selectIdlePose', 'canInteract', 'getMeleeCollider', 'm_getZoom', 'render']),
  sourceClass('client/src/objects/player.ts', 'PlayerBarn', ['getPlayerById', 'getPlayerInfo', 'recomputeTeamData']),
  sourceClass('client/src/game.ts', 'Game', ['tryJoinGame', 'm_sendMessage', 'update']),
  sourceClass('client/src/inputBinds.ts', 'InputBinds', ['isBindDown', 'isBindPressed', 'preventMenuBind']),
  sourceClass('client/src/ui/touch.ts', 'Touch', ['getAimMovement']),
  sourceClass('shared/net/joinMsg.ts', 'JoinMsg', ['serialize']),
  sourceClass('shared/net/inputMsg.ts', 'InputMsg', null),
  sourceClass('client/src/objects/loot.ts', 'LootBarn', ['getClosestLoot']),
  sourceClass('client/src/objects/smoke.ts', 'SmokeParticle', null),
  sourceClass('client/src/objects/smoke.ts', 'SmokeBarn', ['m_allocParticle', 'm_update']),
  sourceClass('server/src/game/weaponManager.ts', 'WeaponManager', ['update', 'meleeUpdate', 'activeWeapon', 'cookingThrowable']),
  sourceClass('client/src/map.ts', 'Map', ['getMinimapRender', 'renderMap']),
].join('\n');
// The methods above are upstream methods, not rewritten equivalents. Collaborators
// below are inert: no sockets, assets, accounts, real gameplay or server is started.
const fixture = `
const v2 = {copy:p=>({...p}),lerp:(t,a,b)=>({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t}),create:(x=0,y=x)=>({x,y}),sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),length:p=>Math.hypot(p.x,p.y),div:(p,k)=>({x:p.x/k,y:p.y/k})};
const Constants={PlayerNameMaxLen:16}; const math={lerp:(t,a,b)=>a+(b-a)*t,clamp:(v,a,b)=>Math.min(b,Math.max(a,v))};
const util={random:(a,b)=>(a+b)/2,randomItem:a=>a[0],hsvToRgb:()=>({}),rgbToInt:()=>0xeeeeee,sameLayer:(a,b)=>(a&1)===(b&1)||!!((a&2)&&(b&2))};
const particles=['part-smoke-02.img','part-smoke-03.img'];
class Sprite { constructor(){this.alpha=1;this.visible=false;this._destroyed=false;this.anchor={set(){}};this.position={set(){}};this.scale={set(){}};this._tintValue=0xffffff;} get tint(){return this._tintValue} set tint(v){this._tintValue=v;} }
const PIXI={Sprite:{from(){return new Sprite()}}};
const fistsDef=${fistsSource}; const GameObjectDefs={typeToDef(){return fistsDef}};
const sharedShapes=[{color:123,scale:3,collider:{type:0,pos:{x:0,y:0},rad:1}}];
const MapObjectDefs={typeToDef(){return {type:'obstacle',img:{zIdx:1},map:{shapes:sharedShapes}}}}; const nativeMap=new Map();
const device = {mobile:false,touch:false}; const window = {};
const GameConfig={protocolVersion:${VERIFIED_PROTOCOL}, WeaponSlot:{Throwable:3},Anim:{Melee:1,Cook:2}};
const net={JoinMsg, MsgType:{Join:1}, MsgStream:class {constructor(){} serializeMsg(type,data){
 const booleans=[]; const stream={writeUint32(){},writeString(){},writeBoolean(v){booleans.push(!!v)},writeGameType(){},writeArray(){}};
 if(type===1)data.serialize(stream); globalThis.sent.push({type,data,booleans}); }}};
class WebsocketConnection { constructor(){} }
const camera = Object.assign(new Camera(),{m_pos:{x:9,y:18},m_ppu:16,m_zoom:2,m_targetZoom:2,m_screenWidth:800,m_screenHeight:600});
function player(id,pos){return Object.assign(new Player(),{__id:id,__type:1,active:true,layer:0,downed:false,container:{},nameText:{visible:false},
  m_pos:pos,m_dir:{x:1,y:0},m_visualPos:pos,m_netData:{m_activeWeapon:'mp5',m_dead:false,m_scale:1,m_role:''},
  m_localData:{m_zoom:48,m_curWeapIdx:0,m_weapons:[{type:'mp5',ammo:20},{type:'mp5',ammo:20},{type:'fists',ammo:0},{type:'frag',ammo:1}]}});}
const hero=player(1,{x:10,y:20}),enemy=player(2,{x:12,y:20}),ally=player(3,{x:11,y:20}),unknown=player(4,{x:11.5,y:20});
const barn=Object.assign(new PlayerBarn(),{playerPool:{m_pool:[hero,enemy,ally,unknown]},playerIds:[1,2,3,4],teamInfo:{},groupInfo:{},playerInfo:{1:{playerId:1,teamId:10,groupId:10},2:{playerId:2,teamId:20,groupId:20},3:{playerId:3,teamId:10,groupId:30}}});
barn.recomputeTeamData();
const input={mousePos:{x:440,y:300},mouseButtons:{0:true},mouseButtonsOld:{},flush(){this.mouseButtonsOld={...this.mouseButtons};},
 isInputValueDown(b){return !!this.mouseButtons[b.code]},isInputValuePressed(b){return !!this.mouseButtons[b.code]&&!this.mouseButtonsOld[b.code]}};
const binds=Object.assign(new InputBinds(),{input,binds:{4:{type:2,code:0}},menuHovered:false});
const game=Object.assign(new Game(),{initialized:true,connecting:false,connected:false,m_input:input,m_camera:camera,m_activePlayer:hero,m_playerBarn:barn,m_inputBinds:binds,m_touch:new Touch(),
 m_uiManager:{spectating:false,setSpectating(){}},m_config:{get(k){return k==='playerName'?'source-fixture':{outfit:'',melee:'',heal:'',boost:'',emotes:[]}}},m_sendMessageImpl(){},
 m_smokeBarn:Object.assign(new SmokeBarn(),{m_particles:[],zIdx:2147483647}),m_emoteBarn:{wheelDisplayed:false},m_lootBarn:Object.assign(new LootBarn(),{closestLoot:{__id:7,__type:3,active:true,type:'9mm',count:30,layer:0,pos:{x:10,y:20},rad:2,ownerId:0}})});
Game.prototype.readInputAim=function(){${aimExpressions} return {toMouseDir,toMouseLen};};
const callbacks=[];
const app={input,game,pixi:{stage:{},ticker:{add(fn,context,priority){callbacks.push({fn,context,priority})},remove(fn){const i=callbacks.findIndex(x=>x.fn===fn);if(i>=0)callbacks.splice(i,1)}}}};
const serverPlayer={animType:0,animTicker:0,shootStart:false,shootHold:false,downed:false,freeSwitchTimer:0,recoilTicker:0,swings:0,
 cancelAction(){},playAnim(type,duration){this.animType=type;this.animTicker=duration;this.swings++;}};
const serverWeapon=Object.assign(new WeaponManager(),{player:serverPlayer,curWeapIdx:0,weapons:[{type:'fists',cooldown:-1,recoilTime:0}],
 meleeAttacks:[],meleeAnimCooldown:0,throwableCooldown:0,meleeDamage(){}});
globalThis.result={app,callbacks,fistsDef,nativeMap,readInputAim:()=>game.readInputAim(),
 frameInput:()=>{const msg=new InputMsg();msg.shootStart=!!binds.isBindPressed(4);msg.shootHold=!!binds.isBindDown(4);if(binds.isBindPressed(10))msg.addInput(10);return msg;},
 setMelee:()=>{hero.m_netData.m_activeWeapon='fists';hero.m_localData.m_curWeapIdx=2;input.mouseButtonsOld[0]=true;},
 serverTick:(msg,dt)=>{serverPlayer.animTicker-=dt;if(serverPlayer.animTicker<=0)serverPlayer.animType=0;serverPlayer.shootStart=msg.shootStart;serverPlayer.shootHold=msg.shootHold;serverWeapon.update(dt);return serverPlayer.swings;},
 spawnSmoke:()=>{const p=game.m_smokeBarn.m_allocParticle();p.m_init({x:10,y:20},2,0,0);return p;},
 updateSmoke:()=>game.m_smokeBarn.m_update(1/60,camera,hero,{insideStructureMask(){return false}},{addPIXIObj(){}}),
 minimap:()=>nativeMap.getMinimapRender({type:'stone_02'}),
 join:()=>{game.initialized=false;game.tryJoinGame('unused','fixture-token',()=>{});game.m_connection.onOpen();game.initialized=true;}};
`;
for (const renamed of [false, true]) for (const lootMode of ['mobile', 'nearby']) {
  const code = transformSync(classes + fixture, { target: 'es2022', minify: renamed,
    ...(renamed ? { mangleProps: /^m(_[a-zA-Z0-9]+)+$/, mangleQuoted: true } : {}) }).code;
  const context = vm.createContext({ sent: [] }); vm.runInContext(code, context);
  const { app, join, readInputAim, frameInput } = context.result;
  const dom = new JSDOM('<body></body>', { url: 'https://survev.io', pretendToBeVisual: true });
  const m = discover(app.game);
  assert.ok(m.schema, `source player schema (${renamed ? 'minified+renamed' : 'unminified'})`);
  assert.ok(m.camera, 'source camera'); assert.ok(m.barn, 'source barn'); assert.ok(discoverSender(app.game), 'source sender');
  const engine = new Features(dom.window, app, { ...DEFAULTS, aim: true, autoLoot: true, lootMode, wallcheck: false, smoothEnabled: false }, () => {}, { '9mm': { type: 'ammo' }, fists: context.result.fistsDef });
  try {
    join();
    assert.equal(engine.protocol, VERIFIED_PROTOCOL, 'Observe desktop Join when device.mobile is false and window.mobile is absent');
    assert.equal(context.sent[0].data.isMobile, lootMode === 'mobile' ? true : undefined, 'Mobile mode changes Join, nearby mode leaves desktop Join alone');
    assert.equal(context.sent[0].booleans[1], lootMode === 'mobile', 'Actual upstream JoinMsg.serialize writes the requested boolean');
    engine.pre();
    assert.ok(engine.target, 'Select a target through upstream methods and renamed properties');
    assert.equal(engine.target.__id, 2, 'Aim excludes faction ally and unknown membership');
    const frame = buildEspFrame(engine.mapping, engine.mapping.players(), { ...DEFAULTS, esp: true }, 800, 600);
    assert.equal(frame.rows.find(row => row.player.__id === 2).relation, 'enemy');
    const allyRow = frame.rows.find(row => row.player.__id === 3);
    assert.equal(allyRow.relation, 'ally'); assert.equal(allyRow.squad, false, 'Different groups within a team remain faction allies');
    assert.equal(frame.rows.find(row => row.player.__id === 4).relation, 'unknown');
    assert.equal(app.input.mousePos.x, 464, 'Aim uses player-relative input projection, not the offset camera center');
    const aim = readInputAim(); assert.ok(Math.abs(aim.toMouseDir.x - 1) < 1e-12 && Math.abs(aim.toMouseDir.y) < 1e-12, 'Actual Game.update expressions yield the target direction');
    assert.equal(frameInput().inputs.includes(10), lootMode === 'nearby', 'Nearby pickup reaches the native binds/InputMsg path');
    app.input.flush(); assert.equal(app.input.mousePos.x, 440, 'Physical input restored');
    // Exercise the actual smoke renderer every frame; the adapter must work with an
    // initially empty m_* array and survive native alpha/tint rewrites.
    assert.equal(engine.smokeSources.length, 1, 'Identify source smoke array before first spawn');
    engine.config.xray = true; engine.config.darkerSmokes = true; engine.config.smokeOpacity = 50;
    const particle = context.result.spawnSmoke(); context.result.updateSmoke(); engine.lastVisual = -Infinity; engine.post();
    assert.equal(particle.sprite.alpha, .05, 'Legacy 50 means 0.05 per-particle alpha, not 50 percent');
    context.result.updateSmoke(); assert.equal(particle.sprite.alpha, .05, 'Native SmokeBarn update cannot overwrite active alpha override');
    assert.equal(particle.sprite.tint, 0x202020, 'Darker smoke uses native sprite tint setter through particle tint');
    engine.config.xray = false; engine.lastVisual = -Infinity; engine.post(); context.result.updateSmoke();
    assert.equal(particle.sprite.alpha, .9, 'Restore latest native alpha on disable'); assert.equal(particle.sprite.tint, 0xeeeeee);
    // An unchanged held mouse must create repeated fist edges, accepted only when
    // the native server WeaponManager.update/meleeUpdate cooldown and anim allow it.
    engine.config.semi = true; context.result.setMelee(); let clock = 1000, swings = 0;
    Object.defineProperty(dom.window.performance, 'now', { value: () => clock, configurable: true });
    for (let frame = 0; frame < 120; frame++) {
      clock += 1000 / 60; engine.pre();
      const msg = frameInput(); swings = context.result.serverTick(msg, 1 / 60);
    }
    assert.ok(swings >= 5 && swings <= 9, `Repeated fists accepted under native cooldown: ${swings}`);
    engine.config.semi = false;
    for (let frame = 0; frame < 30; frame++) { clock += 1000 / 60; engine.pre(); assert.equal(context.result.serverTick(frameInput(), 1 / 60), swings); }
    assert.ok(mapHighlightCompatible(context.result.nativeMap), 'Actual map render AST consumes getMinimapRender and sort');
    const rawMap = context.result.minimap(), marked = highlightMinimap(rawMap, { mapHighlights: true });
    assert.equal(marked.shapes[0].color, 1646367); assert.equal(marked.shapes[0].scale, 6);
    assert.equal(rawMap.shapes[0].color, 123, 'Do not mutate shared shapes returned by native getMinimapRender');

  } finally { engine.dispose(); dom.window.close(); }
  console.log(`PASS upstream source methods: ${renamed ? 'minified + m_* renamed' : 'unminified'}, loot=${lootMode}`);
}
console.log('Public-source integration checks passed. This does not test the live deployment.');
