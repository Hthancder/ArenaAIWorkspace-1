'use strict';
const SnapshotCompare=(()=>{
 function compare(before,after){
  function collect(snapshot){if(!snapshot||!Array.isArray(snapshot.windows))throw Error('Phiên không hợp lệ.');const map=new Map();let count=0;
   snapshot.windows.forEach((window,i)=>{if(!Array.isArray(window))throw Error('Cửa sổ trong phiên không hợp lệ.');window.forEach((tab,j)=>{if(!tab||typeof tab.url!=='string')throw Error('URL trong phiên không hợp lệ.');if(!map.has(tab.url))map.set(tab.url,[]);map.get(tab.url).push({window:i+1,position:j+1,title:typeof tab.title==='string'?tab.title:tab.url,pinned:!!tab.pinned,chromeGroup:tab.chromeGroup&&typeof tab.chromeGroup==='object'?{title:typeof tab.chromeGroup.title==='string'?tab.chromeGroup.title:'',color:typeof tab.chromeGroup.color==='string'?tab.chromeGroup.color:'',collapsed:!!tab.chromeGroup.collapsed}:null});count++})});return {map,count};
  }
  const a=collect(before),b=collect(after),urls=new Set([...a.map.keys(),...b.map.keys()]);let added=0,removed=0,shared=0;const changed=[],metadataChanged=[],unchanged=[];
  for(const url of urls){const left=a.map.get(url)||[],right=b.map.get(url)||[],difference=right.length-left.length;added+=Math.max(0,difference);removed+=Math.max(0,-difference);shared+=Math.min(left.length,right.length);const entry={url,before:left,after:right,difference,metadata:[]};if(!difference&&left.length===1&&right.length===1){const x=left[0],y=right[0];if(x.window!==y.window||x.position!==y.position)entry.metadata.push('Vị trí trong danh sách khác');if(x.pinned!==y.pinned)entry.metadata.push('Trạng thái ghim khác');if(x.title!==y.title)entry.metadata.push('Tiêu đề khác');if(x.chromeGroup&&y.chromeGroup){if(JSON.stringify(x.chromeGroup)!==JSON.stringify(y.chromeGroup))entry.metadata.push('Thông tin nhóm Chrome khác')}else if(!!x.chromeGroup!==!!y.chromeGroup)entry.metadata.push('Chỉ một phiên có metadata nhóm; không thể kết luận nhóm đã thay đổi')}(difference?changed:entry.metadata.length?metadataChanged:unchanged).push(entry)}
  return {beforeTotal:a.count,afterTotal:b.count,added,removed,shared,changed,metadataChanged,unchanged};
 }
 return {compare};
})();
if(typeof module!=='undefined')module.exports=SnapshotCompare;
