'use strict';
// Optional portable preferences; automation remains off after import.
const BackupOptions=(()=>{
 function exportOptions(storage,options,tools){
  const {preferences=false,sound=false,includeAudio=false,overrides=false,reminders=false}=options||{};if([preferences,sound,includeAudio,overrides,reminders].some(v=>typeof v!=='boolean')||includeAudio&&!sound)throw Error('Lựa chọn xuất không hợp lệ.');const result={};
  if(preferences)result.opening={preferences:tools.open.validate(storage.openPreferences),warningLimit:tools.limit.validate(storage.openWarningLimit)};
  if(overrides){const maps=tools.overrides.validate(storage.openOverrides),active=(name,list)=>{const ids=new Set(Array.isArray(list)?list.map(x=>x?.id):[]);return Object.fromEntries(Object.entries(maps[name]).filter(([key])=>ids.has(key)))};result.overrides={groups:active('groups',storage.groups),workspaces:active('workspaces',storage.workspaces)}}
  if(reminders){const inbox=tools.inbox.validate(storage.inboxReminder),backup=tools.backupReminder.validate(storage.backupReminder),retention=tools.retention.validate(storage.retentionConfig);result.reminders={inboxDays:inbox.days,backupDays:backup.days,trashDays:retention.trashDays,historyDays:retention.historyDays}}
  if(sound){const config=tools.sound.validate(storage.soundConfig),omitted=!!config.custom&&!includeAudio;result.sound={config:includeAudio?config:{...config,choice:config.choice==='custom'?'soft':config.choice,custom:null},customOmitted:omitted}}
  return result;
 }
 function opening(value,tools){if(!value||typeof value!=='object'||Array.isArray(value)||value.preferences===undefined||value.warningLimit===undefined)throw Error('Cài đặt mở trong file không hợp lệ.');return {openPreferences:tools.open.validate(value.preferences),openWarningLimit:tools.limit.validate(value.warningLimit)}}
 function overrides(value,backup,importedGroups,importedWorkspaces,existing,mode,tools,existingGroups=[]){
  const incoming=tools.overrides.validate(value),current=tools.overrides.validate(existing);
  if(!['merge','replace'].includes(mode)||!Array.isArray(backup.groups)||!Array.isArray(backup.workspaces)||backup.groups.length!==importedGroups.length||backup.workspaces.length!==importedWorkspaces.length)throw Error('Không ánh xạ được thiết lập riêng.');
  for(const [field,source,target] of [['groups',backup.groups,importedGroups],['workspaces',backup.workspaces,importedWorkspaces]]){
   const mapping=new Map();source.forEach((item,i)=>{if(typeof item?.id!=='string'||!item.id||mapping.has(item.id)||typeof target[i]?.id!=='string'||!target[i].id)throw Error('ID nhóm hoặc workspace trong sao lưu không hợp lệ.');mapping.set(item.id,target[i].id)});
   const result=new Map(Object.entries(current[field]));if(field==='groups'&&mode==='replace'&&[...mapping.values()].includes('inbox'))result.delete('inbox');for(const [oldId,setting] of Object.entries(incoming[field])){if(!mapping.has(oldId))throw Error('Thiết lập riêng không có đối tượng tương ứng trong file.');const newId=mapping.get(oldId);if(field==='groups'&&newId==='inbox'&&mode==='merge'&&existingGroups.some(g=>g?.id==='inbox'))continue;if(newId!=='inbox'&&result.has(newId))throw Error('ID thiết lập riêng bị trùng; chưa nhập.');result.set(newId,setting)}current[field]=Object.fromEntries(result);
  }
  return {openOverrides:tools.overrides.validate(current)};
 }
 function reminders(value,tools){
  if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Cài đặt lời nhắc trong file không hợp lệ.');
  const inbox=tools.inbox.validate({enabled:false,days:value.inboxDays,snoozeUntil:0}),backup=tools.backupReminder.validate({enabled:false,days:value.backupDays,nextAt:0,snoozeUntil:0,lastConfirmedAt:0}),retention=tools.retention.validate({trashEnabled:false,trashDays:value.trashDays,historyEnabled:false,historyDays:value.historyDays});
  return {inboxReminder:inbox,backupReminder:backup,retentionConfig:retention};
 }
 async function sound(value,tools,Context=globalThis.AudioContext,decode64=globalThis.atob){
  if(!value||typeof value!=='object'||Array.isArray(value)||typeof value.customOmitted!=='boolean'||!value.config)throw Error('Cài đặt âm trong file không hợp lệ.');const input=value.customOmitted&&value.config.choice==='custom'&&value.config.custom==null?{...value.config,choice:'soft',custom:null}:value.config;let c=tools.sound.validate(input);if(value.customOmitted&&c.custom)throw Error('Thông tin âm tùy chỉnh không nhất quán.');
  if(c.custom){if(typeof Context!=='function'||typeof decode64!=='function')throw Error('Không thể kiểm tra file âm trong Chrome; chưa nhập.');let binary;try{binary=decode64(c.custom.dataUrl.slice(c.custom.dataUrl.indexOf(',')+1))}catch{throw Error('File âm trong bản sao lưu không hợp lệ.')}if(!binary.length||binary.length>tools.sound.maxBytes)throw Error('File âm trong bản sao lưu quá lớn hoặc rỗng.');const bytes=Uint8Array.from(binary,x=>x.charCodeAt(0));let context,decoded;try{context=new Context();decoded=await context.decodeAudioData(bytes.buffer.slice(0))}catch{throw Error('Chrome không giải mã được file âm trong bản sao lưu.')}finally{try{await context?.close()}catch{}}if(!Number.isFinite(decoded?.duration)||decoded.duration<=0||decoded.duration>tools.sound.maxSeconds)throw Error('Âm trong bản sao lưu phải dài tối đa 5 giây.');c={...c,custom:{...c.custom,duration:decoded.duration}}}
  return {soundConfig:{...c,enabled:false}};
 }
 return {exportOptions,opening,overrides,reminders,sound};
})();
if(typeof module!=='undefined')module.exports=BackupOptions;
