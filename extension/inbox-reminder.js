'use strict';
// On-screen suggestion only; never opens, moves or deletes data.
const InboxReminder=(()=>{
 const day=86400000,defaults=Object.freeze({enabled:false,days:7,snoozeUntil:0});
 function validate(value){if(value===undefined)return {...defaults};if(!value||typeof value!=='object'||Array.isArray(value)||typeof value.enabled!=='boolean'||!Number.isInteger(value.days)||value.days<1||value.days>365||!Number.isFinite(value.snoozeUntil)||value.snoozeUntil<0)throw Error('Thiết lập nhắc phân loại không hợp lệ.');return {enabled:value.enabled,days:value.days,snoozeUntil:value.snoozeUntil}}
 function describe(value,groups,paused,now=Date.now()){
  let c;try{c=validate(value)}catch{return {status:'invalid',count:0}}if(!c.enabled)return {status:'disabled',count:0};if(paused!==undefined&&paused!==false)return {status:'paused',count:0};if(!Array.isArray(groups)||!Number.isFinite(now)||now<=0)return {status:'invalid',count:0};
  const inboxes=groups.filter(g=>g?.id==='inbox');if(inboxes.length>1||inboxes.length&&(!Array.isArray(inboxes[0].items)))return {status:'invalid',count:0};const items=inboxes[0]?.items||[];let count=0,unknown=0;for(const item of items){const at=item?.createdAt;if(!Number.isFinite(at)||at<=0||at>now){unknown++;continue}if(now-at>=c.days*day)count++}if(c.snoozeUntil>now)return {status:'snoozed',count,unknown,until:c.snoozeUntil};return {status:count?'due':'waiting',count,unknown};
 }
 return {day,defaults,validate,describe};
})();
if(typeof module!=='undefined')module.exports=InboxReminder;
