const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');
const part = src.slice(src.indexOf('async function renderTFT('), src.indexOf('\nfunction drawCanvasLoading()', src.indexOf('async function renderTFT(')));
const calls = [];
function canvas(name) {
  const ctx = new Proxy({}, {get(o,k) { if (!(k in o)) o[k] = (...args)=>calls.push([name,k,...args]); return o[k]; }, set(o,k,v) {o[k]=v; return true;}});
  return {width:284,height:240,getContext:()=>ctx};
}
const visible = canvas('visible');
const warning = {classList:{toggle(){}}};
const env = {console: {warn(){}, error: console.error}, TextDecoder, IS_DEV:false, loadingDrawn:false, imageCache:new Map(), imageCacheGeneration:0,
  setTimeout, clearTimeout, Date, document:{createElement: () => canvas('buffer')},
  $: s => s === '#navigator-screen' ? visible : warning,
  Image: class {set src(v) { this.onerror(new Error('not found')); }}};
vm.createContext(env); vm.runInContext(part,env);
const info = [0xaa,8,99,1,28,0,240,0];
const pkt = (fn, values) => [0xaa,3+values.length,fn,...values];
(async()=>{
  const pixel = pkt(19,[0xff,0xfe,0,3,0xf8,0]);
  const result = await env.renderTFT(Uint8Array.from([...info,...pixel]));
  assert.equal(result.missing,0);
  assert.equal(result.unknown,0);
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillRect' && x[2]===-2 && x[3]===3 && x[4]===1 && x[5]===1));
  assert(!calls.some(x=>x[0]==='buffer' && x[1]==='fillRect' && x[4]===284 && x[5]===240), 'screen info must not paint black');
  assert(calls.some(x=>x[0]==='visible' && x[1]==='drawImage'), 'complete frame commits to the visible canvas');
  const before=calls.length;
  await assert.rejects(env.renderTFT(Uint8Array.from([...info,0xaa,0,0])),/Incomplete/);
  assert.equal(calls.length,before,'invalid frame must not erase previous canvas');
  await assert.rejects(env.renderTFT(Uint8Array.from([...info, 0xaa,3,19])),/Incomplete/);
  await assert.rejects(env.renderTFT(Uint8Array.from([0xaa,8,99,0,0,0,240,0])),/dimensions/);
  const image=pkt(18,[0,0,0,0,0,0,0,0,2,...Buffer.from('/missing.png')]);
  assert.equal((await env.renderTFT(Uint8Array.from([...info,...image,...pixel]))).missing,1);
  assert.equal((await env.renderTFT(Uint8Array.from([...info,...pkt(77,[])]))).unknown,1);
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillRect' && x[2]===-2), 'draws following missing images survive');
  const datumText = pkt(22,[0,50,0,40,0,2,0xff,0xff,0,0,4,...Buffer.from('Hi')]);
  calls.length=0;
  await env.renderTFT(Uint8Array.from([...info,...datumText]));
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillText' && x[2]==='Hi' && x[3]===50 && x[4]===32));
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillRect' && x[2]===38 && x[3]===32 && x[4]===24 && x[5]===16));
  const bottomRight = pkt(22,[0,50,0,40,0,1,0xff,0xff,0,0,8,...Buffer.from('XY')]);
  calls.length=0;
  await env.renderTFT(Uint8Array.from([...info,...bottomRight]));
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillText' && x[2]==='XY' && x[3]===50 && x[4]===32));
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillRect' && x[2]===38 && x[3]===32 && x[4]===12 && x[5]===8));
  // Legacy drawString packets retain top-left positioning.
  const oldText = pkt(16,[0,50,0,40,0,1,0xff,0xff,0,0,...Buffer.from('XY')]);
  calls.length=0;
  await env.renderTFT(Uint8Array.from([...info,...oldText]));
  assert(calls.some(x=>x[0]==='buffer' && x[1]==='fillText' && x[2]==='XY' && x[3]===50 && x[4]===40));
  await assert.rejects(env.renderTFT(Uint8Array.from([...info, ...pkt(22, new Array(10).fill(0))])),/Incomplete/);
  console.log('browser renderer regression tests passed');
})().catch(e=>{console.error(e);process.exit(1)});
