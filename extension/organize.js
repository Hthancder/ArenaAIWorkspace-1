'use strict';
const OrganizeTools = (()=>{
  function tags(input){const values=String(input||'').split(',').map(x=>x.trim().replace(/^#+/,'')).filter(Boolean);if(values.some(x=>x.length>80))throw Error('Mỗi tag tối đa 80 ký tự.');const unique=[...new Map(values.map(x=>[x.normalize('NFKC').toLocaleLowerCase('vi'),x])).values()];if(unique.length>50)throw Error('Mỗi mục tối đa 50 tag.');return unique;}
  function move(groups,groupId,itemId,targetId){
    if(groupId===targetId)throw Error('Hãy chọn nhóm khác.');
    const source=groups.find(g=>g.id===groupId),target=groups.find(g=>g.id===targetId);
    if(!source||!target)throw Error('Nhóm nguồn hoặc nhóm đích không còn tồn tại.');
    const index=source.items.findIndex(x=>x.id===itemId);if(index<0)throw Error('Tab đã lưu không còn trong nhóm nguồn.');
    if(groups.some(g=>g!==source&&g.items.some(x=>x.id===itemId)))throw Error('Tab này đã tồn tại trong nhóm khác; không thể tự chuyển.');
    const [item]=source.items.splice(index,1);target.items.unshift(item);return groups;
  }
  function copyItems(groups,plan,targetId,makeId,now=Date.now()){
    const target=groups.find(g=>g.id===targetId);if(!target)throw Error('Nhóm đích không còn tồn tại.');
    const knownIds=new Set(groups.flatMap(g=>g.items.map(x=>x.id))),seen=new Set(),copies=[],results=[];
    for(const p of plan){
      const name=p.name||p.url||'Tab';const key=JSON.stringify([p.groupId,p.id]);
      if(seen.has(key)){results.push({name,error:'Mục bị chọn trùng; đã bỏ qua.'});continue}seen.add(key);
      const source=groups.find(g=>g.id===p.groupId),item=source?.items.find(x=>x.id===p.id);
      if(!item||item.url!==p.url){results.push({name,error:'Tab đã di chuyển, thay đổi URL hoặc không còn tồn tại.'});continue}
      const newId=makeId();if(typeof newId!=='string'||!newId||knownIds.has(newId))throw Error('Không thể tạo ID duy nhất; chưa sao chép mục nào.');knownIds.add(newId);
      copies.push({...item,id:newId,createdAt:now,tags:Array.isArray(item.tags)?[...item.tags]:[]});results.push({name});
    }
    target.items.unshift(...copies);return {results,count:copies.length};
  }
  function reorderGroup(groups,groupId,direction){
    if(![-1,1].includes(direction))throw Error('Hướng sắp xếp không hợp lệ.');const index=groups.findIndex(g=>g.id===groupId);if(index<0)throw Error('Nhóm không còn tồn tại.');const dest=index+direction;if(dest<0||dest>=groups.length)return false;[groups[index],groups[dest]]=[groups[dest],groups[index]];return true;
  }
  function reorderItem(groups,sourceId,itemId,targetId,beforeId=null){
    const source=groups.find(g=>g.id===sourceId),target=groups.find(g=>g.id===targetId);if(!source||!target)throw Error('Nhóm nguồn hoặc đích không còn tồn tại.');
    const from=source.items.findIndex(x=>x.id===itemId);if(from<0)throw Error('Tab đã di chuyển hoặc không còn tồn tại.');
    if(source!==target&&groups.some(g=>g!==source&&g.items.some(x=>x.id===itemId)))throw Error('Tab này đã tồn tại trong nhóm khác.');
    if(beforeId===itemId&&source===target)return false;
    if(beforeId!==null&&!target.items.some(x=>x.id===beforeId))throw Error('Vị trí đích không còn tồn tại.');
    const [item]=source.items.splice(from,1);const to=beforeId===null?target.items.length:target.items.findIndex(x=>x.id===beforeId);target.items.splice(to,0,item);return true;
  }
  function stepItem(groups,groupId,itemId,direction){
    if(![-1,1].includes(direction))throw Error('Hướng sắp xếp không hợp lệ.');const group=groups.find(g=>g.id===groupId);if(!group)throw Error('Nhóm không còn tồn tại.');const index=group.items.findIndex(x=>x.id===itemId);if(index<0)throw Error('Tab không còn tồn tại.');const to=index+direction;if(to<0||to>=group.items.length)return false;[group.items[index],group.items[to]]=[group.items[to],group.items[index]];return true;
  }
  function importTags(value){if(value===undefined||value===null)return [];if(!Array.isArray(value)||value.length>50||value.some(x=>typeof x!=='string'||x.length>80))throw Error('Tag trong bản sao lưu không hợp lệ hoặc vượt giới hạn.');return [...value];}
  function note(value){if(value===undefined||value===null)return '';if(typeof value!=='string'||value.length>4000)throw Error('Ghi chú không hợp lệ hoặc vượt quá 4.000 ký tự.');return value;}
  return {tags,move,copyItems,reorderGroup,reorderItem,stepItem,importTags,note};
})();
if(typeof module!=='undefined')module.exports=OrganizeTools;
