const assert=require('node:assert/strict'),A=require('../extension/auto-discard.js'),OpenGrace=require('../extension/open-grace.js'),Protection=require('../extension/protection.js');
const now=1700000000000,bytes=megabytes=>megabytes*1048576;
let db={},tabs=[],discards=0;
const tab=(id,extra={})=>({id,windowId:1,url:`https://example.com/${id}`,title:'Tab '+id,incognito:false,active:false,pinned:false,audible:false,discarded:false,lastAccessed:now-48*3600000,...extra});
const config={enabled:true,mode:'ask',combine:'any',resources:['memory'],thresholds:{memory:500,cpu:50,heap:200,network:20},cpuCycles:3,idleMinutes:720,maxPerRun:2,everyMinutes:5,lowMemoryOnly:false};
const info={10:{privateMemory:bytes(1400),cpu:20},11:{privateMemory:bytes(2200),cpu:30},12:{privateMemory:bytes(100),cpu:5},13:{privateMemory:bytes(900)}};
// A discard call inside the measurement run would throw: counting it proves the run never reaches that API.
const api=(live=true,extra={})=>({
 processes:live?{getProcessIdForTab:async id=>({1:10,2:11,3:12,4:13,5:14})[id],getProcessInfo:async ids=>Object.fromEntries(ids.map(id=>[id,info[id]]).filter(([,value])=>value))}:undefined,
 storage:{local:{get:async keys=>Array.isArray(keys)?Object.fromEntries(keys.filter(k=>k in db).map(k=>[k,structuredClone(db[k])])):structuredClone(db),set:async value=>{if(extra.failWrite)throw Error('quota');Object.assign(db,structuredClone(value))}}},
 tabs:{query:async()=>structuredClone(tabs),discard:async()=>{discards++;throw Error('a measurement must never discard')}},
});
// storage.session keeps the samples; the stub also answers get(null) so pruning can be observed.
function store(live=true){
 let session={};
 const base=api(live);
 return {...base,storage:{...base.storage,session:{get:async keys=>keys===null?structuredClone(session):Object.fromEntries(keys.filter(k=>k in session).map(k=>[k,structuredClone(session[k])])),set:async value=>Object.assign(session,structuredClone(value)),remove:async keys=>{for(const k of keys)delete session[k]}}},session:()=>session};
}
const deps=(list,extra={})=>({grace:OpenGrace,protection:Protection,tabs:list,...extra});

(async()=>{
 tabs=[tab(1),tab(2),tab(3),tab(4,{pinned:true}),tab(5,{url:'chrome://settings'})];
 db={autoDiscardConfig:config};
 // Without a real source the run stops with an explanation and writes nothing.
 let result=await A.run(api(false),now,deps(tabs));
 assert.deepEqual([result.status,result.plan,result.run],['unmeasurable',undefined,undefined]);
 assert.match(result.reason,/Không đo được tài nguyên trên Chrome này/);
 assert.equal(db.autoDiscardRun,undefined);
 // Off, paused and unreadable settings each have their own reason and never measure.
 db={autoDiscardConfig:{...config,enabled:false}};
 assert.equal((await A.run(api(),now,deps(tabs))).status,'off');
 db={autoDiscardConfig:config,automationPaused:true};
 assert.equal((await A.run(api(),now,deps(tabs))).status,'paused');
 db={autoDiscardConfig:{enabled:'nope'}};
 assert.match((await A.run(api(),now,deps(tabs))).reason,/Cấu hình cho nghỉ theo tài nguyên không hợp lệ/);
 // "Only when the system is short of memory" is refused until a system source exists, instead of idling forever.
 db={autoDiscardConfig:{...config,lowMemoryOnly:true,lowMemoryFloor:12}};
 assert.match((await A.run(api(),now,deps(tabs))).reason,/Không đọc được bộ nhớ hệ thống/);
 assert.throws(()=>A.assertUsable({...config,lowMemoryOnly:true},{measurable:true,systemMemory:false}),/Không đọc được bộ nhớ hệ thống/);
 // A junk or failing system reading stops the run instead of pretending memory is fine.
 for(const memory of [{getInfo:async()=>({})},{getInfo:async()=>({capacityInMB:16384,availableMemoryInMB:99999})},{getInfo:async()=>{throw Error('unavailable')}}])
  assert.match((await A.run(api(),now,deps(tabs,{memory}))).reason,/dừng thay vì đoán/);
 // With plenty of memory free, the cycle does not measure at all and records nothing.
 const roomy={memory:{getInfo:async()=>({capacityInMB:16384,availableMemoryInMB:8192})}};
 result=await A.run(store(),now,deps(tabs,roomy));
 assert.deepEqual([result.status,result.plan,result.run],['waiting',undefined,undefined]);
 assert.match(result.reason,/RAM khả dụng còn 50%, chưa thấp hơn ngưỡng 12%/);
 assert.equal(db.autoDiscardRun,undefined);
 // Only a memory number under the chosen floor lets the cycle through; an explicit measurement still asks.
 assert.equal((await A.run(store(),now,deps(tabs,{memory:{getInfo:async()=>({capacityInMB:16384,availableMemoryInMB:1024})}}))).status,'measured');
 assert.equal((await A.run(store(),now,deps(tabs,roomy),{force:true})).status,'measured');
 assert.throws(()=>A.assertUsable({...config,lowMemoryOnly:true},{measurable:true}),/Không đọc được bộ nhớ hệ thống/);
 assert.equal(A.assertUsable({...config,lowMemoryOnly:true,lowMemoryFloor:12},{measurable:true,systemMemory:true}).lowMemoryFloor,12);
 // A broken protection list stops the run: candidates must never be counted on half a policy.
 db={autoDiscardConfig:config,protectedDomains:['not a domain!!']};
 assert.match((await A.run(api(),now,deps(tabs))).reason,/Danh sách bảo vệ không hợp lệ/);
 assert.deepEqual([db.autoDiscardRun,discards],[undefined,0]);
 // One run counts candidates, and the numbers are attributed to the process, not to a single tab.
 db={autoDiscardConfig:config};
 const box=store();
 result=await A.run(box,now,deps(tabs));
 assert.equal(result.status,'measured');
 assert.deepEqual([result.run.overCount,result.run.blockedCount,result.run.missed],[2,2,undefined]);
 assert.deepEqual([result.plan.candidates.map(r=>r.id),result.run.ids],[[2,1],[2,1]]);
 assert.deepEqual(Object.fromEntries(result.plan.counts.map(x=>[x.reason,x.count])),{'Dưới ngưỡng đã chọn':1,'Tab đã ghim':1});
 assert.match(A.line(result.plan.candidates[0],result.config,now),/RAM 2,1 GB · đo ngay bây giờ · nguồn: tiến trình Chrome/);
 assert.ok(Number.isFinite(db.autoDiscardRun.at));
 // The cycle waits for its own schedule, and a cycle missed while Chrome was closed is only reported.
 assert.match((await A.run(box,now+60000,deps(tabs))).reason,/Chưa đến chu kỳ đo; còn khoảng 4 phút/);
 assert.equal((await A.run(box,now+30*60000,deps(tabs))).run.missed,true);
 assert.equal((await A.run(box,now+31*60000,deps(tabs),{force:true})).run.missed,undefined);
 // Samples stay per process, hold no address, and drop the tabs that are gone.
 assert.deepEqual(Object.keys(box.session()).sort(),[A.key(1),A.key(2),A.key(3),A.key(4)].sort());
 // Each run appends one cycle, and the series stops at the longest streak the policy can ask for.
 assert.equal(box.session()[A.key(1)].series.length,3);
 assert.doesNotMatch(JSON.stringify(box.session()),/https?:|example\.com/);
 result=await A.run(box,now+40*60000,deps([tab(2),tab(1)]),{force:true});
 assert.deepEqual([result.status,result.plan.rows.map(r=>r.id)],['measured',[2,1]]);
 assert.deepEqual(Object.keys(box.session()).sort(),[A.key(1),A.key(2)].sort());
 // The stored record is a count, and a failed write is reported instead of guessed.
 assert.deepEqual(Object.keys(db.autoDiscardRun).sort(),['at','blockedCount','ids','measurable','overCount']);
 await assert.rejects(()=>A.run(api(true,{failWrite:true}),now,deps(tabs),{force:true}),/Không xác nhận được việc lưu kết quả đo/);
 const again=await A.run(store(),now,deps(tabs,{memory:{getInfo:async()=>({})}}),{force:true});
 assert.deepEqual([again.status,again.run.overCount,discards],['measured',2,0]);
 console.log('The measurement cycle stays read-only, waits, and admits every way it cannot run: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
