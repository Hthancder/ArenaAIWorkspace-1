const assert=require('node:assert/strict'),fs=require('node:fs');
const mod=fs.readFileSync('extension/auto-discard.js','utf8'),opts=fs.readFileSync('extension/backup-options.js','utf8'),dash=fs.readFileSync('extension/dashboard.js','utf8'),html=fs.readFileSync('extension/dashboard.html','utf8'),background=fs.readFileSync('extension/background.js','utf8'),manifest=JSON.parse(fs.readFileSync('extension/manifest.json','utf8')),css=fs.readFileSync('extension/style.css','utf8');

// The module is loaded for the settings page and for the shared background cadence, before its callers.
assert.ok(html.includes('<script src="auto-discard.js"></script><script src="dashboard.js"></script>'),'auto-discard.js is loaded before dashboard.js');
assert.ok(/importScripts\([^)]*'auto-discard\.js'/.test(background),'the service worker loads the module too');
// Reading the resource numbers needs a permission this build deliberately does not request.
assert.ok(![...(manifest.permissions||[]),...(manifest.optional_permissions||[])].includes('processes'),'processes permission stays unrequested');
assert.ok(![...(manifest.permissions||[]),...(manifest.optional_permissions||[])].includes('system.memory'),'system.memory permission stays unrequested');

// The worker measures, then hands any automatic plan to the module; it keeps no discard call of its own.
assert.match(background,/const measured=await AutoDiscard\.run\(chrome,Date\.now\(\),\{grace:OpenGrace,protection:Protection,memory:chrome\.system\?\.memory\}\)/);
assert.match(background,/if\(measured\?\.status==='measured'&&measured\.action\)await AutoDiscard\.apply\(chrome,measured,Date\.now\(\),\{discard:DiscardTools,protection:Protection,reminders:ReminderTools\}\)/,'the worker hands the shared hold settings to the run instead of letting the module guess them');
assert.match(background,/catch\(e\)\{console\.error\('Automatic discard run failed',e\)\}/,'an action failure is logged, not replayed silently every minute');
assert.match(background,/importScripts\([^)]*'discard\.js','auto-discard\.js'/,'the shared discard tool is loaded for the worker too');
assert.doesNotMatch(background,/chrome\.tabs\.discard|tabs\.discard\(|tabs\.remove\(/,'the worker never discards or closes a tab by itself');
// A navigation drops the sample of that tab instead of charging the new page with the old numbers.
assert.match(background,/chrome\.tabs\?\.onUpdated\?\.addListener\(\(id,changeInfo\)=>\{if\(typeof AutoDiscard!=='undefined'&&Number\.isInteger\(id\)&&typeof changeInfo\?\.url==='string'\)void AutoDiscard\.forget\(chrome,\[id\]\)\.catch\(\(\)=>\{\}\)\}\)/);

// Only the settings travel, and never the ability to act on them.
assert.match(dash,/function backupOptionTools\(\)\{return \{[^}]*resource:AutoDiscard\}\}/);
assert.match(dash,/if\(applyResource\)Object\.assign\(fields,BackupOptions\.resource\(personal\.resource,backupOptionTools\(\)\)\)/);
assert.match(dash,/\.\.\.\(applyResource\?\['autoDiscardConfig'\]:\[\]\)\];/);
assert.match(opts,/if\(resource\)result\.resource=tools\.resource\.validate\(storage\.autoDiscardConfig\);/);
assert.match(opts,/function resource\(value,tools\)\{[\s\S]{0,200}enabled:false,mode:value\.mode==='auto'\?'ask':value\.mode/);
assert.doesNotMatch(opts,/storage\.session|runKey|overCount/,'a backup never carries measurement values');

// 15.3/15.7: the block schedules nothing on its own, and the header stays usable without a mouse.
assert.doesNotMatch(mod,/alarms\.|setTimeout|setInterval|tabs\.discard|\.create\(|removeAlarm/,'the module waits for the shared alarm and never touches a tab');
assert.equal((background.match(/AutoDiscard\./g)||[]).length,3,'the service worker uses the module in exactly three places: run, apply, forget');
assert.match(css,/\.auto-discard-head\{display:flex;align-items:center;gap:12px;flex-wrap:wrap/);
assert.match(css,/\.auto-discard-head:focus-visible\{outline:3px solid/);
assert.match(css,/@media\(max-width:600px\)\{\.auto-discard-head\{padding:14px 16px\}\.auto-discard-body\{padding:0 16px 16px\}\.auto-discard-head em\{margin-left:auto\}\}/);
assert.doesNotMatch(css,/\.auto-discard[a-z-]*\{[^}]*(overflow:hidden|height:\s*\d)/,'nothing clips the block when the window is narrow or zoomed');
// 5.7 exists now, so the select says where the list lives instead of admitting it is missing.
assert.match(dash,/Mức Chỉ gợi ý chỉ để danh sách ở Sức khỏe tab: không nhắc, không tự chọn tab nào\./);
assert.doesNotMatch(dash,/chưa có danh sách riêng ở Sức khỏe tab/);
const palette=fs.readFileSync('extension/palette.js','utf8');
const health=dash.slice(dash.indexOf('function healthData()'),dash.indexOf('function renderSavedOpen()'));
assert.ok(health.length>500,'the health view is one contiguous block of the dashboard');
assert.ok(html.includes('<button class="nav" data-view="health">')&&html.includes('id="sideHealth"'),'the page has its own place in the sidebar');
assert.match(palette,/\['health','Sức khỏe tab'\],/,'and it is reachable from the command palette');
assert.match(dash,/else if\(view==='health'\)renderHealth\(\)/);
assert.match(dash,/,'health':\['Sức khỏe tab',/,'every view needs a title or the page throws');
assert.ok(dash.includes("$('#sideHealth').textContent=health.list&&!health.list.dismissed?health.list.overCount:''"),'the badge counts the same list the page shows');
assert.equal((dash.match(/AutoDiscard\.health\(/g)||[]).length,3,'one decision function, three readers, no second opinion');
for(const action of ['review','dismiss','restore']){
 assert.ok(health.includes(`data-action="auto-discard-suggest-${action}"`),`the list offers ${action}`);
 assert.ok(dash.includes(`autoDiscardSuggestAction('${action}')`),`and the page handles ${action}`);
}
assert.doesNotMatch(health,/tabs\.discard|data-action="discard"|Cho tab nghỉ|chrome\.|\.set\(|history\.|\"fetch\"/,'the health page reads a record; it never acts on a tab');

// The setting comes from storage.local and the measurement from storage.session, kept fresh in the header.
assert.match(dash,/chrome\.storage\.session\?\.get\?chrome\.storage\.session\.get\(\[AutoDiscard\.runKey\]\)\.catch\(\(\)=>\(\{\}\)\):Promise\.resolve\(\{\}\)/);
assert.match(dash,/autoDiscardConfig=result\.autoDiscardConfig;autoDiscardRun=measurement\?\.\[AutoDiscard\.runKey\];/);
assert.match(dash,/if\(area==='session'&&changes\[AutoDiscard\.runKey\]\)dashboardRefresh\.request\(\);/);
assert.match(mod,/if\(!journal\)return \{status:'blocked',reason:'Không có nơi giữ kết quả đo trên máy; chrome\.storage\.session không khả dụng\.',config\};/);
assert.match(mod,/if\(data\[runKey\]!==undefined\)try\{await api\.storage\.local\.remove\?\.\(runKey\)\}catch\{\}/);
assert.match(mod,/try\{await journal\.set\(\{\[runKey\]:summary\}\)\}catch\{/);
assert.doesNotMatch(mod,/storage\.local\.set\(\{\[runKey\]/,'a measurement never lands in the persisted backup area');
// The setting and its result are saved through the shared lock.
assert.match(dash,/changes\.autoDiscardConfig\|\|changes\.autoDiscardRun\|\|/);
assert.ok(dash.includes('${autoDiscardBlock()}<div class="card settingscard"><h2>Thông báo trên website</h2>'),'the block sits inside the settings view');
// The guarded write is intact even though an acknowledgement dialog may sit in front of it.
assert.match(dash,/async function saveAutoDiscard\(\)\{\n if\(autoDiscardBusy\)return;autoDiscardBusy=true;\n try\{await saveAutoDiscardOnce\(\)\}\n catch\(error\)\{/);
assert.match(dash,/async function saveAutoDiscardOnce\(\)\{[\s\S]{0,700}await MutationLock\.run\(async\(\)=>\{/);
assert.match(dash,/if\(\/xác nhận rủi ro\/\.test\(error\?\.message\|\|''\)\)\{autoDiscardBusy=false;await autoDiscardRiskDialog\(\);return\}/,'the refusal turns into one dialog, never a silent default');
assert.match(mod,/const held=await holdReason\(api,deps,now,data\);\n  if\(held\)return \{status:'waiting',reason:held\};/,'the room is asked once, in one place, and the answer ends the run');
assert.doesNotMatch(mod,/deferFullscreen\(api,data\.deferFullscreenNotifications\)/,'a notification preference never unlocks the unattended discard');
assert.match(dash,/const next=AutoDiscard\.assertUsable\(patch,\{\.\.\.autoDiscardContext\(\),ack:autoDiscardAck\}\);/,'the save hands the acknowledgement to the same gate that refuses without it');
assert.match(dash,/function autoDiscardContext\(\)\{return \{measurable:autoDiscardCapability\(\)\.measurable,systemMemory:chrome\.system\?\.memory\?\.getInfo\?true:false\}\}/);
assert.match(dash,/const stored=Number\.isFinite\(autoDiscardRun\?\.at\)\?autoDiscardRun:null;/);
// Every action of the block is reachable from the delegated handler.
for(const action of ['auto-discard-toggle','auto-discard-save','auto-discard-measure','auto-discard-reset','auto-discard-choose','auto-discard-limits','auto-discard-review','auto-discard-dismiss','auto-discard-restore'])assert.ok(dash.includes(`if(b.dataset.action==='${action}')`),`${action} is wired`);
assert.match(dash,/if\(b\.dataset\.action==='auto-discard-reset'\)\{resetAutoDiscardForm\(\);return\}/);
assert.match(dash,/if\(e\.key==='Escape'&&autoDiscardOpen&&!\$\('#dialog'\)\.open&&!\$\('#palette'\)\.open\)\{e\.preventDefault\(\);collapseAutoDiscard\(\);return\}/);
assert.match(dash,/function collapseAutoDiscard\(\)\{if\(!autoDiscardOpen\|\|autoDiscardBusy\)return;/);
assert.match(dash,/if\(e\.target\.id\?\.startsWith\('autoDiscardRes-'\)\)\{const box=document\.getElementById\('autoDiscardThreshold-'/);

// Both surfaces measure through one entry point, and the manual one cannot trigger a run.
assert.match(dash,/const result=await AutoDiscard\.run\(chrome,Date\.now\(\),\{grace:OpenGrace,protection:Protection,memory:chrome\.system\?\.memory,tabs\},\{force:true\}\);/);
assert.doesNotMatch(dash,/async function autoDiscardMeasure\(\)\{[\s\S]{0,6000}tabs\.discard|async function autoDiscardChoose\(\)\{[\s\S]{0,900}tabs\.discard/);
assert.match(dash,/if\(result\.status!=='measured'\)\{\s*autoDiscardSummary=null;await load\(\);/);

// The memory gate reads a real system number and holds the cycle back when memory is fine.
assert.match(mod,/const free=await systemFreePercent\(deps\.memory\);/);
assert.match(mod,/if\(!options\.force&&free>=config\.lowMemoryFloor\)return \{status:'waiting',config,reason:`RAM khả dụng còn \$\{free\}%/);
assert.match(mod,/if\(!Number\.isFinite\(capacity\)\|\|!Number\.isFinite\(free\)\|\|capacity<=0\|\|free<0\|\|free>capacity\)return null;/);
assert.doesNotMatch(mod,/lowMemoryFloor\s*[<>]/,'no invented comparison against a guessed memory number');

// The measured candidates reach the user as one review card in Cần chú ý, decided by the module.
// The card and the 5.7 list read the same record: one freshness gate, one mode each, never a second copy.
assert.match(mod,/function recent\(c,run,now,mode\)\{[\s\S]{0,240}if\(!c\.enabled\|\|c\.mode!==mode\)return null/);
assert.match(mod,/function attention\(config,run,now\)\{[^}]*recent\(c,run,now,'ask'\)/);
assert.match(mod,/function suggestions\(config,run,now\)\{[^}]*recent\(c,run,now,'suggest'\)/);
assert.equal((mod.match(/now-run\.at>=2\*c\.everyMinutes\*60000/g)||[]).length,1,'the expiry rule exists once for both surfaces');
assert.equal((mod.match(/c\.mode!==mode/g)||[]).length,1,'the mode gate exists once');
assert.match(mod,/if\(now-run\.at>=2\*c\.everyMinutes\*60000\)return null;/);
assert.match(mod,/if\(!run\|\|run\.at!==at\)throw Error\('Lần đo đã thay đổi ở nơi khác/);
assert.match(mod,/next\.dismissedAt=at;/);
assert.match(dash,/function autoDiscardAttention\(\)\{return AutoDiscard\.attention\(autoDiscardConfig,autoDiscardRun,Date\.now\(\)\)\}/);
assert.match(dash,/<\/div>\$\{autoDiscardAttentionCard\(resource\)\}\$\{notificationHistoryPanel\(\)\}/);
assert.ok(dash.includes("if(!card){notify('Thẻ không còn hiệu lực; hãy đo lại trong Cài đặt.');return}"),'an expired card refuses every action');
// The card is decided once, in the module, and counts as something needing attention.
assert.match(dash,/resource:AutoDiscard\.attention\(autoDiscardConfig,autoDiscardRun,Date\.now\(\)\)\};/);
assert.match(dash,/const \{reminders,uncertain,autoIssues,resource\}=attentionData\(\);/);
assert.match(dash,/\$\('#sideAttention'\)\.textContent=attention\.reminders\.length\+attention\.uncertain\.length\+attention\.autoIssues\.length\+\(attention\.resource\?1:0\);/);
// Both entry points mark tabs through one routine, so the card cannot promise more than the dialog does.
assert.match(dash,/function autoDiscardChoose\(\)\{autoDiscardMark\(autoDiscardSummary\?\.ids\|\|\[\],true\)\}/);
assert.match(dash,/function autoDiscardMark\(ids,clearSummary\)\{[\s\S]{0,220}filter\(id=>tabs\.some\(t=>t\.id===id\)\)/);
assert.doesNotMatch(dash,/function autoDiscardAttentionCard\(\)\{[\s\S]{0,1800}tabs\.discard|function autoDiscardAttentionAction\([\s\S]{0,1200}tabs\.discard/);

// The collapsed header is a real toggle, and the animation follows the shared motion settings.
assert.match(dash,/<button type="button" class="auto-discard-head" id="autoDiscardToggle" aria-expanded="\$\{autoDiscardOpen\?'true':'false'\}" aria-controls="autoDiscardBody">/);
assert.match(dash,/<div class="auto-discard-body\$\{autoDiscardOpen\?'':' hidden'\}" id="autoDiscardBody">/);
assert.match(dash,/Số đo lấy lại theo chu kỳ ở trên, chạy cùng lịch với các việc nền khác\. Mức Tự động có đường nghỉ riêng nhưng chỉ chạy khi Chrome cho số đo tiến trình thật \(kênh Dev\)/,'the note no longer promises there is no automatic path');
// 15.3: the automatic level is explained where it is chosen, and its consent is stated as local.
assert.match(dash,/Mức Tự động nghỉ tab mà không hỏi lại, cần bạn xác nhận rủi ro một lần, và chỉ chạy khi Chrome cho số đo thật\./);
assert.match(dash,/Tabspace vẫn chưa xin quyền đọc tiến trình nên trên Chrome ổn định không có lượt tự nghỉ nào/);
assert.match(dash,/autoDiscardAck=stamp/,'the page remembers the acknowledgement without waiting for a reload');
assert.match(dash,/return showDialog\(`<h2>Bạn sắp để Tabspace tự cho nghỉ tab\?/,'one dialog, asking once');
assert.match(dash,/\[AutoDiscard\.ackKey\]:stamp/,'and it is stored under its own key, never inside the config');
assert.doesNotMatch(dash,/autoDiscardConfig=\{[^}]*ack/,'no ack field can leak into the settings object');
assert.match(css,/@keyframes autoDiscardIn\{from\{opacity:0;transform:translateY\(-3px\)\}to\{opacity:1;transform:none\}\}/);
assert.match(css,/:root\[data-motion="reduce"\] \*/);
console.log('Resource measurement shares one entry point, reaches Cần chú ý as a card and Sức khỏe tab as a list, and asks for no new permission: OK');
