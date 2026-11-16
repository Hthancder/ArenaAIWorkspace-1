const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),OpenGrace=require('../extension/open-grace.js'),Protection=require('../extension/protection.js');let onAlarm,onUpdated,onRemoved,runCalls=[],forgetCalls=[],order=[],failNext=false;
const chrome={runtime:{onInstalled:{addListener(){}},onStartup:{addListener(){}},getURL:()=>'chrome-extension://x/'},alarms:{get:async()=>({name:'tick'}),create:async()=>{},onAlarm:{addListener:f=>onAlarm=f}},commands:{onCommand:{addListener(){}}},permissions:{onAdded:{addListener(){}}},tabs:{query:async()=>[],onRemoved:{addListener:f=>onRemoved=f},onUpdated:{addListener:f=>onUpdated=f}},storage:{local:{get:async()=>({}),set:async()=>{}},session:{get:async()=>({}),set:async()=>{},remove:async()=>{}}}};
const AutoDiscard={run:async(api,now,deps)=>{order.push(failNext?'run-fail':'run');runCalls.push({api,now,deps});if(failNext)throw Error('storage unavailable')},forget:async(api,ids)=>{forgetCalls.push(ids);return {ok:true,removed:ids.length}}};
const ctx={chrome,importScripts(...files){order.push(...files)},console,Date,OpenGrace,Protection,ReminderTools:{alarmName:'tick',tick:()=>({changed:false,state:{}}),isQuiet:()=>true,deferFullscreen:async()=>true},AutoSnapshot:{tick:async()=>{}},MutationLock:{run:async work=>work()},AutomationPreview:{},PresetTools:{},AutoDiscard,ScheduledRehearsal:{tick:async()=>{order.push('rehearsal')}}};
vm.runInNewContext(fs.readFileSync('extension/background.js','utf8'),ctx);
const flush=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r))};
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
 // Only a real navigation drops the sample; other updates keep the streak.
 onUpdated(3,{status:'complete'});onUpdated(3,{title:'New title'});await flush();
 assert.deepEqual(forgetCalls.map(ids=>[...ids]),[]);
 onUpdated(3,{url:'https://example.com/other'});onUpdated(undefined,{url:'https://example.com/x'});await flush();
 // The array is built inside the service-worker realm, so only its ids are compared.
 assert.deepEqual(forgetCalls.map(ids=>[...ids]),[[3]]);
 console.log('The alarm measures resources through the shared entry point and never lets one failure stop the rest: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
