'use strict';
importScripts('popup-bulk.js','mutation-lock.js','reminders.js','snapshots.js','auto-snapshot.js','open-grace.js','presets.js','protection.js','discard.js','auto-discard.js','automation-preview.js','scheduled-rehearsal.js','recovery-point.js','batches.js','auto-close.js','auto-notifications.js','page-notice.js','notice-state.js','notification-history.js','retention.js','retention-auto.js');
// Journal page delivery outcomes without recording site, tab, source IDs or message content.
async function deliverPageNotice(kind,now){
 const result=await PageNotice.deliver(chrome,kind,now,ReminderTools);
 try{if(typeof NotificationHistory!=='undefined'){const event=NotificationHistory.pageEvent(kind,result,now,()=>crypto.randomUUID());if(event)await NotificationHistory.record(chrome,[event])}}catch(e){console.error('Notification history unavailable',e)}
 return result;
}
async function journalOSNotice(kind,result,now){
 try{if(typeof NotificationHistory!=='undefined'){const event=NotificationHistory.osEvent(kind,result,now,()=>crypto.randomUUID());if(event)await NotificationHistory.record(chrome,[event])}}catch(e){console.error('Notification history unavailable',e)}
}
async function ensureReminderAlarm(){try{if(!await chrome.alarms.get(ReminderTools.alarmName))await chrome.alarms.create(ReminderTools.alarmName,{periodInMinutes:1})}catch(e){console.error('Cannot schedule reminder alarm',e)}}
chrome.runtime.onInstalled.addListener(()=>{void ensureReminderAlarm()});
chrome.runtime.onStartup.addListener(()=>{void (async()=>{try{await chrome.alarms.clear(ReminderTools.alarmName);await ensureReminderAlarm()}catch(e){console.error('Cannot reset reminder alarm',e)}})()});
chrome.alarms.onAlarm.addListener(alarm=>{if(typeof PopupBulk!=='undefined'&&typeof alarm?.name==='string'&&alarm.name.startsWith(PopupBulk.alarmPrefix)){void PopupBulk.expire(chrome,alarm.name).catch(e=>console.error('Popup selection cleanup failed',e));return}if(alarm.name!==ReminderTools.alarmName)return;const now=Date.now();if(!Number.isFinite(alarm.scheduledTime)||now<alarm.scheduledTime||now-alarm.scheduledTime>=60000)return;void MutationLock.run(async()=>{
 // Unknown pause state is treated as paused. Read under the same lock as UI writes.
 const pauseState=await chrome.storage.local.get('automationPaused');if(pauseState.automationPaused!==undefined&&pauseState.automationPaused!==false)return;
 try{
  const data=await chrome.storage.local.get(['presets','reminderState','remindersPaused','reminderNotifications','quietHours','quietReminderPending','deferFullscreenNotifications','noticeRead']);
  const presets=Array.isArray(data.presets)?data.presets:[],out=ReminderTools.tick(presets,data.reminderState,data.remindersPaused===true,now);
  if(out.changed){await chrome.storage.local.set({reminderState:out.state});try{if(typeof NotificationHistory!=='undefined'&&typeof NoticeState!=='undefined')await NotificationHistory.record(chrome,NotificationHistory.reminderChanges(data.reminderState,out.state,presets,NoticeState))}catch(e){console.error('Notification history unavailable',e)}}
  const hasNew=Object.keys(out.state).some(k=>out.state[k]?.pendingAt&&!data.reminderState?.[k]?.pendingAt);
  if(hasNew&&typeof PageNotice!=='undefined')try{await deliverPageNotice('reminders',Date.now())}catch(e){console.error('Page notice unavailable',e)}
  const hasPending=presets.some(p=>p?.schedule?.enabled&&out.state[p.id]?.pendingAt);
  let hasUnread=hasPending;try{if(typeof NoticeState!=='undefined')hasUnread=presets.some(p=>p?.schedule?.enabled&&out.state[p.id]?.pendingAt&&!NoticeState.isRead(data.noticeRead,NoticeState.reminderId(p.id,out.state[p.id].pendingAt)))}catch{hasUnread=false}
  let quiet;try{quiet=ReminderTools.isQuiet(data.quietHours,now)}catch{quiet=true}
  const deferred=data.quietReminderPending===true;
  if(data.reminderNotifications!==true||!hasUnread){if(deferred)await chrome.storage.local.set({quietReminderPending:false})}
  else if(hasNew||deferred){
   const hold=quiet||await ReminderTools.deferFullscreen(chrome,data.deferFullscreenNotifications);
   if(hold){if(!deferred)await chrome.storage.local.set({quietReminderPending:true})}
   else{
   // Consume before sending: an ambiguous notification result must not be replayed every minute.
   if(deferred)await chrome.storage.local.set({quietReminderPending:false});
   try{if(await chrome.permissions.contains({permissions:['notifications']})){let outcome='attempted';try{await chrome.notifications.create('tabspace-reminders',{type:'basic',iconUrl:chrome.runtime.getURL('reminder-icon.png'),title:'Tabspace',message:'Có lời nhắc dọn tab. Mở Tabspace để kiểm tra.',silent:true})}catch(e){outcome='unavailable';console.error('Reminder notification unavailable',e)}await journalOSNotice('reminders',outcome,Date.now())}}catch(e){console.error('Reminder notification unavailable',e)}
   }
  }
 }catch(e){console.error('Reminder tick failed',e)}
 try{await AutoSnapshot.tick(chrome,now,()=>crypto.randomUUID())}catch(e){console.error('Auto snapshot tick failed',e)}
 try{const autoNow=Date.now();if(autoNow>=alarm.scheduledTime&&autoNow-alarm.scheduledTime<60000&&typeof AutoClose!=='undefined'){let before;try{before=await chrome.storage.local.get('autoCloseRuns')}catch{}await AutoClose.tick(chrome,autoNow,()=>crypto.randomUUID(),{schedule:ScheduledRehearsal,reminders:ReminderTools,grace:OpenGrace,preview:AutomationPreview,presets:PresetTools,protection:Protection,batches:BatchTools,recovery:RecoveryPoint});try{const after=await chrome.storage.local.get('autoCloseRuns');if(before&&typeof NotificationHistory!=='undefined'&&typeof NoticeState!=='undefined')try{await NotificationHistory.record(chrome,NotificationHistory.resultChanges(before.autoCloseRuns,after.autoCloseRuns,NoticeState,Date.now()))}catch(e){console.error('Notification history unavailable',e)}if(before&&(before.autoCloseRuns===undefined||Array.isArray(before.autoCloseRuns))&&typeof PageNotice!=='undefined'&&Array.isArray(after.autoCloseRuns)&&after.autoCloseRuns.some(r=>r&&['complete','blocked','uncertain'].includes(r.status)&&!before.autoCloseRuns?.some(old=>old?.id===r.id)))await deliverPageNotice('results',Date.now())}catch(e){console.error('Page notice unavailable',e)}}}catch(e){console.error('Scheduled auto-close failed',e)}
 try{if(typeof AutoNotifications!=='undefined'){const outcome=await AutoNotifications.deliver(chrome,Date.now(),ReminderTools);await journalOSNotice('results',outcome,Date.now())}}catch(e){console.error('Auto-close notification failed',e)}
 try{if(typeof RetentionAuto!=='undefined')await RetentionAuto.tick(chrome,Date.now(),()=>crypto.randomUUID(),RetentionTools)}catch(e){console.error('Automatic retention failed',e)}
 try{if(typeof AutoDiscard!=='undefined'){const measured=await AutoDiscard.run(chrome,Date.now(),{grace:OpenGrace,protection:Protection,memory:chrome.system?.memory});try{if(measured?.status==='measured'&&measured.action)await AutoDiscard.apply(chrome,measured,Date.now(),{discard:DiscardTools,protection:Protection})}catch(e){console.error('Automatic discard run failed',e)}}}catch(e){console.error('Resource measurement tick failed',e)}
 try{if(typeof ScheduledRehearsal!=='undefined')await ScheduledRehearsal.tick(chrome,now,()=>crypto.randomUUID(),{reminders:ReminderTools,grace:OpenGrace,preview:AutomationPreview,presets:PresetTools,protection:Protection})}catch(e){console.error('Scheduled rehearsal failed',e)}
 }).catch(e=>console.error('Scheduled task skipped',e))});
void ensureReminderAlarm();
if(typeof PopupBulk!=='undefined')void PopupBulk.cleanupExpired(chrome,Date.now()).catch(e=>console.error('Popup selection cleanup failed',e));
chrome.commands.onCommand.addListener(command=>{if(command==='open-dashboard')chrome.tabs.create({url:chrome.runtime.getURL('dashboard.html')})});

let reminderClickBound=false;
function bindReminderClick(){if(reminderClickBound||!chrome.notifications?.onClicked)return;chrome.notifications.onClicked.addListener(notificationId=>{if(notificationId==='tabspace-reminders'||notificationId==='tabspace-auto-close')void chrome.tabs.create({url:chrome.runtime.getURL('dashboard.html?view=presets')})});reminderClickBound=true}
bindReminderClick();chrome.permissions.onAdded.addListener(added=>{if(added.permissions?.includes('notifications'))bindReminderClick()});

// Serialize refreshes so a slow earlier read cannot overwrite a newer badge state.
let badgeRefresh=Promise.resolve();
function refreshReminderBadge(){
 if(!chrome.action?.setBadgeText)return;
 badgeRefresh=badgeRefresh.catch(()=>{}).then(async()=>{const data=await chrome.storage.local.get(['presets','reminderState','reminderBadgeEnabled']);const count=data.reminderBadgeEnabled===true?ReminderTools.pendingCount(data.presets,data.reminderState):0;await chrome.action.setBadgeText({text:count?(count>99?'99+':String(count)):''})}).catch(e=>console.error('Cannot update reminder badge',e));
}
chrome.storage?.onChanged?.addListener((changes,area)=>{if(area==='local'&&(changes.presets||changes.reminderState||changes.reminderBadgeEnabled))refreshReminderBadge()});
refreshReminderBadge();

// Keep creation/removal for one tab ordered even when storage operations overlap.
const openGraceQueue=new Map();
function queueOpenGrace(id,work){const prior=openGraceQueue.get(id)||Promise.resolve(),next=prior.catch(()=>{}).then(work);openGraceQueue.set(id,next);void next.catch(()=>{}).finally(()=>{if(openGraceQueue.get(id)===next)openGraceQueue.delete(id)})}
chrome.tabs?.onCreated?.addListener(tab=>{const now=Date.now();if(Number.isInteger(tab?.id))queueOpenGrace(tab.id,()=>OpenGrace.created(chrome,tab,now))});
chrome.tabs?.onRemoved?.addListener(id=>{if(Number.isInteger(id))queueOpenGrace(id,()=>OpenGrace.removed(chrome,id))});
// A navigation makes the previous sample meaningless: drop it instead of charging the new page with it.
chrome.tabs?.onUpdated?.addListener((id,changeInfo)=>{if(typeof AutoDiscard!=='undefined'&&Number.isInteger(id)&&typeof changeInfo?.url==='string')void AutoDiscard.forget(chrome,[id]).catch(()=>{})});

// On service-worker startup, conservatively start a full grace period for unknown tabs.
if(typeof OpenGrace!=='undefined')void OpenGrace.seed(chrome).catch(()=>{});
