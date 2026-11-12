const assert=require('node:assert/strict');
const T=require('../extension/trash.js');
function mock(){const db={groups:[{id:'g1',name:'Work',items:[{id:'t1',title:'One',url:'https://example.com'}]}],snapshots:[{id:'s1',name:'Session',windows:[]}]};let writes=0,failAt=0;return{db,setFail(n){failAt=n},storage:{local:{async get(keys){let out={};for(const k of (Array.isArray(keys)?keys:[keys]))if(db[k]!==undefined)out[k]=JSON.parse(JSON.stringify(db[k]));return out},async set(v){writes++;if(writes===failAt)throw Error('storage failed');Object.assign(db,JSON.parse(JSON.stringify(v)))},async remove(k){delete db[k]}}}}}
(async()=>{
 let api=mock();await T.move(api,'item','t1','g1',()=> 'r1');assert.equal(api.db.groups[0].items.length,0);assert.equal(api.db[T.prefix+'r1'].value.id,'t1');await T.restore(api,'r1');assert.equal(api.db.groups[0].items[0].id,'t1');assert(!api.db[T.prefix+'r1']);
 api=mock();await T.move(api,'group','g1',null,()=> 'r2');assert.equal(api.db.groups.length,0);await T.restore(api,'r2');assert.equal(api.db.groups[0].items[0].id,'t1');
 api=mock();await T.move(api,'session','s1',null,()=> 'r3');assert.equal(api.db.snapshots.length,0);await T.restore(api,'r3');assert.equal(api.db.snapshots[0].id,'s1');
 api=mock();api.setFail(1);await assert.rejects(T.move(api,'group','g1',null,()=> 'r4'));assert.equal(api.db.groups.length,1);
 api=mock();api.setFail(2);await assert.rejects(T.move(api,'group','g1',null,()=> 'r5'));assert.equal(api.db.groups.length,1);assert(api.db[T.prefix+'r5']);await assert.rejects(T.restore(api,'r5'),/đã tồn tại/);
 api=mock();await T.move(api,'item','t1','g1',()=> 'r6');api.db.groups=[];await assert.rejects(T.restore(api,'r6'),/Nhóm gốc/);assert(api.db[T.prefix+'r6']);
 console.log('Trash move, restore, collision and failure: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
