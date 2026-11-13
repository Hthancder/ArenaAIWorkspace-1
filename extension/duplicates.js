'use strict';
const DuplicateTools=(()=>{
 function find(tabs){
  const byUrl=new Map();
  for(const tab of tabs){if(tab.incognito||typeof tab.url!=='string'||!/^https?:\/\//i.test(tab.url))continue;const list=byUrl.get(tab.url)||[];list.push(tab);byUrl.set(tab.url,list)}
  return [...byUrl.entries()].filter(([,list])=>list.length>1).map(([url,tabs])=>({url,tabs}));
 }
 function savedOpen(tabs,groups){
  const saved=new Map();
  for(const group of groups||[]){for(const item of (Array.isArray(group?.items)?group.items:[])){if(typeof item?.url!=='string'||!/^https?:\/\//i.test(item.url))continue;const refs=saved.get(item.url)||[];refs.push({groupName:group.name||'Nhóm không tên',title:item.title||item.url});saved.set(item.url,refs)}}
  return (tabs||[]).filter(t=>!t.incognito&&typeof t.url==='string'&&saved.has(t.url)).map(tab=>({tab,refs:saved.get(tab.url)}));
 }
 return {find,savedOpen};
})();
if(typeof module!=='undefined')module.exports=DuplicateTools;
