'use strict';
// All extension UI writers use the same origin-scoped Web Lock.
const MutationLock=(()=>{
 async function run(work,locks=globalThis.navigator?.locks){
  if(!locks||typeof locks.request!=='function')throw Error('Chrome không hỗ trợ khóa dữ liệu; thao tác đã dừng để tránh ghi đè.');
  return locks.request('tabspace:data-mutation',{ifAvailable:true},async lock=>{
   if(!lock)throw Error('Tabspace đang xử lý ở cửa sổ khác. Hãy đợi rồi thử lại.');
   return work();
  });
 }
 return {run};
})();
if(typeof module!=='undefined')module.exports=MutationLock;
