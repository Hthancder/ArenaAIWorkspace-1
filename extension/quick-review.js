'use strict';
// One review at a time; labels use textContent so tab titles are never markup.
const QuickReview=(()=>{
 function show(doc,description,rows){
  return new Promise(resolve=>{
   const get=s=>doc.querySelector(s),dialog=get('#quickReview'),list=get('#quickReviewList'),status=get('#quickReviewStatus'),confirm=get('#quickReviewConfirm'),boxes=[];
   get('#quickReviewDescription').textContent=description;list.replaceChildren();
   for(const row of rows){const label=doc.createElement('label'),box=doc.createElement('input'),text=doc.createElement('span'),detail=doc.createElement('small');box.type='checkbox';box.checked=!row.reason;box.disabled=!!row.reason;text.textContent=row.tab.title||row.tab.url;detail.textContent=row.reason||row.tab.url;text.append(detail);label.append(box,text);list.append(label);boxes.push(box)}
   const update=()=>{const n=boxes.filter(b=>b.checked&&!b.disabled).length;status.textContent=`Đã chọn ${n}/${rows.length} tab. Tab không đủ điều kiện được giữ lại.`;confirm.disabled=n===0};
   const finish=chosen=>{dialog.oncancel=null;dialog.close();resolve(chosen)};
   for(const box of boxes)box.onchange=update;get('#quickReviewAll').onclick=()=>{for(const b of boxes)if(!b.disabled)b.checked=true;update()};get('#quickReviewNone').onclick=()=>{for(const b of boxes)b.checked=false;update()};get('#quickReviewCancel').onclick=()=>finish(null);confirm.onclick=()=>finish(rows.filter((_,i)=>boxes[i].checked&&!boxes[i].disabled).map(r=>r.tab));dialog.oncancel=e=>{e.preventDefault();finish(null)};update();dialog.showModal();
  });
 }
 return {show};
})();
if(typeof module!=='undefined')module.exports=QuickReview;
