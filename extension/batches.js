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
      let permitted;try{permitted=tab.url===e.url&&(!Number.isInteger(e.windowId)||tab.windowId===e.windowId)&&await eligible(tab)}catch{stopped=true;break}
      if(!permitted){item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      item.status='closing';try{await write(api,batch)}catch{stopped=true;break}
      // Revalidate after writing the journal: a tab may have navigated or gained protection meanwhile.
      let finalTab;try{finalTab=await api.tabs.get(e.tabId)}catch{item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      try{permitted=finalTab.url===e.url&&(!Number.isInteger(e.windowId)||finalTab.windowId===e.windowId)&&await eligible(finalTab)}catch{stopped=true;break}
      if(!permitted){item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      try{await api.tabs.remove(e.tabId);item.status='closed'}catch{item.status='closing'}
      try{await write(api,batch)}catch{stopped=true;break}
    }
    return {batch,stopped};
  }
  async function reopen(api, key, indexes, expected){
    const data=await api.storage.local.get(key),batch=data[key];if(!batch)throw Error('Lượt này không còn tồn tại.');
    if(expected&&JSON.stringify(batch)!==JSON.stringify(expected))throw Error('Lượt dọn đã thay đổi; hãy mở lại chi tiết trước khi tiếp tục.');
    let opened=0,failed=0,stopped=false;
    for(const i of indexes){const item=batch.items[i];if(!item||item.status!=='closed')continue;
      item.status='opening';try{await write(api,batch)}catch{stopped=true;break}
      try{await api.tabs.create({url:item.url,active:false});item.status='opened';opened++}catch{item.status='opening';failed++}
      try{await write(api,batch)}catch{stopped=true;break}
      if(failed){stopped=true;break}
    }
    return {opened,failed,stopped};
  }
  async function deleteSelected(api, batches){
    const keys=batches.map(b=>prefix+b.id),current=await api.storage.local.get(keys);
    if(batches.some((b,i)=>!current[keys[i]]||JSON.stringify(current[keys[i]])!==JSON.stringify(b)))throw Error('Lịch sử đã thay đổi hoặc không còn tồn tại; hãy mở lại bản xác nhận.');
    let deleted=0,unknown=0;for(const key of keys){try{await api.storage.local.remove(key);deleted++}catch{unknown=1;break}}
    return {deleted,unknown,notAttempted:keys.length-deleted-unknown};
  }
  return {prefix,closeSaved,reopen,deleteSelected};
})();
if(typeof module!=='undefined')module.exports=BatchTools;
