'use strict';
const PopupOrder = (()=>{
 function visibleTabs(tabs,dashboardUrl){return tabs.filter(t=>!t.incognito&&!(dashboardUrl&&typeof t.url==='string'&&t.url.split(/[?#]/,1)[0]===dashboardUrl))}
 function stats(tabs,groups,dashboardUrl){const visible=visibleTabs(tabs,dashboardUrl);return {open:visible.length,sleeping:visible.filter(t=>t.discarded===true).length,saved:groups.reduce((n,g)=>n+(Array.isArray(g?.items)?g.items.length:0),0)}}
 function tabsByEnd(tabs,currentWindowId,dashboardUrl){
  const visible=visibleTabs(tabs,dashboardUrl);
  // Preserve the browser's window order but put the popup's window first.
  const windows=[...new Set(visible.map(t=>t.windowId))];
  const order=windows.filter(id=>id!==currentWindowId);
  if(windows.includes(currentWindowId))order.unshift(currentWindowId);
  const rank=new Map(order.map((id,i)=>[id,i]));
  return [...visible].sort((a,b)=>(rank.get(a.windowId)-rank.get(b.windowId))||((Number.isInteger(b.index)?b.index:-1)-(Number.isInteger(a.index)?a.index:-1)));
 }
 return {visibleTabs,stats,tabsByEnd};
})();
if(typeof module!=='undefined')module.exports=PopupOrder;
