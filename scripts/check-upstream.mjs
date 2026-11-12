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
const classes = [
  sourceClass('client/src/camera.ts', 'Camera', ['m_z', 'm_pointToScreen', 'm_screenToPoint']),
  sourceClass('client/src/objects/player.ts', 'Player', ['selectIdlePose', 'canInteract', 'getMeleeCollider', 'm_getZoom', 'render']),
  sourceClass('client/src/objects/player.ts', 'PlayerBarn', ['getPlayerById', 'getPlayerInfo', 'recomputeTeamData']),
  sourceClass('client/src/game.ts', 'Game', ['tryJoinGame', 'm_sendMessage', 'update']),
  sourceClass('client/src/inputBinds.ts', 'InputBinds', ['isBindDown', 'isBindPressed', 'preventMenuBind']),
  sourceClass('client/src/ui/touch.ts', 'Touch', ['getAimMovement']),
  sourceClass('shared/net/joinMsg.ts', 'JoinMsg', ['serialize']),
  sourceClass('shared/net/inputMsg.ts', 'InputMsg', null),
  sourceClass('client/src/objects/loot.ts', 'LootBarn', ['getClosestLoot']),
].join('\n');
// The methods above are upstream methods, not rewritten equivalents. Collaborators
// below are inert: no sockets, assets, accounts, real gameplay or server is started.
const fixture = `
const v2 = {create:(x=0,y=x)=>({x,y}),sub:(a,b)=>({x:a.x-b.x,y:a.y-b.y}),length:p=>Math.hypot(p.x,p.y),div:(p,k)=>({x:p.x/k,y:p.y/k})};
const Constants={PlayerNameMaxLen:16}; const math={};
const device = {mobile:false,touch:false}; const window = {};
const GameConfig={protocolVersion:${VERIFIED_PROTOCOL}, WeaponSlot:{Throwable:3}};
const net={JoinMsg, MsgType:{Join:1}, MsgStream:class {constructor(){} serializeMsg(type,data){
 const booleans=[]; const stream={writeUint32(){},writeString(){},writeBoolean(v){booleans.push(!!v)},writeGameType(){},writeArray(){}};
 if(type===1)data.serialize(stream); globalThis.sent.push({type,data,booleans}); }}};
class WebsocketConnection { constructor(){} }
const camera = Object.assign(new Camera(),{m_pos:{x:9,y:18},m_ppu:16,m_zoom:2,m_targetZoom:2,m_screenWidth:800,m_screenHeight:600});
function player(id,pos){return Object.assign(new Player(),{__id:id,__type:1,active:true,layer:0,downed:false,container:{},nameText:{visible:false},
  m_pos:pos,m_dir:{x:1,y:0},m_visualPos:pos,m_netData:{m_activeWeapon:'mp5',m_dead:false,m_scale:1,m_role:''},
  m_localData:{m_zoom:48,m_curWeapIdx:0,m_weapons:[{type:'mp5',ammo:20},{type:'mp5',ammo:20},{type:'fists',ammo:0},{type:'frag',ammo:1}]}});}
const hero=player(1,{x:10,y:20}),enemy=player(2,{x:12,y:20});
const barn=Object.assign(new PlayerBarn(),{playerPool:{m_pool:[hero,enemy]},playerIds:[1,2],teamInfo:{},groupInfo:{},playerInfo:{1:{playerId:1,teamId:10,groupId:10},2:{playerId:2,teamId:20,groupId:20}}});
barn.recomputeTeamData();
const input={mousePos:{x:440,y:300},mouseButtons:{0:true},mouseButtonsOld:{},flush(){this.mouseButtonsOld={...this.mouseButtons};},
 isInputValueDown(b){return !!this.mouseButtons[b.code]},isInputValuePressed(b){return !!this.mouseButtons[b.code]&&!this.mouseButtonsOld[b.code]}};
const binds=Object.assign(new InputBinds(),{input,binds:{4:{type:2,code:0}},menuHovered:false});
const game=Object.assign(new Game(),{initialized:true,connecting:false,connected:false,m_input:input,m_camera:camera,m_activePlayer:hero,m_playerBarn:barn,m_inputBinds:binds,m_touch:new Touch(),
 m_uiManager:{spectating:false,setSpectating(){}},m_config:{get(k){return k==='playerName'?'source-fixture':{outfit:'',melee:'',heal:'',boost:'',emotes:[]}}},m_sendMessageImpl(){},
 m_emoteBarn:{wheelDisplayed:false},m_lootBarn:Object.assign(new LootBarn(),{closestLoot:{__id:7,__type:3,active:true,type:'9mm',count:30,layer:0,pos:{x:10,y:20},rad:2,ownerId:0}})});
Game.prototype.readInputAim=function(){${aimExpressions} return {toMouseDir,toMouseLen};};
const callbacks=[];
const app={input,game,pixi:{stage:{},ticker:{add(fn,context,priority){callbacks.push({fn,context,priority})},remove(fn){const i=callbacks.findIndex(x=>x.fn===fn);if(i>=0)callbacks.splice(i,1)}}}};
globalThis.result={app,callbacks,readInputAim:()=>game.readInputAim(),frameInput:()=>{const msg=new InputMsg();if(binds.isBindPressed(10))msg.addInput(10);return msg;},join:()=>{game.initialized=false;game.tryJoinGame('unused','fixture-token',()=>{});game.m_connection.onOpen();game.initialized=true;}};
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
  const engine = new Features(dom.window, app, { ...DEFAULTS, aim: true, autoLoot: true, lootMode, wallcheck: false, smoothEnabled: false }, () => {}, { '9mm': { type: 'ammo' } });
  try {
    join();
    assert.equal(engine.protocol, VERIFIED_PROTOCOL, 'Observe desktop Join when device.mobile is false and window.mobile is absent');
    assert.equal(context.sent[0].data.isMobile, lootMode === 'mobile' ? true : undefined, 'Mobile mode changes Join, nearby mode leaves desktop Join alone');
    assert.equal(context.sent[0].booleans[1], lootMode === 'mobile', 'Actual upstream JoinMsg.serialize writes the requested boolean');
    engine.pre();
    assert.ok(engine.target, 'Select a target through upstream methods and renamed properties');
    assert.equal(app.input.mousePos.x, 464, 'Aim uses player-relative input projection, not the offset camera center');
    const aim = readInputAim(); assert.ok(Math.abs(aim.toMouseDir.x - 1) < 1e-12 && Math.abs(aim.toMouseDir.y) < 1e-12, 'Actual Game.update expressions yield the target direction');
    assert.equal(frameInput().inputs.includes(10), lootMode === 'nearby', 'Nearby pickup reaches the native binds/InputMsg path');
    app.input.flush(); assert.equal(app.input.mousePos.x, 440, 'Physical input restored');
  } finally { engine.dispose(); dom.window.close(); }
  console.log(`PASS upstream source methods: ${renamed ? 'minified + m_* renamed' : 'unminified'}, loot=${lootMode}`);
}
console.log('Public-source integration checks passed. This does not test the live deployment.');
