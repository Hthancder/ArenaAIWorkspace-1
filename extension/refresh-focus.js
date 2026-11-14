'use strict';
// Restore focus only when an unambiguous equivalent still exists after an automatic redraw.
const RefreshFocus=(()=>{
 function render(doc,draw,selector='#contentArea'){
  const root=doc.querySelector(selector),active=doc.activeElement;
  if(!root||!active||!root.contains(active)){draw();return}
  const tag=active.tagName,id=active.id||'',attrs=[...active.attributes].filter(a=>a.name.startsWith('data-')).map(a=>[a.name,a.value]);
  if(!id&&!attrs.length){draw();return}
  draw();if(doc.activeElement!==doc.body&&doc.activeElement!==doc.documentElement&&doc.activeElement!==active)return;
  const options=[...root.querySelectorAll('button,input,select,textarea,a,[tabindex]')].filter(e=>e.tagName===tag&&!e.disabled&&(!id||e.id===id)&&attrs.every(([name,value])=>e.getAttribute(name)===value)&&[...e.attributes].filter(a=>a.name.startsWith('data-')).length===attrs.length&&!e.closest('.hidden'));
  if(options.length===1)options[0].focus({preventScroll:true});
 }
 return {render};
})();
if(typeof module!=='undefined')module.exports=RefreshFocus;
