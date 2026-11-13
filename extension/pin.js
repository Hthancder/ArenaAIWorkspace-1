'use strict';
const PinTools=(()=>{
 async function set(api,original,pinned){
  let current;try{current=await api.tabs.get(original.id)}catch{return {error:'Tab không còn tồn tại hoặc không truy cập được.'}}
  if(current.incognito||current.url!==original.url||current.windowId!==original.windowId||current.groupId!==original.groupId||!!current.pinned!==!!original.pinned)return {error:'Tab đã thay đổi; hãy xem lại trước khi thử.'};
  if(!!current.pinned===pinned)return {unchanged:true};
  try{const result=await api.tabs.update(original.id,{pinned});return result&&result.pinned===pinned?{}:{error:'Không xác nhận được trạng thái; hãy kiểm tra tab trong Chrome.'}}catch{return {error:'Không xác nhận được trạng thái; hãy kiểm tra tab trong Chrome.'}}
 }
 return {set};
})();
if(typeof module!=='undefined')module.exports=PinTools;
