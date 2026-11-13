'use strict';
const WorkspaceTools=(()=>{
 function validate(list,makeId,mapping){
  if(!Array.isArray(list)||list.length>10000)throw Error('Danh sách workspace không hợp lệ.');const missing=new Map();
  return list.map(w=>{if(!w||typeof w.name!=='string'||!w.name.trim()||w.name.length>80||!Array.isArray(w.groupIds)||w.groupIds.length>10000||w.groupIds.some(id=>typeof id!=='string'||!id||id.length>256)||new Set(w.groupIds).size!==w.groupIds.length)throw Error('Workspace không hợp lệ.');const groupIds=w.groupIds.map(id=>{if(mapping.has(id))return mapping.get(id);if(!missing.has(id))missing.set(id,makeId());return missing.get(id)});return {id:makeId(),name:w.name,groupIds,createdAt:Number(w.createdAt)||Date.now()}});
 }
 return {validate};
})();
if(typeof module!=='undefined')module.exports=WorkspaceTools;
