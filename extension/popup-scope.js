'use strict';
// Build a selection atomically; never replace a stale selected tab or silently truncate.
const PopupScope=(()=>{
 async function select(api,oldSelection,origin,scope,dashboardUrl,bulk){
  if(!(oldSelection instanceof Map)||!origin||!['window','all'].includes(scope))throw Error('Lựa chọn không hợp lệ.');
  const [active,all]=await Promise.all([api.tabs.query({active:true,currentWindow:true}),api.tabs.query({})]);const current=active?.[0];
  if(!current||current.id!==origin.id||current.windowId!==origin.windowId||current.incognito!==false||current.url!==origin.url||(current.pendingUrl&&current.pendingUrl!==origin.url))throw Error('Tab hiện tại đã thay đổi; mở lại popup trước khi chọn.');if(!Array.isArray(all))throw Error('Không đọc được danh sách tab.');
  const candidates=all.filter(t=>t.incognito===false&&(scope==='all'||t.windowId===origin.windowId)&&Number.isSafeInteger(t.id)&&t.id>=0&&Number.isSafeInteger(t.windowId)&&t.windowId>=0&&typeof t.url==='string'&&t.url.length<=10000&&/^https?:\/\//i.test(t.url)&&(!t.pendingUrl||t.pendingUrl===t.url)&&t.url.split(/[?#]/,1)[0]!==dashboardUrl);
  const next=new Map(oldSelection);let added=0;for(const t of candidates){if(next.has(t.id)){if(!bulk.same(next.get(t.id),t))throw Error('Một tab đã chọn đã thay đổi; bỏ chọn rồi chọn lại trước.');continue}next.set(t.id,{id:t.id,windowId:t.windowId,url:t.url,title:t.title||t.url});added++}
  if(next.size>bulk.limit)throw Error(`Cần ${next.size} tab, vượt giới hạn ${bulk.limit}; không thay đổi lựa chọn. Hãy chọn ít hơn hoặc dùng trang quản lý.`);
  return {selection:next,added,matched:candidates.length};
 }
 return {select};
})();
if(typeof module!=='undefined')module.exports=PopupScope;
