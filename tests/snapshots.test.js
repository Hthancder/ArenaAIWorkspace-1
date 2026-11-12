const assert = require('node:assert/strict');
const {capture,validate} = require('../extension/snapshots.js');
const tabs = [
  {windowId:1,index:1,url:'https://example.org/two',title:'Two',pinned:false},
  {windowId:1,index:0,url:'https://example.org/one',title:'One',pinned:true},
  {windowId:2,index:0,url:'http://example.org',title:'Other'},
  {windowId:3,index:0,url:'https://secret.example',incognito:true},
  {windowId:1,index:2,url:'chrome://settings'},
];
const {snapshot,skipped} = capture(tabs,'Work',100,()=> 'id');
assert.equal(skipped,2);
assert.equal(snapshot.windows.length,2);
assert.deepEqual(snapshot.windows[0].map(t=>t.title),['One','Two']);
assert.equal(snapshot.windows[0][0].pinned,true);
const imported=validate([snapshot],()=> 'new-id');
assert.equal(imported[0].id,'new-id');
assert.equal(imported[0].windows[0][0].url,'https://example.org/one');
assert.throws(()=>validate([{name:'Bad',windows:[[{url:'javascript:alert(1)',title:'x'}]]}],()=> 'x'));
assert.throws(()=>validate({},()=> 'x'));
console.log('Snapshot capture and import validation: OK');
