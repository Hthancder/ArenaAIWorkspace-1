'use strict';
const Appearance=(()=>{
 const defaults=Object.freeze({theme:'system',density:'comfortable',motion:'system'}),themes=['system','light','dark'],densities=['comfortable','compact'],motions=['system','full','reduce'];
 function normalize(value){return {theme:themes.includes(value?.theme)?value.theme:defaults.theme,density:densities.includes(value?.density)?value.density:defaults.density,motion:motions.includes(value?.motion)?value.motion:defaults.motion}}
 // Older backups omit motion; they retain the safe system setting.
 function validate(value){if(!value||typeof value!=='object'||Array.isArray(value)||!themes.includes(value.theme)||!densities.includes(value.density)||value.motion!==undefined&&!motions.includes(value.motion))throw Error('Cài đặt giao diện trong sao lưu không hợp lệ.');return {theme:value.theme,density:value.density,motion:value.motion??defaults.motion}}
 function apply(value,root,systemDark){const options=normalize(value);root.dataset.theme=options.theme==='system'?(systemDark?'dark':'light'):options.theme;root.dataset.density=options.density;root.dataset.motion=options.motion;return options}
 return {defaults,normalize,validate,apply};
})();
if(typeof module!=='undefined')module.exports=Appearance;
