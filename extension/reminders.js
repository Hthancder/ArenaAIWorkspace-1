'use strict';
const ReminderTools=(()=>{
 const alarmName='tabspace:reminder-tick';
 function validate(schedule){
  if(schedule===undefined||schedule===null)return null;
  if(typeof schedule!=='object'||typeof schedule.enabled!=='boolean'||!Array.isArray(schedule.days)||!schedule.days.length||schedule.days.length>7||schedule.days.some(n=>!Number.isInteger(n)||n<0||n>6)||new Set(schedule.days).size!==schedule.days.length||typeof schedule.time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(schedule.time))throw Error('Lịch nhắc không hợp lệ.');
  return {enabled:schedule.enabled,days:[...schedule.days].sort((a,b)=>a-b),time:schedule.time};
 }
 function tick(presets,state,paused,now){
  const next={...(state&&typeof state==='object'&&!Array.isArray(state)?state:{})};let changed=false;
  if(paused)return {state:next,changed};
  for(const p of presets){let schedule;try{schedule=validate(p.schedule)}catch{continue}if(!schedule?.enabled||typeof p.id!=='string')continue;
   const prior=next[p.id]&&typeof next[p.id]==='object'?next[p.id]:{},entry={...prior};let dirty=false;
   if(Number.isFinite(entry.snoozeUntil)&&now>=entry.snoozeUntil){if(now-entry.snoozeUntil<60000){entry.pendingAt=now;dirty=true}delete entry.snoozeUntil;dirty=true}
   const d=new Date(now),[hour,minute]=schedule.time.split(':').map(Number),due=new Date(d.getFullYear(),d.getMonth(),d.getDate(),hour,minute,0,0),key=`${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()}-${schedule.time}`;
   if(schedule.days.includes(d.getDay())&&due.getHours()===hour&&due.getMinutes()===minute&&now>=due.getTime()&&now-due.getTime()<60000&&entry.lastDue!==key){entry.lastDue=key;dirty=true;if(!entry.pendingAt&&!entry.snoozeUntil)entry.pendingAt=now}
   if(dirty){next[p.id]=entry;changed=true}
  }
  return {state:next,changed};
 }
 return {alarmName,validate,tick};
})();
if(typeof module!=='undefined')module.exports=ReminderTools;
