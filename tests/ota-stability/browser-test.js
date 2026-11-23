const fs = require('fs'), vm = require('vm'), assert = require('assert');
const app = fs.readFileSync(process.argv[2], 'utf8');
const cpp = fs.readFileSync(process.argv[3], 'utf8');
const appCode = app.slice(app.indexOf('$("#ota-cancel-btn").addEventListener'), app.indexOf('$("#wifi-pwd-input").addEventListener'));
const start = cpp.indexOf("$('cancelBtn').addEventListener('click'");
const end = cpp.indexOf('\n</script>',start);
const standaloneCode = cpp.slice(start,end);
assert(appCode && standaloneCode && !appCode.includes('/wificonnect'));
async function scenario(code, standalone, mode) {
  const elems = new Map();
  function element(key) { if(!elems.has(key)) elems.set(key,{handlers:{},style:{},className:'',textContent:'',disabled:false,classList:{add(){},remove(){}},addEventListener(n,fn){this.handlers[n]=fn}}); return elems.get(key); }
  const calls=[]; let finishBegin; let finishCommit;
  const file={size:65536,slice(a,b){return {a,b};}};
  class FormData {append() {}}
  const ctx = {console,FormData,AbortController,IS_DEV:false,selectedOtaFile:file,validFile:file,otaBusy:false,otaCancelled:false,otaCommitting:false,otaAbortCtrl:null,
    window:{addEventListener(){}},location:{reload(){},set href(v){}},
    $:s=>element(s),setTimeout:(f,ms)=>{if(ms<=1500)f();return 1;},clearTimeout(){},
    fetch:async(url,opts={})=>{
      calls.push({url,opts});
      if(url.endsWith('/ota/begin')){
        if(mode==='conflict')return {ok:false,status:409,json:async()=>({msg:'Another OTA transfer is active'})};
        if(mode==='cancel-begin')await new Promise(r=>finishBegin=r);
        return {ok:true,json:async()=>({ok:true,session:'session-A',chunkSize:32768})};
      }
      if(url.includes('/ota/chunk'))return {ok:true,json:async()=>({ok:true,written:opts.body.b})};
      if(url.endsWith('/ota/commit')){
        if(mode==='uncertain')throw new Error('connection lost');
        if(mode==='restart-failed')return {ok:true,json:async()=>({ok:true,restartScheduled:false})};
        if(mode==='cancel-commit')await new Promise(r=>finishCommit=r);
        return {ok:true,json:async()=>({ok:true})};
      }
      return {ok:true,json:async()=>({ok:true})};
    }
  };
  vm.createContext(ctx); vm.runInContext(code,ctx);
  const startEl=element(standalone?'uploadBtn':'#ota-start-btn');
  const cancelEl=element(standalone?'cancelBtn':'#ota-cancel-btn');
  const running=startEl.handlers.click();
  if(mode==='cancel-begin') {await new Promise(r=>setImmediate(r)); await cancelEl.handlers.click(); assert(!calls.some(c=>c.url.endsWith('/abort'))); finishBegin();}
  if(mode==='cancel-commit') {while(!finishCommit) await new Promise(r=>setImmediate(r)); await cancelEl.handlers.click(); assert(!calls.some(c=>c.url.endsWith('/abort'))); finishCommit();}
  await running;
  if(mode==='conflict') assert(!calls.some(c=>c.url.endsWith('/abort')),'failed begin must not abort other transfer');
  if(mode==='cancel-begin') {
    const abort=calls.find(c=>c.url.endsWith('/abort')); assert(abort && abort.opts.headers['X-OTA-Session']==='session-A');
    assert(!calls.some(c=>c.url.includes('/ota/chunk')));
  }
  if(mode==='restart-failed') {
    assert(element(standalone?'fileinfo':'#ota-status').textContent.includes('Restart the device manually'));
    assert(!calls.some(c=>c.url.endsWith('/abort')));
  }
  if(mode==='uncertain') {
    assert(!calls.some(c=>c.url.endsWith('/abort')),'commit outcome can be unknown');
    assert(element(standalone?'fileinfo':'#ota-status').textContent.includes('may have completed'));
  }
  if(['uncertain','cancel-commit'].includes(mode)) {
    for(const c of calls.filter(c=>c.url.includes('/ota/chunk')||c.url.endsWith('/ota/commit'))) assert.strictEqual(c.opts.headers['X-OTA-Session'],'session-A');
  }
}
(async()=>{for(const [code,standalone] of [[appCode,false],[standaloneCode,true]]) for(const mode of ['conflict','cancel-begin','uncertain','cancel-commit','restart-failed']) await scenario(code,standalone,mode); console.log('Both OTA pages: conflict, cancel, session, restart and uncertain commit tests passed');})().catch(e=>{console.error(e);process.exitCode=1;});
