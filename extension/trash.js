'use strict';
const TrashTools = (()=>{
 const prefix='tabspace:trash:';
 async function move(api,type,objectId,groupId,makeId){
   const key=type==='session'?'snapshots':'groups';const data=await api.storage.local.get(key);const list=data[key]||[];
   let value,index,parent;
   if(type==='item'){parent=list.find(g=>g.id===groupId);index=parent?.items.findIndex(x=>x.id===objectId)??-1;if(index<0)throw Error('Tab đã lưu không còn tồn tại.');value=parent.items[index]}
   else {index=list.findIndex(x=>x.id===objectId);if(index<0)throw Error('Dữ liệu không còn tồn tại.');value=list[index]}
   const entry={id:makeId(),type,value,groupId:groupId||null,index,deletedAt:Date.now()};
   // Write the recoverable copy first. If interrupted later, a duplicate is safer than loss.
   await api.storage.local.set({[prefix+entry.id]:entry});
   if(type==='item')parent.items.splice(index,1);else list.splice(index,1);
   try{await api.storage.local.set({[key]:list})}catch{throw Error('Đã lưu bản sao trong thùng rác nhưng chưa thể xóa bản gốc. Hãy kiểm tra lại.')}
   return entry;
 }
 async function restore(api,trashId){
   const trashKey=prefix+trashId,data=await api.storage.local.get([trashKey,'groups','snapshots']),entry=data[trashKey];if(!entry)throw Error('Mục trong thùng rác không còn tồn tại.');
   const key=entry.type==='session'?'snapshots':'groups',list=data[key]||[];
   if(entry.type==='item'){
     const group=list.find(x=>x.id===entry.groupId);if(!group)throw Error('Nhóm gốc không còn tồn tại. Hãy khôi phục nhóm trước.');
     if(list.some(g=>g.items.some(x=>x.id===entry.value.id)))throw Error('Bản lưu này đã tồn tại. Hãy kiểm tra dữ liệu hiện tại.');
     group.items.splice(Math.min(entry.index,group.items.length),0,entry.value);
   }else if(entry.type==='group'||entry.type==='session'){
     if(list.some(x=>x.id===entry.value.id))throw Error('Dữ liệu này đã tồn tại. Hãy kiểm tra dữ liệu hiện tại.');
     if(entry.type==='group' && entry.value.items.some(item=>list.some(g=>g.items.some(x=>x.id===item.id))))throw Error('Một tab trong nhóm đã tồn tại ở nhóm khác. Không thể tự khôi phục nhóm.');
     list.splice(Math.min(entry.index,list.length),0,entry.value);
   }else throw Error('Loại dữ liệu không hỗ trợ.');
   await api.storage.local.set({[key]:list});
   try{await api.storage.local.remove(trashKey)}catch{throw Error('Đã khôi phục dữ liệu nhưng chưa xóa được bản sao trong thùng rác.')}
 }
 return {prefix,move,restore};
})();
if(typeof module!=='undefined')module.exports=TrashTools;
