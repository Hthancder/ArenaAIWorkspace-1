'use strict';
// Read-only scheduled rehearsal. The durable reservation is committed before reading tabs;
// interrupted runs are never replayed. Must be called under Tabspace's mutation lock.
const ScheduledRehearsal=(()=>{
 const limit=20;
 function validate(value){
  if(value===undefined)return {enabled:false,presetIds:[],minutes:30};
  if(!value||typeof value!=='object'||Array.isArray(value)||typeof value.enabled!=='boolean'||!Array.isArray(value.presetIds)||value.presetIds.length>1000||value.presetIds.some(x=>typeof x!=='string'||!x||x.length>256)||new Set(value.presetIds).size!==value.presetIds.length||!Number.isInteger(value.minutes)||value.minutes<1||value.minutes>10080)throw Error('Cấu hình mô phỏng theo lịch không hợp lệ.');
  return {enabled:value.enabled,presetIds:[...value.presetIds],minutes:value.minutes};
 }
 function due(schedule,now,R){const s=R.validate(schedule);if(!s?.enabled)return null;const d=new Date(now),[hour,minute]=s.time.split(':').map(Number),when=new Date(d.getFullYear(),d.getMonth(),d.getDate(),hour,minute,0,0);if(!s.days.includes(d.getDay())||when.getHours()!==hour||when.getMinutes()!==minute||now<when.getTime()||now-when.getTime()>=60000)return null;return `${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()}-${s.time}`}
 async function tick(api,now,makeId,tools){
  const data=await api.storage.local.get(['rehearsalConfig','rehearsalDue','rehearsalRuns','presets','groups','protectedDomains','protectedUrls','openGraceMinutes','automationPaused']);let config;try{config=validate(data.rehearsalConfig)}catch{return}if(!config.enabled||data.automationPaused!==undefined&&data.automationPaused!==false)return;
  if(!Array.isArray(data.presets)||!Array.isArray(data.groups)||data.rehearsalRuns!==undefined&&!Array.isArray(data.rehearsalRuns)||data.rehearsalDue!==undefined&&(!data.rehearsalDue||typeof data.rehearsalDue!=='object'||Array.isArray(data.rehearsalDue)))return;
  const history=data.rehearsalRuns||[],past=data.rehearsalDue||{};if(history.length>=limit)return;
  const duePresets=[];for(const p of data.presets){if(!p||!config.presetIds.includes(p.id))continue;let key;try{key=due(p.schedule,now,tools.reminders)}catch{continue}if(key&&past[p.id]!==key)duePresets.push({preset:p,key})}if(!duePresets.length)return;
  const id=makeId(),nextDue=Object.fromEntries(Object.entries(past));for(const entry of duePresets)Object.defineProperty(nextDue,entry.preset.id,{value:entry.key,enumerable:true,writable:true,configurable:true});
  const report={id,createdAt:now,status:'running',presets:duePresets.map(x=>x.preset.name),reason:'Đang phân tích hoặc đã gián đoạn; không tự chạy lại.',total:0,eligible:0,rows:[]};
  const reserved=JSON.stringify(report);await api.storage.local.set({rehearsalDue:nextDue,rehearsalRuns:[report,...history]});
  try{
   const tabs=await api.tabs.query({}),fullscreen=await tools.reminders.deferFullscreen(api,true),records=await tools.grace.read(api,tabs),openedMinutes=tools.grace.minutes(data.openGraceMinutes);
   const results=tools.preview.run({presets:duePresets.map(x=>x.preset),groups:data.groups,tabs,domains:data.protectedDomains,urls:data.protectedUrls,now,graceMinutes:config.minutes,openedMinutes,openRecords:records,paused:false,fullscreen},tools.presets,tools.protection,tools.grace);
   report.status='complete';report.reason='';report.total=results.length;report.eligible=results.filter(x=>x.eligible).length;report.rows=results.slice(0,200).map(r=>({title:r.tab.title||r.tab.url,url:r.tab.url,matches:r.matches,winner:r.winner,group:r.group,reason:r.reason,eligible:r.eligible}));
  }catch{report.status='error';report.reason='Không đọc hoặc phân tích được dữ liệu; không thay đổi tab.'}
  // Re-read to avoid resurrecting reports deleted or changed outside the extension lock.
  const latest=await api.storage.local.get('rehearsalRuns');if(!Array.isArray(latest.rehearsalRuns))return;const i=latest.rehearsalRuns.findIndex(x=>x?.id===id&&JSON.stringify(x)===reserved);if(i<0)return;latest.rehearsalRuns[i]=report;await api.storage.local.set({rehearsalRuns:latest.rehearsalRuns});
 }
 return {limit,validate,due,tick};
})();
if(typeof module!=='undefined')module.exports=ScheduledRehearsal;
