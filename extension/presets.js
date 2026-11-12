'use strict';
const PresetTools = (() => {
  function normalizeDomain(value) {
    const raw = String(value || '').trim().toLowerCase();
    if (!raw || /[\s/:?#@*]/.test(raw)) throw Error('Nhập tên miền, không kèm https://, đường dẫn, cổng hoặc dấu *.');
    let hostname; try { hostname = new URL('https://' + raw).hostname.replace(/\.$/, ''); } catch { throw Error('Tên miền không hợp lệ: ' + raw); }
    if (!hostname || hostname.includes('..') || !/^[a-z0-9.-]+$/.test(hostname) || hostname.split('.').some(part => !part || part.startsWith('-') || part.endsWith('-'))) throw Error('Tên miền không hợp lệ: ' + raw);
    return hostname;
  }
  function matches(url, domains, subdomains) {
    try { const u = new URL(url); if (!['http:', 'https:'].includes(u.protocol)) return false; const host=u.hostname.toLowerCase().replace(/\.$/,'');return domains.some(d=>host===d||(subdomains&&host.endsWith('.'+d))); } catch { return false; }
  }
  function reason(tab) { if(tab.incognito)return 'Ẩn danh'; if(tab.active)return 'Đang xem'; if(tab.pinned)return 'Đã ghim'; if(tab.audible)return 'Đang phát âm thanh'; return ''; }
  function validate(list, makeId, mapping) {
    if (!Array.isArray(list) || list.length>10000) throw Error('Danh sách preset không hợp lệ.');
    return list.map(p=>{if(!p||typeof p.name!=='string'||!Array.isArray(p.domains)||!p.domains.length||p.domains.length>1000)throw Error('Preset không hợp lệ.');return {id:makeId(),name:p.name.slice(0,80),domains:[...new Set(p.domains.map(normalizeDomain))],subdomains:!!p.subdomains,groupId:mapping.get(p.groupId)||null,createdAt:Number(p.createdAt)||Date.now()}});
  }
  return {normalizeDomain,matches,reason,validate};
})();
if(typeof module!=='undefined')module.exports=PresetTools;
