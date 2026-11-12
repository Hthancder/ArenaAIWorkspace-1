'use strict';
const PopupOrder = (()=>{
 function tabsByEnd(tabs,currentWindowId){
  const visible=tabs.filter(t=>!t.incognito);
  // Preserve the browser's window order but put the popup's window first.
  const windows=[...new Set(visible.map(t=>t.windowId))];
  const order=windows.filter(id=>id!==currentWindowId);
  if(windows.includes(currentWindowId))order.unshift(currentWindowId);
  const rank=new Map(order.map((id,i)=>[id,i]));
  return [...visible].sort((a,b)=>(rank.get(a.windowId)-rank.get(b.windowId))||((Number.isInteger(b.index)?b.index:-1)-(Number.isInteger(a.index)?a.index:-1)));
 }
 return {tabsByEnd};
})();
if(typeof module!=='undefined')module.exports=PopupOrder;
