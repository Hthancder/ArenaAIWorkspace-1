const assert = require('node:assert/strict');
const B = require('../extension/batches.js');
function mock(){let db={},removed=[],opened=[],writes=0,failAt=0;return {db,removed,opened,setFail(n){failAt=n},storage:{local:{async set(v){writes++;if(writes===failAt)throw Error('storage');Object.assign(db,JSON.parse(JSON.stringify(v)))},async get(k){return {[k]:db[k]}}}},tabs:{async get(id){return {url:'https://example.com/'+id}},async remove(id){removed.push(id)},async create({url}){opened.push(url)}}}}
(async()=>{
 const entries=[1,2].map(i=>({tabId:i,url:'https://example.com/'+i,item:{title:'Tab '+i}}));
 let api=mock();let res=await B.closeSaved(api,entries,'manual',()=> 'one',()=>true);assert.deepEqual(api.removed,[1,2]);assert.deepEqual(res.batch.items.map(t=>t.status),['closed','closed']);
 let undo=await B.reopen(api,B.prefix+'one',[0]);assert.equal(undo.opened,1);assert.equal(api.db[B.prefix+'one'].items[0].status,'opened');await B.reopen(api,B.prefix+'one',[0]);assert.equal(api.opened.length,1);
 api=mock();api.setFail(1);await assert.rejects(B.closeSaved(api,entries,'manual',()=> 'two',()=>true));assert.equal(api.removed.length,0);
 api=mock();api.setFail(3);res=await B.closeSaved(api,entries,'manual',()=> 'three',()=>true);assert.equal(res.stopped,true);assert.deepEqual(api.removed,[1]);assert.equal(api.db[B.prefix+'three'].items[0].status,'closing');await B.reopen(api,B.prefix+'three',[0]);assert.equal(api.opened.length,0);
 api=mock();res=await B.closeSaved(api,entries,'preset',()=> 'four',t=>!t.url.endsWith('/1'));assert.deepEqual(api.removed,[2]);assert.equal(res.batch.items[0].status,'skipped');
 console.log('Batch journaling, failures and recovery: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
