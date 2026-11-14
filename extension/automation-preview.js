'use strict';
// Pure rehearsal only; never writes storage or invokes a tab mutation.
const AutomationPreview=(()=>{
 function run({presets,groups,tabs,domains,urls,now,graceMinutes,paused,fullscreen},P,Protection){
  if(!Array.isArray(presets)||!Array.isArray(groups)||!Array.isArray(tabs)||!Number.isFinite(now)||!Number.isInteger(graceMinutes)||graceMinutes<1||graceMinutes>10080||typeof paused!=='boolean'||typeof fullscreen!=='boolean')throw Error('Dữ liệu mô phỏng không hợp lệ.');
  const ids=new Set();for(const p of presets){
   if(!p||typeof p.id!=='string'||!p.id||ids.has(p.id)||typeof p.name!=='string'||typeof p.groupId!=='string'||typeof p.subdomains!=='boolean')throw Error('Preset mô phỏng không hợp lệ.');ids.add(p.id);
   for(const [key,normalizer] of [['domains',P.normalizeDomain],['paths',x=>P.normalizeUrl(x,true)],['exactUrls',P.normalizeUrl],['excludeDomains',P.normalizeDomain],['excludePaths',x=>P.normalizeUrl(x,true)],['excludeUrls',P.normalizeUrl]]){const arr=p[key]??[];if(!Array.isArray(arr)||arr.length>1000||arr.some(x=>typeof x!=='string'||normalizer(x)!==x))throw Error('Quy tắc preset không hợp lệ; hãy sửa trước khi mô phỏng.')}
   if(!(p.domains||[]).length&&!(p.paths||[]).length&&!(p.exactUrls||[]).length)throw Error('Preset không có quy tắc bao gồm.');P.priority(p.priority);P.maxPerRun(p.maxPerRun);
  }
  const protectedDomains=Protection.validate(domains),protectedUrls=Protection.validateUrls(urls),counts=new Map(),rows=[];
  const sorted=[...tabs].sort((a,b)=>(a.windowId??0)-(b.windowId??0)||(a.index??0)-(b.index??0)||(a.id??0)-(b.id??0));
  for(const tab of sorted){if(!tab||tab.incognito||typeof tab.url!=='string'||!/^https?:\/\//i.test(tab.url))continue;const rank=P.rank(tab.url,presets);if(!rank.entries.length)continue;
   const matches=rank.entries.map(e=>e.preset.name);let reason='',winner=null;
   if(paused)reason='Tự động hóa toàn cục đang tạm dừng';else if(fullscreen)reason='Có thể đang toàn màn hình hoặc không đọc được trạng thái';else if(!Number.isInteger(tab.id)||!Number.isInteger(tab.windowId))reason='Không xác định được tab hoặc cửa sổ';else if(tab.pendingUrl&&tab.pendingUrl!==tab.url)reason='Tab đang chuyển URL';else if(P.reason(tab))reason=P.reason(tab);else if(Protection.matches(tab.url,protectedDomains)||Protection.matchesUrl(tab.url,protectedUrls))reason='Website hoặc URL được bảo vệ';else if(!Number.isFinite(tab.lastAccessed)||tab.lastAccessed<=0||tab.lastAccessed>now)reason='Không xác định được thời gian truy cập';else if(now-tab.lastAccessed<graceMinutes*60000)reason='Vừa truy cập trong thời gian miễn xử lý';else if(rank.leaders.length!==1)reason='Xung đột: các preset đồng mức và ưu tiên';else{
    winner=rank.leaders[0].preset;const group=groups.find(g=>g.id===winner.groupId);if(!group||!Array.isArray(group.items))reason='Nhóm đích không còn khả dụng';else {const count=counts.get(winner.id)||0,limit=P.maxPerRun(winner.maxPerRun);if(limit&&count>=limit)reason='Đã đạt giới hạn preset trong lượt mô phỏng';else counts.set(winner.id,count+1)}
   }
   rows.push({tab,matches,winner:winner?.name||'',group:winner?groups.find(g=>g.id===winner.groupId)?.name||'':'',reason,eligible:!reason});
  }
  return rows;
 }
 return {run};
})();
if(typeof module!=='undefined')module.exports=AutomationPreview;
