const fs = require('fs'), vm = require('vm'), assert = require('assert');
const js = fs.readFileSync(process.argv[2], 'utf8');
const html = fs.readFileSync(process.argv[3], 'utf8');
assert(!html.includes('id="pers-bright"'), 'brightness has one editor');
assert(html.includes('id="ux-brightness"'));
assert(!js.includes('bright: $("#pers-bright").value'));
assert(!html.includes('id="mon-wifi-scan"'));
assert(html.includes('id="mon-net-scan"'));
assert(!js.includes('/api/time'));
const start = js.indexOf('// All clock controls use the same device endpoint');
const end = js.indexOf('$("#act-led-theme")', start);
const studioStart = js.indexOf('["st-sync-time", "st-clock-sync"].forEach');
const studioEnd = js.indexOf('document.getElementById("st-qr-add")', studioStart);
assert(start >= 0 && end > start && studioStart >= 0 && studioEnd > studioStart);
const elements = {};
for (const id of ['act-sync-time','dash-action-status','st-sync-time','st-clock-sync']) {
  elements[id] = { textContent: id, className: '', disabled: false, handlers: {},
    addEventListener(event, fn) { this.handlers[event] = fn; } };
}
let calls = [], fail = false, refreshes = 0;
const context = { Date, console, setTimeout: () => {},
  $: selector => elements[selector.slice(1)] || null,
  document: { getElementById: id => elements[id] },
  requestPost: async (url, data) => { calls.push({url, data}); if (fail) throw new Error('offline'); },
  refreshStudio: () => { refreshes++; }
};
vm.createContext(context);
vm.runInContext(js.slice(start, end) + js.slice(studioStart, studioEnd), context);
(async () => {
  for (const id of ['act-sync-time','st-sync-time','st-clock-sync']) {
    await elements[id].handlers.click();
    const call = calls.at(-1);
    assert.equal(call.url, '/personalize');
    const expected = Math.floor(Date.now()/1000) - new Date().getTimezoneOffset()*60;
    assert(Math.abs(Number(call.data.epoch) - expected) <= 1);
  }
  assert.equal(refreshes, 2);
  fail = true;
  await elements['act-sync-time'].handlers.click();
  assert.equal(elements['dash-action-status'].className, 'ota-status err');
  await elements['st-clock-sync'].handlers.click();
  assert.equal(elements['st-clock-sync'].textContent, 'Sync failed');
  assert.equal(elements['st-clock-sync'].disabled, false);
  assert.equal(refreshes, 2);
  console.log('UI deduplication checks passed');
})().catch(err => { console.error(err); process.exitCode = 1; });
