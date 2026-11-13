'use strict';
const Protection=(()=>{
 function domain(value){
  if(typeof value!=='string')throw Error('Tên miền không hợp lệ.');const raw=value.trim().toLowerCase();
  if(!raw||/[\s/:?#@*\\]/.test(raw))throw Error('Nhập tên miền, không kèm URL, cổng, đường dẫn hoặc dấu *.');
  let host;try{host=new URL('https://'+raw).hostname.replace(/\.$/,'')}catch{throw Error('Tên miền không hợp lệ: '+raw)}
  if(!host||host.length>253||!/^[a-z0-9.-]+$/.test(host)||host.split('.').some(x=>!x||x.length>63||x.startsWith('-')||x.endsWith('-')))throw Error('Tên miền không hợp lệ: '+raw);
  return host;
 }
 function validate(value){if(value===undefined)return [];if(!Array.isArray(value)||value.length>500)throw Error('Danh sách bảo vệ không hợp lệ hoặc vượt 500 tên miền.');return [...new Set(value.map(domain))]}
 function parse(text){return validate(String(text).split(/[,\n]+/).map(x=>x.trim()).filter(Boolean))}
 function matches(url,domains){try{const u=new URL(url);if(!['http:','https:'].includes(u.protocol))return false;const h=u.hostname.toLowerCase().replace(/\.$/,'');return domains.some(d=>h===d||h.endsWith('.'+d))}catch{return false}}
 async function check(api,url){const data=await api.storage.local.get('protectedDomains');return matches(url,validate(data.protectedDomains))}
 return {domain,validate,parse,matches,check};
})();
if(typeof module!=='undefined')module.exports=Protection;
