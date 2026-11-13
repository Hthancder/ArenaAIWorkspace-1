'use strict';
const SnapshotCompare=(()=>{
 function compare(before,after){
  function collect(snapshot){if(!snapshot||!Array.isArray(snapshot.windows))throw Error('Phiên không hợp lệ.');const map=new Map();let count=0;
   snapshot.windows.forEach((window,i)=>{if(!Array.isArray(window))throw Error('Cửa sổ trong phiên không hợp lệ.');window.forEach((tab,j)=>{if(!tab||typeof tab.url!=='string')throw Error('URL trong phiên không hợp lệ.');if(!map.has(tab.url))map.set(tab.url,[]);map.get(tab.url).push({window:i+1,position:j+1,title:typeof tab.title==='string'?tab.title:tab.url,pinned:!!tab.pinned});count++})});return {map,count};
  }
  const a=collect(before),b=collect(after),urls=new Set([...a.map.keys(),...b.map.keys()]);let added=0,removed=0,shared=0;const changed=[],unchanged=[];
  for(const url of urls){const left=a.map.get(url)||[],right=b.map.get(url)||[],difference=right.length-left.length;added+=Math.max(0,difference);removed+=Math.max(0,-difference);shared+=Math.min(left.length,right.length);const entry={url,before:left,after:right,difference};(difference?changed:unchanged).push(entry)}
  return {beforeTotal:a.count,afterTotal:b.count,added,removed,shared,changed,unchanged};
 }
 return {compare};
})();
if(typeof module!=='undefined')module.exports=SnapshotCompare;
