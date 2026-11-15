'use strict';
// On-screen reminder, based on the user's own acknowledgement, not a verified download.
const BackupReminder=(()=>{
 const day=86400000,defaults=Object.freeze({enabled:false,days:30,nextAt:0,snoozeUntil:0,lastConfirmedAt:0});
 function validate(v){if(v===undefined)return {...defaults};if(!v||typeof v!=='object'||Array.isArray(v)||typeof v.enabled!=='boolean'||!Number.isInteger(v.days)||v.days<1||v.days>365||['nextAt','snoozeUntil','lastConfirmedAt'].some(k=>!Number.isFinite(v[k])||v[k]<0)||v.enabled&&v.nextAt<=0)throw Error('Thiết lập nhắc sao lưu không hợp lệ.');return {enabled:v.enabled,days:v.days,nextAt:v.nextAt,snoozeUntil:v.snoozeUntil,lastConfirmedAt:v.lastConfirmedAt}}
 function describe(raw,paused,now=Date.now()){let c;try{c=validate(raw)}catch{return {status:'invalid'}}if(!c.enabled)return {status:'disabled'};if(paused!==undefined&&paused!==false)return {status:'paused'};if(!Number.isFinite(now)||now<=0||c.lastConfirmedAt>now)return {status:'invalid'};if(c.snoozeUntil>now)return {status:'snoozed',until:c.snoozeUntil};if(now>=c.nextAt)return {status:'due',since:c.nextAt};return {status:'waiting',until:c.nextAt}}
 return {day,defaults,validate,describe};
})();
if(typeof module!=='undefined')module.exports=BackupReminder;
