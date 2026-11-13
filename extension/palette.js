'use strict';
const PaletteTools=(()=>{
 const commands=[['workspaces','Workspace'],['open','Tab đang mở'],['inbox','Hộp để sau'],['saved','Nhóm đã lưu'],['domains','Theo tên miền'],['search','Tìm tất cả'],['tags','Tag'],['duplicates','Tab trùng'],['sessions','Phiên đã lưu'],['presets','Preset dọn tab'],['history','Lịch sử dọn'],['trash','Thùng rác'],['settings','Cài đặt & sao lưu']];
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
 return {find};
})();
if(typeof module!=='undefined')module.exports=PaletteTools;
