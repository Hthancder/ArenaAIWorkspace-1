'use strict';
const SelectionTools=(()=>{
 function range(visible,anchor,target){const to=visible.indexOf(target);if(to<0)return [];const from=anchor==null?-1:visible.indexOf(anchor);if(from<0)return [target];return visible.slice(Math.min(from,to),Math.max(from,to)+1)}
 return {range};
})();
if(typeof module!=='undefined')module.exports=SelectionTools;
