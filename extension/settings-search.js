'use strict';
// Search presentation only; never mutates a setting or the underlying data.
const SettingsSearch=(()=>{
 const categories=['all','common','automation','notifications','protection','data'];
 function normalize(value){return String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/đ/gi,c=>c==='Đ'?'D':'d').toLocaleLowerCase('vi').trim().replace(/\s+/g,' ')}
 function matches(text,groups,query,category){if(!categories.includes(category))return false;const selected=category==='all'||String(groups||'').split(/\s+/).includes(category),needle=normalize(query);return selected&&(!needle||normalize(text).includes(needle))}
 return {categories,normalize,matches};
})();
if(typeof module!=='undefined')module.exports=SettingsSearch;
