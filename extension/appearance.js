'use strict';
const Appearance=(()=>{
 const defaults=Object.freeze({theme:'system',density:'comfortable'}),themes=['system','light','dark'],densities=['comfortable','compact'];
 function normalize(value){return {theme:themes.includes(value?.theme)?value.theme:defaults.theme,density:densities.includes(value?.density)?value.density:defaults.density}}
 function validate(value){if(!value||typeof value!=='object'||Array.isArray(value)||!themes.includes(value.theme)||!densities.includes(value.density))throw Error('Cài đặt giao diện trong sao lưu không hợp lệ.');return {theme:value.theme,density:value.density}}
 function apply(value,root,systemDark){const options=normalize(value);root.dataset.theme=options.theme==='system'?(systemDark?'dark':'light'):options.theme;root.dataset.density=options.density;return options}
 return {defaults,normalize,validate,apply};
})();
if(typeof module!=='undefined')module.exports=Appearance;
