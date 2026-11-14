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
  async function restore(api,windows,restoreGroups=true,options={}){
    if(typeof restoreGroups!=='boolean'||!options||typeof options!=='object'||Array.isArray(options)||['skipOpen','skipDuplicates'].some(k=>options[k]!==undefined&&typeof options[k]!=='boolean'))throw Error('Tùy chọn mở phiên không hợp lệ.');
    // Validate every selected item before asking Chrome to create anything.
    const selected=validate([{name:'Phiên',windows}],()=> 'validation')[0].windows;
    const result={opened:0,unknown:0,notAttempted:0,skipped:0,pinFailed:0,groupFailed:0,groupSkipped:0,details:[]};let stopped=false;const openedUrls=new Set();
    for(let i=0;i<selected.length;i++){
      const items=selected[i],grouped=new Map();let win=null;
      const remember=(item,tab)=>{if(!restoreGroups||!item.chromeGroup)return;const g=item.chromeGroup;if(!grouped.has(g.key))grouped.set(g.key,{meta:g,entries:[]});grouped.get(g.key).entries.push({tabId:tab.id,url:item.url})};
      for(const item of items){
        if(stopped){result.notAttempted++;continue}
        if((options.skipOpen||options.skipDuplicates)&&openedUrls.has(item.url)){result.skipped++;continue}
        if(options.skipOpen){let live;try{live=await api.tabs.query({});if(!Array.isArray(live)||live.some(t=>!t||typeof t.incognito!=='boolean'||(!t.incognito&&typeof t.url!=='string'&&typeof t.pendingUrl!=='string')))throw Error('Không xác định được tab đang mở.')}catch{stopped=true;result.notAttempted++;result.details.push('Không đọc được tab đang mở; đã dừng trước khi mở tiếp.');continue}if(live.some(t=>!t.incognito&&(t.url===item.url||t.pendingUrl===item.url))){result.skipped++;continue}}
        if(win===null){
          try{const created=await api.windows.create({url:item.url,incognito:false});if(!created||!Number.isInteger(created.id)||created.id<0){if(Number.isInteger(created?.tabs?.[0]?.id)){result.opened++;openedUrls.add(item.url)}else result.unknown++;stopped=true;result.details.push(`Cửa sổ ${i+1}: không xác định được ID cửa sổ; dừng mở tiếp. Kiểm tra Chrome trước khi thử lại.`);continue}win=created;if(win.incognito===true){result.unknown++;stopped=true;result.details.push(`Cửa sổ ${i+1}: cửa sổ ẩn danh ngoài dự kiến; dừng mở tiếp.`);continue}const first=win.tabs?.[0];if(!Number.isInteger(first?.id)||first.id<0){result.unknown++;stopped=true;result.details.push(`Cửa sổ ${i+1}: không xác nhận được tab đầu tiên; dừng mở tiếp. Kiểm tra Chrome trước khi thử lại.`);continue}result.opened++;openedUrls.add(item.url);remember(item,first);
            if(item.pinned){try{const fresh=await api.tabs.get(first.id);if(fresh.id!==first.id||fresh.incognito!==false||fresh.windowId!==win.id||(fresh.pendingUrl?fresh.pendingUrl!==item.url:fresh.url!==item.url))throw Error('Tab đã thay đổi');const updated=await api.tabs.update(first.id,{pinned:true});if(updated?.pinned!==true)throw Error('Không xác nhận được ghim')}catch{result.pinFailed++;result.details.push(`Không xác nhận được ghim: ${item.title}`)}}
          }catch{result.unknown++;stopped=true;result.details.push(`Cửa sổ ${i+1}: không xác nhận được tab đầu tiên đã mở. Kiểm tra Chrome trước khi thử lại.`)}
        }else{
          try{const tab=await api.tabs.create({windowId:win.id,url:item.url,active:false,pinned:item.pinned});if(!Number.isInteger(tab?.id)||tab.id<0)throw Error('Không có ID tab');result.opened++;openedUrls.add(item.url);remember(item,tab);if(item.pinned&&tab.pinned!==true){result.pinFailed++;result.details.push(`Không xác nhận được ghim: ${item.title}`)}}catch{result.unknown++;stopped=true;result.details.push(`Không xác nhận được tab đã mở: ${item.title}. Kiểm tra Chrome trước khi thử lại.`)}
        }
      }
      if(!win||!Number.isInteger(win.id))continue;
      if(stopped){for(const group of grouped.values())result.groupSkipped+=group.entries.length;continue}
      for(const {meta,entries} of grouped.values()){
        const eligible=async entry=>{try{const t=await api.tabs.get(entry.tabId);return t.id===entry.tabId&&t.windowId===win.id&&t.incognito===false&&t.pinned===false&&Number.isInteger(t.groupId)&&t.groupId<0&&(t.pendingUrl?t.pendingUrl===entry.url:t.url===entry.url)}catch{return false}};
        const checked=[];for(const entry of entries)if(await eligible(entry))checked.push(entry);else result.groupSkipped++;
        const ids=[];for(const entry of checked)if(await eligible(entry))ids.push(entry.tabId);else result.groupSkipped++;
        if(!ids.length)continue;
        try{const groupId=await api.tabs.group({tabIds:ids,createProperties:{windowId:win.id}});if(!Number.isInteger(groupId)||groupId<0)throw Error('Không xác định được nhóm');try{await api.tabGroups.update(groupId,{title:meta.title,color:meta.color,collapsed:meta.collapsed})}catch(e){result.groupFailed++;result.details.push(`Đã tạo nhóm ${meta.title||'(không tên)'} nhưng không xác nhận được tên, màu hoặc trạng thái: ${e.message}`)}}catch(e){result.groupFailed++;result.details.push(`Không xác nhận được việc tạo nhóm ${meta.title||'(không tên)'}: ${e.message}`)}
      }
    }
    return result;
  }

  return {capture,validate,restore};
})();
if (typeof module !== 'undefined') module.exports = SnapshotTools;
