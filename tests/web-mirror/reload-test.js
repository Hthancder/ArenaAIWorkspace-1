const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');
const part = src.slice(src.indexOf('const btnForceReload ='), src.indexOf('\nconst eConfigAutoReload', src.indexOf('const btnForceReload =')));
const pending = [];
const status = {textContent:''};
const button = {classList:{add(){},remove(){}}};
const env = {console:{error(){}}, setTimeout, clearTimeout, AbortController, IS_DEV:false,
  $:s => s === '#force-reload' ? button : status,
  fetch: () => new Promise(resolve => pending.push(resolve)),
  renderTFT: async () => ({missing:0,unknown:0})};
vm.createContext(env); vm.runInContext(part,env);
const response = {ok:true, headers:{get:()=>null}, arrayBuffer:async()=>new ArrayBuffer(8)};
const tick = () => new Promise(resolve => setImmediate(resolve));
(async()=>{
  const first = env.reloadScreen();
  assert.equal(pending.length, 1);
  const second = env.reloadScreen(true);
  assert.strictEqual(first, second, 'coalesce simultaneous requests');
  pending.shift()(response);
  await tick();
  assert.equal(pending.length, 1, 'forced refresh after an in-flight request is not lost');
  pending.shift()(response);
  await first;
  assert.equal(status.textContent, 'Screen connected');
  const third = env.reloadScreen();
  assert.equal(pending.length, 1, 'lock is cleared after completion');
  pending.shift()({ok:false,status:503,headers:{get:()=>null}});
  await third;
  assert.match(status.textContent, /503/);
  console.log('refresh coalescing regression tests passed');
})().catch(e => {console.error(e); process.exit(1)});
