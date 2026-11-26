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
import { Container as PixiContainer } from '@pixi/display';
import { TextStyle as PixiTextStyle } from '@pixi/text';
import { Features, VERIFIED_PROTOCOL } from '../src/features.mjs';
import { discover, discoverSender } from '../src/core.mjs';
import { DEFAULTS } from '../src/menu.mjs';
import { buildEspFrame } from '../src/esp.mjs';
import { simulateOpenThrow } from '../src/grenade-aim.mjs';
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
  return `class ${name}${cls.superClass ? ` extends ${js.slice(cls.superClass.start, cls.superClass.end)}` : ''} {\n${members.map(n => js.slice(n.start, n.end)).join('\n')}\n}`;
}
// Use the exact desktop aim expressions from Game.update, up to InputMsg creation.
const gameJS = transformSync(readFileSync(resolve(root, 'client/src/game.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const gameTree = parse(gameJS, { ecmaVersion: 'latest', sourceType: 'module' });
const gameClass = gameTree.body.map(n => n.declaration || n).find(n => n.type === 'ClassDeclaration' && n.id.name === 'Game');
const update = gameClass.body.body.find(n => n.key?.name === 'update');
const statement = name => update.value.body.body.find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === name);
const aimExpressions = gameJS.slice(statement('playerPos').start, statement('inputMsg').start);
const diffIndex = update.value.body.body.indexOf(statement('diff'));
const diffStatements = update.value.body.body.slice(diffIndex, diffIndex + 4).map(n => gameJS.slice(n.start, n.end)).join('\n');
const desktopStart = gameJS.indexOf('inputMsg.moveLeft =', update.start), desktopEnd = gameJS.indexOf('inputMsg.touchMoveDir = v2.normalizeSafe', desktopStart);
const desktopStatements = gameJS.slice(desktopStart, desktopEnd).replace(/}\s*$/, '');
const normalizeStart = desktopEnd, normalizeEnd = gameJS.indexOf('const checkInputs', desktopEnd);
const normalizeStatements = gameJS.slice(normalizeStart, normalizeEnd);
const bbCode = transformSync(readFileSync(resolve(root, 'shared/lib/bitBuffer.ts'), 'utf8'), { loader: 'ts', format: 'iife', globalName: 'bb', target: 'es2022' }).code;

const meleeJS = transformSync(readFileSync(resolve(root, 'shared/defs/gameObjects/meleeDefs.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const meleeTree = parse(meleeJS, { ecmaVersion: 'latest', sourceType: 'module' });
const baseDefs = meleeTree.body.find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === 'BaseDefs').declarations[0].init;
const fistsNode = baseDefs.properties.find(n => n.key.name === 'fists').value;
const fistsSource = meleeJS.slice(fistsNode.start, fistsNode.end);
const throwJS = transformSync(readFileSync(resolve(root, 'shared/defs/gameObjects/throwableDefs.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const throwTree = parse(throwJS, { ecmaVersion: 'latest', sourceType: 'module' });
const throwDefs = throwTree.body.map(n => n.declaration || n).find(n => n.type === 'VariableDeclaration' && n.declarations[0].id.name === 'ThrowableDefs').declarations[0].init;
const throwableNames = ['frag', 'mirv', 'mirv_mini', 'martyr_nade', 'smoke', 'snowball', 'bomb_iron'];
const throwableSource = throwableNames.map(name => {
  const node = throwDefs.properties.find(n => n.key.name === name)?.value;
  assert.ok(node, `source throwable definition ${name}`);
  return `${JSON.stringify(name)}:${throwJS.slice(node.start, node.end)}`;
}).join(',');
const playerJS = transformSync(readFileSync(resolve(root, 'client/src/objects/player.ts'), 'utf8'), { loader: 'ts', target: 'es2022' }).code;
const playerTree = parse(playerJS, { ecmaVersion: 'latest', sourceType: 'module' });
const nativeNameFactory = playerTree.body.find(n => n.type === 'FunctionDeclaration' && n.id.name === 'createPlayerNameText');
assert.ok(nativeNameFactory, 'source native name factory');
const nameFactorySource = playerJS.slice(nativeNameFactory.start, nativeNameFactory.end);
const classes = [
  sourceClass('client/src/objects/objectPool.ts', 'Creator', ['m_getObjById', 'm_deleteObj', 'm_updateObjPart']),
  sourceClass('client/src/camera.ts', 'Camera', ['m_z', 'm_pixels', 'm_pointToScreen', 'm_screenToPoint']),
  sourceClass('client/src/objects/player.ts', 'Player', ['selectIdlePose', 'canInteract', 'getMeleeCollider', 'm_getZoom', 'render', 'm_updateData', 'updateRotation']),
  sourceClass('client/src/objects/player.ts', 'PlayerBarn', ['getPlayerById', 'getPlayerInfo', 'deletePlayerInfo', 'recomputeTeamData']),
  sourceClass('client/src/game.ts', 'Game', ['tryJoinGame', 'm_sendMessage', 'update', 'm_processGameUpdate']),
  sourceClass('client/src/inputBinds.ts', 'InputBinds', ['isBindDown', 'isBindPressed', 'preventMenuBind']),
  sourceClass('client/src/ui/touch.ts', 'Touch', ['getAimMovement']),
  sourceClass('shared/net/joinMsg.ts', 'JoinMsg', ['serialize']),
  sourceClass('shared/net/inputMsg.ts', 'InputMsg', null),
  sourceClass('shared/net/net.ts', 'BitStream', null),
  sourceClass('client/src/objects/loot.ts', 'LootBarn', ['getClosestLoot']),
  sourceClass('client/src/objects/smoke.ts', 'SmokeParticle', null),
  sourceClass('client/src/objects/smoke.ts', 'SmokeBarn', ['m_allocParticle', 'm_update']),
  sourceClass('server/src/game/weaponManager.ts', 'WeaponManager', ['update', 'meleeUpdate', 'activeWeapon', 'cookingThrowable']),
  sourceClass('client/src/map.ts', 'Map', ['getMinimapRender', 'renderMap']),
].join('\n');
// The methods above are upstream methods, not rewritten equivalents. Collaborators
// below are inert: no sockets, assets, accounts, real gameplay or server is started.
const fixture = `
const v2 = {eq:(a,b)=>a.x===b.x&&a.y===b.y,dot:(a,b)=>a.x*b.x+a.y*b.y,normalizeSafe:p=>{const n=Math.hypot(p.x,p.y);return n?{x:p.x/n,y:p.y/n}:{x:1,y:0}},copy:p=>({...p}),lerp:(t,a,b)=>({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t}),create:(x=0,y=x)=>({x,y}),sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),length:p=>Math.hypot(p.x,p.y),div:(p,k)=>({x:p.x/k,y:p.y/k})};
const assert=(value,message)=>{if(!value)throw Error(message||'source assert')}; const Constants={PlayerNameMaxLen:16,MouseMaxDist:64,MaxPosition:1024}; const math={rad2deg:x=>x*180/Math.PI,lerp:(t,a,b)=>a+(b-a)*t,clamp:(v,a,b)=>Math.min(b,Math.max(a,v))};
const util={random:(a,b)=>(a+b)/2,randomItem:a=>a[0],hsvToRgb:()=>({}),rgbToInt:()=>0xeeeeee,sameLayer:(a,b)=>(a&1)===(b&1)||!!((a&2)&&(b&2))};
const particles=['part-smoke-02.img','part-smoke-03.img'];
class Sprite { constructor(){this.alpha=1;this.visible=false;this._destroyed=false;this.anchor={set(){}};this.position={set(){}};this.scale={set(){}};this._tintValue=0xffffff;} get tint(){return this._tintValue} set tint(v){this._tintValue=v;} }
class NativeText extends PixiContainer { constructor(text,style){super();this._text=text;this._style=new PixiTextStyle(style);this.anchor={set(){}};}get style(){return this._style;}get text(){return this._text;}set text(v){this._text=v;} }
const PIXI={Text:NativeText,Sprite:{from(){return new Sprite()}}};
${nameFactorySource}
const fistsDef=${fistsSource}; const throwableDefs={${throwableSource}}; const fragDef=throwableDefs.frag; const GameObjectDefs={typeToId(){return 0},idToType(){return ''},typeToDef(){return fistsDef}};
const sharedShapes=[{color:123,scale:3,collider:{type:0,pos:{x:0,y:0},rad:1}}];
const MapObjectDefs={typeToDef(){return {type:'obstacle',img:{zIdx:1},map:{shapes:sharedShapes}}}}; const nativeMap=new Map();
const device = {mobile:false,touch:false}; const window = {innerWidth:800,innerHeight:600};
const Bones={HandL:0,HandR:1,FootL:2,FootR:3}; const Anim={Revive:99};
const GameConfig={protocolVersion:${VERIFIED_PROTOCOL}, WeaponSlot:{Throwable:3},Anim:{Melee:1,Cook:2}};
const Input={MoveLeft:0,MoveRight:1,MoveUp:2,MoveDown:3,Fire:4}; const Key={Left:37,Right:39,Up:38,Down:40};
const net={JoinMsg,InputMsg,Constants, MsgType:{Join:1,Input:3}, MsgStream:class {constructor(){} serializeMsg(type,data){
 const booleans=[]; const stream={writeUint32(){},writeString(){},writeBoolean(v){booleans.push(!!v)},writeGameType(){},writeArray(){}};
 if(type===1)data.serialize(stream); let decoded=null;if(type===3){const buf=new ArrayBuffer(128);data.serialize(new BitStream(buf));decoded=new InputMsg();decoded.deserialize(new BitStream(buf));decoded.toMouseDir=v2.normalizeSafe(decoded.toMouseDir);} globalThis.sent.push({type,data,booleans,decoded}); }}};
class WebsocketConnection { constructor(){} }
const camera = Object.assign(new Camera(),{m_pos:{x:9,y:18},m_ppu:16,m_zoom:2,m_targetZoom:2,m_screenWidth:800,m_screenHeight:600,m_localRotationEnabled:true});
function player(id,pos){return Object.assign(new Player(),{__id:id,__type:1,active:true,layer:0,downed:false,container:{},nameText:Object.assign(createPlayerNameText(),{text:'native-'+id}),
  m_pos:pos,m_dir:{x:1,y:0},m_visualPos:pos,m_visualPosOld:pos,m_visualDirOld:{x:1,y:0},m_setLocalData(){},isUnderground(){return false},m_netData:{m_pos:pos,m_layer:0,m_perks:[],m_activeWeapon:'mp5',m_dead:false,m_scale:1,m_role:''},
  m_localData:{m_zoom:48,m_curWeapIdx:0,m_weapons:[{type:'mp5',ammo:20},{type:'mp5',ammo:20},{type:'fists',ammo:0},{type:'frag',ammo:1}]}});}
const rotationSubject={m_netData:{m_activeWeapon:'fists'},downed:false,currentAnim(){return 0},gunRecoilL:0,gunRecoilR:0,bodyContainer:{rotation:0},m_visualDir:{x:1,y:0},bones:Array.from({length:4},()=>({pos:{x:0,y:0},pivot:{x:0,y:0},rot:0}))};
for(const key of ['handLContainer','handRContainer','footLContainer','footRContainer'])rotationSubject[key]={position:{set(){}},pivot:{set(){}}};
const hero=player(1,{x:10,y:20}),enemy=player(2,{x:12,y:20}),ally=player(3,{x:11,y:23}),unknown=player(4,{x:11.5,y:23});
const barn=Object.assign(new PlayerBarn(),{playerPool:{m_pool:[hero,enemy,ally,unknown],m_getPool(){return this.m_pool}},playerIds:[1,2,3,4],teamInfo:{},groupInfo:{},playerInfo:{1:{playerId:1,teamId:10,groupId:10},2:{playerId:2,teamId:20,groupId:20},3:{playerId:3,teamId:10,groupId:30}}});
barn.recomputeTeamData();
const input={keyDown(){return false},mousePos:{x:440,y:300},mouseButtons:{0:true},mouseButtonsOld:{},flush(){this.mouseButtonsOld={...this.mouseButtons};},
 isInputValueDown(b){return !!this.mouseButtons[b.code]},isInputValuePressed(b){return !!this.mouseButtons[b.code]&&!this.mouseButtonsOld[b.code]}};
const binds=Object.assign(new InputBinds(),{input,isKeyBound(){return false},binds:{4:{type:2,code:0}},menuHovered:false});
const game=Object.assign(new Game(),{initialized:true,connecting:false,connected:false,m_input:input,m_camera:camera,m_activePlayer:hero,m_playerBarn:barn,m_inputBinds:binds,m_touch:Object.assign(new Touch(),{shotDetected:false}),
 m_uiManager:{spectating:false,setSpectating(){},updateMapIndicators(){}},m_inputMsgTimeout:1,m_prevInputMsg:new InputMsg(),seq:0,seqInFlight:false,m_activeId:1,m_localId:1,lastUpdateTime:0,pings:[],updateIntervals:[],m_map:{factionMode:false},m_renderer:{setActiveLayer(){},setUnderground(){}},m_audioManager:{},m_planeBarn:{updatePlanes(){}},debugHUD:{pingGraph:{addEntry(){}},updateIntervalGraph:{addEntry(){}}},m_config:{get(k){return k==='playerName'?'source-fixture':{outfit:'',melee:'',heal:'',boost:'',emotes:[]}}},m_sendMessageImpl(){},
 m_smokeBarn:Object.assign(new SmokeBarn(),{m_particles:[],zIdx:2147483647}),m_emoteBarn:{wheelDisplayed:false},m_lootBarn:Object.assign(new LootBarn(),{closestLoot:{__id:7,__type:3,active:true,type:'9mm',count:30,layer:0,pos:{x:10,y:20},rad:2,ownerId:0}})});
game.m_objectCreator=Object.assign(new Creator(),{m_idToObj:{1:hero,2:enemy,3:ally,4:unknown},m_types:{}});
// Both tables have native get/delete flow, reproducing preview.3 ambiguity.
// Only the actual Creator receives world delObjIds in the source snapshot receiver.
game.m_decoy={mirror:{2:enemy},get(id){return this.mirror[id]},remove(id){delete this.mirror[id]}};
game.m_creatorAlias=game.m_objectCreator;
Game.prototype.nativeInputFrame=function(dt){${aimExpressions} const inputMsg=new InputMsg();inputMsg.seq=this.seq;${desktopStatements}${normalizeStatements}${diffStatements}return inputMsg;};
Game.prototype.readInputAim=function(){${aimExpressions} return {toMouseDir,toMouseLen};};
const callbacks=[];
const app={input,game,pixi:{stage:{},ticker:{add(fn,context,priority){callbacks.push({fn,context,priority})},remove(fn){const i=callbacks.findIndex(x=>x.fn===fn);if(i>=0)callbacks.splice(i,1)}}}};
const serverPlayer={animType:0,animTicker:0,shootStart:false,shootHold:false,downed:false,freeSwitchTimer:0,recoilTicker:0,swings:0,
 cancelAction(){},playAnim(type,duration){this.animType=type;this.animTicker=duration;this.swings++;}};
const serverWeapon=Object.assign(new WeaponManager(),{player:serverPlayer,curWeapIdx:0,weapons:[{type:'fists',cooldown:-1,recoilTime:0}],
 meleeAttacks:[],meleeAnimCooldown:0,throwableCooldown:0,meleeDamage(){}});
globalThis.result={localRotation:()=>{Player.prototype.updateRotation.call(rotationSubject,input,camera,true,false,false);return rotationSubject.bodyContainer.rotation;},setWall:on=>{if(on)game.m_objectCreator.m_idToObj[99]={__id:99,__type:2,active:true,collidable:true,dead:false,height:1,layer:0,collider:{type:0,pos:{x:10.85,y:20.17},rad:.2}};else delete game.m_objectCreator.m_idToObj[99];},setZoom:z=>{camera.m_zoom=z;camera.m_targetZoom=z;},nativePrevious:()=>game.m_prevInputMsg,nativeFrame:dt=>game.nativeInputFrame(dt),receive:pos=>game.m_processGameUpdate({ack:game.seq,playerInfos:[],deletedPlayerIds:[],delObjIds:[],fullObjects:[],partObjects:[{__id:2,__type:1,pos,dir:{x:1,y:0}}],activePlayerData:{},bullets:[],explosions:[],emotes:[],planes:[],airstrikeZones:[],mapIndicators:[]}),app,callbacks,fistsDef,nativeMap,readInputAim:()=>game.readInputAim(),
 frameInput:()=>{const msg=new InputMsg();msg.shootStart=!!binds.isBindPressed(4);msg.shootHold=!!binds.isBindDown(4);if(binds.isBindPressed(10))msg.addInput(10);return msg;},
 fragDef, throwableDefs, setGrenade:(type='frag')=>{hero.m_netData.m_activeWeapon=type;hero.m_localData.m_curWeapIdx=3;hero.m_localData.m_weapons[3].type=type;input.mouseButtons[0]=true;input.mouseButtonsOld[0]=false;},
 setMelee:()=>{hero.m_netData.m_activeWeapon='fists';hero.m_localData.m_curWeapIdx=2;input.mouseButtonsOld[0]=true;},
 serverTick:(msg,dt)=>{serverPlayer.animTicker-=dt;if(serverPlayer.animTicker<=0)serverPlayer.animType=0;serverPlayer.shootStart=msg.shootStart;serverPlayer.shootHold=msg.shootHold;serverWeapon.update(dt);return serverPlayer.swings;},
 spawnSmoke:()=>{const p=game.m_smokeBarn.m_allocParticle();p.m_init({x:10,y:20},2,0,0);return p;},
 updateSmoke:()=>game.m_smokeBarn.m_update(1/60,camera,hero,{insideStructureMask(){return false}},{addPIXIObj(){}}),
 minimap:()=>nativeMap.getMinimapRender({type:'stone_02'}),
 join:()=>{game.initialized=false;game.tryJoinGame('unused','fixture-token',()=>{});game.m_connection.onOpen();game.initialized=true;}};
`;
for (const renamed of [false, true]) for (const lootMode of ['mobile', 'nearby']) {
  const code = transformSync(bbCode + classes + fixture, { target: 'es2022', minify: renamed,
    ...(renamed ? { mangleProps: /^m(_[a-zA-Z0-9]+)+$/, mangleQuoted: true } : {}) }).code;
  const context = vm.createContext({ sent: [], TextEncoder, TextDecoder, PixiContainer, PixiTextStyle }); vm.runInContext(code, context);
  const { app, join, readInputAim, frameInput } = context.result;
  const dom = new JSDOM('<body></body>', { url: 'https://survev.io', pretendToBeVisual: true });
  let clock = 1000; Object.defineProperty(dom.window.performance, 'now', { value: () => clock, configurable: true });
  const m = discover(app.game);
  assert.ok(m.schema, `source player schema (${renamed ? 'minified+renamed' : 'unminified'})`);
  assert.ok(m.camera, 'source camera'); assert.ok(m.barn, 'source barn'); assert.ok(discoverSender(app.game), 'source sender');
  const engine = new Features(dom.window, app, { ...DEFAULTS, aim: true, autoLoot: true, lootMode, wallcheck: true, humanLikeAim: false }, () => {}, { '9mm': { type: 'ammo' }, fists: context.result.fistsDef,mp5:{type:'gun',bulletType:'bullet_mp5',ammo:'9mm',barrelLength:1,barrelOffset:0},bullet_mp5:{type:'bullet',speed:85,distance:100,variance:0} });
  try {
    join();
    assert.equal(engine.protocol, VERIFIED_PROTOCOL, 'Observe desktop Join when device.mobile is false and window.mobile is absent');
    assert.equal(context.sent[0].data.isMobile, lootMode === 'mobile' ? true : undefined, 'Mobile mode changes Join, nearby mode leaves desktop Join alone');
    assert.equal(context.sent[0].booleans[1], lootMode === 'mobile', 'Actual upstream JoinMsg.serialize writes the requested boolean');
    context.result.receive({x:12,y:20});
    engine.pre();
    assert.equal(engine.capabilities.wallcheck,true,'Native Creator remains identifiable with an entity-shaped decoy');
    assert.equal(engine.mapping.registryState,'snapshot-id-table');
    assert.equal(engine.mapping.registryEvidence.nativeCandidates,2);
    assert.equal(engine.mapping.registryEvidence.receiverCandidates,1);
    assert.equal(frameInput().inputs.includes(10), lootMode === 'nearby', 'Nearby pickup reaches the native binds/InputMsg path');
    assert.ok(engine.target, 'Select a target through upstream methods and renamed properties');
    assert.equal(engine.target.__id, 2, 'Aim excludes faction ally and unknown membership');
    const frame = buildEspFrame(engine.mapping, engine.mapping.players(), { ...DEFAULTS, esp: true }, 800, 600);
    assert.equal(frame.rows.find(row => row.player.__id === 2).relation, 'enemy');
    const allyRow = frame.rows.find(row => row.player.__id === 3);
    assert.equal(allyRow.relation, 'ally'); assert.equal(allyRow.squad, false, 'Different groups within a team remain faction allies');
    assert.equal(frame.rows.find(row => row.player.__id === 4).relation, 'unknown');
    assert.equal(app.input.mousePos.x, 440, 'Aim never mutates physical mouse');
    context.result.nativeFrame(1/60);
    let wire=context.sent.at(-1).decoded;
    assert.ok(wire && Math.abs(wire.toMouseDir.x-1)<1e-4 && Math.abs(wire.toMouseDir.y)<.003, 'Actual source native diff/send and BitStream roundtrip');
    // Exercise the interleaving directly: update arrives after a cached pre plan
    // but before a native send. Force only the fixture scheduler, not production.
    app.input.flush(); clock += 17; engine.pre();
    context.result.receive({x:12,y:20.7}); assert.equal(engine.aimPlanFrame,-1,'Native world update invalidates cached aim');
    app.game[engine.timeoutKey]=0; clock+=10; context.result.nativeFrame(1/60);
    wire=context.sent.at(-1).decoded; assert.ok(wire.toMouseDir.y>.3,'Same-frame update reaches actual serialized direction');
    app.input.flush(); clock+=17; context.result.receive({x:12,y:20}); engine.pre(); context.result.nativeFrame(1/60);
    const count=context.sent.length;
    clock += 34; context.result.receive({x:12,y:20.4});engine.pre();
    const mouseDirection=context.result.readInputAim().toMouseDir;
    assert.ok(mouseDirection.y>.1,'Mouse hook changes actual native desktop aim expressions before the sender');
    assert.ok(Math.abs(context.result.localRotation()+Math.atan2(mouseDirection.y,mouseDirection.x))<1e-8,'Actual Player.updateRotation reads the same corrected mouse direction');
    context.result.nativeFrame(1/60);
    assert.ok(context.sent.length>count, 'Stationary physical mouse still sends corrected direction through timeout');
    wire=context.sent.at(-1).decoded;assert.ok(wire.toMouseDir.y>.1, 'Correct aim on wire after target moves');
    assert.ok(context.result.nativePrevious().toMouseDir.y>.1,'Direct mouse path reaches native input construction and prevInput before sender correction');
    assert.ok(app.input.mousePos.y<300,'Native mouse input vector is corrected during the frame');
    app.input.mousePos.x = 430; app.input.mousePos.y = 280;
    assert.deepEqual(engine.mouseInput.physical(app.input), { x: 430, y: 280 }, 'Physical write is retained separately');
    assert.ok(app.input.mousePos.y < 300 && app.input.mousePos.y !== 280, 'Lock owns game-facing vector after physical mouse writes');
    app.input.flush();
    assert.ok(engine.diagnostics().mouseInput.capturingWrites, 'Lock remains active across native flush');
    assert.ok(Math.abs(context.result.localRotation()+Math.atan2(mouseDirection.y,mouseDirection.x))<1e-8, 'Local rotation stays aligned with locked vector');
    engine.restoreInput(); assert.equal(app.input.mousePos.x,430); assert.equal(app.input.mousePos.y,280);
    app.input.mousePos.x = 440; app.input.mousePos.y = 300;
    const savedDefs=engine.definitions;
    engine.definitions=null;engine.config.esp=true;engine.config.nametags=false;engine.lastVisual=-Infinity;
    clock+=17;engine.pre();context.result.nativeFrame(1/60);engine.post();
    wire=context.sent.at(-1).decoded;
    assert.equal(engine.stats.predictionState,'direct-missing-definitions','Missing item capture does not disable native gun-slot direct aim');
    assert.ok(Math.abs(Math.atan2(wire.toMouseDir.y,wire.toMouseDir.x)-Math.atan2(.4,2))<.005,'Direct fallback still reaches source serializer');
    const sourcePlayers=engine.mapping.players(), namedEnemy=sourcePlayers.find(p=>p.__id===2), namedAlly=sourcePlayers.find(p=>p.__id===3), namedUnknown=sourcePlayers.find(p=>p.__id===4);
    assert.equal(namedEnemy.nameText.style.fill,'#ff6262');assert.equal(namedAlly.nameText.style.fill,'#56b6ff');assert.equal(namedUnknown.nameText.style.fill,'#00ffff');
    assert.equal(namedEnemy.nameText.visible,true);namedEnemy.nameText.visible=false;assert.equal(namedEnemy.nameText.visible,true,'Native visibility writes cannot hide active ESP');
    assert.equal(namedEnemy.nameText.text,'native-2','Source-created name content preserved');assert.equal(engine.names.stats.colored,2);
    engine.config.esp=false;engine.lastVisual=-Infinity;engine.post();
    assert.equal(namedEnemy.nameText.style.fill,'#00ffff');assert.equal(namedEnemy.nameText.visible,false,'Disable restores actual PIXI state');
    engine.definitions=savedDefs;
    engine.config.aim=false;engine.pre();context.result.nativeFrame(1/60);
    assert.ok(Math.abs(context.sent.at(-1).decoded.toMouseDir.y)<.003, 'Disable sends native direction back despite unchanged cursor');
    engine.config.aim=true;
    // Native camera zoom can update between our pre plan and source input creation.
    engine.config.predict=false; engine.config.fov=400; engine.config.humanLikeAim=false;
    engine.pre(); context.result.setZoom(4); context.result.nativeFrame(1/60);
    wire=context.sent.at(-1).decoded; assert.ok(Math.abs(Math.atan2(wire.toMouseDir.y,wire.toMouseDir.x)-Math.atan2(.4,2))<.004, 'Final sender solves world direction after native zoom update');
    assert.equal(wire.shootHold,true,'Aim preserves native Fire'); assert.equal(wire.moveRight,false,'Aim preserves native movement');
    app.input.flush(); engine.config.aim=false;engine.pre();context.result.nativeFrame(1/60);app.input.flush();engine.config.aim=true;engine.config.humanLikeAim=true; engine.config.smooth=50; engine.aimController.reset();
    for(let i=0;i<60;i++){clock+=1000/60;engine.pre();context.result.nativeFrame(1/60);app.input.flush();}
    wire=context.sent.at(-1).decoded;assert.ok(Math.abs(Math.atan2(wire.toMouseDir.y,wire.toMouseDir.x)-Math.atan2(.4,2))<.005, 'Lock converges on source wire, fixed cursor');
    engine.config.aimMode='assist';engine.config.assistStrength=35;clock+=17;engine.pre();context.result.nativeFrame(1/60);app.input.flush();
    wire=context.sent.at(-1).decoded;assert.ok(Math.abs(Math.atan2(wire.toMouseDir.y,wire.toMouseDir.x)-Math.atan2(.4,2)*.35)<.005,'Assist strength on serialized wire');
    const stable=context.sent.length;
    for(let i=0;i<10;i++){clock+=17;engine.pre();context.result.nativeFrame(1/60);app.input.flush();}
    assert.equal(context.sent.length,stable,'Assist does not force extra packets merely for preview');
    engine.config.aimMode='lock';engine.config.humanLikeAim=false;context.result.setZoom(2);
    app.input.flush(); assert.equal(app.input.mousePos.x, 440, 'Physical input restored');
    engine.config.wallcheck=true;context.result.setWall(true);clock+=17;engine.pre();context.result.nativeFrame(1/60);
    assert.equal(engine.stats.aimRejections.wall,1,'Known source registry obstacle still blocks aim; no wallcheck bypass');
    context.result.setWall(false);clock+=17;engine.pre();context.result.nativeFrame(1/60);
    assert.ok(context.sent.at(-1).decoded.toMouseDir.y>.1,'Lock reaches native wire with default wallcheck after obstacle removal');
    const liveEvidence=engine.diagnostics().aimEvidence;
    assert.ok(liveEvidence.lastCorrection.correctionDegrees>1);assert.equal(liveEvidence.lastGameplayForward.firePreserved,true);
    // Controlled virtual-time latency check: a stationary target shifts immediately
    // after a completed frame. Neither this fixture nor the receiver forces the
    // native timeout. The next pre/native frame must reach the real serialized
    // input direction. This measures scheduling in the fixture, not browser CPU,
    // network, live ticks or actual hit latency.
    const originalLoot = engine.config.autoLoot, originalPredict = engine.config.predict;
    engine.config.autoLoot = false; engine.config.predict = false;
    for (const hz of [30, 60, 144]) for (const phase of [.1, .5, .9]) {
      app.input.flush(); clock += 100; context.result.receive({x:12,y:20}); engine.pre(); context.result.nativeFrame(1/hz); app.input.flush();
      const frameMs = 1000 / hz, priorCount = context.sent.length;
      clock += frameMs * phase; const receivedAt = clock;
      context.result.receive({x:12,y:20.7});
      assert.equal(context.sent.length, priorCount, 'Receiver must not emit input');
      clock += frameMs * (1 - phase); engine.pre(); context.result.nativeFrame(1/hz);
      const updated = context.sent.slice(priorCount).find(x => x.type === 3 && x.decoded?.toMouseDir.y > .3);
      assert.ok(updated, `Fresh serialized direction after next native frame at ${hz}Hz, phase ${phase}`);
      assert.ok(Math.abs((clock - receivedAt) - frameMs * (1 - phase)) < 1e-8, 'Virtual frame scheduling delay');
    }
    // Human-like convergence is a separate measurement, still without prediction.
    // Warm up at the original target before each trial, then measure simulated
    // time from receive to 90% of the geometric target angle on the actual wire.
    engine.config.humanLikeAim = true;
    const humanReaction = [];
    for (const smooth of [0, 20, 50]) for (const hz of [30, 60, 144]) {
      engine.config.smooth = smooth;
      const dt = 1 / hz, ms = 1000 / hz;
      app.input.flush(); clock += 100; context.result.receive({x:12,y:20}); engine.aimController.reset();
      for (let i = 0; i < hz; i++) { clock += ms; engine.pre(); context.result.nativeFrame(dt); app.input.flush(); }
      clock += ms / 2; const receivedAt = clock; context.result.receive({x:12,y:20.7});
      const threshold = .9 * Math.atan2(.7, 2), startCount = context.sent.length;
      let elapsed = null;
      for (let i = 0; i < hz; i++) {
        clock += i === 0 ? ms / 2 : ms; engine.pre(); context.result.nativeFrame(dt); app.input.flush();
        if (context.sent.slice(startCount).some(x => x.type === 3 && x.decoded && Math.atan2(x.decoded.toMouseDir.y, x.decoded.toMouseDir.x) >= threshold)) { elapsed = clock - receivedAt; break; }
      }
      assert.notEqual(elapsed, null, `Human-like converges on serialized wire at ${hz}Hz`);
      humanReaction.push(`smooth${smooth}/${hz}Hz=${elapsed.toFixed(1)}ms`);
    }
    console.log(`Fixture receive-to-90%-wire (virtual time, Human-like, predict off): ${humanReaction.join(', ')}`);
    app.input.flush(); engine.config.humanLikeAim = false; engine.config.autoLoot = originalLoot; engine.config.predict = originalPredict;
    clock += 100; context.result.receive({x:12,y:20}); engine.pre(); context.result.nativeFrame(1/60);
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
    // Observe a real source InputMsg Fire edge and actual source frag fuse.
    engine.config.aim = false; engine.config.grenadeTimer = true; engine.definitions.frag = context.result.fragDef;
    context.result.setGrenade(); clock += 17; engine.pre();
    assert.equal(engine.capabilities.grenadeTimer, true);
    const grenadeInput = frameInput(); assert.equal(grenadeInput.shootStart, true); assert.equal(grenadeInput.shootHold, true);
    app.game[discoverSender(app.game)](3, grenadeInput, 128);
    assert.equal(engine.grenadeTimer.sample(engine.grenadeContext(), clock)?.seconds, context.result.fragDef.fuseTime);
    assert.equal(context.sent.at(-1).decoded.shootHold, true, 'Timer does not alter native Fire');
    clock += 500; assert.equal(engine.grenadeTimer.sample(engine.grenadeContext(), clock)?.seconds, 3.5);
    app.input.mouseButtons[0] = false; const release = frameInput(); app.game[discoverSender(app.game)](3, release, 128);
    assert.equal(engine.grenadeTimer.active, null, 'Release hides timer');
    // Same native sender and source definitions for varied fuses, non-cookable
    // smoke and source's sentinel-length snowball. These fixtures do not imply
    // all types are normally equippable in live play.
    Object.assign(engine.definitions, context.result.throwableDefs);
    for (const type of ['mirv', 'mirv_mini', 'martyr_nade', 'smoke', 'snowball', 'bomb_iron']) {
      context.result.setGrenade(type); clock += 17; engine.pre();
      const msg = frameInput(); assert.equal(msg.shootStart, true); assert.equal(msg.shootHold, true);
      app.game[discoverSender(app.game)](3, msg, 128);
      const def = context.result.throwableDefs[type], timer = engine.grenadeTimer.sample(engine.grenadeContext(), clock);
      if (def.cookable && def.fuseTime > 0 && def.fuseTime <= 30) assert.equal(timer?.seconds, def.fuseTime, `${type} uses its source fuse`);
      else assert.equal(timer, null, `${type} must not invent an actionable countdown`);
      assert.equal(context.sent.at(-1).decoded.shootHold, true, `${type} preserves Fire`);
      app.input.mouseButtons[0] = false; app.game[discoverSender(app.game)](3, frameInput(), 128);
      assert.equal(engine.grenadeTimer.active, null, `${type} release clears timer`);
    }
    engine.config.grenadeTimer = false;
    // Exercise experimental grenade Lock through the real source serializer using
    // deterministic injected movement samples and an inert flat-ground adapter.
    // This does not verify live terrain discovery, tick timings or gameplay.
    context.result.setGrenade('frag'); app.input.mouseButtons[0] = false;
    engine.config.grenadeAimMode = 'lock'; engine.config.grenadeAimActivation = 'equip';
    clock += 100; engine.pre(); engine.capabilities.prediction = true; engine.capabilities.wallcheck = true;
    engine.mapping.map = { getGroundSurface() { return { type: 'grass' }; } };
    const own = engine.mapping.active, enemy = engine.mapping.players().find(p => p.__id === 2);
    const ownPos = engine.sourcePos(own), enemyPos = engine.sourcePos(enemy);
    for (const t of [clock - 66, clock - 33, clock]) { engine.grenadeTracker.observe(own, ownPos, t); engine.grenadeTracker.observe(enemy, enemyPos, t); }
    engine.aimPlanFrame = -1;
    const aimInput = frameInput(); aimInput.toMouseLen = 2; app.game[discoverSender(app.game)](3, aimInput, 128);
    const aimWire = context.sent.at(-1).decoded;
    assert.equal(engine.grenadeState, 'estimate-before-throw', 'grenade plan reaches source sender');
    assert.ok(engine.grenadePlan && aimWire.toMouseLen >= 0 && aimWire.toMouseLen <= 18.1, 'serialized grenade throw strength');
    assert.equal(aimWire.shootHold, false, 'grenade aim never starts Fire');
    // Real input-frame scheduler and serializer, with injected stable snapshots,
    // flat terrain and RTT; still not a server acknowledgement or live match.
    engine.config.grenadeAutoThrow = true; engine.config.grenadeAimActivation = 'hold'; engine.config.grenadeFov = 400;
    const fixtureMap = Object.values(app.game).find(v => v && v.factionMode === false);
    Object.assign(fixtureMap, { mapTexture: {}, width: 100, height: 100, getGroundSurface() { return { type: 'grass' }; } }); engine.mapping.map = fixtureMap;
    // Source client receives complete update arrays. Seed explicit positions,
    // then model source server's unchanged-player omission on subsequent ticks.
    const emptyUpdate = { fullObjects: [], partObjects: [], delObjIds: [], activePlayerData: {} };
    engine.grenadeTracker.reset(); engine.grenadeUpdateAt = null;
    engine.observeUpdate({ ...emptyUpdate, fullObjects: [{ __id: own.__id, pos: ownPos }, { __id: enemy.__id, pos: enemyPos }] }, clock);
    context.result.setGrenade('frag'); clock += 33; engine.pre(); context.result.nativeFrame(1 / 30); app.input.flush();
    let autoReleased = false;
    for (let i = 0; i < 115; i++) {
      clock += 33; engine.observeUpdate(emptyUpdate, clock);
      Object.assign(engine.timing, { rtt: 40, lastRtt: 40, rttAt: clock });
      const count = context.sent.length; engine.pre(); context.result.nativeFrame(1 / 30); app.input.flush();
      const wire = context.sent.slice(count).find(x => x.type === 3 && x.decoded?.shootHold === false);
      if (wire) { assert.equal(wire.decoded.shootStart, false); autoReleased = true; break; }
    }
    assert.equal(autoReleased, true, `Source scheduler auto-release: ${engine.grenadeState} / ${engine.grenadeAuto.phase} / ${engine.grenadeAutoPlan?.reason}`);
    app.input.mouseButtons[0] = false; clock += 33; engine.pre(); context.result.nativeFrame(1 / 30); app.input.flush();
    engine.config.grenadeAutoThrow = false;
    engine.config.grenadeAimMode = 'off'; engine.configurationChanged('grenadeAimMode'); app.input.mouseButtons[0] = true;
    // Measure only nominal endpoint changes caused by the real source InputMsg
    // wire quantization. This is not a full server throw or a live hit test.
    let maxQuantizedError = 0, quantizedCount = 0;
    for (let i = 0; i < 16; i++) for (const mouseDistance of [0, 2, 9, 17.9]) {
      const angle = i * Math.PI * 2 / 16, dir = { x: Math.cos(angle), y: Math.sin(angle) };
      const input = frameInput(); input.toMouseDir = dir; input.toMouseLen = mouseDistance;
      app.game[discoverSender(app.game)](3, input, 128);
      const decoded = context.sent.at(-1).decoded, model = { def: context.result.fragDef, origin: { x: 100, y: 100 }, playerVelocity: { x: 0, y: 0 }, fuseRemaining: 2 };
      const before = simulateOpenThrow({ ...model, direction: dir, mouseDistance });
      const after = simulateOpenThrow({ ...model, direction: decoded.toMouseDir, mouseDistance: decoded.toMouseLen });
      assert.ok(before && after, 'Native input quantization remains inside model range');
      maxQuantizedError = Math.max(maxQuantizedError, Math.hypot(before.end.x - after.end.x, before.end.y - after.end.y)); quantizedCount++;
    }
    assert.ok(maxQuantizedError < .3, `Bounded source wire quantization proxy: ${maxQuantizedError}`);
    console.log(`Fixture grenade input quantization: ${quantizedCount} samples, nominal max endpoint error ${maxQuantizedError.toFixed(3)} wu`);
    // An unchanged held mouse must create repeated fist edges, accepted only when
    // the native server WeaponManager.update/meleeUpdate cooldown and anim allow it.
    engine.config.semi = true; context.result.setMelee(); let swings = 0;
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
