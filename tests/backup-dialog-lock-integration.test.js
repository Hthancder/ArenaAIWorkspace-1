// Exercise the real dialog submit wrapper and the real import callback together.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('extension/dashboard.js','utf8');
const slice=(start,end)=>{const a=source.indexOf(start),b=source.indexOf(end,a);assert(a>=0&&b>a);return source.slice(a,b)};
const db={groups:[],workspaces:[],snapshots:[],presets:[],smartGroups:[]};
let held=false,writes=0,mode='merge';const locks={async request(name,options,fn){assert.equal(name,'tabspace:data-mutation');assert.equal(options.ifAvailable,true);if(held)return fn(null);held=true;try{return await fn({name})}finally{held=false}}};
const MutationLock={run:fn=>require('../extension/mutation-lock.js').run(fn,locks)};
const body={innerHTML:'',querySelector:()=>null},dialog={open:false,setAttribute(){},removeAttribute(){},showModal(){this.open=true},close(){this.open=false}},form={},messages=[];
const local={async get(keys){return Object.fromEntries((Array.isArray(keys)?keys:[keys]).filter(k=>k in db).map(k=>[k,structuredClone(db[k])]))},async set(data){assert(held,'import must write under the dialog lock');writes++;Object.assign(db,structuredClone(data))}};
const ctx={MutationLock,chrome:{storage:{local}},$:s=>({'#dialogBody':body,'#dialog':dialog,'#dialogForm':form}[s]),FormData:class{has(){return false}get(){return mode}},notify:s=>messages.push(s),load:async()=>{},confirm:()=>true,validUrl:u=>/^https?:\/\//i.test(u),id:()=>crypto.randomUUID(),BackupTools:require('../extension/backup.js'),SmartGroups:require('../extension/smart-groups.js'),Appearance:require('../extension/appearance.js'),Protection:require('../extension/protection.js'),SnapshotTools:require('../extension/snapshots.js'),PresetTools:require('../extension/presets.js'),WorkspaceTools:require('../extension/workspaces.js'),OrganizeTools:require('../extension/organize.js')};
vm.runInNewContext(slice('function showDialog(','\nfunction keyboardHelp(')+'\n'+slice('function validateImport(',"document.addEventListener('click',async e=>")+'\n'+slice('async function importBackupFile(',"document.addEventListener('change',async e=>"),ctx);
(async()=>{
 const backup=ctx.BackupTools.exportData({groups:[{id:'old',name:'Bản sao',items:[]}]}),file={size:100,text:async()=>JSON.stringify(backup)};
 await ctx.importBackupFile(file);assert(dialog.open);assert.match(body.innerHTML,/Nhập dữ liệu/);
 const submitter={value:'submit',disabled:false},submit=()=>form.onsubmit({preventDefault(){},submitter,currentTarget:form});
 held=true;await submit();assert.equal(writes,0);assert(dialog.open);assert.match(messages.pop(),/đang xử lý/);held=false;
 await submit();assert.equal(writes,1);assert.equal(dialog.open,false);assert(db.groups.some(g=>g.name==='Bản sao'));assert.match(messages.pop(),/Đã nhập dữ liệu/);assert.equal(submitter.disabled,false);
 await ctx.importBackupFile(file);mode='replace';db.groups.push({id:'new',name:'Mới thêm',items:[]});await submit();assert.equal(writes,1);assert(dialog.open);assert.match(messages.pop(),/đã thay đổi/);mode='merge';await submit();assert.equal(writes,2);assert(db.groups.some(g=>g.id==='new'));assert.equal(dialog.open,false);
 console.log('Backup import works through the real dialog lock and retries after contention: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
