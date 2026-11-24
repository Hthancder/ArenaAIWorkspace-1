const fs=require('fs'),vm=require('vm'),assert=require('assert');
const src=fs.readFileSync(process.argv[2],'utf8');
const a=src.indexOf('async function refreshStudio(){'),b=src.indexOf('\nfunction renderStudioOverview',a);assert(a>=0&&b>a);
const msg={classList:{remove(){},add(){}},textContent:'',className:''},last={textContent:''};
let values={}, held=null;
const context={studioRefreshGeneration:0,studioLastSys:{BOARD:'old'},studioLastSecLab:{},studioLastQr:[],studioLastBadusb:{enabled:true},lastSysInfo:{},window:{location:{hostname:'device',port:''}},document:{getElementById:id=>id==='st-msg'?msg:id==='st-last'?last:null},console, requestGet:url=>values[url]==='hold'?new Promise(resolve=>{held=resolve}): values[url] ? Promise.resolve(JSON.stringify(values[url])):Promise.reject(Error('offline')),renderStudioOverview(){},renderStudioMic(){},renderStudioQr(){},renderStudioClock(){},renderStudioBadusb(){}};
vm.createContext(context);vm.runInContext(src.slice(a,b),context);
(async()=>{
 values={'/systeminfo':{BOARD:'new'},'/seclab/status':{},'/studio/qrcodes':{qrcodes:[]}};
 await context.refreshStudio();assert(msg.textContent.includes('Auto-Run'));assert(last.textContent.includes('cũ'));assert.equal(context.studioLastBadusb.enabled,true);
 values['/badusb/autorun']={enabled:false};await context.refreshStudio();assert(last.textContent.includes('Cập nhật'));
 values['/systeminfo']='hold';let old=context.refreshStudio();values['/systeminfo']={BOARD:'latest'};await context.refreshStudio();held(JSON.stringify({BOARD:'obsolete'}));await old;assert.equal(context.studioLastSys.BOARD,'latest');
 console.log('Studio partial failure and out-of-order refresh checks passed');
})().catch(e=>{console.error(e);process.exitCode=1});
