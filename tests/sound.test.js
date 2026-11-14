const assert=require('node:assert/strict');
const S=require('../extension/sound.js'),R=require('../extension/reminders.js');
(async()=>{
 assert.equal(S.validate(undefined).enabled,false);assert.throws(()=>S.validate({...S.defaults,choice:'custom'}));assert.throws(()=>S.validate({...S.defaults,volume:2}));
 const run={id:'one',status:'running'},done={id:'one',status:'complete',closed:1};const change={oldValue:[run],newValue:[done]};assert.equal(S.eventFromChange([], [done]),null);assert.equal(S.eventFromChange([run],[{...done,closed:0}]),null);assert.equal(S.eventFromChange([run],[{...done,status:'blocked'}]).kind,'warning');
 let store={soundConfig:{...S.defaults,enabled:true,complete:true},autoCloseRuns:[done]},plays=0;const api={runtime:{getURL:x=>x},storage:{local:{get:async keys=>Object.fromEntries(keys.filter(k=>k in store).map(k=>[k,store[k]])),set:async v=>Object.assign(store,v)}},windows:{getAll:async()=>[{state:'normal'}]}};const locks={request:async (name,opts,cb)=>cb({})},audio=()=>({play:async()=>{plays++},pause(){}});
 assert.equal(await S.handle(api,change,locks,R,audio,10000),'played');assert.equal(await S.handle(api,change,locks,R,audio,10001),'duplicate');assert.equal(plays,1);
 delete store.soundState;store.quietHours={enabled:true,start:'00:00',end:'23:59'};assert.equal(await S.handle(api,change,locks,R,audio,new Date(2025,1,1,12).getTime()),'quiet');delete store.quietHours;api.windows.getAll=async()=>[{state:'fullscreen'}];assert.equal(await S.handle(api,change,locks,R,audio,20000),'quiet');api.windows.getAll=async()=>[{state:'normal'}];store.soundConfig.enabled=false;assert.equal(await S.handle(api,change,locks,R,audio,20000),'disabled');store.soundConfig.enabled=true;
 assert.equal(await S.handle(api,change,null,R,audio,20000),'ignored');assert.equal(await S.handle(api,change,{request:async(n,o,cb)=>cb(null)},R,audio,20000),'busy');
 assert.equal(await S.handle(api,change,locks,R,()=>({play:async()=>{throw Error('blocked')},pause(){}}),20000),'blocked');assert.equal(store.soundState.id,'one');
 await assert.rejects(S.readFile({name:'x',size:2000000,type:'audio/wav'}),/1 MB/);await assert.rejects(S.readFile({name:'x',size:2,type:'text/html'}),/hợp lệ/);
 console.log('Sound opt-in, quiet hours, fullscreen, deduplication and validation: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
