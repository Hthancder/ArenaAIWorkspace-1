'use strict';
const TimeTools=(()=>{
 function format(value,now=new Date()){
  if(value===null||value===undefined||value==='')return null;
  const d=new Date(value);if(!Number.isFinite(d.getTime()))return null;
  const time=d.toLocaleTimeString('vi-VN',{hour:'2-digit',minute:'2-digit',hour12:false});
  const today=new Date(now.getFullYear(),now.getMonth(),now.getDate());
  const yesterday=new Date(now.getFullYear(),now.getMonth(),now.getDate()-1);
  const day=new Date(d.getFullYear(),d.getMonth(),d.getDate());
  let short;
  if(day.getTime()===today.getTime())short=time;
  else if(day.getTime()===yesterday.getTime())short='Hôm qua · '+time;
  else short=d.toLocaleDateString('vi-VN',{day:'numeric',month:'short',...(d.getFullYear()!==now.getFullYear()?{year:'numeric'}:{})})+' · '+time;
  return {short,full:d.toLocaleString('vi-VN',{dateStyle:'full',timeStyle:'long'}),iso:d.toISOString()};
 }
 return {format};
})();
if(typeof module!=='undefined')module.exports=TimeTools;
