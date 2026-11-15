const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),OpenGrace=require('../extension/open-grace.js');
const source=fs.readFileSync('extension/popup.js','utf8');
const start=source.indexOf('async function discardTab('),end=source.indexOf('\nfunction renderTabs(',start);assert(start>=0&&end>start);
let current, calls, msg, confirmed, asked='', local={}, session={};
const ctx={OpenGrace,Protection:{check:async()=>false},MutationLock:{run:async f=>f()},DiscardTools:require('../extension/discard.js'),chrome:{tabs:{async get(){return {...current}},async discard(){calls++;current.discarded=true}},storage:{local:{get:async()=>({openGraceMinutes:local.minutes})},session:{get:async keys=>Object.fromEntries(keys.filter(k=>k in session).map(k=>[k,structuredClone(session[k])]))}}},showMessage:s=>{msg=s},refresh:async()=>{},confirm:text=>{asked=text;return confirmed}};
vm.runInNewContext(source.slice(start,end),ctx);
(async()=>{const tab={id:1,windowId:1,url:'https://example.com',active:false,pinned:false,audible:false,discarded:false};
 current={...tab};calls=0;confirmed=false;await ctx.discardTab(tab);assert.equal(calls,0);
 current={...tab,pinned:true};calls=0;confirmed=true;await ctx.discardTab(tab);assert.equal(calls,0);assert.match(msg,/bỏ qua/);
 current={...tab};calls=0;await ctx.discardTab(tab);assert.equal(calls,1);assert.match(msg,/đã nghỉ/);
 // The grace window explains itself in the confirmation but never blocks the manual choice.
 session[OpenGrace.key(1)]={windowId:1,openedAt:Date.now()-60000};current={...tab};calls=0;await ctx.discardTab(tab);assert.match(asked,/Tab vừa được mở trong thời gian miễn xử lý · còn khoảng \d+ phút\. Vẫn cho nghỉ nếu bạn xác nhận\./);assert.equal(calls,1);
 session[OpenGrace.key(1)]={windowId:1,openedAt:Date.now()-40*60000};current={...tab};calls=0;await ctx.discardTab(tab);assert.doesNotMatch(asked,/thời gian miễn/);assert.equal(calls,1);
 // An unusable setting is flagged, never treated as "old enough".
 local.minutes='30 phút';current={...tab};calls=0;await ctx.discardTab(tab);assert.match(asked,/Không đọc được thời gian miễn sau mở tab/);assert.equal(calls,1);
 local.minutes=30;session={};
 current={...tab,url:'https://changed.example'};calls=0;await ctx.discardTab(tab);assert.equal(calls,0);assert.match(msg,/thay đổi/);
 current={...tab};calls=0;let replaced=false;ctx.chrome.tabs.get=async()=>{if(replaced)throw Error('No tab with id: 1');return {...current}};ctx.chrome.tabs.discard=async()=>{calls++;replaced=true;return {id:99,discarded:true}};await ctx.discardTab(tab);assert.equal(calls,1);assert.match(msg,/đã nghỉ/);assert.doesNotMatch(msg,/No tab/);
 console.log('Popup discard confirmation and protections: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
