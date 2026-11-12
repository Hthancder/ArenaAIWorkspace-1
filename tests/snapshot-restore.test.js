const assert=require('node:assert/strict');const {restore}=require('../extension/snapshots.js');
const meta={key:'g:1',title:'Work',color:'blue',collapsed:false};
const windows=[[{url:'https://a.test',title:'A',chromeGroup:meta},{url:'https://b.test',title:'B',chromeGroup:meta},{url:'https://c.test',title:'C',pinned:true}]];
function mock(){const calls={groups:[],updates:[],opened:[]};let next=10;return {calls,windows:{async create(opts){calls.opened.push(opts.url);return{id:1,tabs:[{id:next++}]} }},tabs:{async create(opts){calls.opened.push(opts.url);return{id:next++}},async update(id,opts){calls.updates.push({id,...opts})},async group(opts){calls.groups.push(opts);return 42}},tabGroups:{async update(id,opts){calls.updates.push({id,...opts})}}}}
(async()=>{let api=mock(),r=await restore(api,windows,true);assert.equal(r.opened,3);assert.equal(r.failed,0);assert.equal(r.groupFailed,0);assert.deepEqual(api.calls.groups[0].tabIds,[10,11]);assert.equal(api.calls.updates.find(x=>x.id===42).title,'Work');
api=mock();r=await restore(api,windows,false);assert.equal(r.opened,3);assert.equal(api.calls.groups.length,0);
api=mock();api.tabs.group=async()=>{throw Error('denied')};r=await restore(api,windows,true);assert.equal(r.opened,3);assert.equal(r.groupFailed,1);assert.match(r.details.join(' '),/denied/);
api=mock();api.windows.create=async()=>{throw Error('closed')};r=await restore(api,windows,true);assert.equal(r.failed,3);assert.equal(r.opened,0);
api=mock();api.tabs.create=async()=>{throw Error('failed')};r=await restore(api,windows,true);assert.equal(r.failed,2);assert.equal(r.opened,1);assert.equal(api.calls.groups[0].tabIds.length,1);
console.log('Session restore grouping, opt-out and partial errors: OK');})().catch(e=>{console.error(e);process.exitCode=1});
