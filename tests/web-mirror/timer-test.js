const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');
const part = src.slice(src.indexOf('const eConfigAutoReload ='), src.indexOf('\nasync function loadScreenSettings()', src.indexOf('const eConfigAutoReload =')));
const resolvers = [], scheduled = [];
const env = {activeTab:'screen', $:()=>({value:'1000'}),
  reloadScreen:()=>new Promise(resolve => resolvers.push(resolve)),
  setTimeout:fn => {scheduled.push(fn); return scheduled.length;}, clearTimeout:()=>{}};
vm.createContext(env); vm.runInContext(part,env);
const tick = () => new Promise(resolve=>setImmediate(resolve));
(async()=>{
  env.autoReloadScreen(); env.autoReloadScreen();
  assert.equal(resolvers.length, 2);
  resolvers.shift()(); resolvers.shift()();
  await tick();
  assert.equal(scheduled.length, 1, 'a stale timer generation must not restart polling');
  env.activeTab = 'dashboard'; env.autoReloadScreen();
  scheduled[0](); await tick();
  assert.equal(resolvers.length, 0, 'polling stops when the screen tab is left');
  console.log('auto-refresh lifecycle regression tests passed');
})().catch(e=>{console.error(e);process.exit(1)});
