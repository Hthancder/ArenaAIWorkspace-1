// Source-backed synthetic integration harness, NOT a live server or full Player.update.
// Requires a clean audited Survev checkout: node scripts/benchmark-source-duel.mjs [path] [--smoke]
import assert from 'node:assert/strict';
import { loadSource } from './source-duel-runtime.mjs';
import { SnapshotTracker, predictShot, weaponProfile } from '../src/aim.mjs';
import { clippedMuzzle } from '../src/aim-geometry.mjs';

const args=process.argv.slice(2), root=args.find(x=>!x.startsWith('--')) || '.cache/survev', smoke=args.includes('--smoke');
const S=await loadSource(root), {Grid, BulletBarn, WeaponManager, Movement, ObjectType, ObjectSerializeFns, BitStream, InputMsg, v2, collider, GameConfig, GameObjectDefs}=S;
const definitions=Object.fromEntries(GameObjectDefs.getAllTypes().filter(Boolean).map(k=>[k,GameObjectDefs.typeToDef(k)]));
function wirePosition(p) {
  const stream=new BitStream(new ArrayBuffer(6));
  ObjectSerializeFns[ObjectType.Player].serializePart(stream,{pos:p.pos,dir:p.dir});
  stream.index=0; const data={}; ObjectSerializeFns[ObjectType.Player].deserializePart(stream,data);
  return data.pos;
}
function wireAim(dir,len) {
  const stream=new BitStream(new ArrayBuffer(32)), msg=new InputMsg();
  msg.toMouseDir=dir; msg.toMouseLen=Math.max(0,Math.min(64,len)); msg.shootStart=true; msg.shootHold=true;
  msg.serialize(stream); stream.index=0; const out=new InputMsg();out.deserialize(stream);
  return {dir:v2.normalizeSafe(out.toMouseDir),len:out.toMouseLen};
}
const rng=seed=>()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
const copy=p=>({x:p.x,y:p.y});
function gridObject(obj,bounds) { return Object.assign(obj,{bounds,__gridBounds:{min:{x:-1,y:-1},max:{x:-1,y:-1}},__onGrid:false,__gridQueryId:0}); }
function player(game,id,pos,gun,boost) {
  const p=Object.assign(new Movement(),gridObject({__type:ObjectType.Player,__id:id,pos:copy(pos),posOld:copy(pos),vel:{x:0,y:0},moveVel:{x:0,y:0},dir:{x:1,y:0},dirOld:{x:1,y:0},scale:1,rad:1,layer:0,aimLayer:0,teamId:id,dead:false,downed:false,perks:[],boost:boost?75:0,
    touchMoveActive:false,touchMoveLen:0,moveUp:false,moveDown:false,moveLeft:false,moveRight:false,movingTicker:0,timeWithoutMoving:0,stayingStillTicker:0,
    debug:{noClip:false,speedEnabled:false},hasPerk:()=>false,hasActivePan:()=>false,game,activeWeapon:gun,
    actionType:GameConfig.Action.None,action:{},animType:GameConfig.Anim.None,hasteType:GameConfig.HasteType.None,frozen:false,shotSlowdownTimer:0,
    recoilTicker:100,toMouseLen:100,combatStimsActive:false,indoors:false, cancelAction(){},damage(){}}, {min:{x:-1,y:-1},max:{x:1,y:1}}));
  p.weaponManager=new WeaponManager(p); p.weaponManager._curWeapIdx=0;
  Object.assign(p.weaponManager.weapons[0],{type:gun,ammo:1000,recoilTime:0,cooldown:0});
  game.grid.addObject(p); return p;
}
function moveInput(kind,t,phase=0) {
  const x=t+phase;
  if(kind==='still') return [0,0];
  if(kind==='straight') return [0,1];
  if(kind==='approach') return [-1,0];
  if(kind==='retreat') return [1,0];
  if(kind==='ad') return [0,Math.floor(x/.3)%2?-1:1];
  if(kind==='stop-go') return [0,[1,0,-1,0][Math.floor(x/.38)%4]];
  if(kind==='turn') return [[1,0],[0,1],[-1,0],[0,-1]][Math.floor(x/.75)%4];
  if(kind==='irregular') return [[0,1],[1,0],[0,-1],[-1,1],[0,0],[1,-1],[-1,0]][Math.floor(x/.27)%7];
  if(kind==='escape') return x<2.4?[0,Math.floor(x/.48)%2?-1:1]:[0,1];
  throw new Error(`unknown input ${kind}`);
}
function input(p,v) {p.moveRight=v[0]>0;p.moveLeft=v[0]<0;p.moveUp=v[1]>0;p.moveDown=v[1]<0;}
function obstacle(game,x,y) {
  const col=collider.createAabb({x:x-1,y:y-3},{x:x+1,y:y+3});
  const o=gridObject({__type:ObjectType.Obstacle,__id:3,pos:{x,y},collider:col,type:'stone_01',layer:0,height:1,collidable:true,active:true,dead:false,destructible:false,isTree:false,damage(){}},{min:{x:-1,y:-3},max:{x:1,y:3}});
  game.grid.addObject(o);return o;
}
function simulation(opts) {
  const originalRandom=Math.random; Math.random=rng(opts.seed);
  try {
    const game={grid:new Grid(1024,1024),map:{bounds:{min:{x:0,y:0},max:{x:1024,y:1024}},isOnWater:()=>false,factionMode:false,clampToMapBounds:p=>{p.x=Math.max(0,Math.min(1024,p.x));p.y=Math.max(0,Math.min(1024,p.y));}},objectRegister:{getById:id=>id===1?shooter:id===2?target:undefined}};
    const shooter=player(game,1,{x:400,y:500},opts.gun,opts.boost), target=player(game,2,{x:400+opts.distance,y:500},opts.gun,opts.boost);
    game.bulletBarn=new BulletBarn(game);
    const walls=opts.cover?[obstacle(game,400+opts.distance*.55,500)]:[];
    const trackOwn=new SnapshotTracker(),trackTarget=new SnapshotTracker(),profile=weaponProfile(definitions,opts.gun,[]); assert.ok(profile);
    const received=[],commands=[],shots=[],ownership=new Map();
    let nextSnapshot=0,nextFrame=0,nextFire=1,latestOwn=null,latestTarget=null, move=[0,0];
    const ownPhase=.13+(opts.seed%37)/100, targetPhase=.29+(opts.seed%53)/100;
    const tick=.01, end=7;
    for(let step=0;step<=end/tick;step++) {
      const now=step*tick;
      // Deliver packets and render frames in timestamp order between server
      // ticks, so a frame never sees a future snapshot or drops a valid one.
      while (Math.min(received[0]?.at ?? Infinity,nextFrame)<=now+1e-9) {
        if ((received[0]?.at ?? Infinity)<=nextFrame) {
          const msg=received.shift(); latestOwn=msg.own;latestTarget=msg.target;
          trackOwn.observe(shooter,msg.own,msg.at*1000,0);trackTarget.observe(target,msg.target,msg.at*1000,0);
          continue;
        }
        const frame=nextFrame; nextFrame+=1/opts.fps;
        const ownInput=moveInput(opts.own,frame,ownPhase);
        commands.push({at:frame+opts.up,input:ownInput});
        if(frame+1e-9<nextFire || !latestOwn || !latestTarget || frame>=5-1e-9) continue;
        const a=trackOwn.estimate(shooter,frame*1000), b=trackTarget.estimate(target,frame*1000);
        if(!a||!b) continue;
        nextFire+=.5;
        let dir, mouseLen; const dx=b.pos.x-a.pos.x,dy=b.pos.y-a.pos.y,n=Math.hypot(dx,dy);
        mouseLen=n;
        const native=n?{x:dx/n,y:dy/n}:{x:1,y:0};
        if(opts.model==='current') {
          const shot=predictShot({origin:a.pos,target:b.pos,track:b,profile,latency:(opts.down+opts.up)/2,stabilize:true,compensateSnapshot:true,muzzleFor:(pos,d,p)=>clippedMuzzle(pos,d,p,walls,0,0)});
          dir=shot.dir||native; if(shot.dir && Number.isFinite(shot.mouseLen)) mouseLen=shot.mouseLen;
        } else dir=native;
        commands.push({at:frame+opts.up,fire:true,...wireAim(dir,mouseLen)});
      }
      while(commands.length&&commands[0].at<=now+1e-9) {
        const command=commands.shift(); if(command.input) move=command.input; else if(command.fire) (game.fireQueue ||= []).push(command);
      }
      input(shooter,move); input(target,moveInput(opts.target,now,targetPhase));
      for(const p of [shooter,target]) {
        p.step(tick);game.grid.updateObject(p);
        p.recoilTicker+=tick;
        const w=p.weaponManager.weapons[0]; w.cooldown-=tick;w.recoilTime-=tick;
      }
      for(const cmd of game.fireQueue || []) {
        const weapon=shooter.weaponManager.weapons[0]; if(weapon.cooldown>0)continue;
        shooter.dir=cmd.dir; shooter.toMouseLen=cmd.len;
        const before=game.bulletBarn.newBullets.length;
        shooter.weaponManager.fireWeapon(false);
        const record={hit:false,wall:false,bullets:0};shots.push(record);
        for(const b of game.bulletBarn.newBullets.slice(before)) {ownership.set(b,record);record.bullets++;}
      }
      for(const p of [shooter,target]) p.shotSlowdownTimer=Math.max(0,p.shotSlowdownTimer-tick);
      game.fireQueue=[];game.bulletBarn.flush();game.bulletBarn.newBullets.length=0;
      for(const b of game.bulletBarn.bullets) if(b.active) {
        b.update(tick);
        for(const damage of game.bulletBarn.damages) { const r=ownership.get(b); if(damage.obj===target) r.hit=true; if(walls.includes(damage.obj)) r.wall=true; }
        game.bulletBarn.damages.length=0;
      }
      if(now+1e-9>=nextSnapshot) {
        const delay=opts.down+(opts.jitter ? .006*Math.sin(step*1.71)+(step%151===0?.08:0):0);
        const at=Math.max(now+delay,received.at(-1)?.at+0.00001||0);
        received.push({at,own:wirePosition(shooter),target:wirePosition(target)}); nextSnapshot+=1/33;
      }
    }
    return {shots:shots.length,hits:shots.filter(s=>s.hit).length,walls:shots.filter(s=>s.wall).length,bullets:shots.reduce((a,s)=>a+s.bullets,0),shooter:copy(shooter.pos),target:copy(target.pos)};
  } finally { Math.random=originalRandom; }
}
const defaults={own:'still',target:'still',distance:20,gun:'mp5',boost:false,down:.03,up:.03,fps:60,seed:123,cover:false,jitter:false,model:'current'};
// Verify that the real WeaponManager emits bullets, source bullet/grid reports
// target hits, and the same shot is stopped by a source obstacle collision.
const hit=simulation(defaults), blocked=simulation({...defaults,cover:true}), shotgun=simulation({...defaults,gun:'m870'});
assert.ok(hit.shots>0 && hit.bullets>=hit.shots && hit.hits>0,JSON.stringify({hit}));
assert.ok(blocked.walls>0 && blocked.hits===0,JSON.stringify({blocked}));
assert.ok(shotgun.shots>0 && shotgun.bullets>shotgun.shots && shotgun.hits>0,JSON.stringify({shotgun}));
const wallWalk=simulation({...defaults,cover:true,target:'approach'});
assert.ok(wallWalk.target.x >= 412.999 && wallWalk.target.x < 413.1, `source obstacle stops moving player: ${JSON.stringify(wallWalk.target)}`);
for(const fps of [30,60,144]) assert.equal(simulation({...defaults,fps}).shots,8,`frame/packet ordering at ${fps} FPS`);
const walking=simulation({...defaults,own:'straight'}), boosted=simulation({...defaults,own:'straight',boost:true});
assert.ok(boosted.shooter.y>walking.shooter.y, 'source boost increases shooter speed');
assert.deepEqual(simulation(defaults),hit,'seeded simulations must reproduce');
console.log(`PASS source smoke: open ${hit.hits}/${hit.shots} shots hit; cover ${blocked.walls}/${blocked.shots} hit obstacle, ${blocked.hits} hit target; reproducible.`);
if (!smoke) {
  const cases=[['still','still'],['straight','straight'],['straight','turn'],['ad','ad'],['stop-go','irregular'],['turn','stop-go'],['irregular','escape'],['straight','approach'],['turn','retreat']];
  const totals=new Map();
  for(const [own,target] of cases) for(const distance of [20,45]) for(const gun of ['mp5','ak47','m870']) for(const boost of [false,true]) for(const [down,up] of [[.03,.03],[.08,.08],[.03,.12],[.12,.03]]) for(const fps of [30,60,144]) for(const cover of [false,true]) for(const seed of [123,9187,84219]) for(const model of ['direct','current']) {
    const r=simulation({...defaults,own,target,distance,gun,boost,down,up,fps,cover,seed,model,jitter:true});
    for(const group of ['ALL',`target:${target}`,`shooter:${own}`,`gun:${gun}`,`distance:${distance}`,`fps:${fps}`,`network:${down*1000}/${up*1000}`,`cover:${cover}`,`boost:${boost}`]) {
      const k=`${group}\t${model}`, a=totals.get(k)||{shots:0,hits:0,walls:0,bullets:0};
      for(const n of ['shots','hits','walls','bullets']) a[n]+=r[n];totals.set(k,a);
    }
  }
  console.log('group\tmodel\tshots\thit-shots%\twall-shots%\tbullets');
  for(const [k,r] of totals) console.log(`${k}\t${r.shots}\t${(100*r.hits/r.shots).toFixed(1)}\t${(100*r.walls/r.shots).toFixed(1)}\t${r.bullets}`);
  console.log('Source movement block, speed, WeaponManager.fireWeapon, Bullet/BulletBarn and Grid; synthetic snapshots/input/clock and stubbed world. No full game, sender, actual client, target selection or complete wallcheck. Correlated seeded outcomes, not live hitrate.');
}
