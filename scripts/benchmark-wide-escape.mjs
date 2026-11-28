// Snapshot-level reaction of the wide A–D midpoint gate, not hitrate.
// AIM_MODULE points to an experimental aim module (same exports).
const { SnapshotTracker, boundedOscillation, wideBoundedOscillation } = await import(process.env.AIM_MODULE || '../src/aim.mjs');
const period = 1/33, event = 2, radius = 1, origin = {x:0,y:0}, profile = {speed:66};
const quant = n => Math.round(n * 65535 / 1024) * 1024 / 65535;
const q = (a,p) => a.length ? [...a].sort((x,y)=>x-y)[Math.floor((a.length-1)*p)] : null;
const wave = (t,phase) => 2.4 * 2 / Math.PI * Math.asin(Math.sin(2 * Math.PI * (t+phase) / .8));
const scenarios = {
  inline: (t,p) => ({x:60,y:t<event ? wave(t,p) : wave(event,p)+12*(t-event)}),
  side: (t,p) => ({x:60+(t<event?0:12*(t-event)), y:t<event ? wave(t,p) : wave(event,p)}),
  stop: (t,p) => ({x:60,y:wave(Math.min(t,event),p)}),
  'inline-slower': (t,p) => ({x:60,y:t<event ? wave(t,p) : wave(event,p)+6*(t-event)}),
};
console.log('Wide-midpoint gate reaction proxy, sample phases only; no client, sender, smoothing, server tick or live networking.');
console.log('scenario\tdown-ms\tphase-count\teligible\tfirst-post-receive-ms median/p95\tdisable-after-first-ms median/p95\tmissed');
for (const [name,truth] of Object.entries(scenarios)) for (const down of [.03,.08,.15]) {
  const firsts=[], afters=[]; let eligible=0, missed=0;
  for(let phaseIndex=0;phaseIndex<60;phaseIndex++) {
    const phase=phaseIndex*.8/60, tracker=new SnapshotTracker(), entity={__id:1}; let before=false, first=null, detected=null;
    const packetPhase = ((phaseIndex * 37) % 60) * period / 60;
    for(let t=packetPhase;t<event+.8;t+=period) {
      const pos=truth(t,phase), arrival=t+down;
      tracker.observe(entity,{x:quant(pos.x),y:quant(pos.y)},arrival*1000);
      const track=tracker.estimate(entity,arrival*1000);
      const small=boundedOscillation(track,radius), wide=!small && !!wideBoundedOscillation(track,radius,origin,profile);
      if(t<event) { before=wide; continue; }
      if(first===null) { first=arrival; if(before) eligible++; }
      if(!before) break;
      if(!wide) { detected=arrival; break; }
    }
    if(!before) continue;
    firsts.push((first-event)*1000);
    if(detected===null) missed++; else afters.push((detected-first)*1000);
  }
  const fmt=a=>a.length?`${q(a,.5).toFixed(1)}/${q(a,.95).toFixed(1)}`:'n/a';
  console.log(`${name}\t${down*1000}\t60\t${eligible}\t${fmt(firsts)}\t${fmt(afters)}\t${missed}`);
}
console.log('Eligible = wide midpoint active immediately before event; disabling it is not proof of a correct intercept. No inference about unobserved future input.');
