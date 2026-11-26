'use strict';
// Fast explicit user actions. Never infer per-tab resource use or silently truncate.
(()=>{
 const q=s=>document.querySelector(s),result=q('#quickResult');let busy=false,settingsUncertain=false,targets=[];
 const status=s=>{result.textContent=s};
 async function loadTargets(){
  const data=await chrome.storage.local.get(['groups','presets','quickActions']),groups=PopupBulk.groupChoices(data.groups),presets=Array.isArray(data.presets)?data.presets:[];targets=groups.map(g=>({kind:'group',target:g,label:g.name}));targets.push({kind:'new',label:'＋ Tạo nhóm mới…'});
  for(const p of presets){if(!p||typeof p.id!=='string'||typeof p.name!=='string'||typeof p.groupId!=='string')continue;const group=groups.find(g=>g.id===p.groupId&&g.version!==null);if(group)targets.push({kind:'preset',target:group,presetId:p.id,presetVersion:JSON.stringify([p.id,p.name,p.groupId]),label:`Preset ${p.name} → ${group.name}`})}
  const sel=q('#quickTarget');sel.replaceChildren();targets.forEach((t,i)=>{const o=document.createElement('option');o.value=String(i);o.textContent=t.label;sel.append(o)});sel.value='0';q('#quickNameLabel').classList.toggle('hidden',targets[Number(sel.value)]?.kind!=='new');const settings=data.quickActions||{};q('#quickSaveDirect').checked=settings.saveDirect===true;q('#quickSleepDirect').checked=settings.sleepDirect===true;
 }
 async function updateSetting(field,check){
  if(busy)return;if(check.checked&&!confirm(field==='sleepDirect'?'Cho nghỉ ngay không hỏi lại? Trang có thể tải lại và mất nội dung chưa lưu; các bảo vệ vẫn áp dụng.':'Lưu bản sao ngay không hỏi lại? Hãy kiểm tra phạm vi và đích trước khi bấm.')){check.checked=false;return}
  busy=true;check.disabled=true;try{await MutationLock.run(async()=>{const d=await chrome.storage.local.get('quickActions'),old=d.quickActions&&typeof d.quickActions==='object'?d.quickActions:{};await chrome.storage.local.set({quickActions:{saveDirect:old.saveDirect===true,sleepDirect:old.sleepDirect===true,[field]:check.checked}})});status('Đã lưu tùy chọn.')}catch{settingsUncertain=true;status('Không xác nhận được thiết lập; đóng và mở lại popup để kiểm tra trước khi thực hiện.');check.checked=false}finally{busy=false;check.disabled=false}
 }
 async function run(kind){
  if(busy)return;if(settingsUncertain){status('Thiết lập chưa xác định; đóng và mở lại popup trước khi thực hiện.');return}busy=true;q('#quickSave').disabled=q('#quickSleep').disabled=true;
  try{
   const captured=currentTab;if(!captured||captured.incognito||!Number.isSafeInteger(captured.id)||!Number.isSafeInteger(captured.windowId))throw Error('Không xác định được tab hiện tại; hãy mở lại popup từ cửa sổ cần xử lý.');
   const [active,all,data]=await Promise.all([chrome.tabs.query({active:true,currentWindow:true}),chrome.tabs.query({}),chrome.storage.local.get(['groups','presets','quickActions'])]);const origin=active[0];if(!origin||origin.id!==captured.id||origin.windowId!==captured.windowId||origin.incognito!==false||origin.url!==captured.url)throw Error('Tab hiện tại đã thay đổi; hãy mở lại popup.');
   const scope=q('#quickScope').value;if(!['window','all'].includes(scope))throw Error('Phạm vi không hợp lệ.');const include=kind==='sleep'?'others':q('#quickInclude').value;if(!['others','all'].includes(include))throw Error('Nguồn không hợp lệ.');
   const eligible=all.filter(t=>t.incognito===false&&(scope==='all'||t.windowId===origin.windowId)&&(include==='all'||t.id!==origin.id));const tabs=eligible.filter(t=>t.url!==dashboardUrl&&/^https?:\/\//i.test(t.url||'')&&(!t.pendingUrl||t.pendingUrl===t.url)&&Number.isSafeInteger(t.id)&&Number.isSafeInteger(t.windowId)&&t.url.length<=10000);const omitted=eligible.length-tabs.length;
   if(!tabs.length)throw Error('Không có tab web phù hợp trong phạm vi.');if(tabs.length>PopupBulk.limit)throw Error(`Có ${tabs.length} tab phù hợp; tối đa ${PopupBulk.limit} tab/lượt. Hãy chọn từng nhóm tab trong danh sách hoặc trang quản lý; không có tab nào bị xử lý.`);
   const plan=PopupBulk.validPlan(tabs),scopeText=scope==='all'?'mọi cửa sổ thường':'cửa sổ hiện tại',settings=data.quickActions||{};
   if(kind==='save'){
    const selection=targets[Number(q('#quickTarget').value)];if(!selection)throw Error('Hãy chọn đích lưu.');let target;if(selection.kind==='new'){const name=q('#quickName').value.trim();if(!name||name.length>80)throw Error('Nhập tên nhóm từ 1 đến 80 ký tự.');target={id:'__new__',newName:name};}else target=selection.target;
    if(settings.saveDirect!==true&&!confirm(`Lưu bản sao ${plan.length} tab từ ${scopeText} vào ${selection.kind==='new'?'nhóm mới '+target.newName:selection.label}? Không đóng hay cho nghỉ tab. ${omitted} tab không hỗ trợ bị bỏ qua.`))return;
    const out=await MutationLock.run(async()=>{if(selection.kind==='preset'){const latest=await chrome.storage.local.get('presets'),p=Array.isArray(latest.presets)&&latest.presets.find(x=>x.id===selection.presetId);if(!p||JSON.stringify([p.id,p.name,p.groupId])!==selection.presetVersion)throw Error('Preset đã thay đổi; mở lại popup.')}return PopupBulk.saveCopies(chrome,plan,target,()=>crypto.randomUUID(),Date.now())});status(`Đã lưu ${out.saved.length} bản sao; bỏ qua ${out.skipped.length+omitted} tab. Không đóng hay cho nghỉ tab.`);try{await refresh();await loadTargets()}catch{status(`Đã lưu ${out.saved.length} bản sao; không thể làm mới, hãy kiểm tra nhóm đích.`)}
   }else{
    if(settings.sleepDirect!==true&&!confirm(`Cho nghỉ các tab khác trong ${scopeText}? ${plan.length} tab web sẽ được kiểm tra; ${omitted} tab không hỗ trợ bị bỏ qua. Tab đang xem, ghim, phát âm thanh và website được bảo vệ sẽ được giữ. Trang có thể tải lại và mất dữ liệu chưa lưu.`))return;
    const out=await MutationLock.run(()=>PopupBulk.sleep(chrome,plan,Protection,DiscardTools));const counts=key=>out.filter(x=>x.status===key).length;status(`Đã nghỉ ${counts('discarded')} · bỏ qua/bảo vệ ${counts('skipped')+counts('protected')+omitted} · chưa thử ${counts('notAttempted')} · không rõ/lỗi ${counts('unknown')+counts('unavailable')}. Kiểm tra Chrome trước khi thử lại.`);try{await refresh()}catch{}
   }
  }catch(e){status('Không thể thực hiện: '+e.message+' Hãy kiểm tra kết quả trước khi thử lại.')}finally{busy=false;q('#quickSave').disabled=q('#quickSleep').disabled=false}
 }
 q('#bulkQuick').addEventListener('toggle',()=>{if(q('#bulkQuick').open)loadTargets().catch(e=>status('Không tải được đích: '+e.message))});q('#quickTarget').addEventListener('change',()=>q('#quickNameLabel').classList.toggle('hidden',targets[Number(q('#quickTarget').value)]?.kind!=='new'));q('#quickSaveDirect').addEventListener('change',e=>void updateSetting('saveDirect',e.target));q('#quickSleepDirect').addEventListener('change',e=>void updateSetting('sleepDirect',e.target));q('#quickSave').addEventListener('click',()=>void run('save'));q('#quickSleep').addEventListener('click',()=>void run('sleep'));
})();
