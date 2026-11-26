'use strict';
// Popup selection is short-lived and non-destructive until the user confirms a preview.
const PopupBulk=(()=>{
 const limit=100,prefix='tabspace:popup-selection:',alarmPrefix='tabspace:popup-selection-expire:',ttl=120000;
 function validPlan(plan){
  if(!Array.isArray(plan)||!plan.length||plan.length>limit)throw Error('Hãy chọn từ 1 đến 100 tab web.');const ids=new Set();
  return plan.map(t=>{if(!t||!Number.isSafeInteger(t.id)||t.id<0||!Number.isSafeInteger(t.windowId)||t.windowId<0||typeof t.url!=='string'||t.url.length>10000||!/^https?:\/\//i.test(t.url)||ids.has(t.id))throw Error('Lựa chọn tab không hợp lệ.');ids.add(t.id);return {id:t.id,windowId:t.windowId,url:t.url,title:typeof t.title==='string'?t.title.slice(0,300):t.url}});
 }
 function same(old,current){return !!current&&current.id===old.id&&current.incognito===false&&current.windowId===old.windowId&&current.url===old.url&&(!current.pendingUrl||current.pendingUrl===old.url)}
 function reason(tab){return tab.active?'Đang xem':tab.pinned?'Đã ghim':tab.audible?'Đang phát âm thanh':tab.discarded?'Đã nghỉ':''}
 async function preview(api,raw,protection){
  const plan=validPlan(raw),out=[];for(const original of plan){let current;try{current=await api.tabs.get(original.id)}catch{out.push({tab:original,reason:'Tab không còn tồn tại'});continue}if(!same(original,current)){out.push({tab:original,reason:'Tab đã thay đổi hoặc không còn khả dụng'});continue}const status=reason(current);if(status){out.push({tab:original,reason:status});continue}if(await protection.check(api,original.url)){out.push({tab:original,reason:'Website được bảo vệ'});continue}out.push({tab:original,reason:''})}return out;
 }
 async function sleep(api,raw,protection,discard){
  const plan=validPlan(raw),results=[];for(let i=0;i<plan.length;i++){const tab=plan[i];let fresh;try{fresh=await api.tabs.get(tab.id)}catch{results.push({tab,status:'skipped'});continue}if(!same(tab,fresh)||reason(fresh)){results.push({tab,status:'skipped'});continue}
   try{if(await protection.check(api,tab.url)){results.push({tab,status:'protected'});continue}}catch{results.push({tab,status:'unavailable'});for(const next of plan.slice(i+1))results.push({tab:next,status:'notAttempted'});break}
   let result;try{result=await discard.request(api,tab)}catch{results.push({tab,status:'unknown'});for(const next of plan.slice(i+1))results.push({tab:next,status:'notAttempted'});break}results.push({tab,status:result?.status==='discarded'?'discarded':result?.status==='skipped'?'skipped':'unknown'});if(!['discarded','skipped'].includes(result?.status)){for(const next of plan.slice(i+1))results.push({tab:next,status:'notAttempted'});break}
  }return results;
 }
 function groupChoices(raw){
  const groups=raw===undefined?[]:raw;if(!Array.isArray(groups))throw Error('Không đọc được nhóm lưu hợp lệ.');const ids=new Set();for(const g of groups){if(!g||typeof g.id!=='string'||!g.id||ids.has(g.id)||typeof g.name!=='string'||!Array.isArray(g.items))throw Error('Danh sách nhóm lưu không hợp lệ.');ids.add(g.id)}
  const list=groups.map(g=>({id:g.id,name:g.name,version:JSON.stringify([g.id,g.name,g.icon??null,g.color??null])}));if(!ids.has('inbox'))list.unshift({id:'inbox',name:'Để sau (sẽ tạo nếu chọn)',version:null});else list.sort((a,b)=>(a.id==='inbox'?-1:0)-(b.id==='inbox'?-1:0));return list;
 }
 async function savePreview(api,raw){
  const plan=validPlan(raw),data=await api.storage.local.get('groups'),choices=groupChoices(data.groups),rows=[];
  for(const tab of plan){let fresh;try{fresh=await api.tabs.get(tab.id)}catch{rows.push({tab,reason:'Tab không còn tồn tại'});continue}rows.push({tab,reason:same(tab,fresh)?'':'Tab đã thay đổi hoặc không còn khả dụng'})}return {rows,choices};
 }
 async function saveCopies(api,raw,target,makeId,now){
  const plan=validPlan(raw);if(!target||typeof target.id!=='string'||!Number.isFinite(now)||now<=0||typeof makeId!=='function')throw Error('Lựa chọn lưu không hợp lệ.');const accepted=[],skipped=[];
  for(const tab of plan){let fresh;try{fresh=await api.tabs.get(tab.id)}catch{skipped.push(tab);continue}if(!same(tab,fresh)){skipped.push(tab);continue}accepted.push({tab,title:typeof fresh.title==='string'&&fresh.title?fresh.title:tab.url})}
  if(!accepted.length)return {saved:[],skipped};const data=await api.storage.local.get('groups'),choices=groupChoices(data.groups),current=choices.find(x=>x.id===target.id),newGroup=target.id==='__new__'&&typeof target.newName==='string'&&target.newName.trim().length>0&&target.newName.trim().length<=80;if(!newGroup&&(!current||current.version!==target.version))throw Error('Nhóm đích đã thay đổi; hãy mở lại xem trước.');let open;try{open=await api.tabs.query({});if(!Array.isArray(open))throw Error()}catch{throw Error('Không đọc được tab đang mở; chưa lưu.')}const byId=new Map(open.map(t=>[t.id,t])),final=[];for(const entry of accepted){const fresh=byId.get(entry.tab.id);if(!same(entry.tab,fresh)){skipped.push(entry.tab);continue}final.push({tab:entry.tab,title:typeof fresh.title==='string'&&fresh.title?fresh.title:entry.tab.url})}if(!final.length)return {saved:[],skipped};
  const groups=(data.groups??[]).map(g=>({...g,items:[...g.items]}));let group=groups.find(g=>g.id===target.id);if(newGroup){const groupId=makeId();if(typeof groupId!=='string'||!groupId||groups.some(g=>g.id===groupId))throw Error('Không tạo được ID nhóm duy nhất; chưa lưu.');group={id:groupId,name:target.newName.trim(),icon:'✦',color:'#7771df',createdAt:now,items:[]};groups.unshift(group)}if(!group&&target.id==='inbox'){group={id:'inbox',name:'Để sau',icon:'✦',color:'#7771df',createdAt:now,items:[]};groups.unshift(group)}if(!group)throw Error('Nhóm đích không còn tồn tại.');
  const known=new Set(groups.flatMap(g=>g.items.map(x=>x?.id).filter(x=>typeof x==='string'))),items=[];for(const entry of final){const id=makeId();if(typeof id!=='string'||!id||known.has(id))throw Error('Không tạo được ID bản lưu duy nhất; chưa lưu.');known.add(id);items.push({id,url:entry.tab.url,title:entry.title,createdAt:now,tags:[]})}group.items.unshift(...items);
  try{await api.storage.local.set({groups})}catch{throw Error('Không xác nhận được kết quả lưu; hãy kiểm tra nhóm đích trước khi thử lại. Không tab nào bị đóng.')};return {saved:final.map(x=>x.tab),skipped};
 }
 function tokenValid(token){return typeof token==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(token)}
 async function transfer(api,raw,token,now){
  const plan=validPlan(raw);if(!tokenValid(token)||!Number.isFinite(now)||now<=0||!api.storage?.session?.set||!api.storage?.session?.remove||!api.alarms?.create)throw Error('Không thể chuyển lựa chọn an toàn.');const alarm=alarmPrefix+token,key=prefix+token;try{await api.storage.session.set({[key]:{createdAt:now,tabs:plan}})}catch{try{await api.storage.session.remove(key)}catch{throw Error('Không xác nhận được dữ liệu tạm; dữ liệu có thể còn đến khi Chrome đóng.')}throw Error('Không tạo được dữ liệu tạm; chưa chuyển.')}try{await api.alarms.create(alarm,{when:now+ttl})}catch{try{await api.storage.session.remove(key)}catch{throw Error('Không tạo được lịch dọn lựa chọn tạm; dữ liệu có thể còn đến khi Chrome đóng.')}throw Error('Không tạo được lịch dọn lựa chọn tạm; chưa chuyển.') }
 }
 async function expire(api,name){if(typeof name!=='string'||!name.startsWith(alarmPrefix))return;const token=name.slice(alarmPrefix.length);if(!tokenValid(token)||!api.storage?.session?.remove)return;await api.storage.session.remove(prefix+token)}
 async function cleanupExpired(api,now){
  if(!Number.isFinite(now)||now<=0||!api.storage?.session?.get||!api.storage?.session?.remove)return;const records=await api.storage.session.get(null);if(!records||typeof records!=='object'||Array.isArray(records))return;const keys=Object.entries(records).filter(([k,v])=>k.startsWith(prefix)&&(!tokenValid(k.slice(prefix.length))||!v||!Number.isFinite(v.createdAt)||v.createdAt>now||now-v.createdAt>ttl)).map(([k])=>k);if(keys.length)await api.storage.session.remove(keys);
 }
 async function consume(api,token,now,tabs){
  if(!tokenValid(token)||!Number.isFinite(now)||!api.storage?.session?.get||!api.storage?.session?.remove)throw Error('Không thể đọc lựa chọn từ popup.');const key=prefix+token,data=await api.storage.session.get(key),item=data[key];await api.storage.session.remove(key);try{await api.alarms?.clear?.(alarmPrefix+token)}catch{}
  if(!item||!Number.isFinite(item.createdAt)||item.createdAt>now||now-item.createdAt>ttl||!Array.isArray(tabs))throw Error('Lựa chọn popup đã hết hạn hoặc không còn khả dụng.');const plan=validPlan(item.tabs),byId=new Map(tabs.map(t=>[t.id,t])),valid=plan.filter(t=>same(t,byId.get(t.id)));return {ids:valid.map(t=>t.id),tabs:valid,skipped:plan.length-valid.length};
 }
 return {limit,prefix,alarmPrefix,ttl,validPlan,same,preview,sleep,groupChoices,savePreview,saveCopies,transfer,consume,expire,cleanupExpired,tokenValid};
})();
if(typeof module!=='undefined')module.exports=PopupBulk;
