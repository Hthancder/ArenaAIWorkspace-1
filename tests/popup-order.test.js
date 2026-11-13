const assert=require('node:assert/strict');const {tabsByEnd}=require('../extension/popup-order.js');
const tabs=[{id:10,windowId:2,index:0},{id:11,windowId:2,index:1},{id:20,windowId:1,index:0},{id:21,windowId:1,index:1},{id:22,windowId:1,index:2},{id:23,windowId:1,index:3,incognito:true}];
assert.deepEqual(tabsByEnd(tabs,1).map(t=>t.id),[22,21,20,11,10]);
assert.deepEqual(tabsByEnd(tabs,2).map(t=>t.id),[11,10,22,21,20]);
assert.deepEqual(tabs.map(t=>t.id),[10,11,20,21,22,23]);
assert.deepEqual(tabsByEnd([],1),[]);
console.log('Popup ordering by end of current window: OK');
const P=require('../extension/popup-order.js');const dashboard='chrome-extension://abc/dashboard.html';const countTabs=[{id:1,url:'https://one',discarded:true},{id:2,url:'https://two',discarded:false},{id:3,url:dashboard+'?view=inbox',discarded:false},{id:4,url:'https://private',incognito:true,discarded:true}];const counts=P.stats(countTabs,[{items:[{url:'https://one'},{url:'https://one'}]},{items:[]}],dashboard);assert.deepEqual(counts,{open:2,sleeping:1,saved:2});assert.deepEqual(P.visibleTabs(countTabs,dashboard).map(t=>t.id),[1,2]);assert.deepEqual(P.tabsByEnd(countTabs,undefined,dashboard).map(t=>t.id),[1,2]);console.log('Popup counters exclude incognito and dashboard, sleeping is a subset: OK');
