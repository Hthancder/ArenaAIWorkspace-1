'use strict';
// Pure helpers shared by the extension and regression tests.
const SnapshotTools = (() => {
  const isWebUrl = url => typeof url === 'string' && /^https?:\/\//i.test(url);
  function capture(tabs, name, now, makeId) {
    const byWindow = new Map(); let skipped = 0;
    for (const tab of tabs) {
      if (tab.incognito || !isWebUrl(tab.url)) { skipped++; continue; }
      if (!byWindow.has(tab.windowId)) byWindow.set(tab.windowId, []);
      byWindow.get(tab.windowId).push({url:tab.url, title:tab.title || tab.url, pinned:!!tab.pinned, index:Number.isInteger(tab.index)?tab.index:0});
    }
    const windows = [...byWindow.values()].map(items => items.sort((a,b)=>a.index-b.index).map(({index,...item})=>item));
    return {snapshot:{id:makeId(), name, createdAt:now, windows}, skipped};
  }
  function validate(list, makeId) {
    if (!Array.isArray(list) || list.length > 10000) throw Error('Danh sách phiên không hợp lệ.');
    return list.map(s => {
      if (!s || typeof s.name !== 'string' || !Array.isArray(s.windows) || s.windows.length > 10000) throw Error('Phiên không hợp lệ.');
      return {id:makeId(), name:s.name.slice(0,80), createdAt:Number(s.createdAt)||Date.now(), windows:s.windows.map(w=>{
        if (!Array.isArray(w) || w.length > 100000) throw Error('Cửa sổ trong phiên không hợp lệ.');
        return w.map(t=>{if (!t || !isWebUrl(t.url) || typeof t.title !== 'string') throw Error('Tab trong phiên không hợp lệ.');return {url:t.url,title:t.title,pinned:!!t.pinned}});
      })};
    });
  }
  return {capture,validate};
})();
if (typeof module !== 'undefined') module.exports = SnapshotTools;
