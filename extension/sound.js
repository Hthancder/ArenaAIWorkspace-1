'use strict';
// Dashboard-only sound; background and popup never start audio or open a player.
const SoundTools=(()=>{
 const maxBytes=1024*1024,maxSeconds=5,cooldown=5000;
 const types=new Set(['audio/wav','audio/x-wav','audio/mpeg','audio/ogg','audio/webm','audio/mp4','audio/aac','audio/flac']);
 const defaults={enabled:false,complete:false,warning:false,volume:0.35,choice:'soft',custom:null};
 function validate(value){
  if(value===undefined)return {...defaults};
  if(!value||typeof value!=='object'||Array.isArray(value)||typeof value.enabled!=='boolean'||typeof value.complete!=='boolean'||typeof value.warning!=='boolean'||!Number.isFinite(value.volume)||value.volume<0||value.volume>1||!['soft','chime','custom'].includes(value.choice))throw Error('Cấu hình âm báo không hợp lệ.');
  let custom=null;if(value.custom!==null&&value.custom!==undefined){const c=value.custom;if(!c||typeof c.name!=='string'||!c.name||c.name.length>180||!types.has(c.mime)||!Number.isFinite(c.duration)||c.duration<=0||c.duration>maxSeconds||typeof c.dataUrl!=='string'||c.dataUrl.length>Math.ceil(maxBytes*4/3)+100||!c.dataUrl.startsWith(`data:${c.mime};base64,`)||!/^data:audio\/[a-z0-9.+-]+;base64,[A-Za-z0-9+/]+={0,2}$/.test(c.dataUrl))throw Error('Âm tùy chỉnh không hợp lệ.');custom={name:c.name,mime:c.mime,duration:c.duration,dataUrl:c.dataUrl}}
  if(value.choice==='custom'&&!custom)throw Error('Chưa có âm tùy chỉnh hợp lệ.');return {enabled:value.enabled,complete:value.complete,warning:value.warning,volume:value.volume,choice:value.choice,custom};
 }
 function eventFromChange(oldRuns,newRuns){
  if(!Array.isArray(oldRuns)||!Array.isArray(newRuns))return null;const previous=new Map(oldRuns.filter(r=>r&&typeof r.id==='string').map(r=>[r.id,r]));
  for(const r of newRuns){const before=previous.get(r?.id);if(!before||before.status!=='running')continue;if(r.status==='blocked'||r.status==='uncertain')return {id:r.id,status:r.status,kind:'warning'};if(r.status==='complete'&&Number.isInteger(r.closed)&&r.closed>0)return {id:r.id,status:r.status,kind:'complete'}}return null;
 }
 async function readFile(file,Context=globalThis.AudioContext,Reader=globalThis.FileReader,AudioCtor=globalThis.Audio,URLImpl=globalThis.URL){
  if(!file||typeof file.name!=='string'||!file.name||file.name.length>180||!Number.isFinite(file.size)||file.size<=0||file.size>maxBytes||!types.has(file.type))throw Error('Chọn file âm thanh hợp lệ, tối đa 1 MB.');if(typeof Context!=='function'||typeof Reader!=='function'||typeof AudioCtor!=='function'||!URLImpl?.createObjectURL)throw Error('Chrome không hỗ trợ kiểm tra âm thanh.');
  const url=URLImpl.createObjectURL(file),media=new AudioCtor();let timer;try{const duration=await new Promise((resolve,reject)=>{media.preload='metadata';media.onloadedmetadata=()=>resolve(media.duration);media.onerror=()=>reject(Error('Chrome không đọc được thông tin âm thanh.'));timer=setTimeout(()=>reject(Error('Không đọc được thời lượng âm thanh.')),3000);media.src=url;media.load()});if(!Number.isFinite(duration)||duration<=0||duration>maxSeconds)throw Error('Âm thanh phải dài tối đa 5 giây.')}finally{clearTimeout(timer);media.onloadedmetadata=null;media.onerror=null;try{media.removeAttribute('src');media.load()}catch{}URLImpl.revokeObjectURL(url)}
  let buffer;try{buffer=await file.arrayBuffer()}catch{throw Error('Không đọc được file âm thanh.')}if(buffer.byteLength!==file.size)throw Error('File âm thanh đã thay đổi khi đọc.');let context,decoded;try{context=new Context();decoded=await context.decodeAudioData(buffer.slice(0))}catch{throw Error('Chrome không giải mã được file âm thanh.')}finally{try{await context?.close()}catch{}}
  if(!Number.isFinite(decoded?.duration)||decoded.duration<=0||decoded.duration>maxSeconds)throw Error('Âm thanh phải dài tối đa 5 giây.');
  const dataUrl=await new Promise((resolve,reject)=>{const reader=new Reader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('Không đọc được file âm thanh.'));reader.onabort=()=>reject(Error('Đã hủy đọc file âm thanh.'));reader.readAsDataURL(file)});const custom={name:file.name,mime:file.type,duration:decoded.duration,dataUrl};validate({...defaults,choice:'custom',custom});return custom;
 }
 async function play(config,api,makeAudio=src=>new Audio(src)){
  const c=validate(config),source=c.choice==='custom'?c.custom.dataUrl:api.runtime.getURL(`sounds/${c.choice}.wav`),audio=makeAudio(source);audio.volume=c.volume;audio.loop=false;let timer;
  try{await Promise.race([Promise.resolve(audio.play()),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Chrome không cho phát âm.')),2000)})])}catch(e){try{audio.pause()}catch{}throw e}finally{clearTimeout(timer)}
 }
 async function handle(api,change,locks,reminders,makeAudio,now=Date.now()){
  const event=eventFromChange(change?.oldValue,change?.newValue);if(!event||!locks||typeof locks.request!=='function')return 'ignored';
  return locks.request('tabspace:sound-event',{ifAvailable:true},async lock=>{
   if(!lock)return 'busy';let data;try{data=await api.storage.local.get(['soundConfig','soundState','autoCloseRuns','quietHours','deferFullscreenNotifications','automationPaused'])}catch{return 'unavailable'}let c;try{c=validate(data.soundConfig)}catch{return 'invalid'}
   if(!c.enabled||!c[event.kind]||data.automationPaused!==undefined&&data.automationPaused!==false)return 'disabled';
   if(!Array.isArray(data.autoCloseRuns)||!data.autoCloseRuns.some(r=>r?.id===event.id&&r.status===event.status))return 'handled';
   const previous=data.soundState;if(previous!==undefined&&(!previous||typeof previous!=='object'||typeof previous.id!=='string'||!Number.isFinite(previous.at)||previous.at>now))return 'invalid';if(previous?.id===event.id||previous&&now-previous.at<cooldown)return 'duplicate';
   let quiet;try{quiet=reminders.isQuiet(data.quietHours,now)}catch{quiet=true}if(quiet||await reminders.deferFullscreen(api,data.deferFullscreenNotifications))return 'quiet';
   let latest;try{latest=await api.storage.local.get(['soundConfig','autoCloseRuns','quietHours','deferFullscreenNotifications','automationPaused'])}catch{return 'unavailable'}if(['soundConfig','quietHours','deferFullscreenNotifications','automationPaused'].some(k=>JSON.stringify(latest[k])!==JSON.stringify(data[k]))||!Array.isArray(latest.autoCloseRuns)||!latest.autoCloseRuns.some(r=>r?.id===event.id&&r.status===event.status))return 'changed';
   try{await api.storage.local.set({soundState:{id:event.id,at:now}})}catch{return 'unavailable'}
   try{await play(c,api,makeAudio);return 'played'}catch{return 'blocked'}
  });
 }
 return {defaults,maxBytes,maxSeconds,validate,eventFromChange,readFile,play,handle};
})();
if(typeof module!=='undefined')module.exports=SoundTools;
