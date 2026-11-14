'use strict';
// Advisory retention only: no deletion without an explicit, freshly validated selection.
const RetentionTools=(()=>{
 const trashPrefix='tabspace:trash:',batchPrefix='tabspace:batch:',limit=200,day=86400000;
 const defaults=Object.freeze({trashEnabled:false,trashDays:30,historyEnabled:false,historyDays:90});
 function validate(v){if(v===undefined)return {...defaults};if(!v||typeof v!=='object'||Array.isArray(v)||typeof v.trashEnabled!=='boolean'||typeof v.historyEnabled!=='boolean'||!Number.isInteger(v.trashDays)||v.trashDays<1||v.trashDays>3650||!Number.isInteger(v.historyDays)||v.historyDays<1||v.historyDays>3650)throw Error('Cài đặt thời hạn không hợp lệ.');return {trashEnabled:v.trashEnabled,trashDays:v.trashDays,historyEnabled:v.historyEnabled,historyDays:v.historyDays}}
 function references(runs){if(runs===undefined)return new Set();if(!Array.isArray(runs)||runs.some(r=>!r||typeof r!=='object'||typeof r.batchId!=='string'||!r.batchId))throw Error('Không xác định được lượt tự động; tạm giữ lịch sử.');return new Set(runs.map(r=>r.batchId).filter(x=>typeof x==='string'))}
 function candidate(key,value,config,now,refs){
  if(!Number.isFinite(now)||!value||typeof value!=='object'||Array.isArray(value))return null;
  if(key.startsWith(trashPrefix)){
   if(!config.trashEnabled||typeof value.id!=='string'||!value.id||value.id.length>256||key!==trashPrefix+value.id||!['item','group','workspace','session'].includes(value.type)||!value.value||typeof value.value!=='object'||!Number.isFinite(value.deletedAt)||value.deletedAt<=0||value.deletedAt>now-config.trashDays*day)return null;
   const name=value.value.name||value.value.title||value.value.url||'Không có tên';return {key,kind:'trash',at:value.deletedAt,name:typeof name==='string'?name:'Không có tên',type:value.type,closed:0,version:JSON.stringify(value)};
  }
  if(key.startsWith(batchPrefix)){
   if(!config.historyEnabled||!refs||typeof value.id!=='string'||!value.id||value.id.length>256||key!==batchPrefix+value.id||refs.has(value.id)||typeof value.source!=='string'||!Number.isFinite(value.createdAt)||value.createdAt<=0||value.createdAt>now-config.historyDays*day||!Array.isArray(value.items)||value.items.some(x=>!x||!['closed','opened','skipped'].includes(x.status)))return null;
   return {key,kind:'history',at:value.createdAt,name:value.source,type:'history',closed:value.items.filter(x=>x.status==='closed').length,version:JSON.stringify(value)};
  }
  return null;
 }
 function plan(data,now){const config=validate(data.retentionConfig);let refs=null,historyBlocked=false;try{refs=references(data.autoCloseRuns)}catch{historyBlocked=true}const items=[];for(const [key,value] of Object.entries(data)){const entry=candidate(key,value,config,now,refs);if(entry)items.push(entry)}items.sort((a,b)=>a.at-b.at||a.key.localeCompare(b.key));return {items:items.slice(0,limit),total:items.length,historyBlocked,config}}
 async function removeSelected(api,selected,configVersion,now){
  if(!Array.isArray(selected)||!selected.length||selected.length>limit||new Set(selected.map(x=>x.key)).size!==selected.length)throw Error('Hãy chọn các mục hợp lệ.');
  const all=await api.storage.local.get(null);if(JSON.stringify(all.retentionConfig??null)!==configVersion)throw Error('Thiết lập thời hạn đã thay đổi; hãy xem trước lại.');const config=validate(all.retentionConfig);let refs;try{refs=references(all.autoCloseRuns)}catch{refs=null}
  for(const item of selected){const current=candidate(item.key,all[item.key],config,now,refs);if(!current||current.version!==item.version)throw Error('Danh sách hoặc trạng thái mục đã thay đổi; hãy xem trước lại.');}
  let deleted=0,unknown=0,changed=false;
  for(const item of selected){let fresh;try{fresh=await api.storage.local.get([item.key,'retentionConfig','autoCloseRuns']);if(JSON.stringify(fresh.retentionConfig??null)!==configVersion)throw Error('changed');let refs;try{refs=references(fresh.autoCloseRuns)}catch{refs=null}const current=candidate(item.key,fresh[item.key],validate(fresh.retentionConfig),now,refs);if(!current||current.version!==item.version)throw Error('changed')}catch{changed=true;break}
   try{await api.storage.local.remove(item.key);deleted++}catch{unknown=1;break}
  }
  return {deleted,unknown,changed,notAttempted:selected.length-deleted-unknown};
 }
 return {defaults,limit,validate,references,candidate,plan,removeSelected};
})();
if(typeof module!=='undefined')module.exports=RetentionTools;
