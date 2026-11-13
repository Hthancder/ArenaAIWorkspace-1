'use strict';
const SearchTools = (()=>{
 const normalize=value=>String(value??'').normalize('NFKC').toLocaleLowerCase('vi').trim();
 function textMatch(query,...values){const q=normalize(query);return !!q&&values.some(value=>normalize(value).includes(q));}
 function tagMatch(query,tags){const raw=normalize(query), exact=raw.startsWith('#'),q=raw.replace(/^#+/,'');return !!q&&(tags||[]).some(t=>exact?normalize(t)===q:normalize(t).includes(q));}
 function matchesBatch(query,batch){return !normalize(query)||textMatch(query,batch.source)||(Array.isArray(batch.items)&&batch.items.some(item=>textMatch(query,item?.title,item?.url)));}
 function find({query,tabs=[],groups=[],workspaces=[],snapshots=[],presets=[],batches=[]}){
  const q=String(query||'').trim();if(!q)return {open:[],groups:[],workspaces:[],items:[],sessions:[],presets:[],batches:[]};
  const open=tabs.filter(t=>!t.incognito&&textMatch(q,t.title,t.url));
  const foundGroups=groups.filter(g=>textMatch(q,g.name,g.note)||tagMatch(q,g.tags));
  const items=groups.flatMap(g=>g.items.filter(item=>textMatch(q,item.title,item.url,item.note)||tagMatch(q,item.tags)).map(item=>({group:g,item})));
  const byId=new Map(groups.map(g=>[g.id,g]));const foundWorkspaces=workspaces.filter(w=>textMatch(q,w.name,...w.groupIds.map(id=>byId.get(id)?.name)));
  const sessions=snapshots.filter(s=>textMatch(q,s.name)||s.windows.some(w=>w.some(t=>textMatch(q,t.title,t.url))));
  const foundPresets=presets.filter(p=>textMatch(q,p.name,...p.domains,...(p.paths||[]),...(p.exactUrls||[]),...(p.excludeDomains||[]),...(p.excludePaths||[]),...(p.excludeUrls||[])));
  const foundBatches=batches.filter(b=>matchesBatch(q,b));
  return {open,groups:foundGroups,workspaces:foundWorkspaces,items,sessions,presets:foundPresets,batches:foundBatches};
 }
 function collectTags(groups){
  const map=new Map();function add(t,type){const key=normalize(t);if(!key)return;let v=map.get(key);if(!v){v={name:t,groups:0,items:0};map.set(key,v)}v[type]++}
  function unique(values){const seen=new Set();return values.filter(t=>{const key=normalize(t);if(!key||seen.has(key))return false;seen.add(key);return true})}for(const g of groups){for(const t of unique(g.tags||[]))add(t,'groups');for(const item of g.items)for(const t of unique(item.tags||[]))add(t,'items')}
  return [...map.values()].sort((a,b)=>a.name.localeCompare(b.name,'vi'));
 }
 return {find,collectTags,matchesBatch};
})();
if(typeof module!=='undefined')module.exports=SearchTools;
