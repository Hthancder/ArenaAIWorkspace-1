'use strict';
const OpenSaved=(()=>{
 const isWeb=url=>typeof url==='string'&&/^https?:\/\//i.test(url);
 async function execute(api,plan,mode){
  if(!['current','new'].includes(mode))throw Error('Nơi mở không hợp lệ.');
  let windowId=null,stopped=false;
  if(mode==='current'){const win=await api.windows.getCurrent();if(!Number.isInteger(win?.id)||win.id<0||win.incognito)throw Error('Không xác định được cửa sổ Chrome thông thường.');windowId=win.id}
  const results=[];
  for(const item of plan){
   if(stopped){results.push({name:item.name,error:'Chưa thử mở vì không xác định được cửa sổ mới.'});continue}
   let fresh;try{const data=await api.storage.local.get('groups');fresh=(data.groups||[]).find(g=>g.id===item.groupId)?.items.find(x=>x.id===item.id)}catch{results.push({name:item.name,error:'Không đọc được bản lưu; chưa thử mở.'});continue}
   if(!fresh||fresh.url!==item.url||!isWeb(fresh.url)){results.push({name:item.name,error:'Bản lưu đã thay đổi, không còn tồn tại hoặc URL không hỗ trợ; chưa thử mở.'});continue}
   if(mode==='new'&&windowId===null){
    try{const win=await api.windows.create({url:fresh.url,incognito:false});if(!Number.isInteger(win?.id)||win.id<0)throw Error('Không có ID cửa sổ.');windowId=win.id;const first=win.tabs?.[0];results.push({name:item.name,windowId,url:fresh.url,...(Number.isInteger(first?.id)&&first.id>=0?{tabId:first.id}:{})})}catch{stopped=true;results.push({name:item.name,error:'Không xác nhận được việc tạo cửa sổ; hãy kiểm tra Chrome trước khi thử lại.'})}
   }else{
    try{const tab=await api.tabs.create({windowId,url:fresh.url,active:false});if(!Number.isInteger(tab?.id)||tab.id<0)throw Error('Không có ID tab.');results.push({name:item.name,windowId,url:fresh.url,tabId:tab.id})}catch{results.push({name:item.name,error:'Không xác nhận được việc mở tab; hãy kiểm tra Chrome trước khi thử lại.'})}
   }
  }
  return results;
 }
 async function groupOpened(api,results,title,color){
  const colors=['grey','blue','red','yellow','green','pink','purple','cyan','orange'];
  if(typeof title!=='string'||title.length>100||!colors.includes(color))throw Error('Tên hoặc màu nhóm Chrome không hợp lệ.');
  const successful=results.filter(x=>!x.error),ids=[],seen=new Set();let windowId=null,skipped=0;
  for(const item of successful){
   if(!Number.isInteger(item.tabId)||!Number.isInteger(item.windowId)||seen.has(item.tabId)){skipped++;continue}seen.add(item.tabId);
   try{const tab=await api.tabs.get(item.tabId);if(tab.id!==item.tabId||tab.incognito||tab.pinned||tab.url!==item.url||tab.windowId!==item.windowId||(tab.groupId>=0)||(windowId!==null&&windowId!==tab.windowId)){skipped++;continue}windowId=tab.windowId;ids.push(tab.id)}catch{skipped++}
  }
  if(!ids.length)return {message:'Không có tab mới nào đủ điều kiện để tạo nhóm Chrome.',skipped};
  let groupId;try{groupId=await api.tabs.group({tabIds:ids,createProperties:{windowId}});if(!Number.isInteger(groupId)||groupId<0)throw Error('Không có ID nhóm.')}catch{return {message:'Không xác nhận được việc tạo nhóm Chrome. Hãy kiểm tra thanh tab trước khi thử lại.',skipped}}
  try{await api.tabGroups.update(groupId,{title,color});return {message:`Đã tạo nhóm Chrome cho ${ids.length} tab.${skipped?` Bỏ qua ${skipped} tab đã mở nhưng thay đổi hoặc không xác định được ID.`:''}`,skipped}}
  catch{return {message:`Đã tạo nhóm Chrome cho ${ids.length} tab nhưng không xác nhận được tên/màu; hãy kiểm tra thanh tab.${skipped?` Bỏ qua ${skipped} tab.`:''}`,skipped}}
 }
 return {execute,groupOpened};
})();
if(typeof module!=='undefined')module.exports=OpenSaved;
