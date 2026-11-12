'use strict';
// Snapshot metadata is portable; Chrome's live tab/group IDs are never reused on restore.
const SnapshotTools = (() => {
  const isWebUrl = url => typeof url === 'string' && /^https?:\/\//i.test(url);
  const colors = new Set(['grey','blue','red','yellow','green','pink','purple','cyan','orange']);
  function capture(tabs, name, now, makeId, chromeGroups=[]) {
    const byWindow = new Map(),groupMap=new Map(chromeGroups.map(g=>[g.id,g]));let skipped=0,missingGroups=0;
    for (const tab of tabs) {
      if (tab.incognito || !isWebUrl(tab.url)) { skipped++; continue; }
      if (!byWindow.has(tab.windowId)) byWindow.set(tab.windowId, []);
      const item={url:tab.url,title:tab.title||tab.url,pinned:!!tab.pinned,index:Number.isInteger(tab.index)?tab.index:0};
      if(Number.isInteger(tab.groupId)&&tab.groupId>=0){const group=groupMap.get(tab.groupId);if(group&&group.windowId===tab.windowId&&colors.has(group.color)&&!item.pinned){item.chromeGroup={key:'g:'+group.id,title:typeof group.title==='string'?group.title:'',color:group.color,collapsed:!!group.collapsed}}else missingGroups++}
      byWindow.get(tab.windowId).push(item);
    }
    const windows=[...byWindow.values()].map(items=>items.sort((a,b)=>a.index-b.index).map(({index,...item})=>item));
    return {snapshot:{id:makeId(),name,createdAt:now,windows},skipped,missingGroups};
  }
  function validate(list, makeId) {
    if (!Array.isArray(list) || list.length>10000)throw Error('Danh sách phiên không hợp lệ.');
    return list.map(s=>{
      if(!s||typeof s.name!=='string'||!Array.isArray(s.windows)||s.windows.length>10000)throw Error('Phiên không hợp lệ.');
      return {id:makeId(),name:s.name.slice(0,80),createdAt:Number(s.createdAt)||Date.now(),windows:s.windows.map(w=>{
        if(!Array.isArray(w)||w.length>100000)throw Error('Cửa sổ trong phiên không hợp lệ.');const seen=new Map();
        return w.map(t=>{if(!t||!isWebUrl(t.url)||typeof t.title!=='string')throw Error('Tab trong phiên không hợp lệ.');const item={url:t.url,title:t.title,pinned:!!t.pinned};
          if(t.chromeGroup!==undefined){const g=t.chromeGroup;if(!g||typeof g.key!=='string'||!g.key||g.key.length>128||typeof g.title!=='string'||g.title.length>1000||!colors.has(g.color)||typeof g.collapsed!=='boolean'||item.pinned)throw Error('Thông tin nhóm Chrome không hợp lệ.');const group={key:g.key,title:g.title,color:g.color,collapsed:g.collapsed};const sig=JSON.stringify(group);if(seen.has(g.key)&&seen.get(g.key)!==sig)throw Error('Thông tin nhóm Chrome không nhất quán.');seen.set(g.key,sig);item.chromeGroup=group}return item});
      })};
    });
  }
  async function restore(api,windows,restoreGroups=true){
    const result={opened:0,failed:0,pinFailed:0,groupFailed:0,details:[]};
    for(let i=0;i<windows.length;i++){
      const items=windows[i];if(!items.length)continue;const grouped=new Map();let win;
      const remember=(item,tab)=>{if(!restoreGroups||!item.chromeGroup)return;if(!Number.isInteger(tab?.id)){result.groupFailed++;result.details.push(`Cửa sổ ${i+1}: không xác định được tab để tạo nhóm ${item.chromeGroup.title||'(không tên)'}.`);return}const g=item.chromeGroup;if(!grouped.has(g.key))grouped.set(g.key,{meta:g,ids:[]});grouped.get(g.key).ids.push(tab.id)};
      try{win=await api.windows.create({url:items[0].url});result.opened++;remember(items[0],win.tabs?.[0]);if(items[0].pinned&&Number.isInteger(win.tabs?.[0]?.id)){try{await api.tabs.update(win.tabs[0].id,{pinned:true})}catch{result.pinFailed++;result.details.push(`Không ghim được: ${items[0].title}`)}}else if(items[0].pinned){result.pinFailed++;result.details.push(`Không xác định được tab để ghim: ${items[0].title}`)}}catch(e){result.failed+=items.length;result.details.push(`Không tạo được cửa sổ ${i+1}: ${e.message}`);continue}
      for(const item of items.slice(1)){try{const tab=await api.tabs.create({windowId:win.id,url:item.url,active:false,pinned:item.pinned});result.opened++;remember(item,tab)}catch(e){result.failed++;result.details.push(`Không mở được ${item.title}: ${e.message}`)}}
      for(const {meta,ids} of grouped.values()){try{const groupId=await api.tabs.group({tabIds:ids,createProperties:{windowId:win.id}});try{await api.tabGroups.update(groupId,{title:meta.title,color:meta.color,collapsed:meta.collapsed})}catch(e){result.groupFailed++;result.details.push(`Đã tạo nhóm ${meta.title||'(không tên)'} nhưng không đặt được tên, màu hoặc trạng thái: ${e.message}`)}}catch(e){result.groupFailed++;result.details.push(`Không tạo được nhóm ${meta.title||'(không tên)'}: ${e.message}`)}}
    }
    return result;
  }
  return {capture,validate,restore};
})();
if (typeof module !== 'undefined') module.exports = SnapshotTools;
