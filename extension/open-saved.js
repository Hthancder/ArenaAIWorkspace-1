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
    try{const win=await api.windows.create({url:fresh.url,incognito:false});if(!Number.isInteger(win?.id)||win.id<0)throw Error('Không có ID cửa sổ.');windowId=win.id;results.push({name:item.name})}catch{stopped=true;results.push({name:item.name,error:'Không xác nhận được việc tạo cửa sổ; hãy kiểm tra Chrome trước khi thử lại.'})}
   }else{
    try{const tab=await api.tabs.create({windowId,url:fresh.url,active:false});if(!Number.isInteger(tab?.id)||tab.id<0)throw Error('Không có ID tab.');results.push({name:item.name})}catch{results.push({name:item.name,error:'Không xác nhận được việc mở tab; hãy kiểm tra Chrome trước khi thử lại.'})}
   }
  }
  return results;
 }
 return {execute};
})();
if(typeof module!=='undefined')module.exports=OpenSaved;
