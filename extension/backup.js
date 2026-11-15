'use strict';
const BackupTools=(()=>{
 const trashPrefix='tabspace:trash:',batchPrefix='tabspace:batch:';
 function exportData(storage){
  return {format:'tabspace-backup',version:2,exportedAt:new Date().toISOString(),groups:storage.groups||[],smartGroups:storage.smartGroups||[],workspaces:storage.workspaces||[],snapshots:storage.snapshots||[],presets:storage.presets||[],trash:Object.entries(storage).filter(([k])=>k.startsWith(trashPrefix)).map(([,v])=>v),batches:Object.entries(storage).filter(([k])=>k.startsWith(batchPrefix)).map(([,v])=>v),...(storage.appearance?{appearance:storage.appearance}:{}),...(storage.protectedDomains!==undefined?{protectedDomains:storage.protectedDomains}:{}),...(storage.protectedUrls!==undefined?{protectedUrls:storage.protectedUrls}:{})};
 }
 // IDs are renewed on import; reject ambiguity without breaking old ID-less backups.
 function checkIds(backup){
  for(const field of ['workspaces','snapshots','presets']){
   const list=backup[field];if(list===undefined||list===null)continue;if(!Array.isArray(list))throw Error('Danh sách trong bản sao lưu không hợp lệ.');const seen=new Set();
   for(const item of list){const value=item?.id;if(value===undefined||value===null)continue;if(typeof value!=='string'||!value||value.length>256)throw Error('ID trong bản sao lưu không hợp lệ.');if(seen.has(value))throw Error('ID trong danh sách '+field+' bị trùng.');seen.add(value)}
  }
 }
 function mergeGroups(existing, imported){
  if(existing.filter(g=>g.id==='inbox').length>1||imported.filter(g=>g.id==='inbox').length>1)throw Error('Có nhiều Hộp để sau; không thể nhập an toàn.');
  const result=existing.slice(),old=result.findIndex(g=>g.id==='inbox');
  for(const group of imported){if(group.id==='inbox'&&old>=0){const current=result[old];result[old]={...current,items:[...current.items,...group.items]}}else result.push(group)}
  return result;
 }
 function extras(backup, importedGroups, makeId, validateGroups, validateSessions){
  if(backup.version===1){
   const groupMap=new Map(),itemIds=new Set();
   function checkId(value,seen){if(value===undefined||value===null)return false;if(typeof value!=='string'||!value||value.length>256)throw Error('ID trong bản sao lưu không hợp lệ.');if(seen.has(value))throw Error('ID nhóm hoặc tab bị trùng.');return true}
   backup.groups.forEach((g,i)=>{if(checkId(g.id,groupMap))groupMap.set(g.id,importedGroups[i].id);for(const item of g.items)if(checkId(item.id,itemIds))itemIds.add(item.id)});
   return {records:{},groupMap,trashCount:0,batchCount:0};
  }
  if(backup.version!==2||!Array.isArray(backup.trash)||!Array.isArray(backup.batches)||backup.trash.length>10000||backup.batches.length>10000)throw Error('Dữ liệu thùng rác hoặc lịch sử không hợp lệ.');
  const groupMap=new Map(),itemMap=new Map();
  function mapId(map,oldId,newId){if(typeof oldId!=='string'||!oldId)throw Error('Thiếu ID trong bản sao lưu.');if(map.has(oldId)&&newId&&map.get(oldId)!==newId)throw Error('ID nhóm hoặc tab bị trùng.');if(!map.has(oldId))map.set(oldId,newId||makeId());return map.get(oldId)}
  backup.groups.forEach((g,i)=>{mapId(groupMap,g.id,importedGroups[i].id);g.items.forEach((x,j)=>mapId(itemMap,x.id,importedGroups[i].items[j].id))});
  // Preallocate IDs for deleted groups so deleted tabs can reference them regardless of order.
  for(const t of backup.trash)if(t?.type==='group'){if(t.value?.id==='inbox')throw Error('Hộp để sau không thể nằm trong thùng rác.');mapId(groupMap,t.value?.id)}
  const records={};
  for(const t of backup.trash){
   if(!t||!['group','item','session','workspace'].includes(t.type)||!t.value)throw Error('Mục thùng rác không hợp lệ.');
   let value,groupId=null;
   if(t.type==='group'){
    value=validateGroups({format:'tabspace-backup',version:1,groups:[t.value]})[0];value.id=mapId(groupMap,t.value.id);
    t.value.items.forEach((x,i)=>{value.items[i].id=mapId(itemMap,x.id)});
   }else if(t.type==='item'){
    value=validateGroups({format:'tabspace-backup',version:1,groups:[{name:'Temp',items:[t.value]}]})[0].items[0];value.id=mapId(itemMap,t.value.id);groupId=typeof t.groupId==='string'?groupMap.get(t.groupId)||null:null;
   }else if(t.type==='session')value=validateSessions([t.value])[0];else{const tools=typeof module!=='undefined'?require('./workspaces.js'):WorkspaceTools;value=tools.validate([t.value],makeId,groupMap)[0]}
   const key=makeId();records[trashPrefix+key]={id:key,type:t.type,value,groupId,index:Number.isSafeInteger(t.index)&&t.index>=0?t.index:0,deletedAt:Number(t.deletedAt)||Date.now()};
  }
  const allowed=new Set(['queued','closing','closed','close_failed','skipped','opening','opened','open_failed']);
  for(const b of backup.batches){if(!b||typeof b.source!=='string'||!Array.isArray(b.items)||b.items.length>100000)throw Error('Lịch sử dọn không hợp lệ.');const items=b.items.map(x=>{if(!x||typeof x.title!=='string'||typeof x.url!=='string'||!/^https?:\/\//i.test(x.url)||!allowed.has(x.status))throw Error('Tab trong lịch sử không hợp lệ.');if(x.pinned!==undefined&&typeof x.pinned!=='boolean')throw Error('Trạng thái ghim trong lịch sử không hợp lệ.');if(x.groupUnavailable!==undefined&&typeof x.groupUnavailable!=='boolean')throw Error('Trạng thái nhóm trong lịch sử không hợp lệ.');const tools=typeof module!=='undefined'?require('./batches.js'):BatchTools;const chromeGroup=x.chromeGroup===undefined?undefined:tools.validateGroup(x.chromeGroup);if(chromeGroup&&(x.pinned===true||x.groupUnavailable===true))throw Error('Thông tin nhóm Chrome không nhất quán.');return {title:x.title,url:x.url,status:x.status,...(x.pinned!==undefined?{pinned:x.pinned}:{}),...(chromeGroup?{chromeGroup}:{}),...(x.groupUnavailable!==undefined?{groupUnavailable:x.groupUnavailable}:{})}});const key=makeId();records[batchPrefix+key]={id:key,source:b.source,createdAt:Number(b.createdAt)||Date.now(),items,imported:true};}
  return {records,groupMap,trashCount:backup.trash.length,batchCount:backup.batches.length};
 }
 return {exportData,extras,mergeGroups,checkIds};
})();
if(typeof module!=='undefined')module.exports=BackupTools;
