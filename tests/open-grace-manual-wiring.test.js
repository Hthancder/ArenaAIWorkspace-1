const assert=require('node:assert/strict'),fs=require('node:fs');
const dash=fs.readFileSync('extension/dashboard.js','utf8'),popup=fs.readFileSync('extension/popup.js','utf8'),popupHtml=fs.readFileSync('extension/popup.html','utf8');

// The toolbar and the single row both re-read the markers just before showing a manual confirmation.
assert.match(dash,/\{await bulkSleepDialog\(\);return\}/);
assert.match(dash,/if\(a==='discard'&&tab\)\{[\s\S]{0,400}OpenGrace\.notes\(chrome,\[tab\],Date\.now\(\)\)[\s\S]{0,300}confirmAction\('Cho tab nghỉ\?'/);

// The popup needs the same module because its preview and its row action explain the grace window too.
assert.match(popup,/PopupBulk\.preview\(chrome,\[\.\.\.popupSelected\.values\(\)\],Protection,OpenGrace\)/);
assert.match(popup,/const note=\(await OpenGrace\.notes\(chrome,\[fresh\],Date\.now\(\)\)\)/);
assert.ok(popupHtml.indexOf('open-grace.js')>=0&&popupHtml.indexOf('open-grace.js')<popupHtml.indexOf('popup-bulk.js'));
assert.ok(popupHtml.indexOf('open-grace.js')<popupHtml.indexOf('popup.js'));

// A preview note never disables a row: the user keeps the last word on a manual sleep.
assert.match(popup,/input\.checked=!r\.reason&&!r\.note;input\.disabled=!!r\.reason;input\.name='popupSleepTab';/);
console.log('Manual sleep grace wiring covers the dashboard, the popup row and the popup preview: OK');
