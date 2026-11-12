'use strict';
// Independent storage key per operation; pending means the browser call's result is uncertain.
const BatchTools = (() => {
  const prefix = 'tabspace:batch:';
  async function write(api, batch){ await api.storage.local.set({[prefix+batch.id]: batch}); }
  async function closeSaved(api, entries, source, makeId, eligible){
    const batch={id:makeId(),source,createdAt:Date.now(),items:entries.map(e=>({url:e.url,title:e.item.title,status:'queued'}))};
    await write(api,batch); // No tab may be closed if the journal cannot be written.
    let stopped=false;
    for(let i=0;i<entries.length;i++){
      const e=entries[i], item=batch.items[i];
      let tab;try{tab=await api.tabs.get(e.tabId)}catch{item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      if(tab.url!==e.url || !eligible(tab)){item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      item.status='closing';try{await write(api,batch)}catch{stopped=true;break}
      try{await api.tabs.remove(e.tabId);item.status='closed'}catch{item.status='close_failed'}
      try{await write(api,batch)}catch{stopped=true;break}
    }
    return {batch,stopped};
  }
  async function reopen(api, key, indexes){
    const data=await api.storage.local.get(key),batch=data[key];if(!batch)throw Error('Lượt này không còn tồn tại.');
    let opened=0,failed=0,stopped=false;
    for(const i of indexes){const item=batch.items[i];if(!item||item.status!=='closed')continue;
      item.status='opening';try{await write(api,batch)}catch{stopped=true;break}
      try{await api.tabs.create({url:item.url,active:false});item.status='opened';opened++}catch{item.status='open_failed';failed++}
      try{await write(api,batch)}catch{stopped=true;break}
    }
    return {opened,failed,stopped};
  }
  return {prefix,closeSaved,reopen};
})();
if(typeof module!=='undefined')module.exports=BatchTools;
