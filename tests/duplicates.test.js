const assert=require('node:assert/strict');const D=require('../extension/duplicates.js');
const tabs=[
 {id:1,windowId:1,url:'https://example.com/page?q=1#one'},
 {id:2,windowId:2,url:'https://example.com/page?q=1#one'},
 {id:3,windowId:1,url:'https://example.com/page?q=1#two'},
 {id:4,windowId:1,url:'https://example.com/page?q=2#one'},
 {id:5,windowId:3,url:'https://example.com/page?q=1#one',incognito:true},
 {id:6,url:'chrome://settings'}, {id:7,url:'chrome://settings'},
 {id:8,url:undefined}
];
const results=D.find(tabs);assert.equal(results.length,1);assert.deepEqual(results[0].tabs.map(t=>t.id),[1,2]);assert.equal(results[0].url,tabs[0].url);
assert.equal(D.find([{id:1,url:'https://x'},{id:2,url:'https://x',incognito:true}]).length,0);
assert.deepEqual(D.find([]),[]);
console.log('Duplicate detection exact URL and incognito: OK');
