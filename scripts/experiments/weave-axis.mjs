// Benchmark-only counterexample: assumes repeated Y-axis reversals. This is
// intentionally NOT integrated into the userscript; it is pattern-biased and
// cannot predict a real player's future input or generalize to rotated paths.
export function candidate(track, profile, origin, latency) {
  const s=track?.motion;
  if (!s||s.length<12||track.age>.12||s.at(-1).t-s[0].t<500) return null;
  let min=Infinity,max=-Infinity,minX=Infinity,maxX=-Infinity, lastSign=0, turns=[];
  for(let i=0;i<s.length;i++) { const p=s[i].p;min=Math.min(min,p.y);max=Math.max(max,p.y); minX=Math.min(minX,p.x);maxX=Math.max(maxX,p.x); if(i){const d=p.y-s[i-1].p.y,sign=Math.abs(d)>.03?Math.sign(d):0;if(sign){if(lastSign&&sign!==lastSign)turns.push(s[i-1].t);lastSign=sign;}}}
  const width=max-min,speed=Math.abs(track.vy);
  if(width<2||width>8||maxX-minX>.3||turns.length<2||turns.length>7||speed<3||speed>20||Math.abs(track.vx)>1) return null;
  const intervals=turns.slice(1).map((t,i)=>t-turns[i]); if(intervals.some(v=>v<100||v>650)||Math.max(...intervals)/Math.min(...intervals)>1.3)return null;
  const period=intervals.reduce((a,b)=>a+b,0)/intervals.length/1000, expected=width/period;
  if(speed<expected*.6||speed>expected*1.5)return null;
  const direction=Math.sign(track.vy); let time=Math.hypot(track.pos.x-origin.x,track.pos.y-origin.y)/profile.speed;
  let pos;
  for(let i=0;i<3;i++) {
    const z=(track.pos.y-min)+(track.age+latency+time)*speed*direction, span=2*width, m=((z%span)+span)%span, y=min+(m<=width?m:span-m);
    pos={x:track.pos.x,y};time=Math.max(0,Math.hypot(pos.x-origin.x,pos.y-origin.y)-profile.barrel)/profile.speed;
  }
  return pos;
}
