'use strict';
// Defaults are just initial form choices; each operation still requires confirmation.
const OpenPreferences=(()=>{
 const defaults=Object.freeze({destination:'current',savedSkipOpen:false,savedSkipDuplicates:false,sessionSkipOpen:false,sessionSkipDuplicates:false,sessionGroups:true});
 function validate(value){if(value===undefined)return {...defaults};if(!value||typeof value!=='object'||Array.isArray(value)||!['current','new'].includes(value.destination)||['savedSkipOpen','savedSkipDuplicates','sessionSkipOpen','sessionSkipDuplicates','sessionGroups'].some(k=>typeof value[k]!=='boolean'))throw Error('Thiết lập mở tab không hợp lệ.');return {destination:value.destination,savedSkipOpen:value.savedSkipOpen,savedSkipDuplicates:value.savedSkipDuplicates,sessionSkipOpen:value.sessionSkipOpen,sessionSkipDuplicates:value.sessionSkipDuplicates,sessionGroups:value.sessionGroups}}
 return {defaults,validate};
})();
if(typeof module!=='undefined')module.exports=OpenPreferences;
