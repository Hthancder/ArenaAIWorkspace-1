const assert=require('node:assert/strict');const B=require('../extension/bulk.js');
const groups=[{id:'g',name:'Group',items:[{id:'a',title:'A'},{id:'b',title:'B'}]},{id:'inbox',name:'Inbox',items:[{id:'i',title:'I'}]}];
let plan=B.savedPlan(groups,[B.key('group','g'),B.key('item','a'),B.key('item','i')]);assert.equal(plan.length,2);assert.equal(plan[0].type,'group');assert.match(plan[0].name,/2 tab/);assert.equal(plan[1].id,'i');
plan=B.savedPlan(groups,[B.key('item','a'),B.key('item','b')]);assert.equal(plan.length,2);assert.equal(plan[0].groupId,'g');
assert.deepEqual(B.savedPlan(groups,[B.key('group','inbox')]),[]);
const trash=[{id:'i',type:'item'},{id:'s',type:'session'},{id:'g',type:'group'}];assert.deepEqual(B.trashPlan(trash,trash.map(x=>B.key('trash',x.id))).map(x=>x.id),['g','s','i']);
assert.deepEqual(B.selectedIds(['invalid',B.key('session','x')],'session'),['x']);
console.log('Bulk overlap, group inclusion and restore order: OK');
