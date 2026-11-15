'use strict';
// Called under the shared mutation lock. Persist the candidate manifest before deletion.
const RetentionAuto=(()=>{
 const day=86400000;
 const defaults=Object.freeze({enabled:false,trash:false,history:false,everyDays:7,maxPerRun:10,nextAt:0,policyVersion:'',state:'idle',runId:'',lastAt:0,manifest:[],deleted:0,unknown:0,notAttempted:0});
 const states=['idle','running','review','done','missed'];
 function validate(v){
  if(v===undefined)return {...defaults,manifest:[]};
  if(!v||typeof v!=='object'||Array.isArray(v)||typeof v.enabled!=='boolean'||typeof v.trash!=='boolean'||typeof v.history!=='boolean'||!Number.isInteger(v.everyDays)||v.everyDays<1||v.everyDays>30||!Number.isInteger(v.maxPerRun)||v.maxPerRun<1||v.maxPerRun>20||!Number.isFinite(v.nextAt)||v.nextAt<0||typeof v.policyVersion!=='string'||v.policyVersion.length>1000||!states.includes(v.state)||typeof v.runId!=='string'||v.runId.length>128||!Number.isFinite(v.lastAt)||v.lastAt<0||!Array.isArray(v.manifest)||v.manifest.length>20||v.manifest.some(x=>!x||typeof x.key!=='string'||x.key.length>300||!['trash','history'].includes(x.kind)||!Number.isFinite(x.at)||x.at<=0||typeof x.name!=='string'||x.name.length>250||!['item','group','workspace','session','history'].includes(x.type)||!Number.isInteger(x.closed)||x.closed<0)||['deleted','unknown','notAttempted'].some(k=>!Number.isInteger(v[k])||v[k]<0||v[k]>20))throw Error('Cấu hình tự dọn không hợp lệ.');
  if(new Set(v.manifest.map(x=>x.key)).size!==v.manifest.length||v.manifest.some(x=>x.kind==='trash'?!x.key.startsWith('tabspace:trash:')||x.type==='history':!x.key.startsWith('tabspace:batch:')||x.type!=='history')||v.deleted+v.unknown+v.notAttempted>v.manifest.length||v.unknown>1||v.state==='done'&&(v.unknown!==0||v.notAttempted!==0))throw Error('Báo cáo tự dọn không hợp lệ.');if(v.enabled&&(!v.trash&&!v.history||!v.policyVersion||!v.nextAt))throw Error('Cấu hình tự dọn chưa đầy đủ.');if(v.state==='running'&&!v.runId)throw Error('Lượt tự dọn không hợp lệ.');return {...v,manifest:v.manifest.map(x=>({key:x.key,kind:x.kind,at:x.at,name:x.name,type:x.type,closed:x.closed}))};
 }
 function describe(raw,policy,paused){
  let c;try{c=validate(raw)}catch{return 'Cấu hình không hợp lệ; tự dọn đã dừng.'}
  if(['running','review'].includes(c.state))return 'Cần kiểm tra lượt tự dọn trước khi bật lại; kết quả có thể chưa rõ.';
  if(!c.enabled)return 'Tự dọn đang tắt.';if(paused!==undefined&&paused!==false)return 'Tự dọn đã bật nhưng tự động hóa toàn cục đang tạm dừng.';
  if(JSON.stringify(policy??null)!==c.policyVersion)return 'Thời hạn đã thay đổi; tự dọn tạm dừng đến khi xác nhận lại.';
  try{const tools=typeof module!=='undefined'?require('./retention.js'):RetentionTools;const p=tools.validate(policy);if(c.trash&&!p.trashEnabled||c.history&&!p.historyEnabled)return 'Thời hạn không còn bật; tự dọn tạm dừng.'}catch{return 'Thời hạn không hợp lệ; tự dọn tạm dừng.'}
  return `Tự dọn đang bật · tối đa ${c.maxPerRun} mục mỗi ${c.everyDays} ngày.`;
 }
 async function tick(api,now,makeId,tools){
  const data=await api.storage.local.get(null);let c,p;try{c=validate(data.retentionAuto);p=tools.validate(data.retentionConfig)}catch{return}if(!c.enabled||['running','review'].includes(c.state)||data.automationPaused!==undefined&&data.automationPaused!==false||!Number.isFinite(now)||now<c.nextAt||JSON.stringify(data.retentionConfig??null)!==c.policyVersion||c.trash&&!p.trashEnabled||c.history&&!p.historyEnabled)return;
  if(now-c.nextAt>=60000){try{await api.storage.local.set({retentionAuto:{...c,state:'missed',nextAt:now+c.everyDays*day,lastAt:now,manifest:[],deleted:0,unknown:0,notAttempted:0,runId:''}})}catch{}return}
  const plan=tools.plan({...data,retentionConfig:{...p,trashEnabled:p.trashEnabled&&c.trash,historyEnabled:p.historyEnabled&&c.history}},now);
  // Unreadable references must not lead to an incomplete, silently recurring history cleanup.
  if(c.history&&plan.historyBlocked){try{await api.storage.local.set({retentionAuto:{...c,state:'review',lastAt:now,manifest:[],deleted:0,unknown:0,notAttempted:0,runId:''}})}catch{}return}
  const chosen=plan.items.slice(0,c.maxPerRun),runId=makeId();if(typeof runId!=='string'||!runId||runId.length>128)return;
  const marker={...c,state:'running',runId,lastAt:now,nextAt:now+c.everyDays*day,manifest:chosen.map(x=>({key:x.key,kind:x.kind,at:x.at,name:x.name.slice(0,250),type:x.type,closed:x.closed})),deleted:0,unknown:0,notAttempted:chosen.length};
  try{await api.storage.local.set({retentionAuto:marker})}catch{return}
  const guard=async()=>{const fresh=await api.storage.local.get(['retentionAuto','retentionConfig','automationPaused']);if(JSON.stringify(fresh.retentionAuto)!==JSON.stringify(marker)||JSON.stringify(fresh.retentionConfig??null)!==c.policyVersion||fresh.automationPaused!==undefined&&fresh.automationPaused!==false)throw Error('Tự dọn đã thay đổi hoặc tạm dừng.')};
  let result={deleted:0,unknown:0,notAttempted:chosen.length,changed:true};try{if(chosen.length)result=await tools.removeSelected(api,chosen,c.policyVersion,now,guard);else{await guard();result={deleted:0,unknown:0,notAttempted:0,changed:false}}}catch{}
  try{const latest=await api.storage.local.get('retentionAuto');if(JSON.stringify(latest.retentionAuto)!==JSON.stringify(marker))return;const needsReview=result.unknown||result.changed;await api.storage.local.set({retentionAuto:{...marker,state:needsReview?'review':'done',deleted:result.deleted,unknown:result.unknown,notAttempted:result.notAttempted}})}catch{}
 }
 return {defaults,validate,describe,tick};
})();
if(typeof module!=='undefined')module.exports=RetentionAuto;
