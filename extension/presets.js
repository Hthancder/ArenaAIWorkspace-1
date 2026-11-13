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
  function overlaps(url,list,currentId){return list.filter(p=>p&&p.id!==currentId&&matchesPreset(url,p));}
  function reason(tab) { if(tab.incognito)return 'Ẩn danh'; if(tab.active)return 'Đang xem'; if(tab.pinned)return 'Đã ghim'; if(tab.audible)return 'Đang phát âm thanh'; return ''; }
  function validate(list, makeId, mapping) {
    if (!Array.isArray(list) || list.length>10000) throw Error('Danh sách preset không hợp lệ.');
    function arr(p,key,fn){const v=p[key]??[];if(!Array.isArray(v)||v.length>1000)throw Error('Quy tắc preset không hợp lệ.');return [...new Set(v.map(x=>fn(x)))]}
    return list.map(p=>{if(!p||typeof p.name!=='string')throw Error('Preset không hợp lệ.');const domains=arr(p,'domains',normalizeDomain),paths=arr(p,'paths',x=>normalizeUrl(x,true)),exactUrls=arr(p,'exactUrls',normalizeUrl);if(!domains.length&&!paths.length&&!exactUrls.length)throw Error('Preset cần ít nhất một quy tắc bao gồm.');return {id:makeId(),name:p.name.slice(0,80),domains,paths,exactUrls,excludeDomains:arr(p,'excludeDomains',normalizeDomain),excludePaths:arr(p,'excludePaths',x=>normalizeUrl(x,true)),excludeUrls:arr(p,'excludeUrls',normalizeUrl),subdomains:!!p.subdomains,groupId:mapping.get(p.groupId)||null,createdAt:Number(p.createdAt)||Date.now()}});
  }
  return {normalizeDomain,normalizeUrl,matches:domainMatch,included,excluded,matchesPreset,overlaps,reason,validate};
})();
if(typeof module!=='undefined')module.exports=PresetTools;
