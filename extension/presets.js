'use strict';
const PresetTools = (() => {
  function normalizeDomain(value) {
    const raw = String(value || '').trim().toLowerCase();
    if (!raw || /[\s/:?#@*]/.test(raw)) throw Error('Nhập tên miền, không kèm https://, đường dẫn, cổng hoặc dấu *.');
    let hostname; try { hostname = new URL('https://' + raw).hostname.replace(/\.$/, ''); } catch { throw Error('Tên miền không hợp lệ: ' + raw); }
    if (!hostname || hostname.includes('..') || !/^[a-z0-9.-]+$/.test(hostname) || hostname.split('.').some(part => !part || part.startsWith('-') || part.endsWith('-'))) throw Error('Tên miền không hợp lệ: ' + raw);
    return hostname;
  }
  function normalizeUrl(value, pathOnly=false) {
    let u;try{u=new URL(String(value||'').trim())}catch{throw Error('URL không hợp lệ: '+value)}
    if(!['http:','https:'].includes(u.protocol)||u.username||u.password)throw Error('Chỉ hỗ trợ URL http/https không chứa thông tin đăng nhập.');
    if(pathOnly&&(u.search||u.hash))throw Error('Quy tắc đường dẫn không được chứa query (?) hoặc fragment (#).');
    return u.href;
  }
  function domainMatch(url, domains, subdomains) {
    try { const u = new URL(url); if (!['http:', 'https:'].includes(u.protocol)) return false; const host=u.hostname.toLowerCase().replace(/\.$/,'');return domains.some(d=>host===d||(subdomains&&host.endsWith('.'+d))); } catch { return false; }
  }
  function urlMatch(url, paths, exactUrls) {
    try{const u=new URL(url);if(!['http:','https:'].includes(u.protocol))return false;
      if(exactUrls.some(rule=>u.href===rule))return true;
      return paths.some(rule=>{const r=new URL(rule);if(u.origin!==r.origin)return false;const root=r.pathname.replace(/\/+$/,'')||'/';return root==='/'||u.pathname===root||u.pathname.startsWith(root+'/')});
    }catch{return false}
  }
  function included(url,p){return domainMatch(url,p.domains||[],p.subdomains)||urlMatch(url,p.paths||[],p.exactUrls||[])}
  function excluded(url,p){return domainMatch(url,p.excludeDomains||[],p.subdomains)||urlMatch(url,p.excludePaths||[],p.excludeUrls||[])}
  function matchesPreset(url,p){return included(url,p)&&!excluded(url,p)}
  function explain(url,p){
    function collect(domains,paths,exact){const rules=[];
      for(const value of exact||[])if(urlMatch(url,[],[value]))rules.push({type:'exact',value});
      for(const value of paths||[])if(urlMatch(url,[value],[]))rules.push({type:'path',value});
      for(const value of domains||[])if(domainMatch(url,[value],p.subdomains))rules.push({type:'domain',value,subdomains:!!p.subdomains});
      return rules;
    }
    return {included:collect(p.domains,p.paths,p.exactUrls),excluded:collect(p.excludeDomains,p.excludePaths,p.excludeUrls)};
  }
  function parseRules(f){
    const parse=(field,fn)=>[...new Set(String(f.get(field)||'').split(/\n+/).map(x=>x.trim()).filter(Boolean).map(fn))];
    const domains=parse('domains',normalizeDomain),paths=parse('paths',x=>normalizeUrl(x,true)),exactUrls=parse('exactUrls',normalizeUrl),excludeDomains=parse('excludeDomains',normalizeDomain),excludePaths=parse('excludePaths',x=>normalizeUrl(x,true)),excludeUrls=parse('excludeUrls',normalizeUrl);
    if(!domains.length&&!paths.length&&!exactUrls.length)throw Error('Vui lòng thêm ít nhất một quy tắc bao gồm.');if([domains,paths,exactUrls,excludeDomains,excludePaths,excludeUrls].some(a=>a.length>1000))throw Error('Mỗi loại tối đa 1.000 quy tắc.');
    return {domains,paths,exactUrls,excludeDomains,excludePaths,excludeUrls,subdomains:f.has('subdomains')};
  }
  function specificity(url,p){
    if(!matchesPreset(url,p))return null;const reasons=explain(url,p).included;let best=[0,0];
    for(const r of reasons){let score;if(r.type==='exact')score=[4,0];else if(r.type==='path'){const path=new URL(r.value).pathname.replace(/\/+$/,'')||'/';score=[3,path.length]}else score=[r.subdomains?1:2,0];if(score[0]>best[0]||(score[0]===best[0]&&score[1]>best[1]))best=score}return best;
  }
  function priority(value){if(value===undefined)return 0;if(!Number.isInteger(value)||value< -1000||value>1000)throw Error('Ưu tiên preset phải là số nguyên từ -1000 đến 1000.');return value}
  function rank(url,list){const entries=list.map(p=>({preset:p,score:specificity(url,p)})).filter(x=>x.score).map(x=>({...x,priority:priority(x.preset.priority)}));entries.sort((a,b)=>b.score[0]-a.score[0]||b.score[1]-a.score[1]||b.priority-a.priority);if(!entries.length)return {entries,leaders:[]};const top=entries[0];return {entries,leaders:entries.filter(x=>x.score[0]===top.score[0]&&x.score[1]===top.score[1]&&x.priority===top.priority)};}
  function overlaps(url,list,currentId){return list.filter(p=>p&&p.id!==currentId&&matchesPreset(url,p));}
  function overlapReport(tabs,presets){
    const results=[];for(const tab of tabs){if(tab.incognito||typeof tab.url!=='string'||!/^https?:\/\//i.test(tab.url))continue;const matching=presets.filter(p=>p&&matchesPreset(tab.url,p));if(matching.length>1)results.push({tab,presets:matching})}return results;
  }
  function reason(tab) { if(tab.incognito)return 'Ẩn danh'; if(tab.active)return 'Đang xem'; if(tab.pinned)return 'Đã ghim'; if(tab.audible)return 'Đang phát âm thanh'; return ''; }
  function ruleFromUrl(url,mode){
    const normalized=normalizeUrl(url);const parsed=new URL(normalized);
    if(mode==='domain')return normalizeDomain(parsed.hostname);
    if(mode==='path'){parsed.search='';parsed.hash='';return normalizeUrl(parsed.href,true)}
    if(mode==='exact')return normalized;
    throw Error('Kiểu quy tắc không hợp lệ.');
  }
  function maxPerRun(value){if(value===undefined)return 0;if(!Number.isInteger(value)||value<0||value>10000)throw Error('Giới hạn preset phải là số nguyên từ 0 đến 10.000.');return value}
  function validate(list, makeId, mapping) {
    const reminderTools=typeof module!=='undefined'?require('./reminders.js'):ReminderTools;
    if (!Array.isArray(list) || list.length>10000) throw Error('Danh sách preset không hợp lệ.');
    function arr(p,key,fn){const v=p[key]??[];if(!Array.isArray(v)||v.length>1000)throw Error('Quy tắc preset không hợp lệ.');return [...new Set(v.map(x=>fn(x)))]}
    return list.map(p=>{if(!p||typeof p.name!=='string')throw Error('Preset không hợp lệ.');const domains=arr(p,'domains',normalizeDomain),paths=arr(p,'paths',x=>normalizeUrl(x,true)),exactUrls=arr(p,'exactUrls',normalizeUrl);if(!domains.length&&!paths.length&&!exactUrls.length)throw Error('Preset cần ít nhất một quy tắc bao gồm.');return {id:makeId(),name:p.name.slice(0,80),domains,paths,exactUrls,excludeDomains:arr(p,'excludeDomains',normalizeDomain),excludePaths:arr(p,'excludePaths',x=>normalizeUrl(x,true)),excludeUrls:arr(p,'excludeUrls',normalizeUrl),subdomains:!!p.subdomains,maxPerRun:maxPerRun(p.maxPerRun),priority:priority(p.priority),...(p.schedule?{schedule:{...reminderTools.validate(p.schedule),enabled:false}}:{}),groupId:mapping.get(p.groupId)||null,createdAt:Number(p.createdAt)||Date.now()}});
  }
  return {normalizeDomain,normalizeUrl,matches:domainMatch,included,excluded,matchesPreset,explain,parseRules,specificity,priority,rank,overlaps,overlapReport,reason,ruleFromUrl,maxPerRun,validate};
})();
if(typeof module!=='undefined')module.exports=PresetTools;
