'use strict';
// Resource numbers only pick candidates. Without a real per-tab measurement the feature must stay silent,
// so every unreadable, stale or changed sample degrades to "unknown" instead of an estimate.
const AutoDiscard=(()=>{
 const prefix='tabspace:metrics:',settingKey='autoDiscardConfig',runKey='autoDiscardRun',ackKey='autoDiscardAck',actionKey='autoDiscardAction',maxSeries=10,maxTrail=20,uncertainWaitMinutes=10;
 const notMeasurable='Không đo được tài nguyên trên Chrome này';
 const modes=Object.freeze(['suggest','ask','auto']),combines=Object.freeze(['any','all']);
 // `fast` resources need several consecutive cycles; `estimated` ones can never trigger an automatic run.
 const meta=Object.freeze({
  memory:{label:'Bộ nhớ',short:'RAM',unit:'MB',min:50,max:10000,fast:false,estimated:false},
  cpu:{label:'CPU',short:'CPU',unit:'% một lõi',min:5,max:800,fast:true,estimated:false},
  heap:{label:'Heap JavaScript',short:'heap',unit:'MB',min:50,max:4000,fast:false,estimated:true},
  network:{label:'Mạng/hoạt động nền',short:'mạng',unit:'MB/phút',min:1,max:1000,fast:true,estimated:false},
 });
 const keys=Object.freeze(Object.keys(meta));
 const defaults=Object.freeze({enabled:false,mode:'ask',combine:'any',resources:Object.freeze(['memory','cpu']),thresholds:Object.freeze({memory:500,cpu:50,heap:200,network:20}),cpuCycles:3,idleMinutes:720,maxPerRun:10,everyMinutes:5,lowMemoryOnly:false,lowMemoryFloor:20});
 function modeLabel(mode){return mode==='suggest'?'Chỉ gợi ý':mode==='auto'?'Tự động':'Hỏi trước'}
 function integer(value,min,max,name){if(!Number.isInteger(value)||value<min||value>max)throw Error(name+' phải là số nguyên từ '+min+' đến '+max+'.');return value}
 function validate(v){
  if(v===undefined)return {...defaults,resources:[...defaults.resources],thresholds:{...defaults.thresholds}};
  if(!v||typeof v!=='object'||Array.isArray(v)||typeof v.enabled!=='boolean'||!modes.includes(v.mode)||!combines.includes(v.combine)||!Array.isArray(v.resources)||!v.resources.length||v.resources.some(x=>!meta[x])||new Set(v.resources).size!==v.resources.length||!v.thresholds||typeof v.thresholds!=='object'||Array.isArray(v.thresholds))throw Error('Cấu hình cho nghỉ theo tài nguyên không hợp lệ.');
  const thresholds={};
  // A resource that is not selected keeps the default for display only; it never enters the decision.
  for(const k of keys){
   const raw=v.thresholds[k];
   if(raw===undefined){if(v.resources.includes(k))throw Error('Chọn ngưỡng cho '+meta[k].label.toLowerCase()+'.');thresholds[k]=defaults.thresholds[k];continue}
   thresholds[k]=integer(raw,meta[k].min,meta[k].max,'Ngưỡng '+meta[k].label.toLowerCase());
  }
  return {enabled:v.enabled,mode:v.mode,combine:v.combine,resources:[...v.resources],thresholds,cpuCycles:integer(v.cpuCycles,1,maxSeries,'Số chu kỳ liên tiếp'),idleMinutes:integer(v.idleMinutes,15,43200,'Khoảng thời gian không được xem'),maxPerRun:integer(v.maxPerRun,1,100,'Giới hạn mỗi lượt'),everyMinutes:integer(v.everyMinutes,1,60,'Chu kỳ đo'),lowMemoryOnly:v.lowMemoryOnly===true,lowMemoryFloor:v.lowMemoryFloor===undefined?defaults.lowMemoryFloor:integer(v.lowMemoryFloor,5,50,'Ngưỡng bộ nhớ hệ thống')};
 }
 function key(id){return prefix+id}
 // chrome.processes is Dev-channel only and no other API gives a per-tab number, so nothing is guessed.
 function capability(api,granted){
  if(api?.processes?.getProcessIdForTab&&api?.processes?.getProcessInfo)return {measurable:true,reason:'',granted:true};
  // 15.1: the permission is optional and the API is Dev-channel only, so "granted" and "readable" are
  // two different facts. Saying only the first one would promise a number that this Chrome still lacks.
  if(granted===true)return {measurable:false,granted:true,reason:notMeasurable+'. Quyền đọc tiến trình đã bật nhưng Chrome này không có API số đo theo tab.'};
  return {measurable:false,granted:false,reason:notMeasurable+'. Chrome chỉ cho số đo tiến trình ở kênh Dev — nếu máy này chưa bật quyền đọc tiến trình, bấm nút Xin quyền đọc tiến trình trong khối này.'};
 }
 // Turning the policy on without a measurement source would silently do nothing: refuse it while saving.
 function assertUsable(raw,context={}){
  const config=validate(raw);
  if(config.enabled&&context.measurable!==true)throw Error(notMeasurable+'; bật tính năng sẽ không có số để quyết định. Hãy cho nghỉ thủ công trong Tab đang mở.');
  // "Only when the system is short of memory" needs its own source; without it no run would ever happen.
  if(config.enabled&&config.lowMemoryOnly&&context.systemMemory!==true)throw Error('Không đọc được bộ nhớ hệ thống trên Chrome này; thôi chọn "chỉ chạy khi thiếu bộ nhớ" hoặc tắt tính năng.');
  // 15.3: an unattended run is only refused once a human has read the risk; nothing is assumed here.
  if(config.enabled&&config.mode==='auto'&&!ackValid(context.ack,context.now))throw Error('Mức Tự động cần bạn xác nhận rủi ro một lần; thiết lập chưa được lưu.');
  return config;
 }
 function trim(value){return String(Math.round(value*10)/10).replace('.',',')}
 function valueLabel(resource,value){
  if(!Number.isFinite(value))return 'không rõ';
  if(resource==='cpu')return trim(value)+'% một lõi';
  if(resource==='network')return trim(value)+' MB/phút';
  return value>=1024?trim(value/1024)+' GB':trim(value)+' MB';
 }
 function sinceLabel(at,now,verb){
  if(!Number.isFinite(at)||at<=0)return verb==='đo'?'chưa có số đo':'chưa có lượt nào';
  const minutes=Math.max(0,Math.round(((Number.isFinite(now)?now:at)-at)/60000));
  if(minutes<1)return verb==='đo'?'đo ngay bây giờ':'vừa chạy';
  if(minutes<60)return verb==='đo'?`đo ${minutes} phút trước`:`cách đây ${minutes} phút`;
  const hours=Math.round(minutes/60);
  if(hours<24)return verb==='đo'?`đo ${hours} giờ trước`:`cách đây ${hours} giờ`;
  const days=Math.round(hours/24);
  return verb==='đo'?`đo ${days} ngày trước`:`cách đây ${days} ngày`;
 }
 function ageLabel(at,now){return sinceLabel(at,now,'đo')}
 // 15.3: the automatic level needs one explicit human yes, kept out of the config so no backup can carry it.
 function ackValid(value,now){return !!value&&typeof value==='object'&&!Array.isArray(value)&&Number.isFinite(value.at)&&value.at<=(Number.isFinite(now)?now:Date.now())}
 function idleLabel(minutes){if(minutes<60)return `${Math.max(1,Math.round(minutes))} phút`;const hours=minutes/60;return hours<24?`${trim(hours)} giờ`:`${trim(hours/24)} ngày`}
 // A stored sample is untrusted input: a malformed record is dropped, which makes the tab unknown.
 function record(raw){
  if(!raw||typeof raw!=='object'||Array.isArray(raw)||!Number.isInteger(raw.windowId)||!Number.isInteger(raw.processId)||raw.processId<=0)return null;
  const sharedTabs=Number.isInteger(raw.sharedTabs)&&raw.sharedTabs>0?raw.sharedTabs:1;
  const series=(Array.isArray(raw.series)?raw.series:[]).map(entry=>{
   if(!entry||typeof entry!=='object'||!Number.isFinite(entry.at)||entry.at<=0)return null;
   const values={};
   for(const k of keys){const x=entry.values?.[k];if(Number.isFinite(x)&&x>=0&&x<=1e9)values[k]=Math.round(x*10)/10}
   return Object.keys(values).length?{at:entry.at,values}:null;
  }).filter(Boolean).slice(-maxSeries);
  return series.length?{windowId:raw.windowId,processId:raw.processId,sharedTabs,series}:null;
 }
 // Storage answers with the full key, so both shapes are accepted; a foreign key is ignored, not trusted.
 function readRecords(stored){
  const out={};
  if(!stored||typeof stored!=='object'||Array.isArray(stored))return out;
  for(const raw of Object.keys(stored)){
   const id=raw.startsWith(prefix)?raw.slice(prefix.length):raw;
   if(!/^\d+$/.test(id))continue;
   const value=record(stored[raw]);
   if(value)out[key(Number(id))]=value;
  }
  return out;
 }
 async function read(api,ids){
  if(!api?.storage?.session?.get)return {};
  const wanted=[...new Set((Array.isArray(ids)?ids:[]).filter(id=>Number.isInteger(id)&&id>=0).map(key))];
  if(!wanted.length)return {};
  try{return readRecords(await api.storage.session.get(wanted))}catch{return {}}
 }
 async function recall(api,tabs){return read(api,(Array.isArray(tabs)?tabs:[]).map(t=>t?.id))}
 async function forget(api,ids){
  const wanted=[...new Set((Array.isArray(ids)?ids:[]).filter(id=>Number.isInteger(id)&&id>=0).map(key))];
  if(wanted.length&&api?.storage?.session?.remove)await api.storage.session.remove(wanted);
 }
 // Samples live in storage.session only, capped to the cycles a streak needs; a URL is never stored.
 async function remember(api,records,keep=maxSeries){
  if(!api?.storage?.session?.set)return 0;
  const ids=Object.keys(records||{}).filter(id=>/^\d+$/.test(id));if(!ids.length)return 0;
  const limit=Math.max(1,Math.min(maxSeries,Number.isInteger(keep)?keep:maxSeries));
  const stored=await read(api,ids.map(Number)),out={};
  for(const id of ids){
   const next=record(records[id]);if(!next)continue;
   // A tab that moved to another window or process starts a new series instead of mixing two histories.
   const prior=stored[key(Number(id))];
   const usable=prior&&prior.windowId===next.windowId&&prior.processId===next.processId?prior.series:[];
   out[key(Number(id))]={...next,series:[...usable,...next.series].slice(-limit)};
  }
  if(!Object.keys(out).length)return 0;
  await api.storage.session.set(out);return Object.keys(out).length;
 }
 // chrome.processes measures processes, not tabs: a shared process reports the same number for all of its tabs.
 async function measure(api,tabs,now){
  const cap=capability(api);if(!cap.measurable)return {ok:false,reason:cap.reason,records:{}};
  if(!Number.isFinite(now)||now<=0)throw Error('Không xác định được thời gian.');
  const list=(Array.isArray(tabs)?tabs:[]).filter(t=>Number.isInteger(t?.id)&&t.id>=0&&Number.isInteger(t?.windowId)&&typeof t.url==='string'&&/^https?:\/\//i.test(t.url));
  const processes=new Map();
  for(const tab of list){let id;try{id=await api.processes.getProcessIdForTab(tab.id)}catch{continue}if(Number.isInteger(id)&&id>0)processes.set(tab.id,id)}
  const wanted=[...new Set(processes.values())],info=new Map();
  if(wanted.length)try{const raw=await api.processes.getProcessInfo(wanted,true);if(raw&&typeof raw==='object')for(const id of wanted)if(raw[id]&&typeof raw[id]==='object')info.set(id,raw[id])}catch{}
  const shared=new Map();for(const id of processes.values())shared.set(id,(shared.get(id)||0)+1);
  const megabytes=value=>Number.isFinite(value)&&value>=0?Math.round(value/104857.6)/10:undefined;
  const records={};
  for(const tab of list){
   const processId=processes.get(tab.id),value=info.get(processId);if(!value)continue;
   const values={},memory=megabytes(value.privateMemory),heap=megabytes(value.jsMemoryUsed);
   if(memory!==undefined)values.memory=memory;
   if(heap!==undefined)values.heap=heap;
   if(Number.isFinite(value.cpu)&&value.cpu>=0)values.cpu=Math.round(value.cpu*10)/10;
   const network=Number.isFinite(value.network)&&value.network>=0?Math.round(value.network*60/104857.6)/10:undefined;
   if(network!==undefined)values.network=network;
   if(!Object.keys(values).length)continue;
   records[tab.id]={windowId:tab.windowId,processId,sharedTabs:shared.get(processId)||1,series:[{at:now,values}]};
  }
  return {ok:true,reason:'',records};
 }
 // Samples of closed tabs are dropped with each run, so storage.session cannot grow across a Chrome session.
 async function prune(api,liveIds){
  if(!api?.storage?.session?.get||!api?.storage?.session?.remove)return 0;
  const live=new Set((Array.isArray(liveIds)?liveIds:[]).filter(id=>Number.isInteger(id)&&id>=0));
  let stored;try{stored=await api.storage.session.get(null)}catch{return 0}
  if(!stored||typeof stored!=='object')return 0;
  const stale=Object.keys(stored).filter(name=>name.startsWith(prefix)&&!live.has(Number(name.slice(prefix.length))));
  if(stale.length)try{await api.storage.session.remove(stale)}catch{}
  return stale.length;
 }
 // Measuring is the only side effect here: candidates are counted and stored, no tab is ever discarded.
 // chrome.system.memory only gives whole-machine megabytes, so the gate reads it fresh on every cycle.
async function systemFreePercent(memory){
 try{
  const info=await memory?.getInfo?.();
  const capacity=Number(info?.capacityInMB),free=Number(info?.availableMemoryInMB);
  if(!Number.isFinite(capacity)||!Number.isFinite(free)||capacity<=0||free<0||free>capacity)return null;
  return Math.floor(free/capacity*100);
 }catch{return null}
}
async function run(api,now,deps={},options={}){
  if(!Number.isFinite(now)||now<=0)throw Error('Không xác định được thời gian.');
  const data=await api.storage.local.get([settingKey,'automationPaused','protectedDomains','protectedUrls',runKey]);
  // 15.6: a measurement is the newest sample rather than policy, so it is kept in storage.session with the series.
  const journal=api.storage.session?.get&&api.storage.session?.set?api.storage.session:null;
  let config;try{config=validate(data[settingKey])}catch{return {status:'invalid',reason:'Cấu hình cho nghỉ theo tài nguyên không hợp lệ; việc đo đã dừng.'}}
  // A forced run is an explicit request to read the numbers now, so the policy gates do not apply to it.
  if(!config.enabled&&!options.force)return {status:'off',reason:'Tính năng đang tắt; không đo và không nghỉ tab nào.'};
  if(!options.force&&data.automationPaused!==undefined&&data.automationPaused!==false)return {status:'paused',reason:'Tự động hóa toàn cục đang tạm dừng.'};
  const cap=capability(api);if(!cap.measurable)return {status:'unmeasurable',reason:cap.reason,config};
  // 15.3: the low-memory option is a gate on a real system number, never a guess about the machine.
  if(config.lowMemoryOnly){
   if(!deps.memory?.getInfo)return {status:'blocked',reason:'Không đọc được bộ nhớ hệ thống; cần nguồn số RAM khả dụng để chạy ở chế độ chỉ khi thiếu bộ nhớ.',config};
   const free=await systemFreePercent(deps.memory);
   if(free===null)return {status:'blocked',reason:'Không đọc được số RAM khả dụng của hệ thống; lượt đo dừng thay vì đoán.',config};
   // A manual measurement still shows the numbers; only the automatic cycle is held back when memory is fine.
   if(!options.force&&free>=config.lowMemoryFloor)return {status:'waiting',config,reason:`RAM khả dụng còn ${free}%, chưa thấp hơn ngưỡng ${config.lowMemoryFloor}% nên lượt đo bỏ qua.`};
  }
  // Without somewhere to keep the record a cycle would measure for nothing, so the run says so first.
  if(!journal)return {status:'blocked',reason:'Không có nơi giữ kết quả đo trên máy; chrome.storage.session không khả dụng.',config};
  // Older builds kept the record in storage.local, where its tab ids would outlive the tabs they described.
  if(data[runKey]!==undefined)try{await api.storage.local.remove?.(runKey)}catch{}
  const saved=await journal.get([runKey]),last=Number.isFinite(saved?.[runKey]?.at)?saved[runKey].at:0,cycle=config.everyMinutes*60000;
  if(!options.force&&last&&now-last<cycle)return {status:'waiting',config,reason:`Chưa đến chu kỳ đo; còn khoảng ${Math.max(1,Math.ceil((cycle-(now-last))/60000))} phút.`,nextAt:last+cycle};
  // A cycle missed while Chrome was asleep is not caught up; the schedule simply resumes (6.2).
  const missed=!options.force&&last&&now-last>=2*cycle;
  let kept=new Set();
  if(deps.protection){
   let domains,urls;
   try{domains=deps.protection.validate(data.protectedDomains);urls=deps.protection.validateUrls(data.protectedUrls)}catch{return {status:'blocked',reason:'Danh sách bảo vệ không hợp lệ; việc đo đã dừng.',config}}
   kept=new Set((Array.isArray(deps.tabs)?deps.tabs:[]).filter(t=>deps.protection.matches(t?.url,domains)||deps.protection.matchesUrl(t?.url,urls)).map(t=>t.url));
  }
  const tabs=Array.isArray(deps.tabs)?deps.tabs:await api.tabs.query({});
  const normal=tabs.filter(t=>t?.incognito===false&&Number.isInteger(t.id)&&Number.isInteger(t.windowId)&&/^https?:\/\//i.test(t.url||''));
  const measured=await measure(api,normal,now);
  await remember(api,measured.records,Math.max(1,Math.min(maxSeries,config.cpuCycles)));
  await prune(api,normal.map(t=>t.id));
  const records=await recall(api,normal);
  let note=()=>'';
  if(deps.grace?.notes)try{const map=new Map((await deps.grace.notes(api,normal,now)).map(x=>[x.tab?.id,x.note]));note=t=>map.get(t.id)||''}catch{note=()=>deps.grace.manualUnknown}
  // The stored count answers "how many tabs are over the threshold", so it is counted in suggestion mode:
  // policy gates such as the grace window belong to a run, and the run re-checks them anyway.
   const result=plan(normal,records,{...config,mode:'suggest'},now,{protected:kept,note});
  // 15.4.3: only the policy plan may authorise an action, and a forced measurement (an on-demand look) never does.
  const action=config.enabled&&config.mode==='auto'&&!options.force?plan(normal,records,config,now,{protected:kept,note}):null;
  // 15.4 asks for a trail per candidate: which tab, which number crossed, when it was read, where it came from.
  // Only ids and numbers are stored; a URL or a title would outlive the reason it describes.
  const trail=result.chosen.slice(0,maxTrail).map(r=>({id:r.id,windowId:r.tab.windowId,processId:r.processId,sharedTabs:r.sharedTabs,at:r.at,values:r.values,triggered:r.triggered,source:r.source}));
  const summary={at:now,overCount:result.candidates.length,blockedCount:result.rows.length-result.candidates.length,measurable:true,ids:result.chosen.map(r=>r.id),...(trail.length?{trail}:{}),...(result.chosen.length>trail.length?{trailCut:result.chosen.length-trail.length}:{}),...(missed?{missed:true}:{})};
  try{await journal.set({[runKey]:summary})}catch{throw Error('Không xác nhận được việc lưu kết quả đo; hãy kiểm tra rồi thử lại.')}
  return {status:'measured',reason:'',config,plan:result,action,run:summary};
 }
 // Newest value plus the streak of consecutive cycles above the threshold; a missing number or a gap breaks it.
 function resource(sample,name,config,now){
  const threshold=config.thresholds[name],need=meta[name].fast?config.cpuCycles:1,limit=2*config.everyMinutes*60000;
  let streak=0,at=now,value;
  for(let i=sample.series.length-1;i>=0;i--){
   const entry=sample.series[i],candidate=entry.values[name];
   if(!Number.isFinite(candidate)||candidate<0)return {state:'unknown',at:entry.at};
   if(candidate<threshold)return {state:'under',value:candidate,at:entry.at};
   if(!streak)value=candidate;
   at=entry.at;streak++;
   if(streak>=need)break;
  }
  if(now-at>limit)return {state:'stale',value,at};
  return streak>=need?{state:'over',value,at}:{state:'rising',value,at,cycles:streak,need};
 }
 function row(tab,sample,config,now,options={}){
  const states=['incognito','active','pinned','audible','discarded'];
  const base={tab,id:tab?.id,values:{},triggered:[],reason:'',note:'',locked:true,sharedTabs:0,processId:0,at:0,source:'',series:0};
  if(!tab||!Number.isInteger(tab.id)||!Number.isInteger(tab.windowId))return {...base,reason:'Không đọc được tab'};
  if(!states.every(k=>typeof tab[k]==='boolean'))return {...base,reason:'Thiếu trạng thái tab'};
  if(tab.incognito)return {...base,reason:'Tab ẩn danh không được quản lý'};
  if(typeof tab.url!=='string'||!/^https?:\/\//i.test(tab.url))return {...base,reason:'Không phải trang http/https'};
  // A navigation after the sample invalidates it: the tab has to be measured again before any decision.
  if(typeof tab.pendingUrl==='string'&&tab.pendingUrl&&tab.pendingUrl!==tab.url)return {...base,reason:'Trang đang chuyển'};
  if(tab.discarded)return {...base,reason:'Tab đang nghỉ'};
  if(tab.active)return {...base,reason:'Tab đang được xem'};
  if(tab.pinned)return {...base,reason:'Tab đã ghim'};
  if(tab.audible)return {...base,reason:'Tab đang phát âm thanh'};
  if(!Number.isFinite(tab.lastAccessed)||tab.lastAccessed<=0||tab.lastAccessed>now)return {...base,reason:'Không xác định được lần kích hoạt gần nhất'};
  if(now-tab.lastAccessed<config.idleMinutes*60000)return {...base,reason:`Mới được xem ${idleLabel((now-tab.lastAccessed)/60000)} trước`};
  if(options.protected?.has(tab.url))return {...base,reason:'Website hoặc URL được bảo vệ'};
  const measured=record(sample);
  if(!measured)return {...base,reason:'Chưa có số đo cho tab này'};
  if(measured.windowId!==tab.windowId)return {...base,reason:'Tab đã đổi cửa sổ sau lần đo'};
  const newest=measured.series[measured.series.length-1];
  if(now-newest.at>2*config.everyMinutes*60000)return {...base,reason:'Mẫu đo đã cũ',at:newest.at,processId:measured.processId,sharedTabs:measured.sharedTabs};
  const details={},values={};
  for(const name of config.resources){
   const result=resource(measured,name,config,now);
   details[name]=result;
   if(Number.isFinite(result.value))values[name]=result.value;
  }
  const done={...base,values,details,sharedTabs:measured.sharedTabs,processId:measured.processId,at:newest.at,source:'tiến trình Chrome',series:measured.series.length};
  const note=typeof options.note==='function'?String(options.note(tab)||''):'';
  const triggered=config.resources.filter(name=>details[name].state==='over');
  // Only real process numbers may drive a run; a heap estimate stays a labelled hint.
  const real=triggered.filter(name=>!meta[name].estimated);
  if(!triggered.length){
   const rising=config.resources.filter(name=>details[name].state==='rising').map(name=>`${meta[name].label.toLowerCase()} vượt ngưỡng ${details[name].cycles}/${details[name].need} chu kỳ liên tiếp`);
   const missing=config.resources.filter(name=>['unknown','stale'].includes(details[name].state)).map(name=>`Không đọc được ${meta[name].label.toLowerCase()}${details[name].state==='stale'?' (mẫu đo đã cũ)':''}`);
   return {...done,reason:[...rising,...missing].join(' · ')||'Dưới ngưỡng đã chọn'};
  }
  if(config.combine==='all'&&triggered.length!==config.resources.length)return {...done,triggered,reason:'Chưa vượt mọi ngưỡng đã chọn'};
  if(config.mode==='auto'&&!real.length)return {...done,triggered,reason:'Chỉ có số ước lượng; không tự nghỉ tab'};
  if(note&&config.mode!=='suggest')return {...done,triggered,reason:'Tab đang trong thời gian miễn xử lý; chỉ nghỉ khi bạn tự chọn',note};
  return {...done,triggered,locked:false,note};
 }
 // The plan is shared by suggestions, the ask card, an automatic run and the manual shortcut.
 function plan(tabs,records,config,now,options={}){
  const c=validate(config);
  if(!Number.isFinite(now)||now<=0)throw Error('Không xác định được thời gian.');
  // The list arrives as a Set or a plain array depending on the caller; a missing list is read as "nothing kept".
  const kept=typeof options.protected?.has==='function'?options.protected:Array.isArray(options.protected)?new Set(options.protected):undefined;
  const guard={...(kept?{protected:kept}:{}),...(typeof options.note==='function'?{note:options.note}:{})};
  const rows=(Array.isArray(tabs)?tabs:[]).map(tab=>row(tab,records?.[key(tab?.id)],c,now,guard));
  const weight=entry=>Math.max(...entry.triggered.map(name=>(entry.values[name]??0)/c.thresholds[name]),0);
  const candidates=rows.filter(r=>!r.locked).sort((a,b)=>weight(b)-weight(a)||a.id-b.id);
  const counts=new Map();
  for(const r of rows)if(r.locked)counts.set(r.reason,(counts.get(r.reason)||0)+1);
  return {config:c,rows,candidates,chosen:candidates.slice(0,c.maxPerRun),deferred:candidates.slice(c.maxPerRun),counts:[...counts].map(([reason,count])=>({reason,count})),measuredAt:candidates.reduce((max,r)=>Math.max(max,r.at),0)};
 }
 function line(entry,config,now){
  if(!entry)return '';
  if(!Object.keys(entry.values).length)return entry.reason||'Chưa có số đo';
  const names=entry.triggered.length?entry.triggered:config.resources;
  const text=names.map(name=>`${meta[name].short} ${valueLabel(name,entry.values[name])}${meta[name].estimated?' (ước lượng)':''}`).join(' · ');
  return `${text} · ${ageLabel(entry.at,now)}${entry.sharedTabs>1?` · tiến trình chung ${entry.sharedTabs} tab`:''}${entry.source?` · nguồn: ${entry.source}`:''}`;
 }
 // 15.4: every surface reads the same record, so freshness and "did anybody answer" are decided once.
 // A card nobody answers is not consent, and skipping it lasts only for the measurement it describes.
 function recent(c,run,now,mode){
  if(!c.enabled||c.mode!==mode)return null;
  if(!run||run.measurable!==true||!Number.isFinite(run.at)||!(Number.isInteger(run.overCount)&&run.overCount>0))return null;
  // Numbers older than two cycles are already refused as a decision basis, so they must not nag either.
  if(now-run.at>=2*c.everyMinutes*60000)return null;
  const ids=(Array.isArray(run.ids)?run.ids:[]).filter(id=>Number.isInteger(id)&&id>=0);
  if(!ids.length)return null;
  // Rows whose tab vanished are dropped by the page that shows the tabs, not by the decision.
  const rows=(Array.isArray(run.trail)?run.trail:[]).filter(r=>ids.includes(r?.id));
  return {at:run.at,overCount:run.overCount,blockedCount:Number.isInteger(run.blockedCount)?run.blockedCount:0,ids,rows,cut:Number.isInteger(run.trailCut)?run.trailCut:0,dismissed:run.dismissedAt===run.at,age:ageLabel(run.at,now)};
 }
 // A bad config or a missing clock is refused the same way on both paths: throw on time, stay silent on policy.
 function gate(config,now){
  if(!Number.isFinite(now))throw Error('Không xác định được thời gian.');
  try{return validate(config)}catch{return null}
 }
 function attention(config,run,now){
  const c=gate(config,now);
  return c?recent(c,run,now,'ask'):null;
 }
 // 5.7: "Chỉ gợi ý" asks nothing and does nothing, so its candidates belong on the health page, not in a card.
 function suggestions(config,run,now){
  const c=gate(config,now);
  return c?recent(c,run,now,'suggest'):null;
 }
 // The health page also has to say why it is empty, from the same config and the same record.
 function health(raw,run,now,context={}){
  if(!Number.isFinite(now))throw Error('Không xác định được thời gian.');
  let c;try{c=validate(raw)}catch{return {kind:'error',text:'Cấu hình cho nghỉ theo tài nguyên không hợp lệ; việc đo đã dừng.'}}
  if(context.measurable!==true)return {kind:'unmeasurable',text:`${notMeasurable}. Tabspace không suy số từ tên miền, tiêu đề hay số lượng tab, nên không có danh sách nào để xem; việc cho nghỉ thủ công ở Tab đang mở vẫn dùng bình thường.`};
  if(!c.enabled)return {kind:'off',text:'Tính năng đang tắt nên không có lượt đo nào trong nền. Bật lên trong khối Cài đặt & sao lưu rồi đợi một chu kỳ đo.'};
  if(c.mode==='auto')return {kind:'off',text:'Mức Tự động vẫn chưa có ở bản này: mỗi lượt nền chỉ đo và đếm, không có lệnh nghỉ tab nào được gọi.'};
  if(c.mode==='ask')return {kind:'ask',text:'Ở mức Hỏi trước, danh sách nằm trong Cần chú ý kèm nút Xem & nghỉ, không ở trang này.'};
  const list=suggestions(c,run,now);
  if(list)return {kind:'list',list,text:''};
  if(!run||!Number.isFinite(run.at))return {kind:'empty',text:'Chưa có lượt đo nào trong phiên Chrome này; số đo chỉ sống cùng phiên, nên khởi động lại Chrome là danh sách trống.'};
  if(!(Number.isInteger(run.overCount)&&run.overCount>0))return {kind:'empty',text:`Lượt đo ${ageLabel(run.at,now)} không thấy tab nào vượt ngưỡng đã chọn.`};
  return {kind:'stale',text:`Lượt đo ${ageLabel(run.at,now)} đã quá hai chu kỳ nên không còn được dùng để gợi ý; đo lại để có danh sách mới.`};
 }
 // 15.4.3: acting is its own entry point, so every measurement path stays read-only and a stale plan cannot be replayed.
 // The journal is written before a tab is touched: an unrecorded automatic run is worse than a refused one.
  // 15.3 and 15.7: the two shared "do not disturb" settings, read through the app's own checker and never
 // re-decided here. Fail-closed in every direction: no checker, an unreadable clock and an unreadable
 // window state all hold the run, because "unknown" is not evidence that nobody is presenting. The
 // fullscreen hold deliberately ignores deferFullscreenNotifications - that switch says whether a
 // notification waits, and auto-close has never let it authorise acting on a tab either.
 const holdQuiet='Đang giờ yên lặng nên lượt Tự động nhường; chưa tab nào bị nghỉ.';
 const holdFullscreen='Đang toàn màn hình hoặc không xác định được trạng thái cửa sổ; chưa tab nào bị nghỉ.';
 const holdBlind='Không có nguồn kiểm tra giờ yên lặng và toàn màn hình nên lượt Tự động nhường; chưa tab nào bị nghỉ.';
 async function holdReason(api,deps,now,data){
  if(!deps.reminders?.isQuiet||!deps.reminders?.deferFullscreen)return holdBlind;
  let quiet=true;
  try{quiet=deps.reminders.isQuiet(data.quietHours,now)}catch{quiet=true}
  if(quiet)return holdQuiet;
  try{if(await deps.reminders.deferFullscreen(api,true))return holdFullscreen}catch{return holdFullscreen}
  return '';
 }
 // 15.4: the channels that already exist speak a small fixed vocabulary (complete / blocked / uncertain),
 // and a run that found nothing to do is not a result at all. The translation lives here, once, so the
 // journal and the page notice cannot describe one run three different ways.
 const noticePrefix='discard:';
 function notifyStatus(report){
  if(!report||typeof report!=='object')return null;
  if(report.journalFailed===true)return 'blocked';
  if(report.status==='complete')return 'complete';
  if(report.status==='running'||report.status==='partial'||report.status==='uncertain')return 'uncertain';
  return null;
 }
 // The id is derived from the run itself, so a worker that repeats a delivery cannot grow the journal.
 function resultEvent(report){
  const status=notifyStatus(report),at=Number.isFinite(report?.at)?report.at:0,id=Number.isFinite(report?.id)?report.id:0;
  if(!status||!at||!id)return null;
  return {id:noticePrefix+id,kind:'result',at,status};
 }
 // 15.4.3: the one place an automatic run reaches outside the app. The switch is this key alone -
 // autoCloseNotifications belongs to auto-close and never meant to cover these runs - and it is off
 // until the block says otherwise, so a build that only got the journal keeps only the journal.
 const notifyId='tabspace-auto-discard';
 function notifyMessage(report){
  const status=notifyStatus(report);if(!status)return '';
  const n=Number.isFinite(report.counts?.discarded)?report.counts.discarded:null;
  // Fixed copy, no address and no title: an OS notice is readable by anyone sitting at the machine.
  if(status==='complete')return `Một lượt Tự động nhường đã cho nghỉ ${n===null?'vài':n} tab. Mở Tabspace để kiểm tra.`;
  if(status==='uncertain')return 'Một lượt Tự động nhường chưa xác nhận được hết kết quả. Mở Tabspace để xem lại từng tab.';
  return 'Một lượt Tự động nhường bị chặn trước khi ghi được kết quả; mở Tabspace để xem nhật ký.';
 }
 async function notify(api,report,now,reminders){
  // The journal's own gate, reused: a run it refuses to book is a run this channel does not announce either.
  if(!resultEvent(report))return 'silent';
  const message=notifyMessage(report);if(!message||!Number.isFinite(now)||now<=0)return 'silent';
  let data;try{data=await api.storage.local.get(['autoDiscardNotifications','quietHours'])}catch{return 'unavailable'}
  if(data.autoDiscardNotifications!==true)return 'disabled';
  // Asked again here instead of trusted from the run: a notice landing in quiet hours is the exact thing
  // the setting exists to prevent, and nothing is lost by staying quiet - the journal already has the run.
  let quiet=true;try{quiet=reminders?.isQuiet?reminders.isQuiet(data.quietHours,now):true}catch{quiet=true}
  if(quiet)return 'held';
  try{if(reminders?.deferFullscreen&&await reminders.deferFullscreen(api,true))return 'held'}catch{return 'held'}
  let granted=false;try{granted=await api.permissions.contains({permissions:['notifications']})}catch{return 'unavailable'}
  if(!granted||!api.notifications?.create)return 'unavailable';
  // No retry queue on purpose: an ambiguous send must not be replayed, which is the rule the reminder
  // channel follows, and the run itself is already recorded in the journal and in the block.
  try{await api.notifications.create(notifyId,{type:'basic',iconUrl:api.runtime.getURL('reminder-icon.png'),title:'Tabspace',message,silent:true});return 'attempted'}catch{return 'unavailable'}
 }
async function apply(api,result,now,deps={}){
  if(!Number.isFinite(now)||now<=0)throw Error('Không xác định được thời gian.');
  if(!result||result.status!=='measured'||!result.action)return {status:'idle',reason:'Không có lượt đo nào được phép tự nghỉ tab; chưa tab nào bị nghỉ.'};
  let config;try{config=validate(result.config)}catch{return {status:'invalid',reason:'Cấu hình cho nghỉ theo tài nguyên không hợp lệ; chưa tab nào bị nghỉ.'}}
  if(!config.enabled||config.mode!=='auto')return {status:'idle',reason:'Chỉ mức Tự động mới được phép nghỉ tab; chưa tab nào bị nghỉ.'};
  if(!Number.isFinite(result.run?.at)||(now-result.run.at)>=2*config.everyMinutes*60000)return {status:'stale',reason:'Số đo của lượt này đã quá hai chu kỳ nên không còn là căn cứ; chưa tab nào bị nghỉ.'};
  if(!deps.discard?.request)return {status:'unmeasurable',reason:'Không có đường cho nghỉ tab ở điểm gọi này; chưa tab nào bị nghỉ.'};
  const data=await api.storage.local.get(['automationPaused',ackKey,actionKey,'protectedDomains','protectedUrls','quietHours']);
  if(data.automationPaused!==undefined&&data.automationPaused!==false)return {status:'paused',reason:'Tự động hóa toàn cục đang tạm dừng; chưa tab nào bị nghỉ.'};
  if(!ackValid(data[ackKey],now))return {status:'unconfirmed',reason:'Mức Tự động chưa có xác nhận rủi ro trên máy này; chưa tab nào bị nghỉ.'};
  const last=data[actionKey];
  // A previous cycle that could not confirm its own result buys itself ten minutes of quiet, not a retry storm.
  if(last&&(last.status==='running'||last.status==='partial'||last.status==='uncertain'||last.journalFailed===true)&&Number.isFinite(last.at)&&now-last.at<uncertainWaitMinutes*60000)return {status:'waiting',reason:`Lượt tự động trước chưa xác nhận được kết quả nên Tabspace chờ ${uncertainWaitMinutes} phút; chưa tab nào bị nghỉ.`,last};
  // Asked again here rather than trusted from the plan: a presentation can start between the measurement
  // and this line, and a hold leaves no report behind because nothing about the tabs changed.
  const held=await holdReason(api,deps,now,data);
  if(held)return {status:'waiting',reason:held};
  let domains=[],urls=[];
  try{domains=deps.protection?deps.protection.validate(data.protectedDomains):[];urls=deps.protection?deps.protection.validateUrls(data.protectedUrls):[]}catch{return {status:'blocked',reason:'Danh sách bảo vệ không hợp lệ; chưa tab nào bị nghỉ.'}}
  const report={at:result.run.at,id:result.run.at,status:'running',counts:{requested:0,discarded:0,skipped:0,unconfirmed:0,protected:0},results:[]};
  for(const row of result.action.chosen){
   const tab=row?.tab;
   if(!tab||!Number.isInteger(tab.id))continue;
   if(deps.protection&&(deps.protection.matches(tab.url,domains)||deps.protection.matchesUrl(tab.url,urls))){report.counts.protected++;report.results.push({id:tab.id,windowId:tab.windowId,status:'protected'});continue}
   report.counts.requested++;report.results.push({id:tab.id,windowId:tab.windowId,url:tab.url,status:'queued'});
  }
  report.counts.requested=report.results.filter(r=>r.status==='queued').length;
  try{await api.storage.local.set({[actionKey]:report})}catch{return {status:'blocked',reason:'Không ghi được nhật ký cho lượt tự động; chưa tab nào bị nghỉ.'}}
  for(const item of report.results){
   if(item.status!=='queued')continue;
   const original=result.action.chosen.find(r=>r.tab?.id===item.id)?.tab||item;
   let outcome;try{outcome=await deps.discard.request(api,original)}catch{outcome={status:'unknown'}}
   item.status=outcome?.status==='discarded'?'discarded':outcome?.status==='skipped'?'skipped':'unconfirmed';
   if(item.status==='discarded')report.counts.discarded++;else if(item.status==='skipped')report.counts.skipped++;else report.counts.unconfirmed++;
   try{await api.storage.local.set({[actionKey]:report})}catch{report.journalFailed=true}
  }
  const acted=report.counts.discarded+report.counts.skipped+report.counts.unconfirmed;
  report.status=report.journalFailed===true?'uncertain':!acted?'empty':report.counts.unconfirmed?'partial':'complete';
  try{await api.storage.local.set({[actionKey]:report})}catch{report.journalFailed=true;report.status='uncertain'}
  return {status:'applied',report,reason:report.counts.discarded?`${report.counts.discarded} tab đã nghỉ.`:'Không tab nào được nghỉ.'};
 }
 // One line for the outcome, shared by the settings header and the health page so the two cannot disagree.
 function actionLabel(report,now){
  if(!report||!Number.isFinite(report.at))return {kind:'none',text:'Chưa có lượt tự động nào trên máy này.'};
  const c=report.counts||{},num=value=>Number.isInteger(value)&&value>=0?value:0,when=sinceLabel(report.at,Number.isFinite(now)?now:report.at,'chạy');
  const parts=[`nghỉ ${num(c.discarded)} tab`];
  if(num(c.unconfirmed))parts.push(`${num(c.unconfirmed)} tab không xác nhận được`);
  if(num(c.skipped))parts.push(`${num(c.skipped)} tab bị bỏ qua vì đã thay đổi`);
  if(num(c.protected))parts.push(`${num(c.protected)} tab bị danh sách bảo vệ chặn`);
  if(report.status==='running'||report.status==='uncertain')parts.push('kết quả chưa được ghi đầy đủ, hãy xem lại danh sách tab');
  const body=`${when}: ${parts.join(' · ')}`;
  return {kind:report.status==='complete'&&!num(c.unconfirmed)?'done':'warning',text:`Lượt tự động ${body}.`,short:`lượt tự động ${body}`};
 }
 // The note lives on the measurement itself, so the next cycle replaces it instead of hiding future cards.
 async function dismiss(api,at,undo=false){
  if(!Number.isInteger(at))throw Error('Không xác định được lần đo cần ẩn.');
  const journal=api.storage.session;
  if(!journal?.get||!journal?.set)throw Error('Không đọc được nơi giữ kết quả đo; khởi động lại Chrome rồi thử lại.');
  const data=await journal.get([runKey]),run=data&&data[runKey];
  if(!run||run.at!==at)throw Error('Lần đo đã thay đổi ở nơi khác; hãy xem lại danh sách trước khi ẩn thẻ.');
  const next={...run};
  if(undo)delete next.dismissedAt;else next.dismissedAt=at;
   try{await journal.set({[runKey]:next})}catch{throw Error('Không xác nhận được việc ẩn thẻ; hãy kiểm tra lại trước khi thử.')}
  return next;
 }
 function describe(raw,context={}){
  let c;try{c=validate(raw)}catch{return {kind:'error',text:'Cấu hình cho nghỉ theo tài nguyên không hợp lệ; tính năng đã dừng.'}}
  if(context.measurable!==true)return {kind:c.enabled?'warning':'off',text:`${notMeasurable}. ${c.enabled?'Thiết lập đang bật nhưng không có số đo; sẽ không có tab nào được nghỉ.':'Chỉ còn đường cho nghỉ thủ công ở Tab đang mở.'}`};
  if(!c.enabled)return {kind:'off',text:`Tự cho nghỉ theo tài nguyên đang tắt. Ngưỡng hiện tại: ${c.resources.map(name=>`${meta[name].short} ≥ ${valueLabel(name,c.thresholds[name])}`).join(c.combine==='all'?' và ':' hoặc ')}.`};
  if(context.paused!==undefined&&context.paused!==false)return {kind:'paused',text:`${modeLabel(c.mode)} cho nghỉ theo tài nguyên đã bật nhưng tự động hóa toàn cục đang tạm dừng.`};
  const count=Number.isInteger(context.overCount)?context.overCount>0?` · ${context.overCount} tab đang vượt ngưỡng`:' · chưa có tab nào vượt ngưỡng':'';
  const age=Number.isFinite(context.measuredAt)&&context.measuredAt>0?` · ${ageLabel(context.measuredAt,Number.isFinite(context.now)?context.now:context.measuredAt)}`:' · chưa có số đo';
  const status=c.mode==='auto'?' · không hỏi lại từng lượt':c.mode==='ask'?' · chỉ nghỉ khi bạn xác nhận':' · không tự chọn tab nào';
  const acted=Number.isInteger(context.lastAction?.at)?` · ${actionLabel(context.lastAction,Number.isFinite(context.now)?context.now:context.lastAction.at).short}`:'';
  const stale=Number.isFinite(context.measuredAt)&&context.measuredAt>0&&Number.isFinite(context.now)&&context.now-context.measuredAt>2*c.everyMinutes*60000;
  return {kind:c.mode,text:`${modeLabel(c.mode)} · xét ${c.resources.map(name=>meta[name].short).join(', ')} · tối đa ${c.maxPerRun} tab mỗi lượt${count}${age}${stale?' · dữ liệu đo đã cũ, hãy đo lại':''}${context.missed===true?' · có chu kỳ đo đã bỏ lỡ, không chạy bù':''}${status}${acted}`};
 }
 return {prefix,settingKey,runKey,ackKey,actionKey,keys,meta,modes,combines,maxSeries,maxTrail,uncertainWaitMinutes,defaults,notMeasurable,modeLabel,integer,validate,capability,assertUsable,key,record,read,readRecords,recall,forget,remember,measure,prune,run,apply,actionLabel,ackValid,holdReason,notifyStatus,resultEvent,noticePrefix,notify,notifyMessage,notifyId,resource,row,plan,line,attention,suggestions,health,dismiss,describe,valueLabel,ageLabel,idleLabel};
})();
if(typeof module!=='undefined')module.exports=AutoDiscard;
