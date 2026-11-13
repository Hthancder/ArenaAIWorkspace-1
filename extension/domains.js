'use strict';
const DomainView=(()=>{
 function hostname(url){try{const u=new URL(url);if(!['http:','https:'].includes(u.protocol)||!u.hostname)return null;return u.hostname.toLowerCase().replace(/\.$/,'')}catch{return null}}
 function group(groups,predicate=()=>true){
  const byHost=new Map();for(const group of groups)for(const item of group.items){if(!predicate(group,item))continue;const host=hostname(item.url),key=host||'';if(!byHost.has(key))byHost.set(key,[]);byHost.get(key).push({group,item})}
  return [...byHost].sort(([a],[b])=>!a?1:!b?-1:a.localeCompare(b,'vi')).map(([host,items])=>({host:host||null,items}));
 }
 return {hostname,group};
})();
if(typeof module!=='undefined')module.exports=DomainView;
