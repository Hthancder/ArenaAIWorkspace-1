'use strict';
const OpenFilter=(()=>{
 const statuses=['all','active','pinned','audible','discarded','not-discarded'];
 function matches(tab,windowId,status){
  if(windowId!==''&&String(tab.windowId)!==windowId)return false;
  switch(status){case 'all':return true;case 'active':return !!tab.active;case 'pinned':return !!tab.pinned;case 'audible':return !!tab.audible;case 'discarded':return !!tab.discarded;case 'not-discarded':return !tab.discarded;default:return false}
 }
 function windowIds(tabs){return [...new Set(tabs.map(t=>t.windowId))]}
 return {matches,windowIds,statuses};
})();
if(typeof module!=='undefined')module.exports=OpenFilter;
