'use strict';
// Popup selection is short-lived and non-destructive until the user confirms a preview.
const PopupBulk=(()=>{
 const limit=100,prefix='tabspace:popup-selection:',ttl=120000;
 function validPlan(plan){
  if(!Array.isArray(plan)||!plan.length||plan.length>limit)throw Error('Hãy chọn từ 1 đến 100 tab web.');const ids=new Set();
  return plan.map(t=>{if(!t||!Number.isSafeInteger(t.id)||t.id<0||!Number.isSafeInteger(t.windowId)||t.windowId<0||typeof t.url!=='string'||t.url.length>10000||!/^https?:\/\//i.test(t.url)||ids.has(t.id))throw Error('Lựa chọn tab không hợp lệ.');ids.add(t.id);return {id:t.id,windowId:t.windowId,url:t.url,title:typeof t.title==='string'?t.title.slice(0,300):t.url}});
 }
 function same(old,current){return !!current&&current.id===old.id&&current.incognito===false&&current.windowId===old.windowId&&current.url===old.url&&(!current.pendingUrl||current.pendingUrl===old.url)}
 function reason(tab){return tab.active?'Đang xem':tab.pinned?'Đã ghim':tab.audible?'Đang phát âm thanh':tab.discarded?'Đã nghỉ':''}
 async function preview(api,raw,protection){
  const plan=validPlan(raw),out=[];for(const original of plan){let current;try{current=await api.tabs.get(original.id)}catch{out.push({tab:original,reason:'Tab không còn tồn tại'});continue}if(!same(original,current)){out.push({tab:original,reason:'Tab đã thay đổi hoặc không còn khả dụng'});continue}const status=reason(current);if(status){out.push({tab:original,reason:status});continue}if(await protection.check(api,original.url)){out.push({tab:original,reason:'Website được bảo vệ'});continue}out.push({tab:original,reason:''})}return out;
 }
 async function sleep(api,raw,protection,discard){
  const plan=validPlan(raw),results=[];for(let i=0;i<plan.length;i++){const tab=plan[i];let fresh;try{fresh=await api.tabs.get(tab.id)}catch{results.push({tab,status:'skipped'});continue}if(!same(tab,fresh)||reason(fresh)){results.push({tab,status:'skipped'});continue}
   try{if(await protection.check(api,tab.url)){results.push({tab,status:'protected'});continue}}catch{results.push({tab,status:'unavailable'});for(const next of plan.slice(i+1))results.push({tab:next,status:'notAttempted'});break}
   let result;try{result=await discard.request(api,tab)}catch{results.push({tab,status:'unknown'});for(const next of plan.slice(i+1))results.push({tab:next,status:'notAttempted'});break}results.push({tab,status:result?.status==='discarded'?'discarded':result?.status==='skipped'?'skipped':'unknown'});if(!['discarded','skipped'].includes(result?.status)){for(const next of plan.slice(i+1))results.push({tab:next,status:'notAttempted'});break}
  }return results;
 }
 function tokenValid(token){return typeof token==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(token)}
 async function transfer(api,raw,token,now){const plan=validPlan(raw);if(!tokenValid(token)||!Number.isFinite(now)||now<=0||!api.storage?.session?.set)throw Error('Không thể chuyển lựa chọn an toàn.');await api.storage.session.set({[prefix+token]:{createdAt:now,tabs:plan}})}
 async function consume(api,token,now,tabs){
  if(!tokenValid(token)||!Number.isFinite(now)||!api.storage?.session?.get||!api.storage?.session?.remove)throw Error('Không thể đọc lựa chọn từ popup.');const key=prefix+token,data=await api.storage.session.get(key),item=data[key];await api.storage.session.remove(key);
  if(!item||!Number.isFinite(item.createdAt)||item.createdAt>now||now-item.createdAt>ttl||!Array.isArray(tabs))throw Error('Lựa chọn popup đã hết hạn hoặc không còn khả dụng.');const plan=validPlan(item.tabs),byId=new Map(tabs.map(t=>[t.id,t])),valid=plan.filter(t=>same(t,byId.get(t.id)));return {ids:valid.map(t=>t.id),tabs:valid,skipped:plan.length-valid.length};
 }
 return {limit,prefix,ttl,validPlan,same,preview,sleep,transfer,consume,tokenValid};
})();
if(typeof module!=='undefined')module.exports=PopupBulk;
