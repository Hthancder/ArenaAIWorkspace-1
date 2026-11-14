const assert=require('node:assert/strict'),S=require('../extension/refresh-scheduler.js');
(async()=>{
 let time=0,id=0,timers=new Map(),runs=0,errors=0,resolves=[];const now=()=>time,setTimeout=(fn,ms)=>{timers.set(++id,{at:time+ms,fn});return id},clearTimeout=i=>timers.delete(i),micro=async()=>{for(let i=0;i<8;i++)await Promise.resolve()},advance=async n=>{time+=n;for(const [key,timer] of [...timers])if(timer.at<=time){timers.delete(key);timer.fn()}await micro()};
 const scheduler=S.create(()=>{runs++;return new Promise(resolve=>resolves.push(resolve))},()=>errors++,{delay:100,maxWait:300,now,setTimeout,clearTimeout});
 scheduler.request();await advance(70);scheduler.request();await advance(70);scheduler.request();await advance(70);scheduler.request();await advance(90);assert.equal(runs,1,'continuous events capped by maxWait');
 scheduler.request();scheduler.request();await advance(500);assert.equal(runs,1,'no overlap while work is running');resolves.shift()();await micro();await advance(0);assert.equal(runs,2,'an event during refresh schedules another refresh');resolves.shift()();await micro();assert.equal(errors,0);assert.equal(timers.size,0);
 const bad=S.create(()=>{throw Error('read failed')},()=>errors++,{delay:10,maxWait:20,now,setTimeout,clearTimeout});bad.request();await advance(10);assert.equal(errors,1);bad.request();await advance(10);assert.equal(errors,2,'failures do not permanently stop updates');assert.throws(()=>S.create(()=>{},()=>{},{delay:5,maxWait:4}));
 console.log('Refresh coalesces bursts, bounds latency, serializes event work and recovers from errors: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
