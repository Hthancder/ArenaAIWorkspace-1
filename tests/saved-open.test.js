const assert=require('node:assert/strict'),D=require('../extension/duplicates.js');
const groups=[{name:'<Work>',items:[{url:'https://x/a?q=1#f',title:'saved'},{url:'https://x/a?q=1#f',title:'another'}]},{name:'Other',items:[{url:'https://x/a?q=1#f'}]},{name:'Empty'}];
const tabs=[{id:1,url:'https://x/a?q=1#f'},{id:2,url:'https://x/a?q=1'},{id:3,url:'https://x/a?q=1#f',incognito:true},{id:4,url:'chrome://settings'},{id:5,url:'https://x/a?q=1#f'}];
const found=D.savedOpen(tabs,groups);assert.deepEqual(found.map(x=>x.tab.id),[1,5]);assert.equal(found[0].refs.length,3);assert.equal(found[0].refs[0].groupName,'<Work>');assert.deepEqual(D.savedOpen([],groups),[]);assert.deepEqual(D.savedOpen(tabs,[]),[]);
console.log('Saved-open suggestions: exact URLs, multiple copies and privacy OK');
