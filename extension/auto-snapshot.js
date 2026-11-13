'use strict';
const AutoSnapshot=(()=>{
 function validate(config){if(!config||typeof config!=='object'||typeof config.enabled!=='boolean'||!Number.isInteger(config.intervalHours)||config.intervalHours<1||config.intervalHours>168||!Number.isInteger(config.maxSnapshots)||config.maxSnapshots<1||config.maxSnapshots>50||!Number.isFinite(config.nextAt)||config.nextAt<0)throw Error('Cấu hình snapshot tự động không hợp lệ.');return config}
 async function tick(api,now,makeId){
  const data=await api.storage.local.get(['autoSnapshotConfig','snapshots']);let config;try{config=validate(data.autoSnapshotConfig)}catch{return}if(!config.enabled||now<config.nextAt)return;
  const next={...config,nextAt:now+config.intervalHours*3600000,lastAt:now},list=data.snapshots===undefined?[]:data.snapshots;
  if(!Array.isArray(list)){next.lastStatus='invalid-storage';await api.storage.local.set({autoSnapshotConfig:next});return}
  if(now-config.nextAt>=60000){next.lastStatus='missed';await api.storage.local.set({autoSnapshotConfig:next});return}
  if(list.filter(s=>s?.autoSnapshot===true).length>=config.maxSnapshots){next.lastStatus='limit';await api.storage.local.set({autoSnapshotConfig:next});return}
  let tabs,windows,groups=[],groupReadFailed=false;
  try{[tabs,windows]=await Promise.all([api.tabs.query({}),api.windows.getAll({windowTypes:['normal']})])}catch{next.lastStatus='browser-error';await api.storage.local.set({autoSnapshotConfig:next});return}
  try{groups=await api.tabGroups.query({})}catch{groupReadFailed=true}
  const ids=new Set(windows.filter(w=>!w.incognito&&w.type==='normal').map(w=>w.id)),dashboard=api.runtime.getURL('dashboard.html');const current=tabs.filter(t=>ids.has(t.windowId)&&!t.incognito&&(typeof t.url!=='string'||t.url.split(/[?#]/,1)[0]!==dashboard));
  const tools=typeof module!=='undefined'?require('./snapshots.js'):SnapshotTools;const {snapshot,missingGroups}=tools.capture(current,'Snapshot tự động',now,makeId,groups),count=snapshot.windows.reduce((n,w)=>n+w.length,0);if(!count){next.lastStatus='empty';await api.storage.local.set({autoSnapshotConfig:next});return}
  snapshot.autoSnapshot=true;next.lastStatus=groupReadFailed||missingGroups?'partial-groups':'saved';next.lastCount=count;try{await api.storage.local.set({snapshots:[snapshot,...list],autoSnapshotConfig:next})}catch{next.lastStatus='storage-unknown';try{await api.storage.local.set({autoSnapshotConfig:next})}catch{} }
 }
 return {validate,tick};
})();
if(typeof module!=='undefined')module.exports=AutoSnapshot;
