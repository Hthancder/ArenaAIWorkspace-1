const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),AutoDiscard=require('../extension/auto-discard.js'),OpenGrace=require('../extension/open-grace.js'),Protection=require('../extension/protection.js');
const src=fs.readFileSync('extension/dashboard.js','utf8');
const start=src.indexOf('// The resource block stays collapsed by default'),end=src.indexOf('\nasync function journalSound(',start);
assert(start>=0&&end>start,'the auto-discard helpers live in the dashboard');
const now=1700000000000,bytes=megabytes=>megabytes*1048576;
let ctx={},els={},db={},session={},storageFails=false,rendered=[],notices=[],dialog=null,closed=0,loads=0,discards=0,focuses=0;
const makeEl=(attrs={})=>({value:'',checked:false,disabled:false,focus(){focuses++},...attrs});
const ctxBase={
 AutoDiscard,OpenGrace,Protection,esc:value=>String(value??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'),
 view:'settings',tabs:[],automationPaused:false,isDashboard:url=>String(url).includes('dashboard.html'),protectionError:false,protectedDomains:[],protectedUrls:[],
 autoDiscardConfig:undefined,autoDiscardRun:undefined,autoDiscardOpen:false,autoDiscardBusy:false,autoDiscardNotifications:false,autoDiscardSummary:null,autoDiscardAck:null,autoDiscardAction:null,
 query:'x',selected:new Set(),bulkSelected:new Set(),selectionAnchor:1,selectionClick:1,
 render(){rendered.push(ctx.view)},load:async()=>{loads++},notify:message=>notices.push(message),
 $:selector=>els[selector.replace(/^#/,'')],document:{getElementById:id=>els[id]??null},
 MutationLock:{run:work=>work()},
 showDialog:(markup,handler)=>{dialog={markup,handler}},
 chrome:{storage:{local:{get:async()=>structuredClone(db),set:async value=>{if(storageFails)throw Error('unknown');Object.assign(db,structuredClone(value))}}}},
};
vm.runInNewContext(src.slice(start,end),ctxBase);
ctx=ctxBase;
const chromeless=ctx.chrome;
const tab=(id,extra={})=>({id,windowId:1,url:`https://example.com/${id}`,title:'Tab '+id,incognito:false,active:false,pinned:false,audible:false,discarded:false,lastAccessed:now-48*3600000,...extra});
// Every field the block renders, so the form can be filled without a real DOM.
function fillForm(config){
 els={dialog:makeEl({open:false,close(){closed++;els.dialog.open=false}}),search:makeEl({value:'x'}),autoDiscardToggle:makeEl(),autoDiscardBody:makeEl(),
  autoDiscardEnabled:makeEl({checked:config.enabled}),autoDiscardMode:makeEl({value:config.mode}),autoDiscardCombine:makeEl({value:config.combine}),
  autoDiscardCycles:makeEl({value:String(config.cpuCycles)}),autoDiscardIdle:makeEl({value:String(config.idleMinutes)}),
  autoDiscardMax:makeEl({value:String(config.maxPerRun)}),autoDiscardEvery:makeEl({value:String(config.everyMinutes)}),
  autoDiscardLowMemory:makeEl({checked:config.lowMemoryOnly}),autoDiscardLowMemoryFloor:makeEl({value:String(config.lowMemoryFloor)})};
 for(const name of AutoDiscard.keys){
  const on=config.resources.includes(name);
  els['autoDiscardRes-'+name]=makeEl({checked:on});
  els['autoDiscardThreshold-'+name]=makeEl({value:String(config.thresholds[name]??'')});
 }
}

// The collapsed header is understandable on its own and never shows a number Chrome did not give.
ctx.autoDiscardConfig=undefined;
let markup=ctx.autoDiscardBlock();
assert.match(markup,/aria-expanded="false"/);
assert.match(markup,/class="auto-discard-body hidden"/);
assert.match(markup,/Không đo được tài nguyên trên Chrome này/);
assert.match(markup,/Chỉ còn đường cho nghỉ thủ công/);
assert.match(markup,/Quyền đọc tiến trình là quyền tùy chọn: chỉ xin được bằng nút Xin quyền đọc tiến trình trong khối này/);
// A broken setting collapses to an explanation instead of an editable form.
ctx.autoDiscardConfig={enabled:'yes'};
markup=ctx.autoDiscardBlock();
assert.match(markup,/Cấu hình cho nghỉ theo tài nguyên không hợp lệ/);
assert.doesNotMatch(markup,/id="autoDiscardEnabled"/);
assert.doesNotMatch(markup,/data-action="auto-discard-save"/);

(async()=>{
 // Opening the block keeps focus on its button and leaves stored data untouched.
 ctx.autoDiscardConfig=undefined;
 fillForm(AutoDiscard.validate());
 const rendersBefore=rendered.length;
 ctx.toggleAutoDiscard();
 assert.equal(rendered.length,rendersBefore+1);
 assert.equal(ctx.autoDiscardOpen,true);
 assert.ok(focuses>0);
 markup=ctx.autoDiscardBlock();
 assert.match(markup,/aria-expanded="true"/);
 // An unsaved edit survives a background refresh, while the header still states the saved policy.
 els.autoDiscardEvery.value='17';
 els['autoDiscardRes-network'].checked=true;
 markup=ctx.autoDiscardBlock();
 assert.match(markup,/id="autoDiscardEvery" min="1" max="60" step="1" value="17"/);
 assert.match(markup,/id="autoDiscardRes-network" checked/);
 assert.match(markup,/<span>Không đo được tài nguyên trên Chrome này\. Chỉ còn đường cho nghỉ thủ công ở Tab đang mở\.<\/span>/);
 els.autoDiscardEvery.value='5';
 els['autoDiscardRes-network'].checked=false;
 assert.match(markup,/Thu gọn/);
 assert.doesNotMatch(markup,/auto-discard-body hidden/);
 assert.deepEqual(db,{});
 // Esc while an action runs must not throw the user out of a half-finished save.
 ctx.autoDiscardBusy=true;
 ctx.collapseAutoDiscard();
 assert.equal(ctx.autoDiscardOpen,true);
 ctx.autoDiscardBusy=false;
 ctx.collapseAutoDiscard();
 assert.equal(ctx.autoDiscardOpen,false);
 assert.equal(loads,0);

 // Saving reads the form, keeps the module's ranges and refuses to overwrite a newer write.
 fillForm(AutoDiscard.validate());
 await ctx.saveAutoDiscard();
 assert.equal(loads,1);
 assert.deepEqual(db.autoDiscardConfig,AutoDiscard.validate());
 assert.match(notices.at(-1),/Đã lưu thiết lập/);
 db={autoDiscardConfig:{...AutoDiscard.validate(),everyMinutes:9}};
 ctx.autoDiscardConfig=undefined;
 fillForm(AutoDiscard.validate());
 await assert.rejects(()=>ctx.saveAutoDiscard(),/đã thay đổi ở nơi khác/);
 ctx.autoDiscardConfig={...AutoDiscard.validate(),everyMinutes:5};
 await assert.rejects(()=>ctx.saveAutoDiscard(),/đã thay đổi ở nơi khác/);
 assert.equal(db.autoDiscardConfig.everyMinutes,9);
 // Enabling without a measurement source is refused rather than quietly inert.
 db={};ctx.autoDiscardConfig=undefined;
 const enabled={...AutoDiscard.validate(),enabled:true};
 fillForm(enabled);
 await assert.rejects(()=>ctx.saveAutoDiscard(),/Không đo được tài nguyên trên Chrome này/);
 assert.equal(db.autoDiscardConfig,undefined);
 // A threshold out of range is reported by the module, not clamped.
 ctx.autoDiscardConfig=undefined;
 fillForm({...enabled,thresholds:{memory:20000,cpu:50,heap:200,network:20}});
 await assert.rejects(()=>ctx.saveAutoDiscard(),/Ngưỡng bộ nhớ/);
 // An unselected resource with an empty field still saves; it only keeps the default for display.
 const partial={enabled:false,mode:'ask',combine:'any',resources:['memory','cpu'],thresholds:{memory:500,cpu:50,network:20},cpuCycles:3,idleMinutes:720,maxPerRun:10,everyMinutes:5,lowMemoryOnly:false,lowMemoryFloor:20};
 db={autoDiscardConfig:structuredClone(partial)};
 ctx.autoDiscardConfig=structuredClone(partial);
 fillForm(partial);
 assert.deepEqual([els['autoDiscardRes-heap'].checked,els['autoDiscardThreshold-heap'].value],[false,'']);
 await ctx.saveAutoDiscard();
 assert.equal(db.autoDiscardConfig.thresholds.heap,200);
 assert.equal(db.autoDiscardConfig.resources.join(','),'memory,cpu');
 // A storage write that cannot be confirmed is reported and keeps the previous value visible.
 ctx.autoDiscardConfig=structuredClone(db.autoDiscardConfig);
 fillForm({...db.autoDiscardConfig,mode:'suggest'});
 storageFails=true;
 await assert.rejects(()=>ctx.saveAutoDiscard(),/Không xác nhận được việc lưu/);
 storageFails=false;
 assert.equal(db.autoDiscardConfig.mode,'ask');
 // Resetting only fills the form: the stored policy waits for an explicit save.
 const saved=structuredClone(db.autoDiscardConfig);
 ctx.resetAutoDiscardForm();
 assert.match(notices.at(-1),/Đã đặt lại trong biểu mẫu/);
 assert.deepEqual(db.autoDiscardConfig,saved);
 assert.equal(String(els.autoDiscardCycles.value),'3');
 assert.equal(String(els.autoDiscardIdle.value),'720');
 assert.equal(els['autoDiscardThreshold-heap'].disabled,true);

 // The form follows the order of the settings: scope first, then the cadence and its memory gate.
 const body=ctx.autoDiscardBlock();
 for(const [before,after] of [['autoDiscardRes-memory','autoDiscardIdle'],['autoDiscardIdle','autoDiscardMax'],['autoDiscardMax','autoDiscardEvery'],['autoDiscardEvery','autoDiscardCycles'],['autoDiscardCycles','autoDiscardLowMemoryFloor'],['autoDiscardLowMemoryFloor','autoDiscardLowMemory']])
  assert.ok(body.indexOf(`id="${before}"`)<body.indexOf(`id="${after}"`),`${before} comes before ${after}`);
 assert.match(body,/chu kỳ đo chỉ chạy khi RAM khả dụng thấp hơn mức này\./);
 // The limits explainer is readable from the block and changes nothing when it is opened and closed.
 const dbBefore=JSON.stringify(db),loadsBefore=loads;
 ctx.autoDiscardLimits();
 for(const phrase of [/tiến trình renderer/,/không chỉ ra được tab nào nặng hơn/,/không tạo bản lưu để khôi phục/,/luôn ở trạng thái tắt khi nhập/,/giờ yên lặng và toàn màn hình được đọc lại <b>ngay trước khi nghỉ tab<\/b>/,/không cho biết tình trạng cửa sổ/,/không<\/b> mở đường cho lượt tự nghỉ/,/nhật ký sự kiện \(nếu bạn bật nhật ký\)/,/kênh <b>riêng<\/b> trong khối, mặc định tắt/])assert.match(dialog.markup,phrase);
 assert.doesNotMatch(dialog.markup,/bật lại giờ yên lặng trong khối|đặt giờ yên lặng ở đây/);
 assert.doesNotMatch(dialog.markup,/example\.com|https?:/);
 await dialog.handler(new Map(),{close(){closed++}});
 assert.deepEqual([JSON.stringify(db),loads,closed>0],[dbBefore,loadsBefore,true]);

 // Listing without a real source explains itself and touches no tab.
 ctx.autoDiscardOpen=true;
 await ctx.autoDiscardMeasure();
 assert.match(dialog.markup,/Không đo được tài nguyên trên Chrome này/);
 assert.match(dialog.markup,/cho nghỉ thủ công/);
 assert.equal(discards,0);
 assert.equal(ctx.autoDiscardSummary,null);
 await dialog.handler(new Map(),{close(){closed++}});
 // With a measurement source the list is per-process, keeps skip reasons and still does not discard.
 const info={10:{privateMemory:bytes(1400),cpu:20},11:{privateMemory:bytes(100),cpu:90}};
 ctx.tabs=[tab(1),tab(2),tab(3),tab(4,{active:true})];
 ctx.chrome={...chromeless,processes:{getProcessIdForTab:async id=>({1:10,2:11,3:12})[id],getProcessInfo:async ids=>Object.fromEntries(ids.map(id=>[id,info[id]]).filter(([,value])=>value))},
  storage:{...chromeless.storage,session:{get:async keys=>keys===null?structuredClone(session):Object.fromEntries(keys.filter(k=>k in session).map(k=>[k,structuredClone(session[k])])),set:async value=>Object.assign(session,structuredClone(value)),remove:async keys=>{for(const k of keys)delete session[k]}}},
  tabs:{query:async()=>structuredClone(ctx.tabs),discard:async()=>{discards++;throw Error('discard must not run')}}};
 // With a real source the header switches to the policy state instead of the capability warning.
 ctx.autoDiscardConfig={...AutoDiscard.validate(),enabled:false};
 assert.match(ctx.autoDiscardBlock(),/Tự cho nghỉ theo tài nguyên đang tắt/);
 ctx.autoDiscardConfig={...AutoDiscard.validate(),enabled:true,mode:'ask',resources:['memory'],thresholds:{memory:500,cpu:50,heap:200,network:20}};
 Object.assign(db,{autoDiscardConfig:structuredClone(ctx.autoDiscardConfig),protectedUrls:['https://example.com/2']});
 await ctx.autoDiscardMeasure();
 assert.match(dialog.markup,/Vừa đo 4 tab · 1 tab vượt ngưỡng/);
 assert.match(dialog.markup,/RAM 1,4 GB/);
 assert.match(dialog.markup,/Chưa đưa vào danh sách/);
 assert.match(dialog.markup,/Tab đang được xem/);
 assert.match(dialog.markup,/URL được bảo vệ|Website hoặc URL được bảo vệ/);
 assert.match(dialog.markup,/Chưa có số đo cho tab này/);
 assert.match(dialog.markup,/chưa tab nào bị nghỉ/);
 assert.match(dialog.markup,/Không xác định được thời điểm mở tab/);
 assert.match(dialog.markup,/Chọn 1 tab để xem trước/);
 assert.deepEqual([discards,ctx.autoDiscardSummary.overCount,session[AutoDiscard.runKey].overCount,session[AutoDiscard.runKey].blockedCount,loads],[0,1,1,3,loads]);
 assert.deepEqual(session[AutoDiscard.runKey].ids,[1]);
 ctx.autoDiscardRun=structuredClone(session[AutoDiscard.runKey]);
 assert.match(ctx.autoDiscardBlock(),/1 tab đang vượt ngưỡng/);
 // A run that has not refreshed for two cycles says so instead of presenting old numbers as current.
 const manual=ctx.autoDiscardSummary;
 ctx.autoDiscardSummary=null;
 ctx.autoDiscardRun={at:Date.now()-3600000,overCount:1,measurable:true};
 assert.match(ctx.autoDiscardBlock(),/dữ liệu đo đã cũ, hãy đo lại/);
 ctx.autoDiscardRun={at:Date.now(),overCount:1,measurable:true,missed:true};
 assert.match(ctx.autoDiscardBlock(),/có chu kỳ đo đã bỏ lỡ, không chạy bù/);
 ctx.autoDiscardRun={at:Date.now(),overCount:0,measurable:true};
 assert.match(ctx.autoDiscardBlock(),/chưa có tab nào vượt ngưỡng/);
 // A fresher manual measurement wins over the older background record.
 ctx.autoDiscardSummary=manual;
 assert.match(ctx.autoDiscardBlock(),/đo ngay bây giờ/);
 ctx.autoDiscardRun=structuredClone(session[AutoDiscard.runKey]);
 // A blocked measurement never lands in session storage, and no URL is written with it.
 assert.deepEqual(Object.keys(session).sort(),[AutoDiscard.key(1),AutoDiscard.key(2),AutoDiscard.runKey].sort());
 assert.equal(session[AutoDiscard.key(1)].url,undefined);
 assert.doesNotMatch(JSON.stringify(session),/https?:/);
 // The attention card is a pointer to the same manual preview, never a second sleep path.
 const runAt=Date.now();
 ctx.autoDiscardRun={at:runAt,overCount:2,blockedCount:1,measurable:true,ids:[1,2]};
 Object.assign(session,{[AutoDiscard.runKey]:structuredClone(ctx.autoDiscardRun)});
 let cardMarkup=ctx.autoDiscardAttentionCard();
 assert.match(cardMarkup,/Tab vượt ngưỡng tài nguyên \(2\)/);
 assert.match(cardMarkup,/1 tab bị chặn bởi danh sách bảo vệ hoặc đang được xem/);
 assert.match(cardMarkup,/chưa tab nào bị nghỉ; cần bạn xác nhận/);
 assert.match(cardMarkup,/>Xem & nghỉ</);
 assert.doesNotMatch(cardMarkup,/https?:|example\.com|tabspace:metrics/);
 await ctx.autoDiscardAttentionAction('review');
 assert.deepEqual([ctx.view,[...ctx.selected].sort(),discards],['open',[1,2],0]);
 assert.match(notices.at(-1),/Đã chọn 2 tab vượt ngưỡng; chưa cho nghỉ tab nào/);
 // Dismissing notes the measurement; the card then offers only to come back.
 await ctx.autoDiscardAttentionAction('dismiss');
 assert.equal(session[AutoDiscard.runKey].dismissedAt,runAt);
 ctx.autoDiscardRun=structuredClone(session[AutoDiscard.runKey]); // load() refreshes the page state after a write
 cardMarkup=ctx.autoDiscardAttentionCard();
 assert.match(cardMarkup,/đã bỏ qua ở lần đo này/);
 assert.match(cardMarkup,/>Hiện lại thẻ</);
 assert.doesNotMatch(cardMarkup,/auto-discard-review|auto-discard-dismiss/);
 await ctx.autoDiscardAttentionAction('restore');
 assert.equal(session[AutoDiscard.runKey].dismissedAt,undefined);
 ctx.autoDiscardRun=structuredClone(session[AutoDiscard.runKey]);
 assert.match(ctx.autoDiscardAttentionCard(),/>Xem & nghỉ</);
 // Old numbers do not nag, and an expired card refuses every action.
 ctx.autoDiscardRun={at:runAt-3600000,overCount:2,measurable:true,ids:[1,2]};
 assert.equal(ctx.autoDiscardAttentionCard(),'');
 await ctx.autoDiscardAttentionAction('dismiss');
 assert.match(notices.at(-1),/Thẻ không còn hiệu lực; hãy đo lại trong Cài đặt/);
 ctx.autoDiscardRun={at:runAt,overCount:2,measurable:true,ids:[404]};
 await ctx.autoDiscardAttentionAction('review');
 assert.match(notices.at(-1),/Không còn tab nào từ danh sách đo; chưa chọn tab nào/);
 assert.deepEqual([discards,[...ctx.selected].sort(),session[AutoDiscard.runKey].dismissedAt],[0,[1,2],undefined]);
 ctx.autoDiscardRun=structuredClone(session[AutoDiscard.runKey]);
 ctx.autoDiscardChoose();
 assert.equal(closed>=1,true);
 assert.deepEqual([ctx.view,[...ctx.selected],discards],['open',[1],0]);
 assert.match(notices.at(-1),/chưa cho nghỉ tab nào/);
 // The candidate list is dropped when the tabs moved on.
 ctx.tabs=[tab(1,{active:true})];
 ctx.autoDiscardSummary={overCount:1,measuredAt:now,ids:[99]};
 ctx.autoDiscardChoose();
 assert.match(notices.at(-1),/Không còn tab nào từ danh sách đo/);
 // 15.3: the automatic level is saved only after one explicit human yes, asked in a dialog of its own.
 ctx.chrome={...chromeless,processes:{getProcessIdForTab:async()=>10,getProcessInfo:async()=>({10:{privateMemory:bytes(1400),cpu:10}})}};
 const askSaved={...AutoDiscard.validate(),enabled:true,mode:'ask',resources:['memory'],thresholds:{memory:500,cpu:50,heap:200,network:20}};
 db={autoDiscardConfig:structuredClone(askSaved)};ctx.autoDiscardConfig=structuredClone(askSaved);ctx.autoDiscardAck=null;
 fillForm({...askSaved,mode:'auto'});
 dialog=null;
 await ctx.saveAutoDiscard();
 assert.equal(db.autoDiscardConfig.mode,'ask','nothing is stored while the risk is unacknowledged');
 assert.equal(db.autoDiscardAck,undefined,'no acknowledgement is invented on the user behalf');
 assert.match(dialog.markup,/Bạn sắp để Tabspace tự cho nghỉ tab\?/);
 assert.match(dialog.markup,/mỗi chu kỳ đo có thể cho nghỉ tối đa <b>10<\/b> tab <b>không hỏi lại<\/b>/);
 assert.match(dialog.markup,/không có bản lưu để khôi phục/);
 assert.match(dialog.markup,/tiến trình renderer/);
 assert.match(dialog.markup,/được kiểm lại ngay trước từng lệnh nghỉ/);
 assert.match(dialog.markup,/không đi theo file sao lưu/);
 assert.match(dialog.markup,/value="cancel" class="secondary">Hủy<\/button><button class="primary">Tôi hiểu, bật Tự động/);
 assert.doesNotMatch(dialog.markup,/example\.com|https?:/,'the risk dialog speaks about the policy, not about a tab');
 // Leaving the dialog alone changes nothing: the yes is never counted as implied by a closed dialog.
 const closedBefore=closed;
 assert.equal(closed,closedBefore);
 // Confirming writes the acknowledgement under its own key, then saves the level that needs it.
 await dialog.handler(new Map(),{close(){closed++}});
 assert.ok(Number.isFinite(db.autoDiscardAck.at));
 assert.equal(db.autoDiscardConfig.mode,'auto');
 assert.equal(ctx.autoDiscardAck.at,db.autoDiscardAck.at,'the page keeps the yes without waiting for a reload');
 assert.match(notices.at(-1),/xác nhận rủi ro một lần/);
 const closedAfterAccept=closed;
 assert.doesNotMatch(JSON.stringify(db.autoDiscardConfig),/ack|risk/i,'consent is not part of the settings object');
 // A second save of the same level asks nothing: the acknowledgement is one-time, not per run.
 dialog=null;
 await ctx.saveAutoDiscard();
 assert.equal(dialog,null,'the yes is remembered');
 assert.equal(closed,closedAfterAccept,'the remembered yes opens no second dialog');
 // The collapsed header speaks with the module's own label, so the page and the report cannot disagree about a run.
 ctx.autoDiscardAction={at:Date.now()-5000,counts:{requested:2,discarded:1,skipped:0,unconfirmed:1,protected:0},status:'partial',results:[]};
 assert.match(ctx.autoDiscardBlock(),/lượt tự động vừa chạy: nghỉ 1 tab · 1 tab không xác nhận được/);
 assert.match(ctx.autoDiscardBlock(),/Tự động[\s\S]{0,90} · không hỏi lại từng lượt/,'the header still says the level does not ask again');
 ctx.autoDiscardAction=null;
 assert.doesNotMatch(ctx.autoDiscardBlock(),/lượt tự động/);
 // Turning the level off is never a risk, so it needs no yes even with the acknowledgement gone.
 const ackBefore=db.autoDiscardAck.at;
 ctx.autoDiscardAck=null;
 fillForm({...askSaved,mode:'auto',enabled:false});
 dialog=null;
 await ctx.saveAutoDiscard();
 assert.equal(dialog,null,'switching off opens no dialog');
 assert.equal(db.autoDiscardConfig.enabled,false);
 assert.equal(db.autoDiscardAck.at,ackBefore,'and no acknowledgement is written or cleared behind the scenes');
 // 0.126: the block may ask Chrome for the optional permission, and every answer comes back as a notice.
 ctx.chrome={...chromeless};
 ctx.autoDiscardOpen=true;
 assert.match(ctx.autoDiscardBlock(),/data-action="auto-discard-notifications">Bật thông báo hệ điều hành…<\/button>/,'the channel is offered whatever the measurement source is');
 ctx.autoDiscardNotifications=true;
 assert.match(ctx.autoDiscardBlock(),/data-action="auto-discard-notifications">Tắt thông báo kết quả<\/button>/,'and it turns off from the same place');
 ctx.autoDiscardNotifications=false;
 assert.match(ctx.autoDiscardBlock(),/data-action="auto-discard-permission">Xin quyền đọc tiến trình<\/button>/,'a build with no numbers offers the one ask that could change that');
 const asks=loads,savedBefore=JSON.stringify(db),before=notices.length;
 await ctx.autoDiscardPermission();
 assert.deepEqual([notices.length,loads,JSON.stringify(db)],[before+1,asks,savedBefore],'a Chrome with no permissions API is refused out loud, and nothing is saved');
 assert.match(notices.at(-1),/Chrome không cho phép xin quyền này/);
 assert.match(ctx.autoDiscardBlock(),/auto-discard-permission/,'a refusal stays retryable in the same page');
 ctx.chrome={...chromeless,permissions:{request:async()=>false}};
 await ctx.autoDiscardPermission();
 assert.deepEqual([notices.at(-1),loads],['Chưa có quyền đọc tiến trình, nên vẫn không có số đo theo tab.',asks],'Chrome saying no changes only the sentence');
 ctx.chrome={...chromeless,permissions:{request:async()=>true}};
 await ctx.autoDiscardPermission();
 assert.deepEqual([loads,notices.at(-1)],[asks+1,'Không đo được tài nguyên trên Chrome này. Quyền đọc tiến trình đã bật nhưng Chrome này không có API số đo theo tab.'],'a yes without an API is not sold as a number');
 assert.doesNotMatch(ctx.autoDiscardBlock(),/auto-discard-permission/,'and the block stops asking about a grant it already holds');
 ctx.chrome={...chromeless,processes:{getProcessIdForTab(){},getProcessInfo(){}},permissions:{request:async()=>true}};
 assert.deepEqual([ctx.autoDiscardContext().measurable,ctx.autoDiscardBlock().includes('auto-discard-permission')],[true,false],'real numbers retire the ask');
 ctx.chrome=chromeless;
 assert.doesNotMatch(JSON.stringify(db),/permission|granted/i,'the grant stays Chrome\'s to keep');
 console.log('Collapsed resource block: honest state, guarded saves, no silent discards: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
