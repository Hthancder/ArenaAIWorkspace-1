const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),OpenGrace=require('../extension/open-grace.js');
const src=fs.readFileSync('extension/dashboard.js','utf8'),start=src.indexOf('async function bulkSleepDialog(){'),end=src.indexOf('\nfunction nativeGroupDialog()',start);assert(start>=0&&end>start);
let html,handler,results;const tabs=[{id:1,title:'Active',url:'https://a',active:true},{id:2,title:'Pinned',url:'https://b',pinned:true},{id:3,title:'Safe',url:'https://c',windowId:1},{id:4,title:'Recent',url:'https://d',windowId:1}];
let local={openGraceMinutes:30},session={[OpenGrace.key(3)]:{windowId:1,openedAt:Date.now()-40*60000},[OpenGrace.key(4)]:{windowId:1,openedAt:Date.now()-60000}};
const ctx={protectedPreview:()=>false,Protection:{check:async()=>false},OpenGrace,tabs,selected:new Set([1,2,3,4]),esc:x=>String(x??''),showDialog:(h,fn)=>{html=h;handler=fn},notify:()=>{},chrome:{tabs:{async get(id){const t=tabs.find(x=>x.id===id);return id===4?{...t,active:true}:{...t}},async discard(id){return {id:99,discarded:true}}},storage:{local:{get:async()=>({...local})},session:{get:async keys=>Object.fromEntries(keys.filter(k=>k in session).map(k=>[k,structuredClone(session[k])]))}}},DiscardTools:require('../extension/discard.js'),load:async()=>{},bulkResult:(_title,r)=>{results=r}};
vm.runInNewContext(src.slice(start,end),ctx);
(async()=>{
 // A tab that stayed open past the window keeps its default check; a just-opened tab needs the user to opt in.
 await ctx.bulkSleepDialog();
 assert.match(html,/Bỏ qua \(2\)/);assert(!html.includes('value="1"'));assert(html.includes('value="3"'));
 assert.match(html,/<input type="checkbox" name="tab" value="3" checked>/);
 assert.match(html,/<input type="checkbox" name="tab" value="4">/);
 assert.match(html,/còn khoảng \d+ phút · chỉ nghỉ nếu bạn đánh dấu/);
 assert.match(html,/1 tab vừa mở hoặc không xác định được thời điểm mở đang để trống/);
 await handler({getAll:()=>['3','4']},{close(){}});
 assert.equal(results.length,2);assert.equal(results[0].error,undefined);assert.match(results[1].error,/thay đổi/);assert.equal(ctx.selected.size,0);
 // An unreadable window flags every tab, but still leaves the manual action available.
 local.openGraceMinutes='30 phút';session={};ctx.selected.add(3);ctx.selected.add(4);
 await ctx.bulkSleepDialog();
 assert.match(html,new RegExp('<input type="checkbox" name="tab" value="3">'));
 assert.match(html,/2 tab vừa mở hoặc không xác định được thời điểm mở đang để trống/);
 assert.ok(html.includes(OpenGrace.manualUnknown));
 // Without any session marker the tab stays unknown, which is never treated as old.
 local.openGraceMinutes=30;ctx.selected.add(3);ctx.selected.add(4);
 await ctx.bulkSleepDialog();
 assert.match(html,/Không xác định được thời điểm mở tab trong phiên Chrome/);
 console.log('Bulk sleep preview, protections and result reporting: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
