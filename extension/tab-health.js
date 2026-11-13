'use strict';
const TabHealth=(()=>{
 const day=86400000;
 function classify(tabs,days,now){
  if(!Number.isInteger(days)||days<1||days>365||!Number.isFinite(now))throw Error('Ngưỡng thời gian không hợp lệ.');
  const old=[],unknown=[];
  for(const tab of tabs){if(tab.incognito||typeof tab.url!=='string'||!/^https?:\/\//i.test(tab.url))continue;
   const at=tab.lastAccessed;
   if(typeof at!=='number'||!Number.isFinite(at)||at<=0||at>now){unknown.push(tab);continue}
   if(now-at>=days*day)old.push(tab);
  }
  old.sort((a,b)=>a.lastAccessed-b.lastAccessed);return {old,unknown};
 }
 return {classify};
})();
if(typeof module!=='undefined')module.exports=TabHealth;
