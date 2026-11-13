'use strict';
const OpenFilter=(()=>{
 const statuses=['all','active','pinned','audible','discarded','not-discarded'];
 const groupKey=tab=>Number.isInteger(tab.groupId)&&tab.groupId>=0&&Number.isInteger(tab.windowId)?`${tab.windowId}:${tab.groupId}`:null;
 function matches(tab,windowId,status,group='all'){
  if(windowId!==''&&String(tab.windowId)!==windowId)return false;
  const key=groupKey(tab);if(group==='ungrouped'&&key!==null)return false;if(group!=='all'&&group!=='ungrouped'&&key!==group)return false;
  switch(status){case 'all':return true;case 'active':return !!tab.active;case 'pinned':return !!tab.pinned;case 'audible':return !!tab.audible;case 'discarded':return !!tab.discarded;case 'not-discarded':return !tab.discarded;default:return false}
 }
 function windowIds(tabs){return [...new Set(tabs.map(t=>t.windowId))]}
 function groupOptions(tabs,groups){
  const seen=new Set(),options=[];for(const tab of tabs){const key=groupKey(tab);if(!key||seen.has(key))continue;seen.add(key);const info=groups.find(g=>g.id===tab.groupId&&g.windowId===tab.windowId);options.push({key,windowId:tab.windowId,title:info?.title||'Nhóm Chrome không tên'})}return options;
 }
 function order(tabs,mode){
  const collator=new Intl.Collator('vi',{numeric:true,sensitivity:'base'});const host=t=>{try{const u=new URL(t.url);return ['http:','https:'].includes(u.protocol)?u.hostname.toLowerCase():''}catch{return ''}};
  const value=t=>mode==='title'?String(t.title||t.url||''):mode==='domain'?host(t):'';
  return tabs.map((tab,i)=>({tab,i})).sort((a,b)=>{if(mode==='title'||mode==='domain'){const av=value(a.tab),bv=value(b.tab);if(!av&&bv)return 1;if(av&&!bv)return -1;const n=collator.compare(av,bv);if(n)return n}const ai=Number.isInteger(a.tab.index)?a.tab.index:Number.MAX_SAFE_INTEGER,bi=Number.isInteger(b.tab.index)?b.tab.index:Number.MAX_SAFE_INTEGER;return ai-bi||a.i-b.i}).map(x=>x.tab);
 }
 return {matches,windowIds,groupOptions,order,statuses};
})();
if(typeof module!=='undefined')module.exports=OpenFilter;
