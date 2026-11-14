'use strict';
const ReminderTools=(()=>{
 const alarmName='tabspace:reminder-tick';
 function pendingCount(presets,state){
  if(!Array.isArray(presets)||!state||typeof state!=='object'||Array.isArray(state))return 0;
  return presets.filter(p=>p&&typeof p.id==='string'&&p.schedule?.enabled===true&&Number.isFinite(state[p.id]?.pendingAt)&&state[p.id].pendingAt>0).length;
 }
 function validate(schedule){
  if(schedule===undefined||schedule===null)return null;
  if(typeof schedule!=='object'||typeof schedule.enabled!=='boolean'||!Array.isArray(schedule.days)||!schedule.days.length||schedule.days.length>7||schedule.days.some(n=>!Number.isInteger(n)||n<0||n>6)||new Set(schedule.days).size!==schedule.days.length||typeof schedule.time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(schedule.time))throw Error('Lịch nhắc không hợp lệ.');
  return {enabled:schedule.enabled,days:[...schedule.days].sort((a,b)=>a-b),time:schedule.time};
 }
 function validateQuiet(value){
  if(value===undefined)return {enabled:false,start:'22:00',end:'07:00'};
  if(!value||typeof value!=='object'||Array.isArray(value)||typeof value.enabled!=='boolean'||typeof value.start!=='string'||typeof value.end!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(value.start)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(value.end)||value.start===value.end)throw Error('Giờ yên lặng không hợp lệ; thông báo hệ điều hành bị tạm giữ.');
  return {enabled:value.enabled,start:value.start,end:value.end};
 }
 function isQuiet(value,now){
  const config=validateQuiet(value);if(!config.enabled)return false;const minutes=s=>Number(s.slice(0,2))*60+Number(s.slice(3));const a=minutes(config.start),b=minutes(config.end),date=new Date(now),time=date.getHours()*60+date.getMinutes();if(!Number.isFinite(time))throw Error('Không xác định được giờ máy.');return a<b?time>=a&&time<b:time>=a||time<b;
 }
 async function deferFullscreen(api,setting){
  if(setting!==undefined&&typeof setting!=='boolean')return true;
  if(setting===false)return false;
  try{const windows=await api.windows.getAll({windowTypes:['normal','popup']});if(!Array.isArray(windows)||windows.some(w=>!w||!['normal','minimized','maximized','fullscreen','locked-fullscreen'].includes(w.state)))return true;return windows.some(w=>w.state==='fullscreen'||w.state==='locked-fullscreen')}catch{return true}
 }
 function tick(presets,state,paused,now){
  const next={...(state&&typeof state==='object'&&!Array.isArray(state)?state:{})};let changed=false;
  if(paused)return {state:next,changed};
  for(const p of presets){let schedule;try{schedule=validate(p.schedule)}catch{continue}if(!schedule?.enabled||typeof p.id!=='string')continue;
   const prior=next[p.id]&&typeof next[p.id]==='object'?next[p.id]:{},entry={...prior};let dirty=false;
   if(Number.isFinite(entry.snoozeUntil)&&now>=entry.snoozeUntil){if(!entry.pendingAt){entry.pendingAt=entry.snoozeUntil;dirty=true}delete entry.snoozeUntil;dirty=true}
   const d=new Date(now),[hour,minute]=schedule.time.split(':').map(Number),due=new Date(d.getFullYear(),d.getMonth(),d.getDate(),hour,minute,0,0),key=`${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()}-${schedule.time}`;
   if(schedule.days.includes(d.getDay())&&due.getHours()===hour&&due.getMinutes()===minute&&now>=due.getTime()&&now-due.getTime()<60000&&entry.lastDue!==key){entry.lastDue=key;dirty=true;if(!entry.pendingAt&&!entry.snoozeUntil)entry.pendingAt=now}
   if(dirty){next[p.id]=entry;changed=true}
  }
  return {state:next,changed};
 }
 return {alarmName,pendingCount,validate,validateQuiet,isQuiet,deferFullscreen,tick};
})();
if(typeof module!=='undefined')module.exports=ReminderTools;
