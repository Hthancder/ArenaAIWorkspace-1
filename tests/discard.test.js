const assert=require('node:assert/strict');const D=require('../extension/discard.js');
const original={id:7,windowId:1,url:'https://example.com',active:false,pinned:false,audible:false,discarded:false};
(async()=>{
 let gets=0;const changedId={tabs:{async get(id){gets++;if(gets>1)throw Error('No tab with id: '+id);return {...original}},async discard(){return {id:99,discarded:true}}}};let r=await D.request(changedId,original);assert.equal(r.status,'discarded');assert.equal(gets,1);assert.match(D.message(r.status),/đã nghỉ/);
 gets=0;const missing={tabs:{async get(){if(++gets>1)throw Error('No tab');return {...original}},async discard(){return undefined}}};r=await D.request(missing,original);assert.equal(r.status,'unknown');assert.match(D.message(r.status),/không xác nhận/);
 let seen=[];const changedButNotYet={tabs:{async get(id){seen.push(id);return {...original,id,discarded:id===99}},async discard(){return {id:99,discarded:false}}}};r=await D.request(changedButNotYet,original);assert.equal(r.status,'discarded');assert.deepEqual(seen,[7,99]);
 let calls=0;const active={tabs:{async get(){return {...original,active:true}},async discard(){calls++}}};r=await D.request(active,original);assert.equal(r.status,'skipped');assert.equal(calls,0);
 const mismatch={tabs:{async get(){return {...original,url:'https://different'}},async discard(){calls++}}};r=await D.request(mismatch,original);assert.equal(r.status,'skipped');assert.equal(calls,0);
 console.log('Discard result, replaced tab ID and ambiguity: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
