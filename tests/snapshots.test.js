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
const group={id:3,windowId:1,title:'Project',color:'purple',collapsed:true};
const groupedTabs=[{windowId:1,index:0,groupId:3,url:'https://example.com/a',title:'A'},{windowId:1,index:1,groupId:3,url:'https://example.com/b',title:'B'},{windowId:2,index:0,groupId:99,url:'https://example.com/c',title:'C'}];
const captureResult=capture(groupedTabs,'Grouped',100,()=> 'snapshot',[group]);assert.equal(captureResult.missingGroups,1);assert.equal(captureResult.snapshot.windows[0][0].chromeGroup.title,'Project');assert.equal(captureResult.snapshot.windows[0][0].chromeGroup.collapsed,true);
const importedGrouped=validate([captureResult.snapshot],()=> 'new');assert.equal(importedGrouped[0].windows[0][1].chromeGroup.color,'purple');
const broken=JSON.parse(JSON.stringify(captureResult.snapshot));broken.windows[0][1].chromeGroup.color='red';assert.throws(()=>validate([broken],()=> 'new'),/không nhất quán/);
broken.windows[0][1].chromeGroup.color='not-a-color';assert.throws(()=>validate([broken],()=> 'new'),/không hợp lệ/);
console.log('Chrome group snapshot capture and validation: OK');
