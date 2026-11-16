const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),OpenGrace=require('../extension/open-grace.js'),Protection=require('../extension/protection.js'),A=require('../extension/auto-discard.js');let onAlarm,onUpdated,onRemoved,runCalls=[],applyCalls=[],forgetCalls=[],order=[],runReturns=null,applyFails=false,failNext=false,listenerAdds=0,alarmCreates=0,timers=0,journal=[],pageDeliveries=[],journalFails=false,applyReturns=null,notifyCalls=[],notifyReturns='disabled';
const add=f=>async value=>{listenerAdds++;f(value)};
const chrome={runtime:{onInstalled:{addListener(){}},onStartup:{addListener(){}},getURL:()=>'chrome-extension://x/'},alarms:{get:async()=>({name:'tick'}),create:async()=>{alarmCreates++},onAlarm:{addListener:add(f=>onAlarm=f)}},commands:{onCommand:{addListener(){}}},permissions:{onAdded:{addListener(){}}},tabs:{query:async()=>[],onCreated:{addListener:()=>{}},onRemoved:{addListener:add(f=>onRemoved=f)},onUpdated:{addListener:add(f=>onUpdated=f)}},storage:{local:{get:async()=>({}),set:async()=>{}},session:{get:async()=>({}),set:async()=>{},remove:async()=>{}}}};
const DiscardTools={request:async()=>({status:'discarded'})};
const AutoDiscard={run:async(api,now,deps)=>{order.push(failNext?'run-fail':'run');runCalls.push({api,now,deps});if(failNext)throw Error('storage unavailable');return runReturns},apply:async(api,result,now,deps)=>{applyCalls.push({api,result,now,deps});if(applyFails)throw Error('tabs.discard unavailable');return applyReturns},resultEvent:A.resultEvent,notify:async(api,report,now,reminders)=>{notifyCalls.push({report,now,reminders});return notifyReturns},forget:async(api,ids)=>{forgetCalls.push(ids);return {ok:true,removed:ids.length}}};
const ctx={chrome,importScripts(...files){order.push(...files)},console,Date,crypto:{randomUUID:()=>'0'.repeat(64)},DiscardTools,setTimeout(){timers++},setInterval(){timers++},OpenGrace,Protection,ReminderTools:{alarmName:'tick',tick:()=>({changed:false,state:{}}),isQuiet:()=>true,deferFullscreen:async()=>true},AutoSnapshot:{tick:async()=>{}},MutationLock:{run:async work=>work()},NotificationHistory:{record:async(api,events)=>{if(journalFails)throw Error('journal full');journal.push(events)},pageEvent:()=>null,osEvent:(kind,result,at,makeId)=>({id:'os:'+makeId(),kind:'osResult',at,status:result})},PageNotice:{deliver:async(api,kind)=>{pageDeliveries.push(kind);return 'sent'}},AutomationPreview:{},PresetTools:{},AutoDiscard,ScheduledRehearsal:{tick:async()=>{order.push('rehearsal')}}};
vm.runInNewContext(fs.readFileSync('extension/background.js','utf8'),ctx);
const flush=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r))};
const listenersAfterLoad=listenerAdds;
// The real module behind the shared alarm: a minute of ticks must not become a measurement per minute.
function harness(everyMinutes){
 const now=1700000000000;
 let queries=0,reads=0,discards=0;
 const tab={id:1,windowId:1,url:'https://example.com/1',title:'Tab',incognito:false,active:false,pinned:false,audible:false,discarded:false,lastAccessed:now-48*3600000};
 const store={autoDiscardConfig:{...A.defaults,enabled:true,mode:'ask',resources:['memory'],thresholds:{...A.defaults.thresholds,memory:500},everyMinutes}};
 const journal={};
 const pick=(source,keys)=>keys===null?structuredClone(source):Object.fromEntries((Array.isArray(keys)?keys:Object.keys(source)).filter(k=>k in source).map(k=>[k,structuredClone(source[k])]));
 const api={
  processes:{getProcessIdForTab:async()=>10,getProcessInfo:async()=>{reads++;return {10:{privateMemory:1048576*1400,cpu:10}}}},
  storage:{local:{get:async keys=>pick(store,keys),set:async value=>Object.assign(store,structuredClone(value))},
   session:{get:async keys=>pick(journal,keys),set:async value=>Object.assign(journal,structuredClone(value)),remove:async keys=>{for(const k of (Array.isArray(keys)?keys:[keys]))delete journal[k]}}},
  tabs:{query:async()=>{queries++;return structuredClone([tab])},discard:async()=>{discards++;throw Error('a measurement must never discard')}},
 };
 return {api,now,counts:()=>({queries,reads,discards,store,journal})};
}
(async()=>{
 assert(order.indexOf('auto-discard.js')<order.indexOf('scheduled-rehearsal.js'),'the module is loaded before the tick that uses it');
 assert(onAlarm&&onUpdated&&onRemoved);
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();await flush();
 assert.equal(runCalls.length,1);
 assert.equal(runCalls[0].api,chrome,'the run uses the browser APIs, not a copy');
 assert.ok(Number.isFinite(runCalls[0].now));
 assert.deepEqual([runCalls[0].deps.grace,runCalls[0].deps.protection],[OpenGrace,Protection],'the shared grace window and protection lists drive the measurement');
 assert.equal(runCalls[0].deps.memory,undefined,'no system source is invented when the API is missing');
 assert.deepEqual(order.slice(-2),['run','rehearsal'],'a slow measurement cannot starve the rehearsal');
 // A failing tick is logged, not replayed, and the rest of the alarm still runs.
 failNext=true;const errors=[];const error=console.error;console.error=(...a)=>errors.push(a[0]?.message||String(a[0]));
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();await flush();console.error=error;
 assert.deepEqual([runCalls.length,order.slice(-2),errors.length],[2,['run-fail','rehearsal'],1]);
 // A tick acts only on a policy plan, and only through the discard tool the dashboard already uses.
 failNext=false;
 runReturns=null;
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.equal(applyCalls.length,0,'a run that measured nothing authorises nothing');
 runReturns={status:'measured',action:null};
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.equal(applyCalls.length,0,'the counting plan is never a licence to act');
 runReturns={status:'measured',action:{chosen:[{id:1,tab:{id:1}}]}};
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.deepEqual([applyCalls.length,applyCalls[0].api,applyCalls[0].result,applyCalls[0].deps.discard,applyCalls[0].deps.protection],[1,chrome,runReturns,DiscardTools,Protection],'the worker hands over the plan and the shared tools, nothing else');
 assert.ok(Number.isFinite(applyCalls[0].now),'and a clock the module can compare the samples against');
 assert.equal(applyCalls[0].deps.reminders,ctx.ReminderTools,'the quiet hours and the fullscreen hold come from the app-wide tools, not from a copy');
 applyFails=true;const applied=applyCalls.length,errorCount=errors.length,realError=console.error;
 console.error=(...a)=>errors.push(a[0]?.message||String(a[0]));
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();console.error=realError;applyFails=false;
 assert.deepEqual([applyCalls.length>applied,errors.length-errorCount,errors.at(-1),order.slice(-2)],[true,1,'Automatic discard run failed',['run','rehearsal']],'an action failure is admitted once and cannot starve the rest of the tick');
 // 0.127: a finished run is booked in the channels the app already has, and a run with nothing to say is not.
 applyReturns={status:'applied',report:{id:1234,at:1700000000000,status:'partial',counts:{discarded:1,unconfirmed:1}}};
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 const event=journal[0]?.[0]||{};
 assert.deepEqual([journal.length,journal[0]?.length,event.id,event.kind,event.at,event.status],[1,1,'discard:1234','result',1700000000000,'uncertain'],'the journal gets the translated event, once, in the module\'s own words');
 assert.deepEqual(pageDeliveries,['results'],'and the on-page results channel is nudged');
 applyReturns={status:'applied',report:{id:1235,at:1700000000000,status:'empty',counts:{discarded:0}}};
 journal=[];pageDeliveries=[];
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.deepEqual([journal.length,pageDeliveries.length],[0,0],'a cycle that rested nothing has no result to announce');
 applyReturns={status:'applied',report:{id:1236,at:1700000000000,status:'complete',counts:{discarded:2}}};
 journalFails=true;journal=[];pageDeliveries=[];
 const reportError=console.error,reported=[];console.error=(...a)=>reported.push(a[0]?.message||String(a[0]));
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();console.error=reportError;journalFails=false;
 assert.deepEqual([journal.length,pageDeliveries.length,reported.length],[0,1,1],'a broken journal is admitted once and never swallows the page notice');
 assert.deepEqual(order.slice(-2),['run','rehearsal'],'and reporting a run cannot starve the rest of the tick');
 // 0.128: the worker asks the module after every finished run and books only what the channel answered.
 assert.deepEqual(notifyCalls.map(c=>c.report?.id),[undefined,1234,1235,1236],'the worker asks after every run that had a plan - even one whose apply returned nothing and one that rested no tab - because the module is what decides silence');
 assert.ok(notifyCalls.every(c=>c.reminders===ctx.ReminderTools),'always with the shared quiet-hours tools, never a private copy');
 journal=[];notifyReturns='disabled';
 applyReturns={status:'applied',report:{id:1237,at:1700000000000,status:'complete',counts:{discarded:1}}};
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.deepEqual(journal.map(events=>events[0]?.kind),['result'],'a channel that was never turned on adds no OS event, only the run card');
 notifyReturns='attempted';journal=[];
 applyReturns={status:'applied',report:{id:1240,at:1700000000000,status:'complete',counts:{discarded:3}}};
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.deepEqual([journal.length,journal.at(-1)?.[0]?.kind,journal.at(-1)?.[0]?.status],[2,'osResult','attempted'],'and the send is journaled as the channel answer, not as proof the tab was closed');
 notifyReturns='held';journal=[];
 onAlarm({name:'tick',scheduledTime:Date.now()});await flush();
 assert.equal(journal.length,1,'a held notice is not journaled as a send attempt');
 notifyReturns='disabled';applyReturns=null;
 // Only a real navigation drops the sample; other updates keep the streak.
 onUpdated(3,{status:'complete'});onUpdated(3,{title:'New title'});await flush();
 assert.deepEqual(forgetCalls.map(ids=>[...ids]),[]);
 onUpdated(3,{url:'https://example.com/other'});onUpdated(undefined,{url:'https://example.com/x'});await flush();
 // The array is built inside the service-worker realm, so only its ids are compared.
 assert.deepEqual(forgetCalls.map(ids=>[...ids]),[[3]]);
 // Many ticks, one schedule: no extra listener, alarm or timer appears anywhere.
 failNext=false;
 for(let minute=0;minute<5;minute++){onAlarm({name:'tick',scheduledTime:Date.now()});await flush()}
 assert.deepEqual([listenerAdds,alarmCreates,timers],[listenersAfterLoad,0,0],'the resource cycle schedules nothing of its own');
 for(const everyMinutes of [1,60]){
  const box=harness(everyMinutes);
  for(let minute=0;minute<4;minute++)await A.run(box.api,box.now+minute*60000,{grace:OpenGrace,protection:Protection});
  const{queries,reads,discards,store,journal}=box.counts();
  // The shortest cycle measures on every tick; the longest one waits and leaves Chrome alone.
  assert.deepEqual([queries,reads,discards],[everyMinutes===1?4:1,everyMinutes===1?4:1,0],`everyMinutes ${everyMinutes}`);
  assert.equal(store.autoDiscardRun,undefined,'the record is never persisted to storage.local');
  assert.ok(Number.isFinite(journal[A.runKey].at));
  assert.deepEqual(journal[A.runKey].ids,[1]);
 }
 console.log('The alarm measures resources through the shared entry point and never lets one failure stop the rest: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
