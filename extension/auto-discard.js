'use strict';
// Resource numbers only pick candidates. Without a real per-tab measurement the feature must stay silent,
// so every unreadable, stale or changed sample degrades to "unknown" instead of an estimate.
const AutoDiscard=(()=>{
 const prefix='tabspace:metrics:',settingKey='autoDiscardConfig',runKey='autoDiscardRun',maxSeries=10;
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
 function capability(api){
  if(!api?.processes?.getProcessIdForTab||!api?.processes?.getProcessInfo)return {measurable:false,reason:notMeasurable+'. Chrome chỉ cho số đo tiến trình ở kênh Dev và quyền đọc chưa được bật.'};
  return {measurable:true,reason:''};
 }
 // Turning the policy on without a measurement source would silently do nothing: refuse it while saving.
 function assertUsable(raw,context={}){
  const config=validate(raw);
  if(config.enabled&&context.measurable!==true)throw Error(notMeasurable+'; bật tính năng sẽ không có số để quyết định. Hãy cho nghỉ thủ công trong Tab đang mở.');
  // "Only when the system is short of memory" needs its own source; without it no run would ever happen.
  if(config.enabled&&config.lowMemoryOnly&&context.systemMemory!==true)throw Error('Không đọc được bộ nhớ hệ thống trên Chrome này; thôi chọn "chỉ chạy khi thiếu bộ nhớ" hoặc tắt tính năng.');
  return config;
 }
 function trim(value){return String(Math.round(value*10)/10).replace('.',',')}
 function valueLabel(resource,value){
  if(!Number.isFinite(value))return 'không rõ';
  if(resource==='cpu')return trim(value)+'% một lõi';
  if(resource==='network')return trim(value)+' MB/phút';
  return value>=1024?trim(value/1024)+' GB':trim(value)+' MB';
 }
 function ageLabel(at,now){
  if(!Number.isFinite(at)||at<=0)return 'chưa có số đo';
  const minutes=Math.max(0,Math.round(((Number.isFinite(now)?now:at)-at)/60000));
  if(minutes<1)return 'đo ngay bây giờ';
  if(minutes<60)return `đo ${minutes} phút trước`;
  const hours=Math.round(minutes/60);
  return hours<24?`đo ${hours} giờ trước`:`đo ${Math.round(hours/24)} ngày trước`;
 }
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
  const last=Number.isFinite(data[runKey]?.at)?data[runKey].at:0,cycle=config.everyMinutes*60000;
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
  const summary={at:now,overCount:result.candidates.length,blockedCount:result.rows.length-result.candidates.length,measurable:true,ids:result.chosen.map(r=>r.id),...(missed?{missed:true}:{})};
  try{await api.storage.local.set({[runKey]:summary})}catch{throw Error('Không xác nhận được việc lưu kết quả đo; hãy kiểm tra rồi thử lại.')}
  return {status:'measured',reason:'',config,plan:result,run:summary};
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
 // 15.4: in "Hỏi trước", the measured candidates become one card in Cần chú ý. A card nobody answers is
 // not consent, and dismissing it lasts only for the measurement it describes, so no suppression list grows.
 function attention(config,run,now){
  if(!Number.isFinite(now))throw Error('Không xác định được thời gian.');
  let c;try{c=validate(config)}catch{return null}
  if(!c.enabled||c.mode!=='ask')return null;
  if(!run||run.measurable!==true||!Number.isFinite(run.at)||!(Number.isInteger(run.overCount)&&run.overCount>0))return null;
  // Numbers older than two cycles are already refused as a decision basis, so they must not nag either.
  if(now-run.at>=2*c.everyMinutes*60000)return null;
  const ids=(Array.isArray(run.ids)?run.ids:[]).filter(id=>Number.isInteger(id)&&id>=0);
  if(!ids.length)return null;
  return {at:run.at,overCount:run.overCount,blockedCount:Number.isInteger(run.blockedCount)?run.blockedCount:0,ids,dismissed:run.dismissedAt===run.at,age:ageLabel(run.at,now)};
 }
 // The note lives on the measurement itself, so the next cycle replaces it instead of hiding future cards.
 async function dismiss(api,at,undo=false){
  if(!Number.isInteger(at))throw Error('Không xác định được lần đo cần ẩn.');
  const data=await api.storage.local.get([runKey]),run=data&&data[runKey];
  if(!run||run.at!==at)throw Error('Lần đo đã thay đổi ở nơi khác; hãy xem lại danh sách trước khi ẩn thẻ.');
  const next={...run};
  if(undo)delete next.dismissedAt;else next.dismissedAt=at;
  try{await api.storage.local.set({[runKey]:next})}catch{throw Error('Không xác nhận được việc ẩn thẻ; hãy kiểm tra lại trước khi thử.')}
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
  const stale=Number.isFinite(context.measuredAt)&&context.measuredAt>0&&Number.isFinite(context.now)&&context.now-context.measuredAt>2*c.everyMinutes*60000;
  return {kind:c.mode,text:`${modeLabel(c.mode)} · xét ${c.resources.map(name=>meta[name].short).join(', ')} · tối đa ${c.maxPerRun} tab mỗi lượt${count}${age}${stale?' · dữ liệu đo đã cũ, hãy đo lại':''}${context.missed===true?' · có chu kỳ đo đã bỏ lỡ, không chạy bù':''}${status}`};
 }
 return {prefix,settingKey,runKey,keys,meta,modes,combines,maxSeries,defaults,notMeasurable,modeLabel,integer,validate,capability,assertUsable,key,record,read,readRecords,recall,forget,remember,measure,prune,run,resource,row,plan,line,attention,dismiss,describe,valueLabel,ageLabel,idleLabel};
})();
if(typeof module!=='undefined')module.exports=AutoDiscard;
