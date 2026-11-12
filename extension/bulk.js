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
 function tagPlan(groups,keys){
  const gs=new Set(selectedIds(keys,'group')),items=new Set(selectedIds(keys,'item'));const result=[];
  for(const group of groups){if(gs.has(group.id)&&group.id!=='inbox')result.push({type:'group',id:group.id,name:group.name});for(const item of group.items)if(items.has(item.id))result.push({type:'item',id:item.id,groupId:group.id,name:item.title||item.url})}return result;
 }
 function openPlan(groups,keys){
  const gs=new Set(selectedIds(keys,'group')),items=new Set(selectedIds(keys,'item')),seen=new Set(),result=[];
  for(const group of groups)for(const item of group.items){if((gs.has(group.id)||items.has(item.id))&&!seen.has(item.id)){seen.add(item.id);result.push({id:item.id,groupId:group.id,url:item.url,name:item.title||item.url})}}return result;
 }
 function applyTags(groups,plan,input,mode){
  if(!['add','remove'].includes(mode))throw Error('Thao tác tag không hợp lệ.');
  const norm=x=>x.normalize('NFKC').toLocaleLowerCase('vi');const tags=String(input||'').split(',').map(t=>t.trim().replace(/^#+/,'')).filter(Boolean);
  if(!tags.length||tags.length>50||tags.some(t=>t.length>80))throw Error('Nhập từ 1 đến 50 tag, mỗi tag tối đa 80 ký tự.');
  const unique=[...new Map(tags.map(t=>[norm(t),t])).values()],wanted=new Set(unique.map(norm));
  const copy=groups.map(g=>({...g,items:g.items.map(i=>({...i}))})),results=[];
  for(const p of plan){const group=copy.find(g=>g.id===(p.type==='group'?p.id:p.groupId));const item=p.type==='group'?group:group?.items.find(x=>x.id===p.id);if(!item){results.push({name:p.name,error:'Mục không còn tồn tại.'});continue}
   const old=Array.isArray(item.tags)?item.tags:[];let next;if(mode==='remove')next=old.filter(x=>!wanted.has(norm(x)));else{next=[...old];const seen=new Set(old.map(norm));for(const t of unique)if(!seen.has(norm(t))){next.push(t);seen.add(norm(t))}}
   if(next.length>50){results.push({name:p.name,error:'Vượt quá 50 tag; không thay đổi mục này.'});continue}item.tags=next;results.push({name:p.name});
  }return {groups:copy,results};
 }
 return {key,decode,savedPlan,trashPlan,selectedIds,tagPlan,openPlan,applyTags};
})();
if(typeof module!=='undefined')module.exports=BulkTools;
