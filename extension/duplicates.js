'use strict';
const DuplicateTools=(()=>{
 function find(tabs){
  const byUrl=new Map();
  for(const tab of tabs){if(tab.incognito||typeof tab.url!=='string'||!/^https?:\/\//i.test(tab.url))continue;const list=byUrl.get(tab.url)||[];list.push(tab);byUrl.set(tab.url,list)}
  return [...byUrl.entries()].filter(([,list])=>list.length>1).map(([url,tabs])=>({url,tabs}));
 }
 return {find};
})();
if(typeof module!=='undefined')module.exports=DuplicateTools;
