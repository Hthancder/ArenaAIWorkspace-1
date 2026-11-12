'use strict';
const NativeGroups=(()=>{
 const colors=['grey','blue','red','yellow','green','pink','purple','cyan','orange'];
 function selectedWindows(tabs){const groups=new Map();for(const tab of tabs){if(tab.incognito)continue;if(!groups.has(tab.windowId))groups.set(tab.windowId,[]);groups.get(tab.windowId).push(tab)}return [...groups].map(([windowId,items])=>({windowId,items,eligible:items.filter(t=>!t.pinned)}));}
 async function create(api,originals,windowId,title,color){
  if(!colors.includes(color))throw Error('Màu nhóm Chrome không hợp lệ.');const valid=[],skipped=[];
  for(const original of originals){if(original.incognito||original.windowId!==windowId)continue;try{const t=await api.tabs.get(original.id);if(t.incognito||t.pinned||t.windowId!==original.windowId||t.url!==original.url||t.groupId!==original.groupId){skipped.push(original.title||original.url||'Tab');continue}valid.push(t.id)}catch{skipped.push(original.title||original.url||'Tab')}}
  if(!valid.length)throw Error('Không còn tab đủ điều kiện trong cửa sổ này.');
  const groupId=await api.tabs.group({tabIds:valid,createProperties:{windowId}});let updateError='';try{await api.tabGroups.update(groupId,{title,color})}catch(e){updateError=e.message||'Chrome từ chối cập nhật.'}return {groupId,grouped:valid.length,skipped,updateError};
 }
 async function ungroup(api,originals){const valid=[],skipped=[];for(const original of originals){if(original.incognito||!(original.groupId>=0))continue;try{const t=await api.tabs.get(original.id);if(t.incognito||t.groupId!==original.groupId||t.windowId!==original.windowId||t.url!==original.url){skipped.push(original.title||original.url||'Tab');continue}valid.push(t.id)}catch{skipped.push(original.title||original.url||'Tab')}}if(!valid.length)throw Error('Không còn tab đủ điều kiện để bỏ nhóm.');await api.tabs.ungroup(valid);return {ungrouped:valid.length,skipped};}
 return {colors,selectedWindows,create,ungroup};
})();
if(typeof module!=='undefined')module.exports=NativeGroups;
