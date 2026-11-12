const assert=require('node:assert/strict');const N=require('../extension/native-groups.js');
const list=[{id:1,windowId:10,url:'https://a',groupId:-1,title:'A'},{id:2,windowId:10,url:'https://b',groupId:4,title:'B'},{id:3,windowId:10,url:'https://c',groupId:-1,pinned:true,title:'C'},{id:4,windowId:20,url:'https://d',groupId:-1,title:'D'},{id:5,windowId:10,url:'https://private',incognito:true,groupId:-1}];
let calls=[];function mock(){return {tabs:{async get(id){const t=list.find(t=>t.id===id);if(!t)throw Error('gone');return {...t}},async group(arg){calls.push(['group',arg]);return 55},async ungroup(ids){calls.push(['ungroup',ids])}},tabGroups:{async update(id,opts){calls.push(['update',id,opts])}}}}
(async()=>{assert.equal(N.selectedWindows(list).length,2);assert.equal(N.selectedWindows(list)[0].eligible.length,2);
let api=mock(),res=await N.create(api,list,10,'Work','blue');assert.equal(res.grouped,2);assert.deepEqual(calls[0][1].tabIds,[1,2]);assert.deepEqual(res.skipped,['C']);assert.equal(calls[1][2].color,'blue');
calls=[];api=mock();api.tabs.get=async id=>({...list.find(t=>t.id===id),url:'https://changed'});await assert.rejects(N.create(api,[list[0]],10,'X','blue'),/Không còn tab/);assert.equal(calls.length,0);
calls=[];api=mock();api.tabGroups.update=async()=>{throw Error('update failed')};res=await N.create(api,[list[0]],10,'X','red');assert.equal(res.grouped,1);assert.equal(res.updateError,'update failed');
calls=[];api=mock();res=await N.ungroup(api,list);assert.equal(res.ungrouped,1);assert.deepEqual(calls[0][1],[2]);
calls=[];api=mock();api.tabs.get=async id=>({...list.find(t=>t.id===id),groupId:5});await assert.rejects(N.ungroup(api,[list[1]]),/Không còn tab/);assert.equal(calls.length,0);
await assert.rejects(N.create(mock(),list,10,'X','bad'),/Màu/);console.log('Native groups window scope, revalidation and partial failure: OK');})().catch(e=>{console.error(e);process.exitCode=1});
