'use strict';
// Repair only references: never move groups, restore trash, open or close tabs.
const ReferenceAudit=(()=>{
 function inspect(data){
  const groups=data.groups??[],workspaces=data.workspaces??[],presets=data.presets??[];
  if(!Array.isArray(groups)||!Array.isArray(workspaces)||!Array.isArray(presets))throw Error('Không đọc được danh sách nhóm, workspace hoặc preset.');
  const groupIds=new Set();for(const g of groups){if(!g||typeof g.id!=='string'||!g.id||groupIds.has(g.id)||typeof g.name!=='string'||g.id.length>256)throw Error('Danh sách nhóm không hợp lệ.');groupIds.add(g.id)}
  const refs=new Map(),workspaceIds=new Set(),presetIds=new Set();
  function ref(id){const key=id===null?'missing-target':JSON.stringify(['group',id]);if(!refs.has(key))refs.set(key,{key,id,workspaceNames:[],presetNames:[],trashNames:[]});return refs.get(key)}
  for(const w of workspaces){if(!w||typeof w.id!=='string'||!w.id||workspaceIds.has(w.id)||typeof w.name!=='string'||!Array.isArray(w.groupIds)||w.groupIds.some(x=>typeof x!=='string'||!x||x.length>256)||new Set(w.groupIds).size!==w.groupIds.length)throw Error('Danh sách workspace không hợp lệ.');workspaceIds.add(w.id);for(const id of w.groupIds)if(!groupIds.has(id))ref(id).workspaceNames.push(w.name)}
  for(const p of presets){if(!p||typeof p.id!=='string'||!p.id||presetIds.has(p.id)||typeof p.name!=='string'||(p.groupId!=null&&(typeof p.groupId!=='string'||!p.groupId||p.groupId.length>256))||(p.schedule!=null&&(typeof p.schedule!=='object'||Array.isArray(p.schedule)||typeof p.schedule.enabled!=='boolean')))throw Error('Danh sách preset không hợp lệ.');presetIds.add(p.id);if(p.groupId==null||!groupIds.has(p.groupId))ref(p.groupId??null).presetNames.push(p.name)}
  for(const [k,t] of Object.entries(data)){if(!k.startsWith('tabspace:trash:')||t?.type!=='group'||typeof t.value?.id!=='string')continue;const entry=refs.get(JSON.stringify(['group',t.value.id]));if(entry)entry.trashNames.push(typeof t.value.name==='string'?t.value.name:'Nhóm không tên')}
  return [...refs.values()];
 }
 function repair(data,selected,mode,target){
  if(!['relink','remove'].includes(mode)||!Array.isArray(selected)||!selected.length||new Set(selected).size!==selected.length)throw Error('Hãy chọn tham chiếu hợp lệ.');const entries=inspect(data),byKey=new Map(entries.map(e=>[e.key,e]));if(selected.some(k=>!byKey.has(k)))throw Error('Tham chiếu đã thay đổi; hãy xem lại.');
  if(mode==='relink'&&(typeof target!=='string'||!(data.groups??[]).some(g=>g.id===target)))throw Error('Nhóm đích không còn tồn tại.');
  const ids=new Set(selected.map(k=>byKey.get(k).id));let workspaceCount=0,presetCount=0;
  const workspaces=(data.workspaces??[]).map(w=>{if(!w.groupIds.some(id=>ids.has(id)))return w;workspaceCount++;const next=[];for(const id of w.groupIds){if(ids.has(id)){if(mode==='relink'&&!next.includes(target))next.push(target)}else if(!next.includes(id))next.push(id)}return {...w,groupIds:next}});
  const presets=(data.presets??[]).map(p=>{if(!ids.has(p.groupId??null))return p;presetCount++;return {...p,groupId:mode==='relink'?target:null,...(p.schedule?{schedule:{...p.schedule,enabled:false}}:{})}});
  return {workspaces,presets,workspaceCount,presetCount};
 }
 return {inspect,repair};
})();
if(typeof module!=='undefined')module.exports=ReferenceAudit;
