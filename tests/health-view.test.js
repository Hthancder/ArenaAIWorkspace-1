const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),A=require('../extension/auto-discard.js'),TabHealth=require('../extension/tab-health.js'),DuplicateTools=require('../extension/duplicates.js');
// 5.7: the health page is rendered from the same record the card uses, so it can only ever show the last cycle.
const now=1700000000000;
const src=fs.readFileSync('extension/dashboard.js','utf8'),start=src.indexOf('function healthData()'),end=src.indexOf('function renderSavedOpen()',start);
assert.ok(start>=0&&end>start,'the health view is one contiguous slice of the dashboard');
const area={innerHTML:''};
const config={enabled:true,mode:'suggest',combine:'any',resources:['memory'],thresholds:{memory:500,cpu:50,heap:200,network:20},cpuCycles:3,idleMinutes:720,maxPerRun:10,everyMinutes:5,lowMemoryOnly:false};
const row=(id,extra={})=>({id,windowId:1,processId:10,sharedTabs:1,at:now,values:{memory:1400},triggered:['memory'],source:'tiến trình Chrome',...extra});
const ctx={
 $:()=>area,Date:{now:()=>now},esc:value=>String(value).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])),
 TabHealth,DuplicateTools,AutoDiscard:A,PresetTools:require('../extension/presets.js'),oldTabDays:7,groups:[],tabs:[],presets:[],
 autoDiscardContext:()=>({measurable:true}),autoDiscardConfig:config,autoDiscardRun:null,autoDiscardAction:null,
};
vm.runInNewContext(src.slice(start,end),ctx);
const render=()=>{ctx.renderHealth();return area.innerHTML};
(async()=>{
 // Nothing measured yet: the page says so and hands the user to the settings block.
 assert.match(render(),/Chưa có lượt đo nào trong phiên Chrome này/);
 assert.match(render(),/data-view="settings"/);
 assert.doesNotMatch(render(),/Chọn \d+ tab để xem trước/,'an empty list offers nothing to select');
 // A cycle with candidates: one row per tab, with the numbers, the moment and the source it came from.
 ctx.tabs=[{id:1,windowId:1,url:'https://shop.example/1',title:'Giỏ hàng',incognito:false,active:false,pinned:false,audible:false,discarded:false,lastAccessed:now-48*3600000}];
 ctx.autoDiscardRun={at:now,overCount:2,blockedCount:1,measurable:true,ids:[1,2],trail:[row(1,{sharedTabs:2}),row(2,{processId:11})],trailCut:3};
 let html=render();
 assert.match(html,/Được đề xuất nghỉ/);
 assert.match(html,/2 tab vượt ngưỡng, 1 tab còn mở/,'a tab that closed is counted out loud, not hidden');
 assert.match(html,/1 tab không còn mở; chưa chọn tab nào\./);
 assert.match(html,/Giỏ hàng/);
 assert.match(html,/RAM 1,4 GB · đo ngay bây giờ · tiến trình chung 2 tab · nguồn: tiến trình Chrome/,'each row keeps the trail line of the cycle');
 assert.match(html,/1 tab bị chặn bởi danh sách bảo vệ hoặc đang được xem/);
 assert.match(html,/3 tab khác cũng vượt ngưỡng nhưng không có trong danh sách/,'the trail is capped, and the cap is admitted');
 assert.match(html,/data-action="auto-discard-suggest-review">Chọn 1 tab để xem trước/,'selection is the only action');
 assert.match(html,/data-action="auto-discard-suggest-dismiss">Bỏ qua gợi ý này/);
 assert.doesNotMatch(html,/data-action="discard"|Cho tab nghỉ/,'the page never offers the manual discard button itself');
 // Skipping a suggestion is reversible on the same page and does not touch a tab.
 ctx.autoDiscardRun={...ctx.autoDiscardRun,dismissedAt:now};
 html=render();
 assert.match(html,/Bạn đã bỏ qua gợi ý của lượt đo này/);
 assert.match(html,/2 tab vẫn đang vượt ngưỡng/);
 assert.match(html,/data-action="auto-discard-suggest-restore">Hiện lại gợi ý/);
 assert.doesNotMatch(html,/auto-discard-suggest-review/,'a skipped list does not offer to select tabs');
 delete ctx.autoDiscardRun.dismissedAt;
 // Numbers older than two cycles are refused as a basis, so the page asks for a new measurement.
 ctx.autoDiscardRun={...ctx.autoDiscardRun,at:now-3600000};
 assert.match(render(),/đã quá hai chu kỳ nên không còn được dùng để gợi ý/);
 ctx.autoDiscardRun={at:now,overCount:2,blockedCount:0,measurable:true,ids:[1],trail:[row(1)]};
 // Ask mode keeps its card, and the page points there instead of duplicating the reminder.
 ctx.autoDiscardConfig={...config,mode:'ask'};
 assert.match(render(),/Ở mức Hỏi trước, danh sách nằm trong Cần chú ý/);
 assert.match(render(),/data-view="attention">Mở Cần chú ý/);
 // Auto mode is not a promise this build can keep, and the page says so.
 ctx.autoDiscardConfig={...config,mode:'auto'};
 assert.match(render(),/Mức Tự động vẫn chưa có ở bản này/);
 // Off, or without a measurement source, there is nothing to list and no invented number either.
 ctx.autoDiscardConfig={...config,mode:'suggest',enabled:false};
 assert.match(render(),/Tính năng đang tắt nên không có lượt đo nào trong nền/);
 ctx.autoDiscardConfig={...config,enabled:true};
 ctx.autoDiscardContext=()=>({measurable:false});
 assert.match(render(),/Không đo được tài nguyên trên Chrome này/);
 assert.match(render(),/không có danh sách nào để xem/);
 assert.doesNotMatch(render(),/Được đề xuất nghỉ \(\d+\)/,'an unusable source never produces a list');
 ctx.autoDiscardContext=()=>({measurable:true});
 // A finished automatic run is reported on the same page, with the settings header's own words.
 ctx.autoDiscardAction={at:now,counts:{requested:2,discarded:1,skipped:0,unconfirmed:1,protected:0},status:'partial',results:[{id:1,windowId:1,status:'discarded'},{id:2,windowId:1,url:'https://shop.example/2',status:'unconfirmed'}]};
 html=render();
 assert.match(html,/Lượt tự động gần nhất/);
 assert.match(html,/Lượt tự động vừa chạy: nghỉ 1 tab · 1 tab không xác nhận được\./);
 assert.match(html,/Giỏ hàng<\/b><div class="rowurl">đã nghỉ · cửa sổ 1/,'the tab that is still open keeps its title');
 assert.ok(html.includes('<b>https://shop.example/2</b><div class="rowurl">không xác nhận được'),'a tab nobody could confirm is named, not hidden');
 assert.match(html,/Kiểm tra danh sách tab trước khi tin vào số liệu này/);
 ctx.autoDiscardAction={at:now,counts:{requested:1,discarded:1,skipped:0,unconfirmed:0,protected:0},status:'complete',results:[{id:1,windowId:1,status:'discarded'}]};
 assert.doesNotMatch(render(),/Kiểm tra danh sách tab/,'a clean run is not dressed up as a warning');
 assert.doesNotMatch(render(),/Hoàn tác|hoàn tác|undo/,'a discarded tab is never sold as undoable');
 ctx.autoDiscardAction=null;
 // The other kinds are pointers to views that already exist, with their own counts.
 ctx.autoDiscardConfig={...config,mode:'suggest'};
 ctx.tabs=[{id:1,windowId:1,url:'https://example.com/a',title:'A',lastAccessed:now-9*86400000},{id:2,windowId:2,url:'https://example.com/a',title:'B',lastAccessed:now-2*86400000},{id:3,windowId:1,url:'https://example.com/b',title:'C'}];
 ctx.groups=[{id:'g',name:'Nhóm',items:[{url:'https://example.com/a',title:'A'}]}];
 ctx.autoDiscardRun={at:now,overCount:1,blockedCount:0,measurable:true,ids:[1],trail:[row(1)]};
 html=render();
 assert.match(html,/Tab trùng<\/b><div class="rowurl">Cùng URL trong các tab đang mở<\/div><\/div><div class="rowactions"><span>1 gợi ý<\/span><button data-view="duplicates">/);
 assert.match(html,/Lâu chưa truy cập/);
 assert.match(html,/1 tab không rõ nên không được xét/,'a tab without a usable timestamp is counted as unknown, not as old');
 assert.match(html,/>Lâu chưa truy cập<\/b><div class="rowurl">chỉ tab có thời gian Chrome ghi nhận/);
 assert.match(html,/Đã lưu nhưng còn mở/);
 assert.match(html,/Không cặp quy tắc nào trùng miền hay chồng đường dẫn/,'an empty preset list is reported as empty, not as a missing feature');
 assert.ok(!/chưa so sánh|chưa triển khai/i.test(html),'and the row no longer claims the comparison does not exist');
 // The row reads the same rule comparison the preset dialog uses: no tab, no alarm, no guess.
 ctx.presets=[{id:'p1',name:'Work',domains:['github.com']},{id:'p2',name:'Play',domains:['github.com'],subdomains:true}];
 html=render();
 assert.match(html,/1 cặp preset cùng khớp một miền hoặc chồng đường dẫn, so từ chính quy tắc nên không cần tab nào đang mở: Work \+ Play/,'the pair is counted and named from the rules alone');
 ctx.presets=[{id:'p1',name:'A',domains:['a.dev']},{id:'p2',name:'B',domains:['a.dev']},{id:'p3',name:'C',domains:['a.dev']},{id:'p4',name:'D',domains:['a.dev']},{id:'p5',name:'E',domains:['a.dev']},{id:'p6',name:'F',domains:['a.dev']},{id:'p7',name:'G',domains:['a.dev']}];
 html=render();
 assert.match(html,/21 cặp preset cùng khớp một miền hoặc chồng đường dẫn[^<]*: A \+ B, A \+ C…/,'seven presets on one host give twenty-one pairs, listed by name with the rest folded away');
 ctx.presets=[];
 // The view never reaches for a tab: no discard call, no chrome API beyond the storage the record already came from.
 const health=src.slice(start,end);
 assert.doesNotMatch(health,/tabs\.discard|chrome\.tabs|\.remove\(|\.set\(/,'the health page reads a record, it does not write or discard');
 assert.equal((health.match(/AutoDiscard\.health\(/g)||[]).length,1,'one decision function, called once here');
 console.log('The health page lists the last cycle\'s suggestions, points at the other kinds, and never picks a tab: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
