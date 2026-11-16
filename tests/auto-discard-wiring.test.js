const assert=require('node:assert/strict'),fs=require('node:fs');
const dash=fs.readFileSync('extension/dashboard.js','utf8'),html=fs.readFileSync('extension/dashboard.html','utf8'),background=fs.readFileSync('extension/background.js','utf8'),manifest=JSON.parse(fs.readFileSync('extension/manifest.json','utf8')),css=fs.readFileSync('extension/style.css','utf8');

// The module is loaded for the settings page and for the shared background cadence, before its callers.
assert.ok(html.includes('<script src="auto-discard.js"></script><script src="dashboard.js"></script>'),'auto-discard.js is loaded before dashboard.js');
assert.ok(/importScripts\([^)]*'auto-discard\.js'/.test(background),'the service worker loads the module too');
// Reading the resource numbers needs a permission this build deliberately does not request.
assert.ok(![...(manifest.permissions||[]),...(manifest.optional_permissions||[])].includes('processes'),'processes permission stays unrequested');
assert.ok(![...(manifest.permissions||[]),...(manifest.optional_permissions||[])].includes('system.memory'),'system.memory permission stays unrequested');

// The background run only measures: no discard writer and no second sleep path.
assert.match(background,/try\{if\(typeof AutoDiscard!=='undefined'\)await AutoDiscard\.run\(chrome,Date\.now\(\),\{grace:OpenGrace,protection:Protection,memory:chrome\.system\?\.memory\}\)\}catch\(e\)\{console\.error\('Resource measurement tick failed',e\)\}/);
assert.doesNotMatch(background,/tabs\.discard|DiscardTools/);
// A navigation drops the sample of that tab instead of charging the new page with the old numbers.
assert.match(background,/chrome\.tabs\?\.onUpdated\?\.addListener\(\(id,changeInfo\)=>\{if\(typeof AutoDiscard!=='undefined'&&Number\.isInteger\(id\)&&typeof changeInfo\?\.url==='string'\)void AutoDiscard\.forget\(chrome,\[id\]\)\.catch\(\(\)=>\{\}\)\}\)/);

// The setting and its result are loaded, kept fresh in the header, and saved through the shared lock.
assert.match(dash,/autoDiscardConfig=result\.autoDiscardConfig;autoDiscardRun=result\.autoDiscardRun;/);
assert.match(dash,/changes\.autoDiscardConfig\|\|changes\.autoDiscardRun\|\|/);
assert.ok(dash.includes('${autoDiscardBlock()}<div class="card settingscard"><h2>Thông báo trên website</h2>'),'the block sits inside the settings view');
assert.match(dash,/async function saveAutoDiscard\(\)\{[\s\S]{0,600}if\(autoDiscardBusy\)return;autoDiscardBusy=true;[\s\S]{0,400}await MutationLock\.run\(async\(\)=>\{/);
assert.match(dash,/const next=AutoDiscard\.assertUsable\(patch,autoDiscardContext\(\)\);/);
assert.match(dash,/function autoDiscardContext\(\)\{return \{measurable:autoDiscardCapability\(\)\.measurable,systemMemory:chrome\.system\?\.memory\?\.getInfo\?true:false\}\}/);
assert.match(dash,/const stored=Number\.isFinite\(autoDiscardRun\?\.at\)\?autoDiscardRun:null;/);
// Every action of the block is reachable from the delegated handler.
for(const action of ['auto-discard-toggle','auto-discard-save','auto-discard-measure','auto-discard-reset','auto-discard-choose'])assert.ok(dash.includes(`if(b.dataset.action==='${action}')`),`${action} is wired`);
assert.match(dash,/if\(b\.dataset\.action==='auto-discard-reset'\)\{resetAutoDiscardForm\(\);return\}/);
assert.match(dash,/if\(e\.key==='Escape'&&autoDiscardOpen&&!\$\('#dialog'\)\.open&&!\$\('#palette'\)\.open\)\{e\.preventDefault\(\);collapseAutoDiscard\(\);return\}/);
assert.match(dash,/function collapseAutoDiscard\(\)\{if\(!autoDiscardOpen\|\|autoDiscardBusy\)return;/);
assert.match(dash,/if\(e\.target\.id\?\.startsWith\('autoDiscardRes-'\)\)\{const box=document\.getElementById\('autoDiscardThreshold-'/);

// Both surfaces measure through one entry point, and the manual one cannot trigger a run.
assert.match(dash,/const result=await AutoDiscard\.run\(chrome,Date\.now\(\),\{grace:OpenGrace,protection:Protection,memory:chrome\.system\?\.memory,tabs\},\{force:true\}\);/);
assert.doesNotMatch(dash,/async function autoDiscardMeasure\(\)\{[\s\S]{0,6000}tabs\.discard|async function autoDiscardChoose\(\)\{[\s\S]{0,900}tabs\.discard/);
assert.match(dash,/if\(result\.status!=='measured'\)\{\s*autoDiscardSummary=null;await load\(\);/);

// The collapsed header is a real toggle, and the animation follows the shared motion settings.
assert.match(dash,/<button type="button" class="auto-discard-head" id="autoDiscardToggle" aria-expanded="\$\{autoDiscardOpen\?'true':'false'\}" aria-controls="autoDiscardBody">/);
assert.match(dash,/<div class="auto-discard-body\$\{autoDiscardOpen\?'':' hidden'\}" id="autoDiscardBody">/);
assert.match(dash,/Số đo lấy lại theo chu kỳ ở trên, chạy cùng lịch với các việc nền khác; chưa có lượt nghỉ tự động và chưa xin quyền đọc tiến trình/);
assert.match(css,/@keyframes autoDiscardIn\{from\{opacity:0;transform:translateY\(-3px\)\}to\{opacity:1;transform:none\}\}/);
assert.match(css,/:root\[data-motion="reduce"\] \*/);
console.log('Resource measurement shares one entry point, stays read-only, and asks for no new permission: OK');
