const assert=require('node:assert/strict'),G=require('../extension/open-grace.js'),B=require('../extension/popup-bulk.js');
const now=1800000000000,tab=(id,extra={})=>({id,windowId:1,url:`https://example.com/${id}`,title:'T'+id,incognito:false,active:false,pinned:false,audible:false,discarded:false,...extra});
const record=(id,ago,at=now)=>[G.key(id),{windowId:1,openedAt:at-ago}];

// A manual action is never blocked by grace: recent and unknown tabs are only flagged for an explicit check.
const rows=G.review([tab(1),tab(2),tab(3)],Object.fromEntries([record(1,40*60000),record(2,9*60000+1000)]),now,30);
assert.deepEqual(rows.map(r=>r.state),['old','recent','unknown']);
assert.deepEqual(rows.map(r=>r.flagged),[false,true,true]);
assert.equal(G.note(rows[0]),'');
assert.equal(rows[1].minutesLeft,21);
assert.equal(G.note(rows[1]),'Tab vừa được mở trong thời gian miễn xử lý · còn khoảng 21 phút');
assert.equal(G.note(rows[2]),'Không xác định được thời điểm mở tab trong phiên Chrome');
assert.equal(G.note(undefined),'');
assert.equal(G.review([tab(1)],Object.fromEntries([record(1,1000)]),now,1)[0].minutesLeft,1);
assert.deepEqual(G.review([],{},now,30),[]);
assert.throws(()=>G.review([tab(1)],{},now,0),/từ 1 đến 10080/);

(async()=>{
 // notes() owns both reads so every surface explains the same state.
 let local={openGraceMinutes:30},session=Object.fromEntries([record(1,40*60000),record(2,60000)]);
 const api={storage:{local:{get:async()=>({...local})},session:{get:async keys=>Object.fromEntries(keys.filter(k=>k in session).map(k=>[k,structuredClone(session[k])]))}}};
 const notes=async(list,at=now,target=api)=>new Map((await G.notes(target,list,at)).map(x=>[x.tab.id,x.note]));
 const all=await notes([tab(1),tab(2),tab(3)]);
 assert.equal(all.get(1),'');assert.match(all.get(2),/vừa được mở/);assert.match(all.get(3),/Không xác định được thời điểm mở/);
 // The window is read again per preview, so a longer setting can turn "old" back into "recent".
 local.openGraceMinutes=45;
 assert.match((await notes([tab(1)])).get(1),/còn khoảng 5 phút/);
 // Unusable settings, clocks or storage flag every tab instead of defaulting to "old".
 local.openGraceMinutes='45 phút';
 assert.equal((await notes([tab(1),tab(3)])).get(1),G.manualUnknown);
 local.openGraceMinutes=30;
 assert.equal((await notes([tab(1)])).get(1),'');
 assert.equal((await notes([tab(1)],Number.NaN)).get(1),G.manualUnknown);
 assert.match((await notes([tab(1)],now,{storage:{}})).get(1),/Không đọc được thời gian miễn/);
 assert.deepEqual(await G.notes(api,[{id:1},{id:2,windowId:1.5},undefined],now),[]);

 // The popup preview keeps every tab selectable: a flagged row only loses its default check.
 const live=new Map([[10,tab(10)],[11,tab(11,{active:true})],[12,tab(12)]]);
 const grace={notes:async(_api,plan)=>plan.map(t=>({tab:t,note:t.id===10?'Tab vừa được mở trong thời gian miễn xử lý':t.id===12?'Không xác định được thời điểm mở tab trong phiên Chrome':''}))};
 const preview=(plan,options)=>B.preview({tabs:{get:async id=>({...live.get(id)})}},plan,{check:async()=>false,...(options||{})},grace);
 assert.deepEqual((await preview([tab(10),tab(11),tab(12)])).map(r=>[r.reason,r.note]),
  [['','Tab vừa được mở trong thời gian miễn xử lý'],['Đang xem',''],['','Không xác định được thời điểm mở tab trong phiên Chrome']]);
 assert.deepEqual((await B.preview({tabs:{get:async id=>({...live.get(id)})}},[tab(10),tab(12)],{check:async()=>false})).map(r=>r.note),['','']);
 console.log('Manual sleep review flags recent and unverified tabs without blocking the action: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
