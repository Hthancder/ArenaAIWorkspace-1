'use strict';
const PaletteTools=(()=>{
 const commands=[['workspaces','Workspace'],['open','Tab đang mở'],['inbox','Hộp để sau'],['saved','Nhóm đã lưu'],['domains','Theo tên miền'],['smart','Nhóm thông minh'],['search','Tìm tất cả'],['tags','Tag'],['duplicates','Tab trùng'],['old-tabs','Lâu chưa truy cập'],['saved-open','Đã lưu còn mở'],['sessions','Phiên đã lưu'],['attention','Cần chú ý'],['presets','Preset dọn tab'],['history','Lịch sử dọn'],['trash','Thùng rác'],['settings','Cài đặt & sao lưu']];
 const norm=s=>String(s??'').normalize('NFKC').toLocaleLowerCase('vi').trim();
 function find(input,state,search){
  const q=norm(input),items=[];let truncated=false;
  function add(type,entries,make){if(entries.length>6)truncated=true;for(const e of entries.slice(0,6))items.push(make(e))}
  const nav=commands.filter(([,label])=>!q||norm(label).includes(q));if(!q){return {items:nav.map(([view,label])=>({type:'navigate',view,label,detail:'Đi đến mục trong Tabspace'})),truncated:false}}
  add('commands',nav,([view,label])=>({type:'navigate',view,label,detail:'Đi đến mục trong Tabspace'}));
  const found=search.find({...state,query:input});
  add('tabs',found.open,t=>({type:'tab',id:t.id,windowId:t.windowId,url:t.url,label:t.title||t.url||'Tab',detail:'Chuyển đến tab đang mở · '+(t.url||'URL không rõ')}));
  add('items',found.items,({group,item})=>({type:'item',id:item.id,groupId:group.id,url:item.url,label:item.title||item.url,detail:'Mở bản lưu · '+group.name+' · '+item.url}));
  add('workspaces',found.workspaces,w=>({type:'workspace',id:w.id,label:w.name,detail:'Xem workspace và nhóm đã lưu'}));
  add('groups',found.groups,g=>({type:'group',id:g.id,label:g.name,detail:'Tìm nhóm theo tên trong Nhóm đã lưu'}));
  add('sessions',found.sessions,s=>({type:'session',id:s.id,label:s.name,detail:'Xem phiên đã lưu'}));
  add('presets',found.presets,p=>({type:'preset',id:p.id,label:p.name,detail:'Xem trước preset'}));
  add('history',found.batches,b=>({type:'batch',id:b.id,label:b.source,detail:'Xem lịch sử dọn'}));
  const tagQuery=q.replace(/^#+/,'');const tags=tagQuery?search.collectTags(state.groups||[]).filter(t=>norm(t.name).includes(tagQuery)):[];
  add('tags',tags,t=>({type:'tag',name:t.name,label:'#'+t.name,detail:'Tìm theo tag'}));
  return {items,truncated};
 }
 function selectionKind(item){if(item?.type==='tab'&&Number.isInteger(item.id)&&Number.isInteger(item.windowId)&&typeof item.url==='string'&&/^https?:\/\//i.test(item.url))return 'open';if(item?.type==='item'&&typeof item.id==='string'&&item.id&&typeof item.groupId==='string'&&item.groupId&&typeof item.url==='string'&&/^https?:\/\//i.test(item.url))return 'saved';if(item?.type==='group'&&typeof item.id==='string'&&item.id&&item.id!=='inbox')return 'saved';return null}
 function selectionKey(item){return selectionKind(item)?JSON.stringify([item.type,item.id]):null}
 function revalidateSelection(items,state){
  if(!Array.isArray(items)||items.length>100||!Array.isArray(state.tabs)||!Array.isArray(state.groups))throw Error('Không đọc được dữ liệu để kiểm tra lựa chọn.');const kind=selectionKind(items[0]);if(!kind||items.some(x=>selectionKind(x)!==kind)||new Set(items.map(selectionKey)).size!==items.length)throw Error('Lựa chọn không hợp lệ.');const valid=[];
  const tabs=new Map(),groups=new Map(),saved=new Map();function add(map,key,value){if(map.has(key))map.set(key,null);else map.set(key,value)}for(const tab of state.tabs)if(tab&&Number.isInteger(tab.id))add(tabs,tab.id,tab);for(const group of state.groups){if(!group||typeof group.id!=='string')continue;add(groups,group.id,group);if(Array.isArray(group.items))for(const entry of group.items)if(entry&&typeof entry.id==='string')add(saved,entry.id,{group,entry})}
  for(const item of items){if(item.type==='tab'){const tab=tabs.get(item.id);if(tab&&tab.incognito===false&&tab.windowId===item.windowId&&tab.url===item.url&&(!tab.pendingUrl||tab.pendingUrl===item.url))valid.push(item.id)}else if(item.type==='group'){if(groups.get(item.id))valid.push(['group',item.id])}else{const hit=saved.get(item.id);if(hit&&groups.get(item.groupId)===hit.group&&hit.group.id===item.groupId&&hit.entry.url===item.url)valid.push(['item',item.id])}}
  return {kind,valid,skipped:items.length-valid.length};
 }
 return {find,selectionKind,selectionKey,revalidateSelection};
})();
if(typeof module!=='undefined')module.exports=PaletteTools;
