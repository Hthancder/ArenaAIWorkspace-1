'use strict';
const OrganizeTools = (()=>{
  function tags(input){return [...new Set(String(input||'').split(',').map(x=>x.trim().replace(/^#+/,'')).filter(Boolean))].slice(0,50).map(x=>x.slice(0,80));}
  function move(groups,groupId,itemId,targetId){
    if(groupId===targetId)throw Error('Hãy chọn nhóm khác.');
    const source=groups.find(g=>g.id===groupId),target=groups.find(g=>g.id===targetId);
    if(!source||!target)throw Error('Nhóm nguồn hoặc nhóm đích không còn tồn tại.');
    const index=source.items.findIndex(x=>x.id===itemId);if(index<0)throw Error('Tab đã lưu không còn trong nhóm nguồn.');
    if(groups.some(g=>g!==source&&g.items.some(x=>x.id===itemId)))throw Error('Tab này đã tồn tại trong nhóm khác; không thể tự chuyển.');
    const [item]=source.items.splice(index,1);target.items.unshift(item);return groups;
  }
  function importTags(value){return Array.isArray(value)?value.filter(x=>typeof x==='string').slice(0,50).map(x=>x.slice(0,80)):[];}
  function note(value){return typeof value==='string'?value.slice(0,4000):'';}
  return {tags,move,importTags,note};
})();
if(typeof module!=='undefined')module.exports=OrganizeTools;
