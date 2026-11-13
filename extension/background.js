'use strict';
importScripts('mutation-lock.js','reminders.js','snapshots.js','auto-snapshot.js');
async function ensureReminderAlarm(){try{if(!await chrome.alarms.get(ReminderTools.alarmName))await chrome.alarms.create(ReminderTools.alarmName,{periodInMinutes:1})}catch(e){console.error('Cannot schedule reminder alarm',e)}}
chrome.runtime.onInstalled.addListener(()=>{void ensureReminderAlarm()});
chrome.runtime.onStartup.addListener(()=>{void (async()=>{try{await chrome.alarms.clear(ReminderTools.alarmName);await ensureReminderAlarm()}catch(e){console.error('Cannot reset reminder alarm',e)}})()});
chrome.alarms.onAlarm.addListener(alarm=>{if(alarm.name!==ReminderTools.alarmName)return;const now=Date.now();if(now-alarm.scheduledTime>=60000)return;void MutationLock.run(async()=>{
 try{
  const data=await chrome.storage.local.get(['presets','reminderState','remindersPaused','reminderNotifications','quietHours','quietReminderPending']);
  const presets=Array.isArray(data.presets)?data.presets:[],out=ReminderTools.tick(presets,data.reminderState,data.remindersPaused===true,now);
  if(out.changed)await chrome.storage.local.set({reminderState:out.state});
  const hasNew=Object.keys(out.state).some(k=>out.state[k]?.pendingAt&&!data.reminderState?.[k]?.pendingAt);
  const hasPending=presets.some(p=>p?.schedule?.enabled&&out.state[p.id]?.pendingAt);
  let quiet;try{quiet=ReminderTools.isQuiet(data.quietHours,now)}catch{quiet=true}
  const deferred=data.quietReminderPending===true;
  if(data.reminderNotifications!==true||!hasPending){if(deferred)await chrome.storage.local.set({quietReminderPending:false})}
  else if(quiet){if(hasNew&&!deferred)await chrome.storage.local.set({quietReminderPending:true})}
  else if(hasNew||deferred){
   // Consume before sending: an ambiguous notification result must not be replayed every minute.
   if(deferred)await chrome.storage.local.set({quietReminderPending:false});
   try{if(await chrome.permissions.contains({permissions:['notifications']}))await chrome.notifications.create('tabspace-reminders',{type:'basic',iconUrl:chrome.runtime.getURL('reminder-icon.png'),title:'Tabspace',message:'Có lời nhắc dọn tab. Mở Tabspace để xem và quyết định.',silent:true})}catch(e){console.error('Reminder notification unavailable',e)}
  }
 }catch(e){console.error('Reminder tick failed',e)}
 try{await AutoSnapshot.tick(chrome,now,()=>crypto.randomUUID())}catch(e){console.error('Auto snapshot tick failed',e)}
 }).catch(e=>console.error('Scheduled task skipped',e))});
void ensureReminderAlarm();
chrome.commands.onCommand.addListener(command=>{if(command==='open-dashboard')chrome.tabs.create({url:chrome.runtime.getURL('dashboard.html')})});

let reminderClickBound=false;
function bindReminderClick(){if(reminderClickBound||!chrome.notifications?.onClicked)return;chrome.notifications.onClicked.addListener(notificationId=>{if(notificationId==='tabspace-reminders')void chrome.tabs.create({url:chrome.runtime.getURL('dashboard.html?view=presets')})});reminderClickBound=true}
bindReminderClick();chrome.permissions.onAdded.addListener(added=>{if(added.permissions?.includes('notifications'))bindReminderClick()});
