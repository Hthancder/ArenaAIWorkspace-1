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
 function validateUrls(value){
  if(value===undefined)return [];if(!Array.isArray(value)||value.length>500)throw Error('Danh sách URL bảo vệ không hợp lệ hoặc vượt 500 URL.');
  return [...new Set(value.map(raw=>{if(typeof raw!=='string'||raw.length>4096)throw Error('URL bảo vệ không hợp lệ.');let u;try{u=new URL(raw.trim())}catch{throw Error('URL bảo vệ không hợp lệ.')}if(!['http:','https:'].includes(u.protocol)||u.username||u.password)throw Error('Chỉ bảo vệ URL http/https không chứa thông tin đăng nhập.');return u.href}))];
 }
 function parseUrls(text){return validateUrls(String(text??'').split(/\n+/).map(s=>s.trim()).filter(Boolean))}
 function matchesUrl(url,protectedUrls){try{const u=new URL(url);return ['http:','https:'].includes(u.protocol)&&protectedUrls.includes(u.href)}catch{return false}}
 async function check(api,url){const data=await api.storage.local.get(['protectedDomains','protectedUrls']);const domains=validate(data.protectedDomains),urls=validateUrls(data.protectedUrls);return matches(url,domains)||matchesUrl(url,urls)}
 return {domain,validate,parse,matches,validateUrls,parseUrls,matchesUrl,check};
})();
if(typeof module!=='undefined')module.exports=Protection;
