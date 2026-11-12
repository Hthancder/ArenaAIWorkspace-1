'use strict';
const BulkTools=(()=>{
 function key(type,id){return JSON.stringify([type,id]);}
 function decode(key){try{const value=JSON.parse(key);return Array.isArray(value)&&value.length===2&&typeof value[0]==='string'&&typeof value[1]==='string'?value:null}catch{return null}}
 function savedPlan(groups,keys){
  const selected=keys.map(decode).filter(Boolean),groupIds=new Set(selected.filter(([type])=>type==='group').map(([,id])=>id)),itemIds=new Set(selected.filter(([type])=>type==='item').map(([,id])=>id));
  const result=[];for(const group of groups){if(groupIds.has(group.id)&&group.id!=='inbox'){result.push({type:'group',id:group.id,name:group.name+' ('+group.items.length+' tab, gồm cả tab không hiển thị)'});continue}for(const item of group.items)if(itemIds.has(item.id))result.push({type:'item',id:item.id,groupId:group.id,name:item.title||item.url})}return result;
 }
 function trashPlan(trash,keys){const ids=new Set(keys.map(decode).filter(x=>x&&x[0]==='trash').map(x=>x[1]));const rank={group:0,session:1,item:2};return trash.filter(x=>ids.has(x.id)).slice().sort((a,b)=>(rank[a.type]??3)-(rank[b.type]??3));}
 function selectedIds(keys,type){return keys.map(decode).filter(x=>x&&x[0]===type).map(x=>x[1]);}
 return {key,decode,savedPlan,trashPlan,selectedIds};
})();
if(typeof module!=='undefined')module.exports=BulkTools;
