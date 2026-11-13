'use strict';
// Independent storage key per operation; pending means the browser call's result is uncertain.
const BatchTools = (() => {
  const prefix = 'tabspace:batch:';
  const colors=new Set(['grey','blue','red','yellow','green','pink','purple','cyan','orange']);
  function validateGroup(g){if(!g||typeof g!=='object'||typeof g.key!=='string'||!g.key||g.key.length>128||typeof g.title!=='string'||g.title.length>1000||!colors.has(g.color)||typeof g.collapsed!=='boolean')throw Error('Thông tin nhóm Chrome trong lịch sử không hợp lệ.');return {key:g.key,title:g.title,color:g.color,collapsed:g.collapsed}}
  async function captureGroup(api,tab){
    if(!Number.isInteger(tab.groupId)||tab.groupId<0)return null;
    try{const g=await api.tabGroups.get(tab.groupId);if(g.id!==tab.groupId||g.windowId!==tab.windowId||!Number.isInteger(tab.windowId)||tab.windowId<0||tab.pinned!==false)throw Error('group changed');return validateGroup({key:`${tab.windowId}:${tab.groupId}`,title:typeof g.title==='string'?g.title:'',color:g.color,collapsed:!!g.collapsed})}catch{return null}
  }
  async function restoreGroups(api,items){
    const buckets=new Map(),seen=new Set();let skipped=0,failed=0,created=0;
    async function eligible(item,tab){try{const fresh=await api.tabs.get(tab.id);return fresh.id===tab.id&&!fresh.incognito&&fresh.windowId===tab.windowId&&fresh.pinned===false&&Number.isInteger(fresh.groupId)&&fresh.groupId<0&&(fresh.url===item.url||fresh.pendingUrl===item.url)}catch{return false}}
    for(const {item,tab} of items){
      if(!Number.isInteger(tab?.id)||!Number.isInteger(tab?.windowId)||tab.id<0||tab.windowId<0||seen.has(tab.id)){skipped++;continue}seen.add(tab.id);
      if(!await eligible(item,tab)){skipped++;continue}
      const key=JSON.stringify([tab.windowId,item.chromeGroup]);if(!buckets.has(key))buckets.set(key,{windowId:tab.windowId,meta:item.chromeGroup,entries:[]});buckets.get(key).entries.push({item,tab});
    }
    for(const {windowId,meta,entries} of buckets.values()){
      const ids=[];for(const entry of entries){if(await eligible(entry.item,entry.tab))ids.push(entry.tab.id);else skipped++}if(!ids.length)continue;
      try{const groupId=await api.tabs.group({tabIds:ids,createProperties:{windowId}});if(!Number.isInteger(groupId)||groupId<0)throw Error('Không xác định được nhóm.');await api.tabGroups.update(groupId,{title:meta.title,color:meta.color,collapsed:meta.collapsed});created++}catch{failed++}
    }
    return {skipped,failed,created};
  }

  async function write(api, batch){ await api.storage.local.set({[prefix+batch.id]: batch}); }
  async function closeSaved(api, entries, source, makeId, eligible){
    const batch={id:makeId(),source,createdAt:Date.now(),items:entries.map(e=>({url:e.url,title:e.item.title,status:'queued'}))};
    await write(api,batch); // No tab may be closed if the journal cannot be written.
    let stopped=false;
    for(let i=0;i<entries.length;i++){
      const e=entries[i], item=batch.items[i];
      let tab;try{tab=await api.tabs.get(e.tabId)}catch{item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      let permitted;try{permitted=tab.url===e.url&&(!Number.isInteger(e.windowId)||tab.windowId===e.windowId)&&await eligible(tab,e)}catch{stopped=true;break}
      if(!permitted){item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      if(typeof tab.pinned==='boolean')item.pinned=tab.pinned;if(Number.isInteger(tab.groupId)&&tab.groupId>=0){const group=await captureGroup(api,tab);if(group)item.chromeGroup=group;else item.groupUnavailable=true}item.status='closing';try{await write(api,batch)}catch{stopped=true;break}
      // Revalidate after writing the journal: a tab may have navigated or gained protection meanwhile.
      let finalTab;try{finalTab=await api.tabs.get(e.tabId)}catch{item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      try{permitted=finalTab.url===e.url&&(!Number.isInteger(e.windowId)||finalTab.windowId===e.windowId)&&(item.pinned===undefined||finalTab.pinned===item.pinned)&&(!Number.isInteger(tab.groupId)||finalTab.groupId===tab.groupId)&&await eligible(finalTab,e)}catch{stopped=true;break}
      if(!permitted){item.status='skipped';try{await write(api,batch)}catch{stopped=true;break}continue}
      try{await api.tabs.remove(e.tabId);item.status='closed'}catch{item.status='closing'}
      try{await write(api,batch)}catch{stopped=true;break}
      if(item.status==='closing'){stopped=true;break}
    }
    return {batch,stopped};
  }
  async function reopen(api, key, indexes, expected, options={}){
    const destination=options.destination??'current';if(!['current','new'].includes(destination))throw Error('Nơi mở lại không hợp lệ.');
    const data=await api.storage.local.get(key),batch=data[key];if(!batch)throw Error('Lượt này không còn tồn tại.');
    if(expected&&JSON.stringify(batch)!==JSON.stringify(expected))throw Error('Lượt dọn đã thay đổi; hãy mở lại chi tiết trước khi tiếp tục.');
    if(indexes.some(i=>batch.items[i]?.pinned!==undefined&&typeof batch.items[i].pinned!=='boolean'))throw Error('Thông tin ghim trong lịch sử không hợp lệ; chưa mở tab.');
    for(const i of indexes){const item=batch.items[i];if(item?.chromeGroup!==undefined){validateGroup(item.chromeGroup);if(item.pinned===true)throw Error('Tab ghim không thể thuộc nhóm Chrome; chưa mở tab.')}}
    let opened=0,failed=0,pinUnconfirmed=0,stopped=false,windowId=null;const toGroup=[];
    for(const i of indexes){const item=batch.items[i];if(!item||item.status!=='closed')continue;
      item.status='opening';try{await write(api,batch)}catch{stopped=true;break}
      const pin=options.restorePinned===true&&item.pinned===true;let firstTab=null,firstInNew=false,openedTab=null;
      try{
        if(destination==='new'&&windowId===null){const win=await api.windows.create({url:item.url,incognito:false});if(!Number.isInteger(win?.id)||win.id<0)throw Error('Không xác định được cửa sổ.');windowId=win.id;firstInNew=true;firstTab=win.tabs?.[0];openedTab=firstTab?{...firstTab,windowId:win.id}:null}
        else{const tab=await api.tabs.create({url:item.url,active:false,...(destination==='new'?{windowId}:{}),...(pin?{pinned:true}:{})});openedTab=tab;if(pin&&tab?.pinned!==true)pinUnconfirmed++}
        item.status='opened';opened++;
      }catch{item.status='opening';failed++}
      try{await write(api,batch)}catch{stopped=true;break}
      if(failed){stopped=true;break}
      if(options.restoreGroups===true&&item.chromeGroup)toGroup.push({item,tab:openedTab});
      // The first new-window tab is journaled as opened before attempting optional pinning.
      if(firstInNew&&pin){
        try{if(!Number.isInteger(firstTab?.id)||firstTab.id<0)throw Error('Không có ID tab.');const fresh=await api.tabs.get(firstTab.id);if(fresh.incognito||fresh.windowId!==windowId||(fresh.url!==item.url&&fresh.pendingUrl!==item.url))throw Error('Tab đã thay đổi.');const updated=await api.tabs.update(firstTab.id,{pinned:true});if(updated?.pinned!==true)throw Error('Không xác nhận ghim.')}catch{pinUnconfirmed++}
      }
    }
    const grouped=options.restoreGroups===true?await restoreGroups(api,toGroup):{skipped:0,failed:0,created:0};
    return {opened,failed,pinUnconfirmed,groupsCreated:grouped.created,groupSkipped:grouped.skipped,groupFailed:grouped.failed,stopped};
  }

  async function deleteSelected(api, batches){
    const keys=batches.map(b=>prefix+b.id),current=await api.storage.local.get(keys);
    if(batches.some((b,i)=>!current[keys[i]]||JSON.stringify(current[keys[i]])!==JSON.stringify(b)))throw Error('Lịch sử đã thay đổi hoặc không còn tồn tại; hãy mở lại bản xác nhận.');
    let deleted=0,unknown=0;for(const key of keys){try{await api.storage.local.remove(key);deleted++}catch{unknown=1;break}}
    return {deleted,unknown,notAttempted:keys.length-deleted-unknown};
  }
  return {prefix,validateGroup,closeSaved,reopen,deleteSelected};
})();
if(typeof module!=='undefined')module.exports=BatchTools;
