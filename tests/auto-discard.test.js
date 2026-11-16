const assert=require('node:assert/strict'),A=require('../extension/auto-discard.js');
const now=1700000000000,bytes=megabytes=>megabytes*1048576;
const tab=(id,extra={})=>({id,windowId:1,url:`https://example.com/${id}`,title:'T'+id,incognito:false,active:false,pinned:false,audible:false,discarded:false,lastAccessed:now-48*3600000,...extra});
const base={enabled:true,mode:'ask',combine:'any',resources:['memory','cpu'],thresholds:{memory:500,cpu:50},cpuCycles:3,idleMinutes:720,maxPerRun:10,everyMinutes:5,lowMemoryOnly:false};
// Measurement entries are oldest first; the newest cycle is the last one.
const sample=(entries,windowId=1,processId=10,sharedTabs=1)=>({windowId,processId,sharedTabs,series:entries.map(([ago,values])=>({at:now-ago,values}))});

// Thresholds belong to each resource on their own range; nothing is merged into one combined score.
assert.deepEqual(A.validate(),{...A.defaults,resources:['memory','cpu'],thresholds:{memory:500,cpu:50,heap:200,network:20}});
assert.equal(A.validate(base).thresholds.heap,200);
assert.equal(A.validate({...base,thresholds:{memory:500,cpu:50,heap:60}}).thresholds.heap,60);
assert.throws(()=>A.validate({...base,thresholds:{memory:49,cpu:50}}),/Ngưỡng bộ nhớ phải là số nguyên từ 50 đến 10000/);
assert.throws(()=>A.validate({...base,thresholds:{memory:10001,cpu:50}}),/Ngưỡng bộ nhớ/);
assert.throws(()=>A.validate({...base,thresholds:{memory:500,cpu:801}}),/Ngưỡng cpu phải là số nguyên từ 5 đến 800/);
assert.throws(()=>A.validate({...base,thresholds:{memory:500,cpu:50,heap:200,network:0}}),/Ngưỡng mạng\/hoạt động nền/);
assert.throws(()=>A.validate({...base,thresholds:{memory:500}}),/Chọn ngưỡng cho cpu/);
assert.throws(()=>A.validate({...base,resources:[]}),/Cấu hình cho nghỉ theo tài nguyên không hợp lệ/);
assert.throws(()=>A.validate({...base,resources:['memory','memory']}),/không hợp lệ/);
assert.throws(()=>A.validate({...base,mode:'auto-all'}),/không hợp lệ/);
assert.throws(()=>A.validate({...base,cpuCycles:11}),/Số chu kỳ liên tiếp phải là số nguyên từ 1 đến 10/);
assert.throws(()=>A.validate({...base,idleMinutes:14}),/Khoảng thời gian không được xem phải là số nguyên từ 15 đến 43200/);
assert.throws(()=>A.validate({...base,maxPerRun:101}),/Giới hạn mỗi lượt phải là số nguyên từ 1 đến 100/);
assert.throws(()=>A.validate({...base,everyMinutes:0}),/Chu kỳ đo phải là số nguyên từ 1 đến 60/);
assert.throws(()=>A.validate({...base,lowMemoryFloor:4}),/Ngưỡng bộ nhớ hệ thống/);
assert.equal(A.validate({...base,lowMemoryOnly:true,lowMemoryFloor:15}).lowMemoryFloor,15);

// An enabled policy needs a real measurement source; without one the save is refused instead of going quiet.
assert.equal(A.capability({}).measurable,false);
assert.match(A.capability({processes:{getProcessIdForTab:()=>{}}}).reason,/kênh Dev/);
assert.equal(A.capability({processes:{getProcessIdForTab(){},getProcessInfo(){}}}).measurable,true);
 assert.deepEqual([A.capability({},false).granted,A.capability({},undefined).granted],[false,false],'an unknown answer is not a grant');
 assert.deepEqual([A.capability({},true).granted,A.capability({},true).measurable],[true,false],'a grant is Chrome saying yes, not Chrome handing out numbers');
 assert.match(A.capability({},true).reason,/Quyền đọc tiến trình đã bật nhưng Chrome này không có API/,'the granted sentence names the missing API, not the missing consent');
 assert.match(A.capability({},false).reason,/kênh Dev/);
 assert.match(A.capability({},false).reason,/bấm nút Xin quyền đọc tiến trình trong khối này/,'and the sentence points at the one button that can change it');
assert.equal(A.assertUsable({...base,enabled:false},{}).enabled,false);
assert.equal(A.assertUsable(base,{measurable:true}).mode,'ask');
assert.throws(()=>A.assertUsable(base,{}),/Không đo được tài nguyên trên Chrome này/);
assert.throws(()=>A.assertUsable(base,{}),/cho nghỉ thủ công/);
 // 15.3: "Tự động" is refused until a human has read the risk once, and the yes is not part of the config.
 assert.throws(()=>A.assertUsable({...base,mode:'auto'},{measurable:true}),/xác nhận rủi ro một lần/);
 assert.throws(()=>A.assertUsable({...base,mode:'auto'},{measurable:true,now,ack:{at:now+60000}}),/một lần/,'an acknowledgement from the future is no acknowledgement');
 assert.equal(A.assertUsable({...base,mode:'auto'},{measurable:true,ack:{at:now}}).mode,'auto');
 assert.equal(A.assertUsable({...base,mode:'auto',enabled:false},{}).mode,'auto','an automatic policy that is off needs no yes yet');
 assert.deepEqual([A.ackValid(undefined,now),A.ackValid('yes',now),A.ackValid({at:now+1},now),A.ackValid({at:now},now)],[false,false,false,true]);
 assert.doesNotMatch(JSON.stringify(A.validate({...base,mode:'auto'})),/ack|risk|action/i,'consent never travels inside the settings object');
 // 15.4.3: one sentence describes a finished run, and it says so when a result could not be confirmed.
 const counts=(discarded,unconfirmed,extra={})=>({at:now,counts:{requested:discarded+unconfirmed,discarded,unconfirmed,skipped:0,protected:0,...extra},results:[]});
 assert.deepEqual([A.actionLabel(null,now).kind,A.actionLabel(null,now).text],['none','Chưa có lượt tự động nào trên máy này.']);
 assert.match(A.actionLabel(counts(0,0),now).text,/^Lượt tự động vừa chạy: nghỉ 0 tab\.$/);
 assert.match(A.actionLabel({...counts(3,0),status:'complete'},now).text,/^Lượt tự động vừa chạy: nghỉ 3 tab\.$/);
 assert.equal(A.actionLabel({...counts(3,0),status:'complete'},now).kind,'done');
 assert.match(A.actionLabel({...counts(3,1,{skipped:2,protected:4}),status:'partial'},now).text,/nghỉ 3 tab · 1 tab không xác nhận được · 2 tab bị bỏ qua vì đã thay đổi · 4 tab bị danh sách bảo vệ chặn/);
 assert.equal(A.actionLabel({...counts(3,1),status:'partial'},now).kind,'warning');
 assert.match(A.actionLabel({...counts(2,0),status:'uncertain',journalFailed:true},now).text,/kết quả chưa được ghi đầy đủ/);
 assert.match(A.actionLabel({...counts(2,0),at:now-42*60000,status:'complete'},now).short,/^lượt tự động cách đây 42 phút/,'the age is read against the page clock, not the fixture one');

// The exact threshold counts as over, one unit below does not; only consecutive cycles build a streak.
const c=A.validate(base),single=value=>({windowId:1,processId:10,sharedTabs:1,series:[{at:now,values:{memory:value}}]});
const cpu=values=>({windowId:1,processId:10,sharedTabs:1,series:values.map(([ago,value])=>({at:now-ago,values:{cpu:value}}))});
assert.equal(A.resource(single(500),'memory',c,now).state,'over');
assert.equal(A.resource(single(499.9),'memory',c,now).state,'under');
assert.equal(A.resource(cpu([[0,60]]),'cpu',c,now).state,'rising');
assert.equal(A.resource(cpu([[300000,60],[0,60]]),'cpu',c,now).state,'rising');
assert.equal(A.resource(cpu([[300000,60],[0,20]]),'cpu',c,now).state,'under');
assert.deepEqual([A.resource(cpu([[600000,60],[300000,60],[0,60]]),'cpu',c,now).state,A.resource(cpu([[300000,60],[0,60]]),'cpu',A.validate({...base,cpuCycles:2}),now).state],['over','over']);
// A gap in the middle of the streak is stale data, not three quiet high cycles.
assert.equal(A.resource(cpu([[12*60000,60],[6*60000,60],[0,60]]),'cpu',c,now).state,'stale');
// A cycle the browser could not read leaves no entry behind, so an old value is only ever as old as it is.
const dropped=A.record({windowId:1,processId:10,sharedTabs:1,series:[{at:now-300000,values:{memory:900}},{at:now,values:{}}]});
assert.equal(dropped.series.length,1);
assert.equal(A.resource(dropped,'memory',c,now).state,'over');
assert.equal(A.record({windowId:1,processId:0,series:[{at:now,values:{memory:900}}]}),null);
assert.equal(A.record({windowId:1,processId:1,series:[{at:now,values:{memory:'900'}}]}),null);
assert.equal(A.record({windowId:1,processId:1,series:[{at:now,values:{memory:900,cpu:-1}}]}).series[0].values.cpu,undefined);
assert.deepEqual([A.valueLabel('memory',1400),A.valueLabel('cpu',75.5),A.valueLabel('network',20),A.valueLabel('heap',4096),A.valueLabel('memory',NaN)],['1,4 GB','75,5% một lõi','20 MB/phút','4 GB','không rõ']);
assert.deepEqual([A.ageLabel(now-240000,now),A.ageLabel(now-3*3600000,now),A.ageLabel(now-3*86400000,now),A.ageLabel(0,now)],['đo 4 phút trước','đo 3 giờ trước','đo 3 ngày trước','chưa có số đo']);
assert.deepEqual([A.idleLabel(59),A.idleLabel(90),A.idleLabel(48*60),A.idleLabel(48*60*2)],['59 phút','1,5 giờ','2 ngày','4 ngày']);

(async()=>{
 // chrome.processes answers per renderer process: shared numbers stay labelled as shared, tabs without a process are skipped.
 const info={10:{privateMemory:bytes(1400),jsMemoryUsed:bytes(300),cpu:62,network:0},11:{jsMemoryUsed:bytes(858.4)},12:{}};
 const api={processes:{getProcessIdForTab:async id=>({1:10,2:10,3:11,4:12})[id],getProcessInfo:async ids=>Object.fromEntries(ids.map(id=>[id,info[id]]).filter(([,value])=>value))}};
 const measured=await A.measure(api,[tab(1),tab(2),tab(3),tab(4),tab(5,{url:'chrome://extensions'})],now);
 assert.equal(measured.ok,true);
 assert.deepEqual(Object.keys(measured.records).map(Number),[1,2,3]);
 assert.deepEqual([measured.records[1].series[0].values.memory,measured.records[1].series[0].values.cpu,measured.records[1].series[0].values.network],[1400,62,0]);
 assert.equal(measured.records[1].sharedTabs,2);
 assert.deepEqual([measured.records[3].series[0].values.memory,measured.records[3].series[0].values.heap],[undefined,858.4]);
 assert.deepEqual([(await A.measure({processes:{}},[tab(1)],now)).ok,(await A.measure({},[tab(1)],now)).ok],[false,false]);
 await assert.rejects(()=>A.measure(api,[tab(1)],Number.NaN),/Không xác định được thời gian/);

 // Samples stay in storage.session, capped to the streak length, and restart when the window or process changes.
 let session={};
 const store={storage:{session:{get:async keys=>Object.fromEntries(keys.filter(k=>k in session).map(k=>[k,structuredClone(session[k])])),set:async value=>Object.assign(session,structuredClone(value)),remove:async keys=>{for(const k of keys)delete session[k]}}}};
 assert.equal(await A.remember(store,measured.records),3);
 assert.deepEqual(Object.keys(session).sort(),[A.key(1),A.key(2),A.key(3)].sort());
 assert.equal(session[A.key(1)].url,undefined);
 assert.equal(session[A.key(1)].series.length,1);
 for(const step of [1,2,3,4,5])await A.remember(store,{1:{windowId:1,processId:10,sharedTabs:1,series:[{at:now+step*1000,values:{memory:600}}]}},3);
 assert.deepEqual(session[A.key(1)].series.map(x=>x.at),[now+3000,now+4000,now+5000]);
 await A.remember(store,{1:{windowId:2,processId:10,sharedTabs:1,series:[{at:now+9000,values:{memory:700}}]}},3);
 assert.deepEqual(session[A.key(1)].series.map(x=>x.at),[now+9000]);
 assert.deepEqual(Object.keys(await A.recall(store,[tab(1,{windowId:2}),tab(2)])),[A.key(1),A.key(2)]);
 assert.equal((await A.read(store,[1]))[A.key(1)].series.length,1);
 await A.forget(store,[1,1]);
 assert.equal(session[A.key(1)],undefined);
 assert.equal(await A.remember({},measured.records),0);
 assert.equal(await A.remember(store,{5:'not a record'},3),0);
 assert.deepEqual(await A.read({storage:{}},[1]),{});
 assert.deepEqual(A.readRecords({[A.key(7)]:{windowId:1,processId:0,series:[{at:now,values:{memory:900}}]}}),{});

 // Guards run first, then the measured numbers; a blocked row keeps its reason instead of disappearing.
 const records={
  [A.key(1)]:sample([[0,{memory:1400,cpu:20}]],1,10,2),
  [A.key(2)]:sample([[600000,{cpu:80}],[300000,{cpu:80}],[0,{cpu:80}]],1,11),
  [A.key(3)]:sample([[0,{memory:100,cpu:10}]],1,12),
  [A.key(4)]:sample([[0,{memory:900,cpu:90}]],1,13),
  [A.key(5)]:sample([[300000,{cpu:60}],[0,{cpu:60}]],1,14),
  [A.key(6)]:sample([[11*60000,{memory:900,cpu:90}]],1,15),
  [A.key(7)]:sample([[0,{memory:900,cpu:90}]],2,16),
 };
 const extra={8:{active:true},9:{pinned:true},10:{audible:true},11:{discarded:true},12:{lastAccessed:now-59*60000},13:{lastAccessed:Number.NaN},14:{url:'file:///tmp/x'},15:{pendingUrl:'https://example.com/next'}};
 const tabs=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15].map(id=>tab(id,extra[id]||{}));
 const plan=A.plan(tabs,records,base,now),byId=new Map(plan.rows.map(r=>[r.id,r]));
 assert.deepEqual(plan.candidates.map(r=>r.id),[1,4,2]);
 assert.deepEqual([byId.get(1).triggered,byId.get(4).triggered,byId.get(2).triggered],[['memory'],['memory'],['cpu']]);
 assert.deepEqual([byId.get(3).reason,byId.get(5).reason],['Dưới ngưỡng đã chọn','cpu vượt ngưỡng 2/3 chu kỳ liên tiếp · Không đọc được bộ nhớ']);
 assert.deepEqual([byId.get(6).reason,byId.get(7).reason,byId.get(8).reason],['Mẫu đo đã cũ','Tab đã đổi cửa sổ sau lần đo','Tab đang được xem']);
 assert.deepEqual([byId.get(9).reason,byId.get(10).reason,byId.get(11).reason],['Tab đã ghim','Tab đang phát âm thanh','Tab đang nghỉ']);
 assert.match(byId.get(12).reason,/Mới được xem 59 phút trước/);
 assert.deepEqual([byId.get(13).reason,byId.get(14).reason,byId.get(15).reason],['Không xác định được lần kích hoạt gần nhất','Không phải trang http/https','Trang đang chuyển']);
 assert.equal(plan.counts.reduce((sum,x)=>sum+x.count,0),12);
 assert.equal(plan.measuredAt,now);
 // Every number carries its source and age, and a shared process says so instead of pretending to be per tab.
 assert.equal(A.line(byId.get(1),plan.config,now),'RAM 1,4 GB · đo ngay bây giờ · tiến trình chung 2 tab · nguồn: tiến trình Chrome');
 assert.match(A.line(byId.get(3),plan.config,now),/RAM 100 MB · CPU 10% một lõi/);
 assert.match(A.line({values:{heap:900},triggered:['heap'],at:now-240000,sharedTabs:1,source:'ước lượng'},c,now),/heap 900 MB \(ước lượng\) · đo 4 phút trước/);
 assert.equal(A.line(byId.get(8),plan.config,now),'Tab đang được xem');

 // The idle boundary is inclusive: exactly the configured window is old enough to be a candidate.
 assert.deepEqual(A.plan([tab(16,{lastAccessed:now-720*60000})],{[A.key(16)]:sample([[0,{memory:600}]],1,17)},base,now).candidates.map(r=>r.id),[16]);
 assert.match(A.plan([tab(16,{lastAccessed:now-720*60000+1})],{[A.key(16)]:sample([[0,{memory:600}]],1,17)},base,now).rows[0].reason,/^Mới được xem 12 giờ trước$/);

 // "All" needs every selected resource; an estimate is a hint only, and the cap keeps the excess visible.
 assert.deepEqual(A.plan(tabs,records,{...base,combine:'all'},now).candidates,[]);
 assert.equal(A.plan(tabs,records,{...base,combine:'all'},now).rows.find(r=>r.id===1).reason,'Chưa vượt mọi ngưỡng đã chọn');
 const heap={...base,mode:'auto',resources:['heap'],thresholds:{heap:200}};
 assert.equal(A.plan([tab(1)],{[A.key(1)]:sample([[0,{heap:900}]])},heap,now).rows[0].reason,'Chỉ có số ước lượng; không tự nghỉ tab');
 assert.deepEqual(A.plan([tab(1)],{[A.key(1)]:sample([[0,{heap:900}]])},{...heap,mode:'suggest'},now).candidates.map(r=>r.id),[1]);
 // A real number beside an estimate still justifies the run; the estimate only never does.
 const mixed=A.plan([tab(1)],{[A.key(1)]:sample([[0,{heap:900,memory:1400}]])},{...heap,resources:['heap','memory'],thresholds:{heap:200,memory:500}},now);
 assert.deepEqual([mixed.candidates.map(r=>r.id),mixed.candidates[0].triggered],[[1],['heap','memory']]);
 // Protection and the grace window are re-read here too, so no surface has to repeat the policy.
 assert.equal(A.plan([tab(1)],records,base,now,{protected:new Set(['https://example.com/1'])}).rows[0].reason,'Website hoặc URL được bảo vệ');
 assert.deepEqual(A.plan([tab(1)],records,{...base,mode:'suggest'},now,{note:t=>t.id===1?'vừa mở':''}).candidates.map(r=>r.note),['vừa mở']);
 assert.equal(A.plan([tab(1)],records,base,now,{note:()=>'vừa mở'}).rows[0].reason,'Tab đang trong thời gian miễn xử lý; chỉ nghỉ khi bạn tự chọn');
 const capped=A.plan([20,21,22].map(id=>tab(id)),{[A.key(20)]:sample([[0,{memory:600}]],1,20),[A.key(21)]:sample([[0,{memory:700}]],1,21),[A.key(22)]:sample([[0,{memory:800}]],1,22)},{...base,maxPerRun:2},now);
 assert.deepEqual(capped.chosen.map(r=>r.id),[22,21]);
 assert.deepEqual(capped.deferred.map(r=>r.id),[20]);
 assert.deepEqual([A.plan([],records,base,now).rows,A.plan([tab(1)],{},base,now).rows[0].reason],[[],'Chưa có số đo cho tab này']);
 assert.throws(()=>A.plan([tab(1)],records,base,Number.NaN),/Không xác định được thời gian/);

 // Changing the policy between cycles re-decides from the same samples; nothing is cached from the old numbers.
 const spike={[A.key(1)]:{windowId:1,processId:10,sharedTabs:1,series:[{at:now,values:{cpu:60}}]}};
 assert.match(A.plan([tab(1)],spike,{...base,resources:['cpu'],thresholds:{memory:500,cpu:50},cpuCycles:3},now).rows[0].reason,/cpu vượt ngưỡng 1\/3 chu kỳ/);
 assert.deepEqual(A.plan([tab(1)],spike,{...base,resources:['cpu'],thresholds:{memory:500,cpu:50},cpuCycles:1},now).candidates.map(r=>r.id),[1]);
 assert.deepEqual(A.plan([tab(1)],records,{...base,thresholds:{memory:1401,cpu:50}},now).candidates.map(r=>r.id),[]);
 assert.deepEqual(A.plan([tab(1)],records,{...base,thresholds:{memory:1400,cpu:50}},now).candidates.map(r=>r.id),[1]);
 // Shortening the cycle window turns a sample that was fresh into stale data, so no candidate list is built on it.
 assert.match(A.plan([tab(1)],{[A.key(1)]:{windowId:1,processId:10,sharedTabs:1,series:[{at:now-9*60000,values:{memory:1400}}]}},{...base,everyMinutes:1},now).rows[0].reason,/đã cũ|Không đọc được/);

 // The collapsed header says what the body will do, including the Chrome that cannot measure anything.
 assert.deepEqual(A.describe(undefined,{measurable:true}),{kind:'off',text:'Tự cho nghỉ theo tài nguyên đang tắt. Ngưỡng hiện tại: RAM ≥ 500 MB hoặc CPU ≥ 50% một lõi.'});
 assert.match(A.describe({...base,enabled:false},{measurable:false}).text,/Chỉ còn đường cho nghỉ thủ công/);
 assert.match(A.describe(base,{measurable:false}).text,/Thiết lập đang bật nhưng không có số đo/);
 assert.equal(A.describe({...base,enabled:true},{measurable:true,paused:true}).kind,'paused');
 assert.match(A.describe({...base,enabled:true},{measurable:true,overCount:12,measuredAt:now-240000,now}).text,/Hỏi trước · xét RAM, CPU · tối đa 10 tab mỗi lượt · 12 tab đang vượt ngưỡng · đo 4 phút trước · chỉ nghỉ khi bạn xác nhận/);
 assert.match(A.describe({...base,enabled:true,mode:'auto'},{measurable:true,overCount:0,now}).text,/Tự động · xét RAM, CPU · tối đa 10 tab mỗi lượt · chưa có tab nào vượt ngưỡng · chưa có số đo · không hỏi lại từng lượt/);
 assert.equal(A.describe({enabled:'yes'},{}).kind,'error');
 // The card in Cần chú ý belongs to "Hỏi trước" only, and it expires together with the numbers it reports.
 const card={at:now,overCount:3,blockedCount:2,measurable:true,ids:[7,8,9]};
 const ask={...base,mode:'ask',resources:['memory'],thresholds:{memory:500,cpu:50}};
 assert.deepEqual(A.attention(ask,card,now),{at:now,overCount:3,blockedCount:2,ids:[7,8,9],rows:[],cut:0,dismissed:false,age:'đo ngay bây giờ'});
 assert.equal(A.attention({...ask,mode:'suggest'},card,now),null);
 assert.equal(A.attention({...ask,mode:'auto'},card,now),null);
 assert.equal(A.attention({...ask,enabled:false},card,now),null);
 assert.equal(A.attention({enabled:'nope'},card,now),null);
 assert.equal(A.attention(ask,null,now),null);
 assert.equal(A.attention(ask,{...card,measurable:false},now),null);
 assert.equal(A.attention(ask,{...card,overCount:0},now),null);
 assert.equal(A.attention(ask,{...card,ids:[]},now),null);
 // 5.7: the same record also feeds the health list, but a suggestion never borrows the card's reminder channel.
 const withTrail={...card,trail:[{id:7,windowId:1,processId:10,sharedTabs:2,at:now,values:{memory:1400},triggered:['memory'],source:'tiến trình Chrome'},{id:8,windowId:1,processId:11,sharedTabs:1,at:now,values:{memory:900},triggered:['memory'],source:'tiến trình Chrome'}],trailCut:4};
 const suggest={...base,mode:'suggest',resources:['memory'],thresholds:{memory:500,cpu:50}};
 assert.equal(A.suggestions(ask,withTrail,now),null,'a card is only ever an ask-mode surface');
 const list=A.suggestions(suggest,withTrail,now);
 assert.deepEqual([list.overCount,list.ids.length,list.cut,list.dismissed],[3,3,4,false]);
 assert.deepEqual(list.rows.map(r=>r.id),[7,8],'only the tabs the cycle left a trail for');
 assert.match(A.line(list.rows[0],suggest,now),/RAM 1,4 GB · đo ngay bây giờ · tiến trình chung 2 tab · nguồn: tiến trình Chrome/);
 assert.equal(A.suggestions(suggest,{...withTrail,ids:[42,43]},now).rows.length,0,'a trail with no matching id is no list');
 assert.equal(A.attention(ask,withTrail,now).rows.length,2,'the card can read the same trail when it needs to');
 // Every empty state names its own reason, so the page never shows a blank box and never guesses one.
 assert.match(A.health(suggest,null,now,{measurable:true}).text,/Chưa có lượt đo nào trong phiên Chrome này/);
 assert.match(A.health(suggest,{at:now-3600000,overCount:2,measurable:true,ids:[1]},now,{measurable:true}).text,/đã quá hai chu kỳ/);
 assert.match(A.health(suggest,{at:now,overCount:0,measurable:true,ids:[]},now,{measurable:true}).text,/không thấy tab nào vượt ngưỡng/);
 assert.match(A.health({...suggest,mode:'ask'},withTrail,now,{measurable:true}).text,/Ở mức Hỏi trước, danh sách nằm trong Cần chú ý/);
 assert.match(A.health({...suggest,mode:'auto'},withTrail,now,{measurable:true}).text,/Mức Tự động vẫn chưa có ở bản này/);
 assert.match(A.health({...suggest,enabled:false},withTrail,now,{measurable:true}).text,/Tính năng đang tắt/);
 assert.equal(A.health(suggest,withTrail,now,{measurable:false}).kind,'unmeasurable');
 assert.match(A.health(suggest,withTrail,now,{measurable:false}).text,/Không đo được tài nguyên trên Chrome này/);
 assert.match(A.health(suggest,withTrail,now,{}).text,/không suy số từ tên miền/);
 assert.equal(A.health({enabled:'nope'},withTrail,now,{measurable:true}).kind,'error');
 assert.throws(()=>A.health(suggest,withTrail,'now',{measurable:true}),/Không xác định được thời gian/);
 assert.throws(()=>A.suggestions(suggest,withTrail,undefined),/Không xác định được thời gian/);
 assert.equal(A.attention(ask,{...card,ids:['7',-2,1.5,8]},now).ids.join(), '8');
 assert.equal(A.attention({...ask,everyMinutes:5},card,now+9*60000).age,'đo 9 phút trước');
 assert.equal(A.attention({...ask,everyMinutes:5},card,now+10*60000),null);
 assert.equal(A.attention(ask,{...card,dismissedAt:card.at},now).dismissed,true);
 assert.equal(A.attention(ask,{...card,dismissedAt:card.at-1},now).dismissed,false);
 assert.throws(()=>A.attention(ask,card,'x'),/Không xác định được thời gian/);
 // 15.4: one translation from a run report to the vocabulary the existing channels speak.
assert.deepEqual(['complete','partial','uncertain','running'].map(name=>A.notifyStatus({status:name})),['complete','uncertain','uncertain','uncertain'],'a half-confirmed run is never booked as a success');
assert.deepEqual([A.notifyStatus({status:'empty'}),A.notifyStatus({status:'complete',journalFailed:true}),A.notifyStatus(null),A.notifyStatus('nope')],[null,'blocked',null,null],'nothing to do is not a result, and a report that could not be written is a blocked one');
assert.deepEqual(A.resultEvent({id:1234,at:2345,status:'partial',counts:{unconfirmed:2}}),{id:'discard:1234',kind:'result',at:2345,status:'uncertain'},'the event id comes from the run, so a repeated delivery cannot grow the journal');
assert.deepEqual([A.resultEvent({id:1,at:2,status:'empty'}),A.resultEvent({status:'complete'}),A.resultEvent({id:0,at:1,status:'complete'}),A.resultEvent(undefined)],[null,null,null,null],'no identity or no result means no event at all');
assert.equal(A.noticePrefix,'discard:','the prefix is a fact of this module, and the page pins it too');
 // 15.4.3 as an opt-in channel: one switch, five answers, and silence is the default in every direction.
 const ran={id:9,at:1700000000000,status:'complete',counts:{discarded:2}};
 function fakeApi({enabled=true,reads='ok',granted=true,sendFails=false}={}){
  const sent=[];let looked=0;
  const api={sent,get reads(){return looked},runtime:{getURL:path=>'chrome-extension://x/'+path},
   storage:{local:{get:async()=>{if(reads==='fail')throw Error('storage unavailable');looked++;return {autoDiscardNotifications:enabled,quietHours:null}}}},
   notifications:{create:async(id,options)=>{if(sendFails)throw Error('no channel at all');sent.push({id,options});return true}}};
  if(granted!==undefined)api.permissions={contains:async()=>{if(granted==='fail')throw Error('Chrome said nothing');return granted===true}};
  return api;
 }
 const calm={isQuiet:()=>false,deferFullscreen:async()=>false};
 assert.equal(A.notifyId,'tabspace-auto-discard','the id is a fact of this module, and the worker opens the same page for it');
 assert.deepEqual([await A.notify(fakeApi(),{...ran,status:'empty'},1700000000000,calm),await A.notify(fakeApi(),null,1700000000000,calm)],['silent','silent'],'no result, nothing to say');
 {
  const api=fakeApi();
  assert.equal(await A.notify(api,ran,1700000000000,calm),'attempted','switch on, quiet off, permission granted: one notice');
  assert.equal(api.sent.length,1);
  const {id,options}=api.sent[0];
  assert.deepEqual([id,options.type,options.silent,options.title],[A.notifyId,'basic',true,'Tabspace'],'silent flag, fixed title, and only this id to click');
  assert.match(options.message,/đã cho nghỉ 2 tab/,'the count in the notice is the count in the report');
  assert.ok(!/https?:\/\/|\.com|tab id/i.test(options.message),'and no address, domain or tab id crosses the OS channel');
 }
 {
  const api=fakeApi({enabled:false});
  assert.equal(await A.notify(api,ran,1700000000000,calm),'disabled','a build that never turned the channel on stays exactly as quiet as before');
  assert.equal(api.sent.length,0);
 }
 {
  const api=fakeApi();
  assert.deepEqual([await A.notify(api,ran,1700000000000,{isQuiet:()=>true,deferFullscreen:async()=>false}),
   await A.notify(api,ran,1700000000000,{isQuiet:()=>false,deferFullscreen:async()=>true}),
   await A.notify(api,ran,1700000000000,{}),
   await A.notify(api,ran,1700000000000,{isQuiet:()=>{throw Error('unreadable')},deferFullscreen:async()=>false})],
   ['held','held','held','held'],'quiet hours, a presentation, a missing checker and a broken checker all hold');
  assert.equal(api.sent.length,0,'and holding sends nothing on the way out');
 }
 {
  const api=fakeApi({granted:false});
  assert.equal(await A.notify(api,ran,1700000000000,calm),'unavailable','no permission is admitted, not guessed at');
  assert.equal(await A.notify(fakeApi({granted:'fail'}),ran,1700000000000,calm),'unavailable','and a Chrome that will not answer is the same answer');
  assert.equal(await A.notify(fakeApi({sendFails:true}),ran,1700000000000,calm),'unavailable','a failed send is said once and never queued for replay');
  const broken=fakeApi({reads:'fail'});
  assert.equal(await A.notify(broken,ran,1700000000000,calm),'unavailable','even an unreadable setting stops the send rather than assuming yes');
 }
 {
  const api=fakeApi();
  assert.equal(await A.notify(api,{id:9,at:0,status:'complete',counts:{}},1700000000000,calm),'silent','a run without a clock is not a result to announce');
  assert.deepEqual([A.notifyMessage({...ran,status:'uncertain'}),A.notifyMessage({...ran,status:'complete',journalFailed:true})].map(x=>/chưa xác nhận|bị chặn/.test(x)),[true,true],'an unclear run and a blocked one say what they are');
  assert.ok(!/đã cho nghỉ \d+ tab/.test(A.notifyMessage({...ran,status:'partial',counts:{discarded:1,unconfirmed:1}})),'a half-confirmed run never reads as a success');
 }
console.log('Resource thresholds, streaks, guards and honest unmeasurable state: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
