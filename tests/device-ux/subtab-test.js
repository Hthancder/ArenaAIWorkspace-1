const fs=require('fs'),vm=require('vm'),assert=require('assert');
const src=fs.readFileSync(process.argv[2],'utf8');
const html=fs.readFileSync(process.argv[3],'utf8');
function piece(start,end){const a=src.indexOf(start),b=src.indexOf(end,a);assert(a>=0&&b>a, start);return src.slice(a,b);}
function el(id,dataset={}) {const classes=new Set(); return {id,dataset,classes,attrs:{},events:{},
 classList:{toggle:(name,on)=>on?classes.add(name):classes.delete(name),add:(...xs)=>xs.forEach(x=>classes.add(x)),remove:(...xs)=>xs.forEach(x=>classes.delete(x))},
 setAttribute(k,v){this.attrs[k]=v}, addEventListener(k,f){this.events[k]=f}, click(){this.events.click?.()}}; }
const views=['slab-overview','slab-wifi','monslab-overview','monslab-network','stslab-overview','stslab-mic'].map(x=>el(x));
const buttons=[el('s0',{slab:'overview'}),el('s1',{slab:'wifi'}),el('m0',{monslab:'overview'}),el('m1',{monslab:'network'}),el('t0',{stslab:'overview'}),el('t1',{stslab:'mic'})];
const filters=[el('all',{filter:'all'}),el('wifi',{filter:'wids'})],clear=el('mon-alerts-clear');
const byid=Object.fromEntries([...views,...buttons,clear].map(x=>[x.id,x]));
const doc={getElementById:id=>byid[id]||null,querySelectorAll(sel){
 if(sel==='[id^="slab-"]')return views.filter(x=>x.id.startsWith('slab-'));
 if(sel==='[id^="monslab-"]')return views.filter(x=>x.id.startsWith('monslab-'));
 if(sel==='[id^="stslab-"]')return views.filter(x=>x.id.startsWith('stslab-'));
 if(sel==='[data-slab]')return buttons.filter(x=>x.dataset.slab);
 if(sel==='[data-monslab]')return buttons.filter(x=>x.dataset.monslab);
 if(sel==='[data-stslab]')return buttons.filter(x=>x.dataset.stslab);
 if(sel==='.mon-filter')return filters;
 return [];
},querySelector(sel){return sel==='.mon-filter[data-filter="all"]'?filters[0]:null}};
let renderCount=0;const ctx={document:doc,localStorage:{setItem(){}},refreshSecLab(){},renderMonitorAlerts(){renderCount++},monLastSecLab:{},console};vm.createContext(ctx);
vm.runInContext(piece('function switchStSlab(name){','\ndocument.querySelectorAll("[data-stslab]").forEach'),ctx);
vm.runInContext(piece('function switchMonSlab(name){','async function refreshMonitor()'),ctx);
vm.runInContext(piece(' function switchSlab(name){',' function syncOverviewTiles('),ctx);
vm.runInContext('let monFilter="all";'+piece(' document.querySelectorAll("[data-slab]").forEach(btn=>{',' document.getElementById("mon-refresh")'),ctx);
ctx.switchStSlab('mic');ctx.switchMonSlab('network');ctx.switchSlab('wifi');
assert(!byid['stslab-mic'].classes.has('hidden'));assert(!byid['monslab-network'].classes.has('hidden'));assert(!byid['slab-wifi'].classes.has('hidden'));
assert(buttons[3].classes.has('active'));assert(buttons[5].classes.has('active'));
buttons[0].click();assert(!byid['stslab-mic'].classes.has('hidden'));assert(!byid['monslab-network'].classes.has('hidden'));
ctx.switchSlab('unknown');assert(!byid['slab-overview'].classes.has('hidden'));
filters[1].click();clear.click();assert(filters[0].classes.has('active'));assert(!filters[1].classes.has('active'));assert.equal(renderCount,2);
assert(html.includes('id="mon-alerts-clear"'));
assert(src.includes('state.running || state.starting ? "stop" : "start"'));
assert(src.includes('openFileInEditor("LittleFS", "/napt_dns.log")'));
console.log('Subtab isolation, filter and NAPT control checks passed');
