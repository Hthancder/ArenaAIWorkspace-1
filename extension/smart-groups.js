'use strict';
const SmartGroups=(()=>{
 const day=86400000,norm=x=>String(x??'').normalize('NFKC').trim().toLocaleLowerCase('vi');
 function domainValue(raw){if(typeof raw!=='string'||raw.length>253||/[\s\/@\\?#:]/.test(raw))throw Error('Tên miền không hợp lệ; chỉ nhập tên miền, không gồm giao thức, cổng hoặc đường dẫn.');if(!raw)return '';try{const u=new URL('https://'+raw),host=u.hostname.toLowerCase().replace(/\.$/,'');if(!host||u.username||u.password||u.port||u.pathname!=='/'||u.search||u.hash)throw Error();return host}catch{throw Error('Tên miền không hợp lệ; chỉ nhập tên miền, không gồm giao thức, cổng hoặc đường dẫn.')}}
 function age(v){if(v===undefined||v===null)return null;if(!Number.isInteger(v)||v<0||v>3650)throw Error('Số ngày cần từ 0 đến 3650.');return v}
 function validate(list,makeId,renew=false){
  if(!Array.isArray(list)||list.length>200)throw Error('Danh sách nhóm thông minh không hợp lệ (tối đa 200).');
  const seen=new Set();return list.map(x=>{
   if(!x||typeof x.id!=='string'||!x.id||x.id.length>200||seen.has(x.id)||typeof x.name!=='string'||!x.name.trim()||x.name.length>80||typeof x.text!=='string'||x.text.length>200||typeof x.tag!=='string'||x.tag.length>80)throw Error('Nhóm thông minh không hợp lệ.');
   const domain=domainValue(x.domain===undefined?'':typeof x.domain==='string'?x.domain.trim():x.domain),mode=x.domainMode??'exact',min=age(x.minAgeDays),max=age(x.maxAgeDays);if(!['exact','subdomains'].includes(mode)||min!==null&&max!==null&&min>max)throw Error('Phạm vi tên miền hoặc số ngày không hợp lệ.');if(!x.text.trim()&&!x.tag.trim().replace(/^#+/,'').trim()&&!domain&&min===null&&max===null)throw Error('Nhóm thông minh cần ít nhất một điều kiện.');
   seen.add(x.id);return {id:renew?makeId():x.id,name:x.name.trim(),text:x.text.trim(),tag:x.tag.trim().replace(/^#+/,'').trim(),...(domain?{domain,domainMode:mode}:{}),...(min!==null?{minAgeDays:min}:{}),...(max!==null?{maxAgeDays:max}:{})};
  });
 }
 function find(rule,groups,now=Date.now()){
  const text=norm(rule.text),tag=norm((rule.tag||'').replace(/^#+/,'')),domain=rule.domain||'',mode=rule.domainMode||'exact',min=rule.minAgeDays??null,max=rule.maxAgeDays??null;
  return groups.flatMap(group=>(Array.isArray(group.items)?group.items:[]).filter(item=>{
   const textOk=!text||[item.title,item.url,item.note,group.name].some(v=>norm(v).includes(text));const tagOk=!tag||[...(Array.isArray(item.tags)?item.tags:[]),...(Array.isArray(group.tags)?group.tags:[])].some(v=>norm(v)===tag);
   let domainOk=!domain;if(domain){try{const u=new URL(item.url),host=u.hostname.toLowerCase().replace(/\.$/,'');domainOk=['http:','https:'].includes(u.protocol)&&(host===domain||mode==='subdomains'&&host.endsWith('.'+domain))}catch{domainOk=false}}
   let ageOk=true;if(min!==null||max!==null){const at=item.createdAt,elapsed=now-at;ageOk=Number.isFinite(now)&&Number.isFinite(at)&&at>0&&elapsed>=0&&(min===null||elapsed>=min*day)&&(max===null||elapsed<=max*day)}return textOk&&tagOk&&domainOk&&ageOk;
  }).map(item=>({group,item})));
 }
 return {validate,find,domainValue};
})();
if(typeof module!=='undefined')module.exports=SmartGroups;
