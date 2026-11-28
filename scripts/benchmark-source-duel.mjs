// Source-backed synthetic integration harness, NOT a live server or full Player.update.
// Requires a clean audited Survev checkout: node scripts/benchmark-source-duel.mjs [path] [--smoke]
import assert from 'node:assert/strict';
import { loadSource } from './source-duel-runtime.mjs';
import { clippedMuzzle } from '../src/aim-geometry.mjs';
import { projectOwnOrigin } from '../src/self-motion.mjs';
import { inferredStationary } from '../src/stationary-inference.mjs';
const { SnapshotTracker, predictShot, weaponProfile } = await import(process.env.AIM_MODULE || '../src/aim.mjs');

const args=process.argv.slice(2), root=args.find(x=>!x.startsWith('--')) || '.cache/survev', smoke=args.includes('--smoke'), holdout=args.includes('--holdout'), quick=args.includes('--quick');
const models=process.env.SOURCE_MODELS ? process.env.SOURCE_MODELS.split(',') : ['direct','current'];
if(models.some(x=>!['direct','current','fast-stop','projected','stable-own','project-25','project-50','project-75'].includes(x))) throw new Error('invalid SOURCE_MODELS');
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
  if(kind==='irregular-alt') return [[1,-1],[-1,0],[0,1],[1,1],[0,-1],[0,0],[-1,-1],[1,0]][Math.floor(x/.31)%8];
  if(kind==='irregular-exit') return x<2.6?moveInput('irregular-alt',t,phase):[0,1];
  if(kind==='escape') return x<2.4?[0,Math.floor(x/.48)%2?-1:1]:[0,1];
  throw new Error(`unknown input ${kind}`);
}
function input(p,v) {p.moveRight=v[0]>0;p.moveLeft=v[0]<0;p.moveUp=v[1]>0;p.moveDown=v[1]<0;}
function obstacle(game,x,y) {
  const col=collider.createAabb({x:x-1,y:y-3},{x:x+1,y:y+3});
  const o=gridObject({__type:ObjectType.Obstacle,__id:3,pos:{x,y},collider:col,type:'stone_01',layer:0,height:1,collidable:true,active:true,dead:false,destructible:false,isTree:false,damage(){}},{min:{x:-1,y:-3},max:{x:1,y:3}});
  game.grid.addObject(o);return o;
}
// Experimental only: verify that own recent observations fit a long straight
// path. This does not anticipate a sudden stop, wall or server input timing.
function stableOwn(track, projected) {
  const s=track?.motion;
  if(!projected || !s || s.length<12 || s.at(-1).t-s[0].t<650) return null;
  const first=s[0], last=s.at(-1), span=last.t-first.t;
  for(let i=1;i<s.length;i++) {
    if(s[i].t<=s[i-1].t || s[i].t-s[i-1].t>100) return null;
    const f=(s[i].t-first.t)/span;
    if(Math.hypot(s[i].p.x-first.p.x-(last.p.x-first.p.x)*f,s[i].p.y-first.p.y-(last.p.y-first.p.y)*f)>.12) return null;
  }
  return projected;
}
function simulation(opts) {
  const originalRandom=Math.random; Math.random=rng(opts.seed);
  try {
    const game={grid:new Grid(1024,1024),map:{bounds:{min:{x:0,y:0},max:{x:1024,y:1024}},isOnWater:()=>false,factionMode:false,clampToMapBounds:p=>{p.x=Math.max(0,Math.min(1024,p.x));p.y=Math.max(0,Math.min(1024,p.y));}},objectRegister:{getById:id=>id===1?shooter:id===2?target:undefined}};
    const shooter=player(game,1,{x:400,y:500},opts.gun,opts.boost), target=player(game,2,{x:400+opts.distance,y:500},opts.gun,opts.boost);
    game.bulletBarn=new BulletBarn(game);
    const walls=opts.cover?[obstacle(game,400+opts.distance*.55,500)]:[];
    const trackOwn=new SnapshotTracker(),trackTarget=new SnapshotTracker(),stationaryTarget=new SnapshotTracker(),profile=weaponProfile(definitions,opts.gun,[]); assert.ok(profile);
    const received=[],commands=[],shots=[],ownership=new Map();
    let nextSnapshot=0,nextFrame=0,nextFire=1,latestOwn=null,latestTarget=null, move=[0,0];
    let ownDirty=true,targetDirty=true,lastUpdate=null, targetUpdates=0,targetOmissions=0,inferredShots=0,nativeFallbacks=0;
    const ownPhase=.13+(opts.seed%37)/100, targetPhase=.29+(opts.seed%53)/100;
    const tick=.01, end=7;
    for(let step=0;step<=end/tick;step++) {
      const now=step*tick;
      // Deliver packets and render frames in timestamp order between server
      // ticks, so a frame never sees a future snapshot or drops a valid one.
      while (Math.min(received[0]?.at ?? Infinity,nextFrame)<=now+1e-9) {
        if ((received[0]?.at ?? Infinity)<=nextFrame) {
          const msg=received.shift(), at=msg.at*1000;
          const cadence=lastUpdate!==null && at>lastUpdate && at-lastUpdate<=150;
          if(!cadence && at!==lastUpdate) stationaryTarget.reset();
          lastUpdate=at;
          if(msg.own) {latestOwn=msg.own;trackOwn.observe(shooter,msg.own,at,0);}
          if(msg.target) {
            targetUpdates++;latestTarget=msg.target;trackTarget.observe(target,msg.target,at,0);stationaryTarget.observe(target,msg.target,at,0);
          } else if(latestTarget && cadence) {
            targetOmissions++;
            const s=stationaryTarget.states.get(target);
            const settled=s && at>s.time && at-s.time<50 && Math.hypot(s.vx,s.vy)<.1 && s.samples?.length>=3
              && s.samples.every(o=>Math.hypot(o.p.x-latestTarget.x,o.p.y-latestTarget.y)<.02);
            if(!settled) stationaryTarget.observe(target,latestTarget,at,0);
          }
          continue;
        }
        const frame=nextFrame; nextFrame+=1/opts.fps;
        const ownInput=moveInput(opts.own,frame,ownPhase);
        commands.push({at:frame+opts.up,input:ownInput});
        if(frame+1e-9<nextFire || !latestOwn || !latestTarget || frame>=5-1e-9) continue;
        const a=trackOwn.estimate(shooter,frame*1000);
        let b=trackTarget.estimate(target,frame*1000);
        const s=stationaryTarget.estimate(target,frame*1000);
        const stale=!b || b.age>.15;
        const inferred=stale || opts.model==='fast-stop' ? inferredStationary(b,s,!stale) : null;
        if(stale || inferred) {
          b=inferred;
          if (b) inferredShots++; else nativeFallbacks++;
        }
        nextFire+=.5;
        let dir, mouseLen; const dx=latestTarget.x-latestOwn.x,dy=latestTarget.y-latestOwn.y,n=Math.hypot(dx,dy);
        mouseLen=n;
        const native=n?{x:dx/n,y:dy/n}:{x:1,y:0};
        if(opts.model!=='direct' && b) {
          const projection = opts.model==='projected' || opts.model==='stable-own' || opts.model.startsWith('project-')
            ? projectOwnOrigin(latestOwn,a,{x:ownInput[0],y:ownInput[1]}, {rtt:(opts.down+opts.up)*1000,lastRtt:(opts.down+opts.up)*1000,rttAt:frame*1000},frame*1000) : null;
          const selected = opts.model==='stable-own'?stableOwn(a,projection):projection;
          const ratio = opts.model.startsWith('project-') ? Number(opts.model.slice(8))/100 : 1;
          const origin = selected ? {x:latestOwn.x+(selected.x-latestOwn.x)*ratio,y:latestOwn.y+(selected.y-latestOwn.y)*ratio} : latestOwn;
          const shot=predictShot({origin,target:b.pos,track:b,profile,latency:(opts.down+opts.up)/2,stabilize:true,compensateSnapshot:true,muzzleFor:(pos,d,p)=>clippedMuzzle(pos,d,p,walls,0,0)});
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
        if(!v2.eq(p.pos,p.posOld)) { if(p===shooter) ownDirty=true; else targetDirty=true; }
        p.recoilTicker+=tick;
        const w=p.weaponManager.weapons[0]; w.cooldown-=tick;w.recoilTime-=tick;
      }
      for(const cmd of game.fireQueue || []) {
        const weapon=shooter.weaponManager.weapons[0]; if(weapon.cooldown>0)continue;
        if(!v2.eq(shooter.dir,cmd.dir)) ownDirty=true;
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
        received.push({at,own:ownDirty?wirePosition(shooter):null,target:targetDirty?wirePosition(target):null});
        ownDirty=false;targetDirty=false; nextSnapshot+=1/33;
      }
    }
    return {shots:shots.length,hits:shots.filter(s=>s.hit).length,walls:shots.filter(s=>s.wall).length,bullets:shots.reduce((a,s)=>a+s.bullets,0),targetUpdates,targetOmissions,inferredShots,nativeFallbacks,shooter:copy(shooter.pos),target:copy(target.pos)};
  } finally { Math.random=originalRandom; }
}
const defaults={own:'still',target:'still',distance:20,gun:'mp5',boost:false,down:.03,up:.03,fps:60,seed:123,cover:false,jitter:false,model:'current'};
// Verify that the real WeaponManager emits bullets, source bullet/grid reports
// target hits, and the same shot is stopped by a source obstacle collision.
const hit=simulation(defaults), blocked=simulation({...defaults,cover:true}), shotgun=simulation({...defaults,gun:'m870'});
assert.ok(hit.shots>0 && hit.bullets>=hit.shots && hit.hits>0,JSON.stringify({hit}));
assert.ok(hit.targetOmissions>0 && hit.inferredShots>0,`omitted stationary updates must exercise inference: ${JSON.stringify(hit)}`);
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
  const cases=[['still','still'],['straight','straight'],['straight','turn'],['ad','ad'],['stop-go','irregular'],['turn','stop-go'],['irregular','escape'],['straight','approach'],['turn','retreat'],
    ['still','irregular-alt'],['straight','irregular-alt'],['turn','irregular-exit'],['ad','retreat'],['still','stop-go'],['irregular','turn']];
  const totals=new Map();
  for(const [own,target] of cases) for(const distance of [20,45]) for(const gun of ['mp5','ak47','m870']) for(const boost of [false,true]) for(const [down,up] of (quick?[[.03,.03],[.08,.08]]:[[.03,.03],[.08,.08],[.03,.12],[.12,.03]])) for(const fps of (quick?[60]:[30,60,144])) for(const cover of [false,true]) for(const seed of (holdout ? [5039,72911,174293] : [123,9187,84219])) for(const model of models) {
    const r=simulation({...defaults,own,target,distance,gun,boost,down,up,fps,cover,seed,model,jitter:true});
    for(const group of ['ALL',`target:${target}`,`shooter:${own}`,`duel:${own}/${target}`,`target-cover:${target}/${cover}`,`gun:${gun}`,`distance:${distance}`,`fps:${fps}`,`network:${down*1000}/${up*1000}`,`cover:${cover}`,`boost:${boost}`]) {
      const k=`${group}\t${model}`, a=totals.get(k)||{shots:0,hits:0,walls:0,bullets:0};
      for(const n of ['shots','hits','walls','bullets']) a[n]+=r[n];totals.set(k,a);
    }
  }
  console.log(`seed set: ${holdout?'holdout 5039,72911,174293':'development 123,9187,84219'}; 15 movement pairs`);
  console.log('group\tmodel\tshots\thit-shots%\twall-shots%\tbullets');
  for(const [k,r] of totals) console.log(`${k}\t${r.shots}\t${(100*r.hits/r.shots).toFixed(1)}\t${(100*r.walls/r.shots).toFixed(1)}\t${r.bullets}`);
  console.log('Source movement block, speed, WeaponManager.fireWeapon, Bullet/BulletBarn and Grid; synthetic snapshots/input/clock and stubbed world. No full game, sender, actual client, target selection or complete wallcheck. Correlated seeded outcomes, not live hitrate.');
}
