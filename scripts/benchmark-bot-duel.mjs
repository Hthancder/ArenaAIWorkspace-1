// Deterministic synthetic duel bot. Not a live client or a source-server replay.
// Usage: node scripts/benchmark-bot-duel.mjs [--details]
// AIM_MODULE can point to an experimental compatible aim module.
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { projectOwnOrigin } from '../src/self-motion.mjs';
const { SnapshotTracker, predictShot, muzzleAt } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const experiment = process.env.BOT_EXPERIMENT ? await import(process.env.BOT_EXPERIMENT) : null;
// Center test coordinates in the source's positive [0, 1024] map domain.
const quant = n => Math.round((n + 512) * 65535 / 1024) * 1024 / 65535 - 512;
export const SIM = Object.freeze({ baseSpeed: 12, boostBonus: 1.85, fireMultiplier: .5, radius: 1 });
const dt = 1 / 120, duration = 6.5;
const pairs = [
  ['still','still'], ['still','straight'], ['still','ad-fast'], ['still','ad-wide'], ['still','irregular'], ['still','stop-go'], ['still','zigzag'],
  ['straight','still'], ['straight','straight'], ['straight','ad-fast'], ['straight','irregular'],
  ['ad-fast','still'], ['ad-fast','ad-fast'], ['ad-fast','ad-wide'], ['ad-fast','zigzag'],
  ['irregular','straight'], ['irregular','ad-fast'], ['irregular','irregular'], ['stop-go','ad-wide'], ['zigzag','zigzag'],
  ['still','ad-escape'], ['ad-fast','ad-escape'], ['still','ad-jitter'], ['irregular','ad-jitter'],
  ['still','ad-diagonal'], ['ad-fast','ad-diagonal'], ['straight','turn'], ['ad-fast','circle'],
];
export function movement(kind, t, phase) {
  const x = t + phase;
  if (kind === 'still') return { x: 0, y: 0 };
  if (kind === 'straight') return { x: 0, y: 1 };
  if (kind === 'ad-fast') return { x: 0, y: Math.floor(x / .18) % 2 ? -1 : 1 };
  if (kind === 'ad-wide') return { x: 0, y: Math.floor(x / .48) % 2 ? -1 : 1 };
  if (kind === 'ad-escape') return { x: 0, y: x < 2.4 ? (Math.floor(x / .48) % 2 ? -1 : 1) : 1 };
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
for (const slower of [false,true]) for (const targetSlow of [false,true]) for (const [down,up] of [[.03,.03],[.08,.08],[.03,.12],[.12,.03]]) for (const bullet of [66,100,182]) for (const hz of [30,60,144]) {
  // Own commands originate locally and reach the simulated server after uplink.
  const ownAt = trajectory(ownKind, .07, SIM.baseSpeed + (ownBoost ? SIM.boostBonus : 0), slower, up), targetAt = trajectory(targetKind, .19, SIM.baseSpeed + (targetBoost ? SIM.boostBonus : 0), targetSlow);
  const own = new SnapshotTracker(), enemy = new SnapshotTracker(), me = {__id:1}, target = {__id:2};
  const profile = { speed: bullet, range: 250, barrel: 2, offset: .25, variance: 1 };
  const packets = []; let lastArrival = 0;
  for (let i=0; i<150; i++) {
    const t=i/33, jitter=.006*Math.sin(i*2.7)+(i%67===60?.09:0), arrival=Math.max(t+down+jitter,lastArrival+.00001); lastArrival=arrival;
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
    if(now+1e-8<nextShot)continue; nextShot+=.12;
    const a=own.estimate(me,now*1000), b=enemy.estimate(target,now*1000); if(!a||!b)continue;
    const input=movement(ownKind,now,.07), realOrigin=ownAt(now+up), transit=(down+up)/2;
    const projected=projectOwnOrigin(a.pos,a,input,{rtt:(down+up)*1000,lastRtt:(down+up)*1000,rttAt:now*1000},now*1000);
    const stable = stableProjection(a,projected);
    for (const model of ['direct','current','guarded','stable-own','oracle-origin', ...(experiment ? ['experimental'] : [])]) {
      const origin=model==='guarded'&&projected?projected:model==='stable-own'&&stable?stable:model==='oracle-origin'?realOrigin:a.pos;
      const predicted=model==='experimental' ? experiment.candidate(b,profile,origin,transit) : null;
      const adjusted=predicted?{...b,pos:predicted,vx:0,vy:0,age:0,error:0,velocityError:0,motion:[]}:b;
      const shot=model==='direct'?null:predictShot({origin,target:adjusted.pos,track:adjusted,profile,latency:predicted?0:transit,stabilize:!predicted,compensateSnapshot:!predicted});
      const fallback=model!=='direct'&&!shot?.dir;
      let dir=shot?.dir;
      if(!dir) { const dx=b.pos.x-a.pos.x,dy=b.pos.y-a.pos.y,n=Math.hypot(dx,dy); dir={x:dx/n,y:dy/n}; }
      const start=muzzleAt(realOrigin,dir,profile), result=collision(start,dir,bullet,profile.range,targetAt,now+up,distance);
      const keys=['ALL',`distance:${distance}`,`target:${targetKind}`,`shooter:${ownKind}`,`shooter-boost:${ownBoost}`,`target-boost:${targetBoost}`,`shooter-slow:${slower}`,`target-slow:${targetSlow}`,`down-up-ms:${down*1000}/${up*1000}`,`bullet:${bullet}`,`fps:${hz}`];
      if(process.argv.includes('--details')) keys.push(`duel:${ownKind}/${targetKind}/${distance}/${ownBoost}/${targetBoost}/${slower}/${targetSlow}/${down}/${up}/${bullet}/${hz}`);
      for(const k of keys) record(k,model,result,fallback,model==='guarded'&&!!projected || model==='stable-own'&&!!stable);
    }
  }
}
console.log('Synthetic moving-circle hit proxy; source-shaped movement speeds, but no actual server, obstacles, spread, collision resolution, recoil or live networking. Oracle uses future shooter position for scoring only.');
console.log('group\tmodel\tn\thit%\tmean-miss-wu\tfallback%\tprojected%');
for(const [key,r] of totals) console.log(`${key}\t${r.n}\t${(100*r.hits/r.n).toFixed(1)}\t${(r.miss/r.n).toFixed(3)}\t${(100*r.fallback/r.n).toFixed(1)}\t${(100*r.projected/r.n).toFixed(1)}`);
}
