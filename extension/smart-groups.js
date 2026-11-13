'use strict';
const SmartGroups=(()=>{
 const norm=x=>String(x??'').normalize('NFKC').trim().toLocaleLowerCase('vi');
 function validate(list,makeId,renew=false){
  if(!Array.isArray(list)||list.length>200)throw Error('Danh sách nhóm thông minh không hợp lệ (tối đa 200).');
  const seen=new Set();return list.map(x=>{
   if(!x||typeof x.id!=='string'||!x.id||x.id.length>200||seen.has(x.id)||typeof x.name!=='string'||!x.name.trim()||x.name.length>80||typeof x.text!=='string'||x.text.length>200||typeof x.tag!=='string'||x.tag.length>80||(!x.text.trim()&&!x.tag.trim().replace(/^#+/,'').trim()))throw Error('Nhóm thông minh không hợp lệ: cần tên và ít nhất một điều kiện.');
   seen.add(x.id);return {id:renew?makeId():x.id,name:x.name.trim(),text:x.text.trim(),tag:x.tag.trim().replace(/^#+/,'').trim()};
  });
 }
 function find(rule,groups){
  const text=norm(rule.text),tag=norm(rule.tag.replace(/^#+/,''));
  return groups.flatMap(group=>(Array.isArray(group.items)?group.items:[]).filter(item=>{
   const textOk=!text||[item.title,item.url,item.note,group.name].some(v=>norm(v).includes(text));
   const tagOk=!tag||[...(Array.isArray(item.tags)?item.tags:[]),...(Array.isArray(group.tags)?group.tags:[])].some(v=>norm(v)===tag);
   return textOk&&tagOk;
  }).map(item=>({group,item})));
 }
 return {validate,find};
})();
if(typeof module!=='undefined')module.exports=SmartGroups;
