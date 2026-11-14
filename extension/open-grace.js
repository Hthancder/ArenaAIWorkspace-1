'use strict';
// Ephemeral tab IDs are only used inside Chrome's current storage.session lifetime.
// A missing or untrustworthy marker is always unknown, never considered old.
const OpenGrace=(()=>{
 const prefix='tabspace:opened:';
 function minutes(value){if(value===undefined)return 30;if(!Number.isInteger(value)||value<1||value>10080)throw Error('Thời gian miễn sau mở tab phải từ 1 đến 10080 phút.');return value}
 function key(id){return prefix+id}
 async function created(api,tab,now){if(tab?.incognito!==false||!Number.isInteger(tab.id)||tab.id<0||!Number.isInteger(tab.windowId)||tab.windowId<0||!Number.isFinite(now)||now<=0)return;if(!api.storage?.session?.set)return;await api.storage.session.set({[key(tab.id)]:{windowId:tab.windowId,openedAt:now}})}
 async function removed(api,id){if(Number.isInteger(id)&&id>=0&&api.storage?.session?.remove)await api.storage.session.remove(key(id))}
 async function read(api,tabs){if(!api.storage?.session?.get)return {};const keys=[...new Set(tabs.filter(t=>Number.isInteger(t?.id)&&t.id>=0).map(t=>key(t.id)))];try{const result=await api.storage.session.get(keys);return result&&typeof result==='object'&&!Array.isArray(result)?result:{}}catch{return {}}}
 async function seed(api,clock=()=>Date.now()){
  if(!api.tabs?.query||!api.storage?.session?.get||!api.storage?.session?.set)return;
  // Unknown tabs start a full grace period from observation, never from an assumed old ID.
  const tabs=await api.tabs.query({}),normal=tabs.filter(t=>t?.incognito===false&&Number.isInteger(t.id)&&t.id>=0&&Number.isInteger(t.windowId)&&t.windowId>=0),keys=normal.map(t=>key(t.id));
  if(!keys.length)return;const records=await api.storage.session.get(keys),now=clock();if(!Number.isFinite(now)||now<=0)throw Error('Không xác định được thời gian.');const values={};
  for(const tab of normal){const k=key(tab.id),v=records?.[k];if(!v||v.windowId!==tab.windowId||!Number.isFinite(v.openedAt)||v.openedAt<=0||v.openedAt>now)values[k]={windowId:tab.windowId,openedAt:now}}
  if(Object.keys(values).length)await api.storage.session.set(values);
 }
 function status(tab,records,now,graceMinutes){minutes(graceMinutes);const v=records?.[key(tab?.id)];if(!tab||!Number.isInteger(tab.id)||!Number.isInteger(tab.windowId)||!v||v.windowId!==tab.windowId||!Number.isFinite(v.openedAt)||v.openedAt<=0||v.openedAt>now)return 'unknown';return now-v.openedAt<graceMinutes*60000?'recent':'old'}
 return {minutes,key,created,removed,read,seed,status};
})();
if(typeof module!=='undefined')module.exports=OpenGrace;
