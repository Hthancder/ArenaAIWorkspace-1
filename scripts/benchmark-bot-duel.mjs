// Deterministic synthetic duel bot. Not a live client or a source-server replay.
// Usage: node scripts/benchmark-bot-duel.mjs [--details]
// AIM_MODULE can point to an experimental compatible aim module.
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { projectOwnOrigin } from '../src/self-motion.mjs';
const { SnapshotTracker, predictShot, muzzleAt } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const experiment = process.env.BOT_EXPERIMENT ? await import(process.env.BOT_EXPERIMENT) : null;
const quick = process.argv.includes('--quick'), holdout = process.argv.includes('--holdout'), tickCollision = process.argv.includes('--tick-collision');
const chosenModels = process.env.BOT_MODELS ? new Set(process.env.BOT_MODELS.split(',')) : null;
// Center test coordinates in the source's positive [0, 1024] map domain.
const quant = n => Math.round((n + 512) * 65535 / 1024) * 1024 / 65535 - 512;
export const SIM = Object.freeze({ baseSpeed: 12, boostBonus: 1.85, fireMultiplier: .5, radius: 1, gameTps: 100, netSyncTps: 33 });
const dt = 1 / 120, duration = 6.5;
const pairs = [
  ['still','still'], ['still','straight'], ['still','ad-fast'], ['still','ad-wide'], ['still','irregular'], ['still','stop-go'], ['still','zigzag'],
  ['straight','still'], ['straight','straight'], ['straight','ad-fast'], ['straight','irregular'],
  ['ad-fast','still'], ['ad-fast','ad-fast'], ['ad-fast','ad-wide'], ['ad-fast','zigzag'],
  ['irregular','straight'], ['irregular','ad-fast'], ['irregular','irregular'], ['stop-go','ad-wide'], ['zigzag','zigzag'],
  ['still','ad-escape'], ['ad-fast','ad-escape'], ['still','ad-jitter'], ['irregular','ad-jitter'],
  ['still','ad-diagonal'], ['ad-fast','ad-diagonal'], ['straight','turn'], ['ad-fast','circle'],
  ['still','ad-pause'], ['ad-fast','ad-pause'], ['still','ad-side-escape'], ['ad-fast','ad-side-escape'],
  ['still','ad-drift'], ['straight','ad-drift'], ['still','ad-shrink-escape'], ['ad-fast','ad-shrink-escape'],
  ['still','ad-escape-stop'], ['ad-fast','ad-escape-stop'], ['still','ad-escape-return'], ['ad-fast','ad-escape-return'],
];
const eventTimes = Object.freeze({'ad-escape':2.4,'ad-side-escape':2.4,'ad-pause':2.4,'ad-shrink-escape':3,'ad-escape-stop':2.4,'ad-escape-return':2.4});
export function eventWindow(kind, firedAt, phase, isHoldout = false) {
  if (eventTimes[kind] === undefined) return null;
  const since = firedAt - (eventTimes[kind] / (isHoldout ? 1.13 : 1) - phase);
  return since >= 0 && since < .2 ? '0-200ms' : since >= .2 && since < .5 ? '200-500ms' : since >= .5 && since < 1 ? '500-1000ms' : null;
}
export function movement(kind, t, phase) {
  const x = (t + phase) * (holdout ? 1.13 : 1);
  if (kind === 'still') return { x: 0, y: 0 };
  if (kind === 'straight') return { x: 0, y: 1 };
  if (kind === 'ad-fast') return { x: 0, y: Math.floor(x / .18) % 2 ? -1 : 1 };
  if (kind === 'ad-wide') return { x: 0, y: Math.floor(x / .48) % 2 ? -1 : 1 };
  if (kind === 'ad-escape') return { x: 0, y: x < 2.4 ? (Math.floor(x / .48) % 2 ? -1 : 1) : 1 };
  if (kind === 'ad-escape-stop' || kind === 'ad-escape-return') {
    const y = x < 2.4 ? (Math.floor(x / .48) % 2 ? -1 : 1) : x < 2.7 ? 1 : kind === 'ad-escape-stop' ? 0 : -1;
    return { x: 0, y };
  }
  if (kind === 'ad-pause') return { x: 0, y: x < 2.4 ? (Math.floor(x / .48) % 2 ? -1 : 1) : 0 };
  if (kind === 'ad-side-escape') return x < 2.4 ? { x: 0, y: Math.floor(x / .48) % 2 ? -1 : 1 } : { x: 1, y: 0 };
  if (kind === 'ad-drift') { const s = Math.floor(x / .48) % 2 ? -1 : 1, n = Math.hypot(.15,1); return { x:.15/n, y:s/n }; }
  if (kind === 'ad-shrink-escape') {
    const s = x < 2 ? (Math.floor(x / .48) % 2 ? -1 : 1) : x < 3 ? (Math.floor((x - 2) / .16) % 2 ? -1 : 1) : 1;
    return { x: 0, y: s };
  }
  if (kind === 'ad-diagonal') { const s = Math.floor(x / .48) % 2 ? -Math.SQRT1_2 : Math.SQRT1_2; return { x: s, y: s }; }
  if (kind === 'ad-jitter') {
    const spans = [.18,.55,.26,.4,.65,.31], cycle = spans.reduce((a,b)=>a+b,0); let t = x % cycle, i = 0;
    while(t >= spans[i]) t -= spans[i++];
    return { x:0, y:i%2 ? -1 : 1 };
  }
  if (kind === 'circle') return { x: Math.cos(x*1.2), y: Math.sin(x*1.2) };
  if (kind === 'turn') return Math.floor(x / .9) % 2 ? { x: 1, y: 0 } : { x: 0, y: 1 };
  if (kind === 'stop-go') return { x: 0, y: [1, 0, -1, 0][Math.floor(x / .38) % 4] };
  if (kind === 'zigzag') { const n = Math.SQRT1_2; return [{ x: n, y: n }, { x: -n, y: n }, { x: -n, y: -n }, { x: n, y: -n }][Math.floor(x / .33) % 4]; }
  // Fixed irregular sequence: reversals, pauses and diagonals; no future input
  // is exposed to the predictor. Phase shifts keep the two bots independent.
  const sequence = [[0,1],[0,-1],[0,1],[1,1],[0,0],[0,-1],[-1,1],[0,-1],[0,1],[-1,-1]];
  const step = Math.floor(x / .23), [a,b] = sequence[((step % sequence.length) + sequence.length) % sequence.length], len = Math.hypot(a,b);
  return len ? { x: a / len, y: b / len } : { x: 0, y: 0 };
}
export function trajectory(kind, phase, speed, slowdown, controlDelay = 0) {
  const out = [{ x: 0, y: 0 }];
  for (let i = 1; i <= Math.ceil(duration / dt); i++) {
    const t = (i - 1) * dt, m = movement(kind, Math.max(0, t - controlDelay), phase);
    // Sustained firing approximation from recalculateSpeed's 0.5 multiplier.
    // Does not model attack/equip bonuses, collision, tick ordering or perks.
    const s = speed * (slowdown ? SIM.fireMultiplier : 1), prev = out[i - 1];
    out.push({ x: prev.x + m.x * s * dt, y: prev.y + m.y * s * dt });
  }
  return t => { const n = Math.max(0, Math.min(out.length - 1.000001, t / dt)), i = Math.floor(n), f = n - i; return { x: out[i].x * (1-f) + out[i+1].x * f, y: out[i].y * (1-f) + out[i+1].y * f }; };
}
export function collision(start, dir, speed, range, targetAt, firedAt, distance) {
  // Relative segment/circle sweep against piecewise-linear target trajectory.
  // A target initially overlapping the muzzle also counts as a model hit.
  let t = 0, last = targetAt(firedAt), rx = start.x - distance - last.x, ry = start.y - last.y, best = Math.hypot(rx, ry);
  if (best <= SIM.radius) return { hit: true, miss: 0 };
  const max = Math.min(range / speed, duration - firedAt);
  while (t < max) {
    const next = Math.min(t + dt, max), p = targetAt(firedAt + next);
    const nx = start.x + dir.x * speed * next - distance - p.x, ny = start.y + dir.y * speed * next - p.y;
    const dx = nx - rx, dy = ny - ry, den = dx*dx + dy*dy;
    const u = den ? Math.max(0, Math.min(1, -(rx*dx + ry*dy) / den)) : 0;
    const r = Math.hypot(rx + dx*u, ry + dy*u); best = Math.min(best, r);
    if (r <= SIM.radius) return { hit: true, miss: 0 };
    rx = nx; ry = ny; t = next;
  }
  return { hit: false, miss: Math.max(0, best - SIM.radius) };
}
// Segment/circle predicate follows the pinned coldet implementation, including
// its exit intersection for a segment starting inside the target. A segment
// entirely inside the target is not itself a hit under those source semantics.
export function tickSegmentCircle(start, end, center, radius) {
  const dx = end.x - start.x, dy = end.y - start.y, len = Math.max(Math.hypot(dx, dy), .000001);
  const ux = dx / len, uy = dy / len, mx = start.x - center.x, my = start.y - center.y;
  const b = mx * ux + my * uy, c = mx * mx + my * my - radius * radius;
  if (c > 0 && b > 0) return false;
  const disc = b * b - c; if (disc < 0) return false;
  let t = -b - Math.sqrt(disc); if (t < 0) t = -b + Math.sqrt(disc);
  return t <= len;
}
export function tickCollisionSweep(start, dir, speed, range, targetAt, firedAt, distance) {
  const tick = 1 / SIM.gameTps, max = Math.min(range / speed, duration - firedAt);
  let best = Infinity, t = 0;
  while (t < max) {
    const next = Math.min(t + tick, max), p = targetAt(firedAt + t);
    const from = { x:start.x + dir.x * speed * t, y:start.y + dir.y * speed * t };
    const to = { x:start.x + dir.x * speed * next, y:start.y + dir.y * speed * next };
    const center = { x:distance + p.x, y:p.y };
    if (tickSegmentCircle(from, to, center, SIM.radius)) return { hit:true, miss:0 };
    const dx = to.x - from.x, dy = to.y - from.y, den = dx*dx + dy*dy;
    const u = den ? Math.max(0, Math.min(1, ((center.x-from.x)*dx + (center.y-from.y)*dy) / den)) : 0;
    best = Math.min(best, Math.hypot(from.x+dx*u-center.x, from.y+dy*u-center.y)); t = next;
  }
  return { hit:false, miss:Math.max(0, best - SIM.radius) };
}
const totals = new Map();
function stableProjection(track, projected) {
  const s = track?.motion;
  if (!projected || !s || s.length < 12 || s.at(-1).t - s[0].t < 650) return null;
  const first = s[0], last = s.at(-1), span = last.t - first.t;
  for (let i = 1; i < s.length; i++) {
    if (s[i].t <= s[i-1].t || s[i].t - s[i-1].t > 100) return null;
    const f = (s[i].t - first.t) / span;
    if (Math.hypot(s[i].p.x - first.p.x - (last.p.x - first.p.x)*f, s[i].p.y - first.p.y - (last.p.y - first.p.y)*f) > .12) return null;
  }
  return projected;
}
function record(key, model, result, fallback, projected) {
  const k = `${key}\t${model}`, r = totals.get(k) || { n:0, hits:0, miss:0, fallback:0, projected:0 };
  r.n++; r.hits += result.hit; r.miss += result.miss; r.fallback += fallback; r.projected += projected; totals.set(k,r);
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
for (const [ownKind, targetKind] of pairs) for (const distance of [12,35,70]) for (const ownBoost of [false,true]) for (const targetBoost of [false,true])
for (const slower of [false,true]) for (const targetSlow of [false,true]) for (const [down,up] of (quick ? [[.03,.03],[.08,.08]] : [[.03,.03],[.08,.08],[.03,.12],[.12,.03]])) for (const bullet of [66,100,182]) for (const hz of (quick ? [60] : [30,60,144])) {
  // Own commands originate locally and reach the simulated server after uplink.
  const ownPhase = holdout ? .16 : .07, targetPhase = holdout ? .37 : .19;
  const ownAt = trajectory(ownKind, ownPhase, SIM.baseSpeed + (ownBoost ? SIM.boostBonus : 0), slower, up), targetAt = trajectory(targetKind, targetPhase, SIM.baseSpeed + (targetBoost ? SIM.boostBonus : 0), targetSlow);
  const own = new SnapshotTracker(), enemy = new SnapshotTracker(), me = {__id:1}, target = {__id:2};
  const profile = { speed: bullet, range: 250, barrel: 2, offset: .25, variance: 1 };
  const packets = []; let lastArrival = 0;
  for (let i=0; i<150; i++) {
    const t=i/SIM.netSyncTps, jitter=holdout ? .009*Math.sin(i*1.37)+(i%71===62?.12:0) : .006*Math.sin(i*2.7)+(i%67===60?.09:0);
    const arrival=Math.max(t+down+jitter,lastArrival+.00001); lastArrival=arrival;
    packets.push({t,arrival});
  }
  let cursor=0, nextShot=1;
  for (let frame=0; frame/hz<4.45; frame++) {
    const now=frame/hz;
    while (cursor<packets.length && packets[cursor].arrival<=now) {
      const p=packets[cursor++], a=ownAt(p.t), b=targetAt(p.t);
      own.observe(me,{x:quant(a.x),y:quant(a.y)},p.arrival*1000,0);
      enemy.observe(target,{x:quant(distance+b.x),y:quant(b.y)},p.arrival*1000,0);
    }
    if(now+1e-8<nextShot)continue; nextShot+=holdout ? .137 : .12;
    const a=own.estimate(me,now*1000), b=enemy.estimate(target,now*1000); if(!a||!b)continue;
    // Tick mode rounds Fire to a simulated game tick; the pinned source does
    // not establish the live server's scheduling or actual tick phase.
    const firedAt = tickCollision ? Math.ceil((now+up)*SIM.gameTps - 1e-8)/SIM.gameTps : now+up;
    const input=movement(ownKind,now,ownPhase), realOrigin=ownAt(firedAt), transit=(down+up)/2;
    const projected=projectOwnOrigin(a.pos,a,input,{rtt:(down+up)*1000,lastRtt:(down+up)*1000,rttAt:now*1000},now*1000);
    const stable = stableProjection(a,projected);
    for (const model of ['direct','current','guarded','stable-own','oracle-origin', ...(experiment ? ['experimental'] : [])]) {
      if (chosenModels && !chosenModels.has(model)) continue;
      const origin=model==='guarded'&&projected?projected:model==='stable-own'&&stable?stable:model==='oracle-origin'?realOrigin:a.pos;
      const predicted=model==='experimental' ? experiment.candidate(b,profile,origin,transit) : null;
      const adjusted=predicted?{...b,pos:predicted,vx:0,vy:0,age:0,error:0,velocityError:0,motion:[]}:b;
      const shot=model==='direct'?null:predictShot({origin,target:adjusted.pos,track:adjusted,profile,latency:predicted?0:transit,stabilize:!predicted,compensateSnapshot:!predicted});
      const fallback=model!=='direct'&&!shot?.dir;
      let dir=shot?.dir;
      if(!dir) { const dx=b.pos.x-a.pos.x,dy=b.pos.y-a.pos.y,n=Math.hypot(dx,dy); dir={x:dx/n,y:dy/n}; }
      const start=muzzleAt(realOrigin,dir,profile), result=tickCollision
        ? tickCollisionSweep(start,dir,bullet,profile.range,targetAt,firedAt,distance)
        : collision(start,dir,bullet,profile.range,targetAt,firedAt,distance);
      const keys=['ALL',`distance:${distance}`,`target:${targetKind}`,`shooter:${ownKind}`,`shooter-boost:${ownBoost}`,`target-boost:${targetBoost}`,`shooter-slow:${slower}`,`target-slow:${targetSlow}`,`down-up-ms:${down*1000}/${up*1000}`,`bullet:${bullet}`,`fps:${hz}`];
      // Condition on the simulated event at the server's shot time, not on a
      // future event exposed to prediction. Non-overlapping windows show the
      // transient cost that aggregate per-pattern hit rate can conceal.
      const window = eventWindow(targetKind, firedAt, targetPhase, holdout);
      if (window) keys.push(`event:${targetKind}:${window}`);
      if(process.argv.includes('--details')) keys.push(`duel:${ownKind}/${targetKind}/${distance}/${ownBoost}/${targetBoost}/${slower}/${targetSlow}/${down}/${up}/${bullet}/${hz}`);
      for(const k of keys) record(k,model,result,fallback,model==='guarded'&&!!projected || model==='stable-own'&&!!stable);
    }
  }
}
console.log(`Synthetic ${tickCollision ? '100 Hz tick/static-circle' : 'continuous moving-circle'} hit proxy; source-shaped movement speeds, but no actual server, obstacles, spread, collision resolution, recoil or live networking. Oracle uses future shooter position for scoring only.`);
console.log('group\tmodel\tn\thit%\tmean-miss-wu\tfallback%\tprojected%');
for(const [key,r] of totals) console.log(`${key}\t${r.n}\t${(100*r.hits/r.n).toFixed(1)}\t${(r.miss/r.n).toFixed(3)}\t${(100*r.fallback/r.n).toFixed(1)}\t${(100*r.projected/r.n).toFixed(1)}`);
}
