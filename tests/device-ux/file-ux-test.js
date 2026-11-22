const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(process.argv[2], 'utf8');
const tick = () => new Promise(r => setImmediate(r));
const slice = (a,b) => src.slice(src.indexOf(a),src.indexOf(b,src.indexOf(a)));
(async () => {
  // Upload: the destination belongs to the selected file, not a later navigation;
  // failures must not stall the rest of the queue or be reported as success.
  const requests=[], labels=[], body={innerHTML:'',appendChild(){}}, summary={textContent:''}, close={disabled:false};
  const env={console, currentDrive:'SD',currentPath:'/first',IS_DEV:false, URLSearchParams,
    Dialog:{show(){}}, fetchSystemInfo:async()=>{}, fetchFiles:async()=>{},
    $:s => s.includes('dialog-body') ? body : s.includes('upload-close') ? close : summary,
    T:{uploadLoading(){const label={textContent:''},bar={style:{}}; labels.push(label); return {querySelector:s=>s.includes('bar')?bar:label};}},
    FormData:class{append(){}}, XMLHttpRequest:class {constructor(){this.upload={};requests.push(this)} open(method,url){this.url=url} send(){}},
    File:class{constructor(parts,name){this.name=name}}};
  vm.createContext(env); vm.runInContext(slice('const _queueUpload = [];','\nasync function runCommand'),env);
  env.appendFileToQueue([{name:'a.txt'},{name:'b.txt'}]);
  const upload = env.uploadFile(); env.currentPath='/second';
  assert(requests[0].url.includes('folder=%2Ffirst'));
  requests[0].status=500; requests[0].responseText='disk full'; requests[0].onload(); await tick();
  assert(labels[0].textContent.includes('failed')); assert.equal(requests.length,2);
  requests[1].onerror(); await upload;
  assert(labels[1].textContent.includes('incomplete')); assert(!close.disabled); assert(summary.textContent.includes('2 file(s) failed'));
  const batches=[[{isFile:true,fullPath:'/dir/a',file(cb){cb({type:'text/plain'})}}],[{isFile:true,fullPath:'/dir/b',file(cb){cb({type:'text/plain'})}}],[]];
  await env.appendDroppedFiles({isDirectory:true,createReader(){return {readEntries(cb){cb(batches.shift())}}}},'SD','/original');
  assert(labels.some(l=>l.textContent.includes('dir/a')) && labels.some(l=>l.textContent.includes('dir/b')));
  await assert.rejects(env.appendDroppedFiles({isFile:true,file(ok,err){err(new Error('read denied'))}},'SD','/'));

  // Out-of-order folder responses cannot overwrite the newly selected folder.
  const waiting=[], table={innerHTML:'',children:[],querySelector(){return {textContent:''}}}, cls={add(){},remove(){}};
  const folderEnv={console, currentDrive:'',currentPath:'',filesRequestGeneration:0,btnRefreshFolder:{classList:cls},
    $:s=>s==='table.explorer tbody'?table:s==='.current-path'?{textContent:''}:null,
    updateURL(){},getURLParams(){return {}},renderFileRow(x){folderEnv.rendered=x;table.children=[1]},
    requestGet:()=>new Promise((res,rej)=>waiting.push({res,rej}))};
  vm.createContext(folderEnv); vm.runInContext(slice('async function fetchFiles(', '\nfunction applyThemeCss'),folderEnv);
  const a=folderEnv.fetchFiles('SD','/a'), b=folderEnv.fetchFiles('SD','/b');
  waiting[1].res('B'); await b; waiting[0].res('A'); await a; assert.equal(folderEnv.rendered,'B');
  const c=folderEnv.fetchFiles('SD','/c'); waiting[2].rej(new Error('offline')); await c;
  assert(!table.innerHTML.includes('Loading'));

  // A failed save remains dirty, including empty files, and must not run.
  let hash='old', rejectSave, ran=0, alerts=[];
  const editor={value:'new',getAttribute(){return hash},setAttribute(k,v){hash=v}};
  const saveButton={disabled:false},runButton={disabled:false};
  const editorEnv={console,currentDrive:'SD',alert:m=>alerts.push(m),calcHash:s=>s,isModified:e=>e.value!==hash,
    $:s=>s.includes('file-content')?editor:s.includes('editor-file-name')?{textContent:'/x.js'}:s.includes('act-save')?saveButton:runButton,
    Dialog:{loading:{show(){},hide(){}}},getSerialCommand:()=> 'js',runCommand:async()=>{ran++},
    requestPost:()=>new Promise((resolve,reject)=>{rejectSave=reject})};
  vm.createContext(editorEnv); vm.runInContext(slice('let editorSaving = false;', '\nfunction isModified'),editorEnv);
  const saving=editorEnv.saveEditorFile(true); rejectSave(new Error('offline')); await saving;
  assert.equal(hash,'old'); assert(!saveButton.disabled); assert.equal(ran,0); assert(alerts.length);
  console.log('File upload, folder race and editor recovery regression tests passed');
})().catch(e=>{console.error(e);process.exit(1)});
