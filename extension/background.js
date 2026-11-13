'use strict';
importScripts('mutation-lock.js','reminders.js');
async function ensureReminderAlarm(){try{if(!await chrome.alarms.get(ReminderTools.alarmName))await chrome.alarms.create(ReminderTools.alarmName,{periodInMinutes:1})}catch(e){console.error('Cannot schedule reminder alarm',e)}}
chrome.runtime.onInstalled.addListener(()=>{void ensureReminderAlarm()});
chrome.runtime.onStartup.addListener(()=>{void (async()=>{try{await chrome.alarms.clear(ReminderTools.alarmName);await ensureReminderAlarm()}catch(e){console.error('Cannot reset reminder alarm',e)}})()});
chrome.alarms.onAlarm.addListener(alarm=>{if(alarm.name!==ReminderTools.alarmName)return;const now=Date.now();if(now-alarm.scheduledTime>=60000)return;void MutationLock.run(async()=>{const data=await chrome.storage.local.get(['presets','reminderState','remindersPaused']);const out=ReminderTools.tick(Array.isArray(data.presets)?data.presets:[],data.reminderState,data.remindersPaused===true,now);if(out.changed)await chrome.storage.local.set({reminderState:out.state})}).catch(e=>console.error('Reminder tick skipped',e))});
void ensureReminderAlarm();
chrome.commands.onCommand.addListener(command=>{if(command==='open-dashboard')chrome.tabs.create({url:chrome.runtime.getURL('dashboard.html')})});
