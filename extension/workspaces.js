'use strict';
const WorkspaceTools=(()=>{
 function validate(list,makeId,mapping){
  if(!Array.isArray(list)||list.length>10000)throw Error('Danh sách workspace không hợp lệ.');const missing=new Map();
  return list.map(w=>{if(!w||typeof w.name!=='string'||!w.name.trim()||w.name.length>80||!Array.isArray(w.groupIds)||w.groupIds.length>10000||w.groupIds.some(id=>typeof id!=='string'||!id||id.length>256)||new Set(w.groupIds).size!==w.groupIds.length)throw Error('Workspace không hợp lệ.');const groupIds=w.groupIds.map(id=>{if(mapping.has(id))return mapping.get(id);if(!missing.has(id))missing.set(id,makeId());return missing.get(id)});return {id:makeId(),name:w.name,groupIds,createdAt:Number(w.createdAt)||Date.now()}});
 }
 function transition(workspace,groups,tabs,reason){
  const byId=new Map(groups.map(g=>[g.id,g])),selected=workspace.groupIds.map(id=>byId.get(id)).filter(Boolean),urls=new Set();
  for(const group of selected)for(const item of (Array.isArray(group.items)?group.items:[]))if(typeof item.url==='string'&&/^https?:\/\//i.test(item.url))urls.add(item.url);
  const candidates=tabs.filter(t=>!t.incognito&&typeof t.url==='string'&&/^https?:\/\//i.test(t.url)&&!urls.has(t.url)).map(tab=>({tab,reason:reason(tab)||''}));
  return {groups:selected,missing:workspace.groupIds.length-selected.length,candidates};
 }
 return {validate,transition};
})();
if(typeof module!=='undefined')module.exports=WorkspaceTools;
