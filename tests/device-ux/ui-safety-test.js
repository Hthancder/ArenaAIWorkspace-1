const fs = require('fs'), vm = require('vm'), assert = require('assert');
const [jsPath, htmlPath, qrPath] = process.argv.slice(2);
const js = fs.readFileSync(jsPath, 'utf8'), html = fs.readFileSync(htmlPath, 'utf8');
const lib = fs.readFileSync(qrPath, 'utf8');
assert(html.includes('/qr_local.js'));
assert(!js.includes('api.qrserver.com'));
for (const cmd of ['mic spectrum','mic db','mic record','sonar','megalodon','timer'])
  assert(!html.includes(`quickCli('${cmd}')`), `unsupported action ${cmd}`);
assert(!js.includes('dataset.ssid='));
const begin = js.indexOf(' document.getElementById("mon-net-scan")?.addEventListener');
const end = js.indexOf(' document.getElementById("mon-napt-toggle")', begin);
assert(begin >= 0 && end > begin);
function element() { return { children:[], textContent:'', className:'', handlers:{},
  replaceChildren(){this.children=[];}, append(...nodes){this.children.push(...nodes);}, appendChild(n){this.children.push(n);},
  addEventListener(name, fn){this.handlers[name]=fn;} }; }
const scan=element(), box=element();
const hostile = `network'\"<script>alert(1)</script>`;
let selected;
const ctx = { document:{getElementById: id => id==='mon-net-scan'?scan:box, createElement:()=>element()},
  requestGet: async ()=>JSON.stringify({nets:[{ssid:hostile,saved:true,rssi:-42,channel:1}]}),
  openWifiModal: n => { selected=n; }, console };
vm.createContext(ctx); vm.runInContext(js.slice(begin,end), ctx);
(async()=>{
  await scan.handlers.click();
  assert(box.children[0].children[0].textContent.includes(hostile));
  box.children[0].children[1].handlers.click();
  assert.equal(selected.ssid, hostile);
  // Generate a real local QR, including non-ASCII content, without network access.
  const qrContext = {}; vm.createContext(qrContext); vm.runInContext(lib,qrContext);
  const qr=qrContext.qrcode; qr.stringToBytes=qr.stringToBytesFuncs['UTF-8'];
  const code=qr(0,'M'); code.addData('Xin chào 🌏'); code.make();
  assert(code.getModuleCount() > 0); assert(code.createImgTag(4,16).includes('data:image/gif'));
  console.log('Wi-Fi rendering and offline QR checks passed');
})().catch(e=>{ console.error(e); process.exitCode=1; });
