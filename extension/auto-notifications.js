'use strict';
// Coalesced, privacy-preserving notification; called under the shared mutation lock.
const AutoNotifications=(()=>{
 async function deliver(api,now,reminders){
  const data=await api.storage.local.get(['autoCloseNotifications','autoCloseNoticePending','autoCloseRuns','quietHours','deferFullscreenNotifications']);
  const ids=data.autoCloseNoticePending?.ids;if(!Array.isArray(ids)||!ids.length)return;
  if(!Array.isArray(data.autoCloseRuns))return;const current=new Set(data.autoCloseRuns.filter(r=>r&&typeof r.id==='string').map(r=>r.id));if(!ids.some(id=>typeof id==='string'&&current.has(id))){await api.storage.local.set({autoCloseNoticePending:null});return}
  if(data.autoCloseNotifications!==true){await api.storage.local.set({autoCloseNoticePending:null});return}
  let quiet;try{quiet=reminders.isQuiet(data.quietHours,now)}catch{quiet=true}if(quiet||await reminders.deferFullscreen(api,data.deferFullscreenNotifications))return;
  let granted;try{granted=await api.permissions.contains({permissions:['notifications']})}catch{return}if(!granted)return;
  // Consume before emitting: ambiguous Chrome results must not be replayed.
  await api.storage.local.set({autoCloseNoticePending:null});
  try{await api.notifications.create('tabspace-auto-close',{type:'basic',iconUrl:api.runtime.getURL('reminder-icon.png'),title:'Tabspace',message:'Có kết quả dọn tự động. Mở Tabspace để kiểm tra.',silent:true})}catch{}
 }
 return {deliver};
})();
if(typeof module!=='undefined')module.exports=AutoNotifications;
