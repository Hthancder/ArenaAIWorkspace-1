'use strict';
// Read state is separate from dismissing reminders or deleting reports.
const NoticeState=(()=>{
 const limit=5000;
 function reminderId(id,at){if(typeof id!=='string'||!id.length||id.length>256||!Number.isFinite(at)||at<=0)return null;const key=JSON.stringify(['reminder',id,at]);return key.length<=400?key:null}
 function resultId(id){if(typeof id!=='string'||!id.length||id.length>256)return null;const key=JSON.stringify(['result',id]);return key.length<=400?key:null}
 function active(data){const events=[];if(Array.isArray(data.presets)&&data.reminderState&&typeof data.reminderState==='object'&&!Array.isArray(data.reminderState))for(const p of data.presets){if(!p?.schedule?.enabled)continue;const at=data.reminderState[p.id]?.pendingAt,id=reminderId(p.id,at);if(id)events.push({id,kind:'reminder',sourceId:p.id,at})}if(Array.isArray(data.autoCloseRuns))for(const r of data.autoCloseRuns){if(!r||!['complete','blocked','uncertain'].includes(r.status))continue;const id=resultId(r.id);if(id)events.push({id,kind:'result',sourceId:r.id,at:r.createdAt})}return events}
 function read(value){if(value===undefined)return new Set();if(!Array.isArray(value)||value.length>limit||value.some(x=>typeof x!=='string'||x.length>400)||new Set(value).size!==value.length)throw Error('Trạng thái đã đọc không hợp lệ.');return new Set(value)}
 function isRead(value,id){if(!id)return false;return read(value).has(id)}
 function update(data,id,checked){const events=active(data),current=new Set(events.map(x=>x.id));if(!current.has(id))throw Error('Thông báo đã thay đổi hoặc không còn tồn tại.');const readIds=read(data.noticeRead);for(const key of readIds)if(!current.has(key))readIds.delete(key);if(checked)readIds.add(id);else readIds.delete(id);if(readIds.size>limit)throw Error('Đã đạt giới hạn trạng thái đã đọc; hãy xử lý bớt lời nhắc hoặc báo cáo cũ.');return [...readIds]}
 function saveFields(data,next){const seen=read(next),events=active(data),out={noticeRead:next};if(!events.some(e=>e.kind==='reminder'&&!seen.has(e.id)))out.quietReminderPending=false;if(Array.isArray(data.autoCloseNoticePending?.ids)){const valid=new Set(events.filter(e=>e.kind==='result'&&!seen.has(e.id)).map(e=>e.sourceId));const ids=data.autoCloseNoticePending.ids.filter(id=>valid.has(id));out.autoCloseNoticePending=ids.length?{ids}:null}return out}
 return {limit,reminderId,resultId,active,read,isRead,update,saveFields};
})();
if(typeof module!=='undefined')module.exports=NoticeState;
