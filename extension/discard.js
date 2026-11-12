'use strict';
const DiscardTools=(()=>{
 async function request(api,original){
  const current=await api.tabs.get(original.id);
  if(current.incognito||current.active||current.pinned||current.audible||current.discarded||current.url!==original.url||current.windowId!==original.windowId)return {status:'skipped'};
  // Chrome may replace a tab during discard: trust the returned tab, not the old ID.
  const result=await api.tabs.discard(original.id);
  if(result?.discarded===true)return {status:'discarded'};
  const checkId=Number.isInteger(result?.id)?result.id:original.id;
  try{const check=await api.tabs.get(checkId);if(check.discarded===true)return {status:'discarded'};return {status:'not-confirmed'}}catch{return {status:'unknown'}}
 }
 function message(status){return status==='discarded'?'Tab đã nghỉ.':status==='skipped'?'Tab đã thay đổi hoặc được bảo vệ; không thực hiện.':'Đã gửi yêu cầu nhưng không xác nhận được trạng thái. Hãy kiểm tra danh sách tab.'}
 return {request,message};
})();
if(typeof module!=='undefined')module.exports=DiscardTools;
