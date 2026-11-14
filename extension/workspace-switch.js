'use strict';
// Called under the shared mutation lock. Errors after a possible side effect are returned,
// never retried automatically, so the caller can show exactly where execution stopped.
const WorkspaceSwitch=(()=>{
 const web=u=>typeof u==='string'&&/^https?:\/\//i.test(u);
 function reason(tab,base){if(!tab)return 'Không xác định được trạng thái bảo vệ';const existing=base(tab);if(existing)return existing;if(!tab||['incognito','active','pinned','audible'].some(k=>typeof tab[k]!=='boolean'))return 'Không xác định được trạng thái bảo vệ';return ''}
 function fingerprint(workspace,groups){return JSON.stringify(workspace.groupIds.map(id=>groups.find(g=>g.id===id)||null))}
 async function run(api,request,tools){
  const {workspace,workspaceGroups,sourceId,sourceVersion,closeTabs,openItems,destination,skipOpen,skipDuplicates}=request;
  if(!workspace||!Array.isArray(workspace.groupIds)||!Array.isArray(closeTabs)||!Array.isArray(openItems)||(!closeTabs.length&&!openItems.length))throw Error('Hãy chọn ít nhất một tab để xử lý.');
  if(!['current','new'].includes(destination)||typeof skipOpen!=='boolean'||typeof skipDuplicates!=='boolean')throw Error('Tùy chọn mở không hợp lệ.');
  if(new Set(closeTabs.map(t=>t.id)).size!==closeTabs.length||closeTabs.some(t=>!Number.isInteger(t.id)||!Number.isInteger(t.windowId)||!web(t.url))||openItems.some(t=>!workspace.groupIds.includes(t.groupId)||!web(t.url)))throw Error('Danh sách tab không hợp lệ.');
  if(closeTabs.length&&(!sourceId||workspace.groupIds.includes(sourceId)))throw Error('Hãy chọn nhóm lưu không thuộc workspace đích.');
  async function current(){const data=await api.storage.local.get(['workspaces','groups']);if(!Array.isArray(data.workspaces)||!Array.isArray(data.groups))throw Error('Không đọc được workspace hoặc nhóm.');const w=data.workspaces.find(x=>x.id===workspace.id);if(!w||JSON.stringify(w)!==JSON.stringify(workspace)||fingerprint(w,data.groups)!==workspaceGroups||w.groupIds.some(id=>!data.groups.some(g=>g.id===id)))throw Error('Workspace hoặc nhóm đích đã thay đổi, thiếu hoặc bị xóa.');return data}
  let data=await current(),source=data.groups.find(g=>g.id===sourceId);
  if(closeTabs.length&&(!source||JSON.stringify(source)!==sourceVersion||!Array.isArray(source.items)))throw Error('Nhóm lưu tab cũ đã thay đổi hoặc bị xóa.');
  const destUrls=new Set(workspace.groupIds.flatMap(gid=>data.groups.find(g=>g.id===gid).items.map(x=>x.url)));
  if(openItems.some(x=>!data.groups.find(g=>g.id===x.groupId)?.items.some(t=>t.id===x.id&&t.url===x.url)))throw Error('Bản lưu đích đã thay đổi; hãy xem trước lại.');
  // Preflight the planned opening before any irreversible close. It is checked again
  // during opening; Chrome can still change while the operation is in progress.
  if(openItems.length&&destination==='current'){let win;try{win=await api.windows.getCurrent()}catch{throw Error('Không đọc được cửa sổ đích; chưa đóng tab.')}if(!Number.isInteger(win?.id)||win.id<0||win.incognito!==false)throw Error('Không xác định được cửa sổ Chrome thông thường; chưa đóng tab.')}
  if(openItems.length&&skipOpen){let tabs;try{tabs=await api.tabs.query({});if(!Array.isArray(tabs)||tabs.some(t=>!t||typeof t.incognito!=='boolean'||(!t.incognito&&typeof t.url!=='string'&&typeof t.pendingUrl!=='string')))throw Error('missing tab information')}catch{throw Error('Không kiểm tra được tab đang mở; chưa đóng tab.')}}
  const entries=[];
  for(const tab of closeTabs){let fresh;try{fresh=await api.tabs.get(tab.id)}catch{throw Error('Tab được chọn đã thay đổi hoặc không còn mở.')}if(fresh.id!==tab.id||fresh.windowId!==tab.windowId||fresh.url!==tab.url||(fresh.pendingUrl&&fresh.pendingUrl!==tab.url)||reason(fresh,tools.reason)||destUrls.has(fresh.url)||await tools.protected(api,fresh.url))throw Error('Tab đã thay đổi, thuộc workspace đích hoặc được bảo vệ; hãy xem trước lại.');entries.push({tabId:tab.id,windowId:tab.windowId,url:tab.url,item:{id:tools.id(),url:tab.url,title:fresh.title||tab.url,createdAt:Date.now(),tags:[]}})}
  if(entries.length){
   await tools.recovery(api,entries,Date.now(),tools.id);
   data=await current();source=data.groups.find(g=>g.id===sourceId);if(!source||JSON.stringify(source)!==sourceVersion)throw Error('Nhóm lưu tab cũ đã thay đổi; chưa lưu hoặc đóng.');
   source.items.unshift(...entries.map(e=>e.item));
   try{await api.storage.local.set({groups:data.groups})}catch{return {saved:'unknown',error:'Không xác nhận được việc lưu tab cũ; chưa yêu cầu đóng. Kiểm tra nhóm trước khi thử lại.'}}
   let batch;
   try{batch=await tools.close(api,entries,'Chuyển workspace: '+workspace.name,tools.id,async t=>{await current();return !reason(t,tools.reason)&&(!t.pendingUrl||t.pendingUrl===t.url)&&!await tools.protected(api,t.url)})}
   catch{return {saved:entries.length,error:'Đã lưu tab cũ nhưng không xác nhận được trạng thái lịch sử hoặc đóng; chưa mở workspace đích. Kiểm tra lịch sử và Chrome trước khi thử lại.'}}
   const closed=batch.batch.items.filter(t=>t.status==='closed').length;
   if(batch.stopped||closed!==entries.length)return {saved:entries.length,batch:batch.batch,closed,error:'Bước đóng chưa hoàn tất hoặc không rõ; chưa mở workspace đích. Kiểm tra lịch sử và Chrome.'};
   try{await current()}catch{return {saved:entries.length,batch:batch.batch,closed,error:'Workspace hoặc nhóm đích đã thay đổi; chưa mở tab đích. Kiểm tra trước khi tiếp tục.'}}
   try{return {saved:entries.length,batch:batch.batch,closed,opened:openItems.length?await tools.open(api,openItems,destination,{skipOpen,skipDuplicates}):[]}}
   catch{return {saved:entries.length,batch:batch.batch,closed,error:'Không xác nhận được bước mở. Kiểm tra Chrome trước khi thử lại.'}}
  }
  return {saved:0,closed:0,opened:await tools.open(api,openItems,destination,{skipOpen,skipDuplicates})};
 }
 return {run,fingerprint,reason};
})();
if(typeof module!=='undefined')module.exports=WorkspaceSwitch;
