'use strict';
// A conservative count of selected entries, before deduplication or stale checks.
const OpenLimit=(()=>{
 const defaultLimit=20;
 function validate(value){if(value===undefined)return defaultLimit;if(!Number.isInteger(value)||value<1||value>500)throw Error('Ngưỡng cảnh báo mở tab không hợp lệ; hãy sửa trong Cài đặt.');return value}
 async function confirmSelection(api,count,ask=globalThis.confirm){
  if(!Number.isInteger(count)||count<1)throw Error('Số tab được chọn không hợp lệ.');let data;try{data=await api.storage.local.get('openWarningLimit')}catch{throw Error('Không đọc được ngưỡng cảnh báo; chưa mở hoặc đóng tab.')}
  const limit=validate(data.openWarningLimit);if(count<=limit)return true;if(typeof ask!=='function')throw Error('Không thể xác nhận số lượng tab; chưa mở hoặc đóng tab.');return ask(`Bạn đã chọn ${count} tab để mở (ngưỡng cảnh báo: ${limit}). Trang có thể tải ngay và dùng tài nguyên. Tiếp tục?`)===true;
 }
 return {defaultLimit,validate,confirmSelection};
})();
if(typeof module!=='undefined')module.exports=OpenLimit;
