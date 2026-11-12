const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('extension/dashboard.js','utf8'),start=source.indexOf('let loadRevision=0,'),end=source.indexOf('\nfunction showDialog',start);assert(start>=0&&end>start);
const reads=[],tabReads=[];let renders=0;const defer=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve}};
const ctx={chrome:{storage:{local:{get(){const d=defer();reads.push(d);return d.promise}}},tabs:{query(){const d=defer();tabReads.push(d);return d.promise}}},TrashTools:{prefix:'trash:'},BatchTools:{prefix:'batch:'},isDashboard:()=>false,selected:new Set(),render:()=>renders++,groups:[],snapshots:[],presets:[],trash:[],batches:[],tabs:[],Promise,Object,Array,Set};
vm.runInNewContext(source.slice(start,end),ctx);
(async()=>{const older=ctx.load(),newer=ctx.load();reads[1].resolve({groups:[{name:'new'}]});tabReads[1].resolve([]);await newer;reads[0].resolve({groups:[{name:'old'}]});tabReads[0].resolve([]);await older;assert.equal(ctx.groups[0].name,'new');assert.equal(renders,1);console.log('Out-of-order storage refresh: OK')})().catch(e=>{console.error(e);process.exitCode=1});
