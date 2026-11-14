const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('extension/popup.js','utf8');const start=source.indexOf('function renderTabs('),end=source.indexOf('\nasync function refresh(',start);assert(start>=0&&end>start);
function element(){return {dataset:{},scrollTop:0,children:[],hidden:false,classList:{toggle(_name,state){this.hidden=state}},replaceChildren(){this.children=[]},append(...items){this.children.push(...items)},addEventListener(){},setAttribute(){}}}
const controls={};for(const name of ['#tabSearch','#tabList','#tabCount','#moreTabs','#lessTabs'])controls[name]=element();controls['#tabSearch'].value='';
const context={RefreshFocus:{render:(_doc,draw)=>draw()},$:s=>controls[s],document:{createElement:()=>element()},PopupOrder:require('../extension/popup-order.js'),supported:()=>false,URL,makeButton:()=>element(),switchTab:()=>{},discardTab:()=>{}};
context.allTabs=Array.from({length:15},(_,i)=>({id:i,index:i,windowId:1,title:`Tab ${i}`,url:`https://site.test/${i}`}));context.currentTab={windowId:1};context.visibleLimit=6;
vm.runInNewContext(source.slice(start,end),context);context.renderTabs();assert.equal(controls['#tabList'].children.length,6);assert.equal(controls['#moreTabs'].classList.hidden,false);assert.equal(controls['#lessTabs'].classList.hidden,true);
context.visibleLimit=12;context.renderTabs();assert.equal(controls['#tabList'].children.length,12);assert.equal(controls['#moreTabs'].textContent,'Xem thêm (3)');assert.equal(controls['#lessTabs'].classList.hidden,false);
context.visibleLimit=18;context.renderTabs();assert.equal(controls['#tabList'].children.length,15);assert.equal(controls['#moreTabs'].classList.hidden,true);
context.visibleLimit=6;controls['#tabSearch'].value='Tab 1';context.renderTabs();assert.equal(controls['#tabList'].children.length,6);assert.equal(controls['#moreTabs'].classList.hidden,true);
console.log('Popup pagination and search: OK');
