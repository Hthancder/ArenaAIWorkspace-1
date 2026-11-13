'use strict';
const RecoveryPoint=(()=>{
 function validate(value){if(value===undefined)return {enabled:false,maxPoints:10};if(!value||typeof value!=='object'||typeof value.enabled!=='boolean'||!Number.isInteger(value.maxPoints)||value.maxPoints<1||value.maxPoints>50)throw Error('Cài đặt điểm khôi phục không hợp lệ; chưa đóng tab.');return value}
 async function captureIfEnabled(api,selected,now,makeId){
  const data=await api.storage.local.get(['recoverySettings','snapshots']),settings=validate(data.recoverySettings);if(!settings.enabled)return false;
  const snapshots=data.snapshots===undefined?[]:data.snapshots;if(!Array.isArray(snapshots))throw Error('Dữ liệu phiên không hợp lệ; chưa đóng tab.');if(snapshots.filter(s=>s?.recoveryPoint===true).length>=settings.maxPoints)throw Error('Đã đạt giới hạn điểm khôi phục; xóa bớt hoặc tắt thiết lập trước khi đóng tab.');
  let tabs,windows,groups;try{[tabs,windows,groups]=await Promise.all([api.tabs.query({}),api.windows.getAll({windowTypes:['normal','popup']}),api.tabGroups.query({})])}catch{throw Error('Không đọc được tab, cửa sổ hoặc nhóm Chrome để tạo điểm khôi phục; chưa đóng tab.')}
  const allowed=new Set(windows.filter(w=>!w.incognito&&['normal','popup'].includes(w.type)).map(w=>w.id)),dashboard=api.runtime.getURL('dashboard.html');const current=tabs.filter(t=>!t.incognito&&allowed.has(t.windowId)&&typeof t.url==='string'&&/^https?:\/\//i.test(t.url)&&t.url.split(/[?#]/,1)[0]!==dashboard);
  const available=new Map(current.map(t=>[t.id,t]));if(selected.some(e=>{const t=available.get(e.tabId);return !t||t.url!==e.url||t.windowId!==e.windowId}))throw Error('Tab được chọn đã thay đổi hoặc không có trong điểm khôi phục; chưa đóng tab.');
  const tools=typeof module!=='undefined'?require('./snapshots.js'):SnapshotTools,{snapshot,missingGroups}=tools.capture(current,'Trước lượt lưu & đóng',now,makeId,groups);if(!snapshot.windows.some(w=>w.length)||missingGroups)throw Error('Không tạo được điểm khôi phục đầy đủ về URL hoặc nhóm Chrome; chưa đóng tab.');snapshot.recoveryPoint=true;
  try{await api.storage.local.set({snapshots:[snapshot,...snapshots]})}catch{throw Error('Không xác nhận được việc tạo điểm khôi phục; kiểm tra danh sách phiên trước khi thử lại. Chưa đóng tab.')}
  return true;
 }
 return {validate,captureIfEnabled};
})();
if(typeof module!=='undefined')module.exports=RecoveryPoint;
