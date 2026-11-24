const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const html = fs.readFileSync(process.argv[3], 'utf8');
for (const id of ['ux-find','ux-stop','ux-sound','ux-menu-tones','ux-volume','ux-brightness','ux-save','ux-status'])
  assert(html.includes(`id="${id}"`));
const marker = '// Board controls: all mutations';
const endMarker = '// ==== SecLab compact subtabs + overview mirror';
const blockStart = source.indexOf(marker);
const blockEnd = source.indexOf(endMarker, blockStart);
assert(blockStart >= 0 && blockEnd > blockStart, 'device controls block markers are present');
const elements = {};
for (const id of ['ux-find','ux-stop','ux-sound','ux-menu-tones','ux-volume','ux-brightness','ux-save','ux-status','ux-volume-label','ux-brightness-label']) {
  elements[id] = { value:'', checked:false, disabled:false, textContent:'', handlers:{}, addEventListener(e,cb){this.handlers[e]=cb;} };
}
const calls = [];
class FakeForm { constructor(){ this.values={}; } append(k,v){ this.values[k]=v; } }
const ctx = {console, IS_DEV:false, FormData: FakeForm, setTimeout,
  $: s => elements[s.slice(1)] || null,
  requestGet: async () => JSON.stringify({sound:true,menuTones:true,volume:35,brightness:75,find:'idle'}),
  fetch: async (url,opts) => { calls.push({url,opts}); return {ok:true,json:async()=>({ok:true,msg:'queued'})}; }
};
vm.createContext(ctx); vm.runInContext(source.slice(blockStart, blockEnd),ctx);
(async()=>{
  await new Promise(r=>setImmediate(r));
  assert.strictEqual(elements['ux-sound'].checked,true);
  assert.strictEqual(elements['ux-volume'].value,35);
  elements['ux-volume'].value = 55; elements['ux-brightness'].value = 65;
  await elements['ux-save'].handlers.click();
  assert.strictEqual(calls.length,4);
  assert.deepStrictEqual(calls.map(c=>c.opts.body.values.action),['sound','menuTones','volume','brightness']);
  assert.strictEqual(calls[2].opts.body.values.value,'55');
  for(const c of calls) { assert.strictEqual(c.opts.headers['X-Bruce-UI'],'1'); assert.strictEqual(c.opts.credentials,'same-origin'); }
  assert(elements['ux-status'].textContent.includes('Saved'));
  await elements['ux-stop'].handlers.click();
  assert.strictEqual(calls[4].opts.body.values.action,'stop');
  // A status request begun before Stop cannot overwrite its newer message.
  let resolveOld;
  ctx.requestGet = () => new Promise(resolve => { resolveOld = resolve; });
  const old = ctx.uxLoad(false);
  await elements['ux-stop'].handlers.click();
  const stoppedMessage = elements['ux-status'].textContent;
  resolveOld(JSON.stringify({find:'playing'}));
  await old;
  assert.strictEqual(elements['ux-status'].textContent, stoppedMessage);
  let finishFind;
  const ordered = [];
  ctx.fetch = async (url, opts) => {
    const action = opts.body.values.action; ordered.push(action);
    if (action === 'find') await new Promise(resolve => { finishFind = resolve; });
    return {ok:true,json:async()=>({ok:true,msg:action})};
  };
  const finding = elements['ux-find'].handlers.click();
  assert(elements['ux-status'].textContent.includes('Sending find request'));
  const stopping = elements['ux-stop'].handlers.click();
  await new Promise(r=>setImmediate(r));
  assert.deepStrictEqual(ordered,['find']);
  assert(elements['ux-find'].disabled);
  finishFind(); await finding; await stopping;
  assert.deepStrictEqual(ordered,['find','stop']);
  assert(!elements['ux-find'].disabled);
  assert.strictEqual(elements['ux-status'].textContent, 'stop');


  console.log('Device UX browser regression tests passed');
})().catch(err=>{ console.error(err); process.exitCode=1; });
