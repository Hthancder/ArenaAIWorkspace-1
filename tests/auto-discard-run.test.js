const assert=require('node:assert/strict'),A=require('../extension/auto-discard.js'),OpenGrace=require('../extension/open-grace.js'),Protection=require('../extension/protection.js'),ReminderTools=require('../extension/reminders.js');
const now=1700000000000,bytes=megabytes=>megabytes*1048576;
let db={},tabs=[],discards=0,removed=[];
const tab=(id,extra={})=>({id,windowId:1,url:`https://example.com/${id}`,title:'Tab '+id,incognito:false,active:false,pinned:false,audible:false,discarded:false,lastAccessed:now-48*3600000,...extra});
const config={enabled:true,mode:'ask',combine:'any',resources:['memory'],thresholds:{memory:500,cpu:50,heap:200,network:20},cpuCycles:3,idleMinutes:720,maxPerRun:2,everyMinutes:5,lowMemoryOnly:false};
const info={10:{privateMemory:bytes(1400),cpu:20},11:{privateMemory:bytes(2200),cpu:30},12:{privateMemory:bytes(100),cpu:5},13:{privateMemory:bytes(900)}};
// A discard call inside the measurement run would throw: counting it proves the run never reaches that API.
// storage.session holds the series and the newest record; only the config is persisted, so a failed record
// write is reported and a restart drops the measurement instead of reviving tab ids that mean other tabs now.
function journal(box,extra={}){
 return {
  get:async keys=>keys===null?structuredClone(box):Object.fromEntries((Array.isArray(keys)?keys:Object.keys(box)).filter(k=>k in box).map(k=>[k,structuredClone(box[k])])),
  set:async value=>{if(extra.failRecord&&A.runKey in value)throw Error('quota');Object.assign(box,structuredClone(value))},
  remove:async keys=>{for(const k of Array.isArray(keys)?keys:[keys]){delete box[k];removed.push(k)}},
 };
}
const api=(live=true,extra={})=>{
 // `seed` pre-places a record so a write failure can be observed on a real record.
 const series={...(extra.seed?{[A.runKey]:{at:now,overCount:1,measurable:true,ids:[1]}}:{})};
 return {
  processes:live?{getProcessIdForTab:async id=>({1:10,2:11,3:12,4:13,5:14})[id],getProcessInfo:async ids=>Object.fromEntries(ids.map(id=>[id,info[id]]).filter(([,value])=>value))}:undefined,
  storage:{local:{get:async keys=>Array.isArray(keys)?Object.fromEntries(keys.filter(k=>k in db).map(k=>[k,structuredClone(db[k])])):structuredClone(db),set:async value=>{if(extra.failWrite)throw Error('quota');Object.assign(db,structuredClone(value))},remove:async keys=>{for(const k of Array.isArray(keys)?keys:[keys]){delete db[k];removed.push(k)}}},...(extra.noJournal?{}:{session:journal(series,extra)})},
  tabs:{query:async()=>structuredClone(tabs),discard:async()=>{discards++;throw Error('a measurement must never discard')}},
  session:()=>series,
 };
};
const store=(live=true,extra={})=>api(live,extra);
const deps=(list,extra={})=>({grace:OpenGrace,protection:Protection,tabs:list,...extra});
const record=box=>box.session()[A.runKey];
// 0.125: the hold is fail-closed, so every call site that expects an action has to hand over a way to
// ask about the room. This is that answer for cases that are not about the hold itself.
const free={isQuiet:()=>false,deferFullscreen:async()=>false};

(async()=>{
 tabs=[tab(1),tab(2),tab(3),tab(4,{pinned:true}),tab(5,{url:'chrome://settings'})];
 db={autoDiscardConfig:config};
 // Without a real source the run stops with an explanation and writes nothing.
 let result=await A.run(api(false),now,deps(tabs));
 assert.deepEqual([result.status,result.plan,result.run],['unmeasurable',undefined,undefined]);
 assert.match(result.reason,/Không đo được tài nguyên trên Chrome này/);
 assert.deepEqual([db.autoDiscardRun,removed],[undefined,[]]);
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
 // No place to keep the result means no measurement, rather than numbers that vanish on the next cycle.
 assert.match((await A.run(api(true,{noJournal:true}),now,deps(tabs))).reason,/chrome\.storage\.session không khả dụng/);
 // One run counts candidates, and the numbers are attributed to the process, not to a single tab.
 db={autoDiscardConfig:config};
 const box=store();
 result=await A.run(box,now,deps(tabs));
 assert.equal(result.status,'measured');
 assert.deepEqual([result.run.overCount,result.run.blockedCount,result.run.missed],[2,2,undefined]);
 assert.deepEqual([result.plan.candidates.map(r=>r.id),result.run.ids],[[2,1],[2,1]]);
 assert.deepEqual(Object.fromEntries(result.plan.counts.map(x=>[x.reason,x.count])),{'Dưới ngưỡng đã chọn':1,'Tab đã ghim':1});
 assert.match(A.line(result.plan.candidates[0],result.config,now),/RAM 2,1 GB · đo ngay bây giờ · nguồn: tiến trình Chrome/);
 assert.ok(Number.isFinite(record(box).at));
 // 15.4: each candidate leaves a trail of its own — ids and numbers, never an address or a title.
 assert.deepEqual(record(box).trail.map(r=>r.id),[2,1],'the trail keeps the order the cycle chose');
 assert.deepEqual(Object.keys(record(box).trail[0]).sort(),['at','id','processId','sharedTabs','source','triggered','values','windowId']);
 assert.deepEqual([record(box).trail[0].values,record(box).trail[0].triggered,record(box).trail[0].sharedTabs],[{memory:2200},['memory'],1]);
 assert.equal(record(box).trailCut,undefined,'a list the run can carry is not cut');
 assert.doesNotMatch(JSON.stringify(record(box)),/https?:|example\.com|Tab /);
 assert.deepEqual(Object.keys(record(box)).sort(),['at','blockedCount','ids','measurable','overCount','trail']);
 assert.equal(db.autoDiscardRun,undefined,'the record is not persisted');
 // The cycle waits for its own schedule, and a cycle missed while Chrome was closed is only reported.
 assert.match((await A.run(box,now+60000,deps(tabs))).reason,/Chưa đến chu kỳ đo; còn khoảng 4 phút/);
 assert.equal((await A.run(box,now+30*60000,deps(tabs))).run.missed,true);
 assert.equal((await A.run(box,now+31*60000,deps(tabs),{force:true})).run.missed,undefined);
 // Samples stay per process, hold no address, and drop the tabs that are gone.
 assert.deepEqual(Object.keys(box.session()).sort(),[A.key(1),A.key(2),A.key(3),A.key(4),A.runKey].sort());
 // Each run appends one cycle, and the series stops at the longest streak the policy can ask for.
 assert.equal(box.session()[A.key(1)].series.length,3);
 assert.doesNotMatch(JSON.stringify(box.session()),/https?:|example\.com/);
 result=await A.run(box,now+40*60000,deps([tab(2),tab(1)]),{force:true});
 assert.deepEqual([result.status,result.plan.rows.map(r=>r.id)],['measured',[2,1]]);
 assert.deepEqual(Object.keys(box.session()).sort(),[A.key(1),A.key(2),A.runKey].sort());
 // A record left in storage.local by an older build is dropped, and nothing new is written there.
 db={autoDiscardConfig:config,autoDiscardRun:{at:now-60000,overCount:1,measurable:true,ids:[1]}};
 const migrated=store();
 assert.equal((await A.run(migrated,now,deps(tabs))).status,'measured');
 assert.deepEqual([db.autoDiscardRun,record(migrated).at===now,removed.includes(A.runKey)],[undefined,true,true]);
 // A failed write is reported instead of guessed.
 db={autoDiscardConfig:config};
 await assert.rejects(()=>A.run(store(true,{failRecord:true}),now,deps(tabs),{force:true}),/Không xác nhận được việc lưu kết quả đo/);
 const noteBox=store(),again=await A.run(noteBox,now,deps(tabs,{memory:{getInfo:async()=>({})}}),{force:true});
 assert.deepEqual([again.status,again.run.overCount,discards],['measured',2,0]);
 // Hiding the card notes this measurement only; the next cycle replaces the note.
 const noted=await A.dismiss(noteBox,again.run.at);
 assert.deepEqual([noted.dismissedAt,record(noteBox).dismissedAt,A.attention(config,record(noteBox),now).dismissed],[again.run.at,again.run.at,true]);
 assert.equal((await A.dismiss(noteBox,again.run.at,true)).dismissedAt,undefined);
 assert.equal((await A.run(noteBox,now+60000,deps(tabs),{force:true})).run.dismissedAt,undefined);
 await assert.rejects(()=>A.dismiss(noteBox,again.run.at),/Lần đo đã thay đổi ở nơi khác/);
 await assert.rejects(()=>A.dismiss(store(true,{failRecord:true,seed:true}),now),/Không xác nhận được việc ẩn thẻ/);
 await assert.rejects(()=>A.dismiss(store(true,{noJournal:true}),1),/Không đọc được nơi giữ kết quả đo/);
 await assert.rejects(()=>A.dismiss(noteBox),/Không xác định được lần đo cần ẩn/);
 // A long candidate list keeps a bounded trail, so the record stays a session item and not an archive.
 db={autoDiscardConfig:{...config,maxPerRun:40}};
 const many=Array.from({length:25},(_,i)=>tab(i+1));
 const wide=api();
 wide.processes={getProcessIdForTab:async id=>10+id,getProcessInfo:async ids=>Object.fromEntries(ids.map(id=>[id,{privateMemory:bytes(1400),cpu:20}]))};
 const capped=await A.run(wide,now+20*60000,deps(many));
 assert.deepEqual([capped.run.overCount,capped.run.trail.length,capped.run.trailCut,A.maxTrail],[25,A.maxTrail,5,20]);
 assert.deepEqual(capped.run.trail.map(r=>r.id),capped.run.ids.slice(0,A.maxTrail),'the rows in front of the list survive, the rest is only counted');
 assert.deepEqual([db.autoDiscardRun,discards],[undefined,0],'a capped trail is still not persisted and still discards nothing');
 // 15.4.3: the counting plan never authorises an action; only the automatic policy plan may, and only with a human yes.
 db={autoDiscardConfig:{...config,mode:'auto'},openGraceMinutes:5};
 const autoBox=store();
 const autoRun=await A.run(autoBox,now,{tabs});
 assert.deepEqual(autoRun.action.chosen.map(r=>r.id),[2,1],'the automatic plan is the policy plan');
 // 15.2: the free window after opening is a hard gate for an unattended run, while the counting list may still name the tab.
 const guarded=await A.run(autoBox,now+11*60000,deps(tabs));
 assert.deepEqual([guarded.plan.candidates.map(r=>r.id),guarded.action.chosen.length],[[2,1],0],'a tab nobody can date is never rested unattended');
 assert.equal(autoRun.plan.chosen.length,autoRun.action.chosen.length,'both plans see the same two tabs here');
 assert.equal((await A.run(autoBox,now,deps(tabs),{force:true})).action,null,'a forced on-demand measurement authorises nothing');
 let requested=[];
 const tool={request:async(api,tab)=>{requested.push(tab.id);return {status:tab.id===2?'discarded':'not-confirmed'}}};
 assert.match((await A.apply(autoBox,autoRun,now,{discard:tool,protection:Protection,reminders:free})).reason,/chưa có xác nhận rủi ro/);
 assert.deepEqual([requested.length,db.autoDiscardAction,db.autoDiscardAction],[0,undefined,undefined],'an unacknowledged level touches no tab and writes no report');
 assert.match((await A.apply(autoBox,autoRun,now,{})).reason,/Không có đường cho nghỉ tab/);
 db.autoDiscardAck={at:now-1};
 assert.match((await A.apply(autoBox,autoRun,now+30*60000,{discard:tool,protection:Protection,reminders:free})).status,/stale/,'numbers two cycles old are not a basis for acting');
 assert.equal(requested.length,0);
 const applied=await A.apply(autoBox,autoRun,now,{discard:tool,protection:Protection,reminders:free});
 assert.deepEqual([applied.status,applied.report.counts],['applied',{requested:2,discarded:1,skipped:0,unconfirmed:1,protected:0}]);
 assert.deepEqual(requested,[2,1],'the heaviest tab is rested first, in the order the cycle chose');
 assert.deepEqual(db.autoDiscardAction.results.map(r=>[r.id,r.status]),[[2,'discarded'],[1,'unconfirmed']]);
 assert.equal(db.autoDiscardAction.status,'partial','a run whose result is unclear is reported as such');
 assert.match(A.actionLabel(db.autoDiscardAction,now).text,/1 tab không xác nhận được/);
 // The next cycle waits while a result is unclear, instead of hammering tabs nobody can account for.
 requested=[];
 assert.match((await A.apply(autoBox,autoRun,now+5*60000,{discard:tool,protection:Protection,reminders:free})).reason,/chờ 10 phút/);
 assert.deepEqual([requested.length,db.autoDiscardAction.status],[0,'partial']);
 requested=[];
 // Protection is checked again at the moment of acting, not only when the list was built.
 const loose=await A.run(autoBox,now+21*60000,{});
 assert.deepEqual(loose.action.chosen.map(r=>r.id),[2,1]);
 db.protectedDomains=['example.com'];
 const late=await A.apply(autoBox,loose,now+21*60000,{discard:tool,protection:Protection,reminders:free});
 assert.deepEqual([late.report.counts.protected,late.report.counts.requested,requested.length],[2,0,0],'a domain protected after the measurement is never discarded');
 db.protectedDomains=[];
 // A cycle that found nothing to do is a clean answer, not a reason to hold the next one back.
 db.autoDiscardAction={at:now+21*60000,status:'empty',counts:{requested:0,discarded:0,skipped:0,unconfirmed:0,protected:2},results:[]};
 const nothing=await A.apply(autoBox,{...loose,action:{chosen:[]}},now+21*60000,{discard:tool,protection:Protection,reminders:free});
 assert.deepEqual([nothing.status,db.autoDiscardAction.status],['applied','empty']);
 assert.match(A.actionLabel(db.autoDiscardAction,now+21*60000).text,/nghỉ 0 tab/);
 // A run that cannot be journaled is refused before a single tab is touched.
 const blind=store(true,{failWrite:true});
 const before=requested.length;
 assert.match((await A.apply(blind,loose,now+21*60000,{discard:tool,protection:Protection,reminders:free})).reason,/Không ghi được nhật ký/);
 assert.equal(requested.length,before,'no unrecorded automatic discard happens');
 // A tab that moved between the measurement and the action is skipped by the shared discard tool, and counted.
 db.protectedDomains=[];
 const movedBox=store();
 const moved=await A.run(movedBox,now+22*60000,deps(tabs));
 db.autoDiscardAck={at:now};
 delete db.autoDiscardAction;
 const movedRun=await A.apply(movedBox,{...moved,action:{chosen:[{tab:{id:9,windowId:1,url:'https://example.com/9'}}]}},now+22*60000,{discard:{request:async()=>({status:'skipped'})},protection:Protection,reminders:free});
 assert.deepEqual([movedRun.report.counts,movedRun.report.status],[{requested:1,discarded:0,skipped:1,unconfirmed:0,protected:0},'complete']);
 assert.match(A.actionLabel(movedRun.report,now).text,/1 tab bị bỏ qua vì đã thay đổi/);
 assert.doesNotMatch(JSON.stringify(db.autoDiscardConfig),/ack|risk/i);
 // 15.3/15.7: the unattended run yields to the settings the app already has, and holds before any tab is touched.
 const held={at:now+22*60000,status:'complete',counts:{requested:0,discarded:0,skipped:0,unconfirmed:0,protected:0},results:[]};
 const never={request:async()=>{throw Error('a held run must not reach the discard tool')}};
 const chosen=[{tab:{id:9,windowId:1,url:'https://example.com/9'}}];
 const reminders=(quiet,fullscreen)=>({isQuiet:()=>{if(quiet==='throw')throw Error('no clock');return quiet==='on'},deferFullscreen:async()=>{if(fullscreen==='throw')throw Error('no window state');return fullscreen==='on'}});
 for(const [name,rem] of [['quiet hours',reminders('on','off')],['fullscreen',reminders('off','on')],['an unreadable clock',reminders('throw','off')],['an unreadable window state',reminders('off','throw')]]){
  db.autoDiscardAction=held;
  const heldOut=await A.apply(autoBox,{...loose,action:{chosen}},now+22*60000,{discard:never,protection:Protection,reminders:rem});
  assert.deepEqual([heldOut.status,heldOut.report,db.autoDiscardAction],['waiting',undefined,held],`a hold for ${name} writes no report and no tab is rested`);
 }
 assert.match((await A.apply(autoBox,{...loose,action:{chosen}},now+22*60000,{discard:never,protection:Protection,reminders:reminders('on','off')})).reason,/giờ yên lặng/);
 assert.match((await A.apply(autoBox,{...loose,action:{chosen}},now+22*60000,{discard:never,protection:Protection,reminders:reminders('off','on')})).reason,/toàn màn hình/);
 db.autoDiscardAction=held;
 // The hold is not a blanket excuse: outside quiet hours and not fullscreen, the run acts and says what it did.
 const passed=await A.apply(autoBox,{...loose,action:{chosen}},now+22*60000,{discard:{request:async()=>({status:'discarded'})},protection:Protection,reminders:reminders('off','off')});
 assert.deepEqual([passed.status,db.autoDiscardAction.status,db.autoDiscardAction.counts.discarded],['applied','complete',1],'a free moment is not a reason to do nothing');
 db.autoDiscardAction=held;
 // 0.125: the hold is fail-closed, so a caller that never handed over the checker may not act either.
 db.autoDiscardAction=held;
 const blindHold=await A.apply(autoBox,{...loose,action:{chosen}},now+22*60000,{discard:never,protection:Protection});
 assert.deepEqual([blindHold.status,blindHold.report,db.autoDiscardAction],['waiting',undefined,held],'no checker means no discard and no report');
 assert.equal(blindHold.reason,'Không có nguồn kiểm tra giờ yên lặng và toàn màn hình nên lượt Tự động nhường; chưa tab nào bị nghỉ.');
 // Through the app's own window reader, a notification preference unlocks nothing: the hold stays.
 const fsBox=store();
 fsBox.windows={getAll:async()=>[{state:'locked-fullscreen'}]};
 db.autoDiscardAction=held;
 db.deferFullscreenNotifications=false;
 const strict=await A.apply(fsBox,{...loose,action:{chosen}},now+22*60000,{discard:never,protection:Protection,reminders:ReminderTools});
 assert.deepEqual([strict.status,strict.report,db.autoDiscardAction],['waiting',undefined,held],'a switch about deferring notifications does not unlock a discard');
 assert.equal(strict.reason,'Đang toàn màn hình hoặc không xác định được trạng thái cửa sổ; chưa tab nào bị nghỉ.');
 // The hold stops the discard and nothing else: a quiet night never makes the numbers go stale.
 const quietCycle=await A.run(store(),now+40*60000,deps(tabs,{reminders:reminders('on','on')}));
 assert.equal(quietCycle.status,'measured','quiet hours stop the automatic discard, never the measurement');
 // holdReason alone, with the real checker behind it.
 fsBox.windows={getAll:async()=>[{state:'normal'}]};
 assert.equal(await A.holdReason(fsBox,{reminders:ReminderTools},now,{}),'','a normal window with quiet hours off is a free moment');
 assert.match(await A.holdReason({},{reminders:ReminderTools},now,{}),/toàn màn hình/,'a build with no windows API is not read as permission to act');
 assert.match(await A.holdReason(fsBox,{reminders:ReminderTools},now,{quietHours:{enabled:'nope',start:'22:00',end:'07:00'}}),/giờ yên lặng/,'an unreadable quiet-hours value is treated as quiet');
 assert.equal(await A.holdReason(fsBox,{},now,{}),'Không có nguồn kiểm tra giờ yên lặng và toàn màn hình nên lượt Tự động nhường; chưa tab nào bị nghỉ.');
 delete db.deferFullscreenNotifications;
 assert.doesNotMatch(JSON.stringify(db.autoDiscardConfig),/ack|risk|quietHours/i);
 assert.deepEqual([discards,record(noteBox).at,db.autoDiscardRun],[0,now+60000,undefined],'the measurement path still discards nothing');
 console.log('The measurement cycle stays read-only, waits, and admits every way it cannot run: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
