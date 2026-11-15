const assert=require('node:assert/strict'),fs=require('node:fs');
const dash=fs.readFileSync('extension/dashboard.js','utf8'),html=fs.readFileSync('extension/dashboard.html','utf8'),background=fs.readFileSync('extension/background.js','utf8'),manifest=JSON.parse(fs.readFileSync('extension/manifest.json','utf8')),css=fs.readFileSync('extension/style.css','utf8');

// The module is loaded for the settings page only, and before the page script that calls it.
assert.ok(html.includes('<script src="auto-discard.js"></script><script src="dashboard.js"></script>'),'auto-discard.js is loaded before dashboard.js');
assert.doesNotMatch(background,/AutoDiscard/,'no background sampler or automatic run yet');
// Reading the resource numbers needs a permission this build deliberately does not request.
assert.ok(![...(manifest.permissions||[]),...(manifest.optional_permissions||[])].includes('processes'),'processes permission stays unrequested');

// The setting is loaded, kept fresh in the header, and saved through the shared lock.
assert.match(dash,/autoDiscardConfig=result\.autoDiscardConfig;/);
assert.match(dash,/changes\.openGraceMinutes\|\|changes\.autoDiscardConfig\|\|/);
assert.ok(dash.includes('${autoDiscardBlock()}<div class="card settingscard"><h2>Thông báo trên website</h2>'),'the block sits inside the settings view');
assert.match(dash,/async function saveAutoDiscard\(\)\{[\s\S]{0,600}if\(autoDiscardBusy\)return;autoDiscardBusy=true;[\s\S]{0,400}await MutationLock\.run\(async\(\)=>\{/);
assert.match(dash,/const next=AutoDiscard\.assertUsable\(patch,autoDiscardCapability\(\)\);/);
// Every action of the block is reachable from the delegated handler.
for(const action of ['auto-discard-toggle','auto-discard-save','auto-discard-measure','auto-discard-reset','auto-discard-choose'])assert.ok(dash.includes(`if(b.dataset.action==='${action}')`),`${action} is wired`);
assert.match(dash,/if\(b\.dataset\.action==='auto-discard-reset'\)\{resetAutoDiscardForm\(\);return\}/);
assert.match(dash,/if\(e\.key==='Escape'&&autoDiscardOpen&&!\$\('#dialog'\)\.open&&!\$\('#palette'\)\.open\)\{e\.preventDefault\(\);collapseAutoDiscard\(\);return\}/);
assert.match(dash,/function collapseAutoDiscard\(\)\{if\(!autoDiscardOpen\|\|autoDiscardBusy\)return;/);
assert.match(dash,/if\(e\.target\.id\?\.startsWith\('autoDiscardRes-'\)\)\{const box=document\.getElementById\('autoDiscardThreshold-'/);

// Listing candidates never discards and never asks for a second sleep path.
assert.match(dash,/async function autoDiscardMeasure\(\)\{[\s\S]{0,200}if\(protectionError\)throw Error\('Danh sách bảo vệ không hợp lệ/);
assert.doesNotMatch(dash,/async function autoDiscardMeasure\(\)\{[\s\S]{0,6000}tabs\.discard|async function autoDiscardChoose\(\)\{[\s\S]{0,900}tabs\.discard/);
assert.match(dash,/async function autoDiscardMeasure\(\)\{[\s\S]{0,3000}mode:'suggest'[\s\S]{0,300}protected:kept/);
assert.match(dash,/function autoDiscardState\(\)\{[\s\S]{0,300}measurable:autoDiscardCapability\(\)\.measurable,paused:automationPaused/);

// The collapsed header is a real toggle, and the animation follows the shared motion settings.
assert.match(dash,/<button type="button" class="auto-discard-head" id="autoDiscardToggle" aria-expanded="\$\{autoDiscardOpen\?'true':'false'\}" aria-controls="autoDiscardBody">/);
assert.match(dash,/<div class="auto-discard-body\$\{autoDiscardOpen\?'':' hidden'\}" id="autoDiscardBody">/);
assert.match(css,/@keyframes autoDiscardIn\{from\{opacity:0;transform:translateY\(-3px\)\}to\{opacity:1;transform:none\}\}/);
assert.match(css,/:root\[data-motion="reduce"\] \*/);
console.log('Resource block is wired for review only, with no permission and no background sampler: OK');
