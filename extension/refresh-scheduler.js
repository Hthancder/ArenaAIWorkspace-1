'use strict';
// Event refreshes are coalesced, bounded in latency and never overlap each other.
// Explicit user operations can still request an immediate, independently revalidated load.
const RefreshScheduler=(()=>{
 function create(work,onError=()=>{},options={}){
  const delay=options.delay??120,maxWait=options.maxWait??700,now=options.now??Date.now,set=options.setTimeout??setTimeout,clear=options.clearTimeout??clearTimeout;
  if(typeof work!=='function'||typeof onError!=='function'||!Number.isFinite(delay)||delay<0||!Number.isFinite(maxWait)||maxWait<delay)throw Error('Invalid refresh scheduler configuration');
  let first=null,timer=null,running=false,pending=false;
  function arm(){if(running||!pending)return;if(timer!==null)clear(timer);const wait=Math.max(0,Math.min(delay,first+maxWait-now()));timer=set(fire,wait)}
  function request(){if(first===null)first=now();pending=true;arm()}
  function fire(){timer=null;if(running||!pending)return;running=true;pending=false;first=null;Promise.resolve().then(work).catch(e=>{try{onError(e)}catch{}}).finally(()=>{running=false;if(pending)arm()})}
  return {request};
 }
 return {create};
})();
if(typeof module!=='undefined')module.exports=RefreshScheduler;
