'use strict';
const AutoStatus=(()=>{
 function describe(configValue,pausedValue,presets,runsValue,AutoClose,groups){
  let config;try{config=AutoClose.validate(configValue)}catch{return {show:true,kind:'error',text:'Cấu hình tự động đóng không hợp lệ; tính năng đã dừng.'}}
  const paused=pausedValue!==undefined&&pausedValue!==false;
  if(runsValue!==undefined&&!Array.isArray(runsValue))return {show:true,kind:'error',text:'Không đọc được báo cáo tự động đóng; tính năng đã dừng.'};
  const runs=runsValue||[],blocked=runs.some(r=>!r||r.status!=='complete'),full=runs.length>=AutoClose.limit;
  if(blocked)return {show:true,kind:'warning',text:'Tự động đóng đang dừng: có lượt cần kiểm tra trước khi tiếp tục.'};
  if(full)return {show:true,kind:'warning',text:'Tự động đóng đang dừng: danh sách lượt đã đầy.'};
  if(!config.enabled)return {show:false,kind:'off',text:'Tự động đóng đang tắt.'};
  if(paused)return {show:true,kind:'paused',text:'Tự động đóng đã bật nhưng tự động hóa toàn cục đang tạm dừng.'};
  if(!Array.isArray(presets)||!config.presetIds.length||config.presetIds.some((id,i)=>JSON.stringify(presets.find(p=>p?.id===id))!==config.versions[i]))return {show:true,kind:'warning',text:'Preset tự động đã thay đổi hoặc bị xóa; hãy xem lại và xác nhận cấu hình.'};
  if(Array.isArray(groups)&&config.presetIds.some(id=>{const p=presets.find(x=>x?.id===id);return !p?.schedule?.enabled||!Number.isInteger(p.maxPerRun)||p.maxPerRun<1||p.maxPerRun>100||!groups.some(g=>g?.id===p.groupId&&Array.isArray(g.items))}))return {show:true,kind:'warning',text:'Preset tự động thiếu lịch, nhóm đích hoặc giới hạn hợp lệ; hãy kiểm tra.'};
  return {show:true,kind:'active',text:'Tự động đóng theo lịch đang bật; tab đủ điều kiện có thể đóng mà không hỏi lại.'};
 }
 return {describe};
})();
if(typeof module!=='undefined')module.exports=AutoStatus;
