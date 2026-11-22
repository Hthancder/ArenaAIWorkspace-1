const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(process.argv[2], 'utf8');
const start = src.indexOf('function prepareUiSound('), end = src.indexOf('\n$("#ux-wav-upload")', start);
assert(start >= 0 && end > start);
const ctx = {}; vm.createContext(ctx); vm.runInContext(src.slice(start, end), ctx);
// WAV with an extra metadata chunk; conversion removes it and trims only to whole frames.
const dataLen = 48000 * 2, a = Buffer.alloc(44 + 12 + dataLen);
a.write('RIFF',0); a.writeUInt32LE(a.length - 8,4); a.write('WAVEfmt ',8);
a.writeUInt32LE(16,16); a.writeUInt16LE(1,20); a.writeUInt16LE(1,22);
a.writeUInt32LE(48000,24); a.writeUInt32LE(96000,28); a.writeUInt16LE(2,32); a.writeUInt16LE(16,34);
a.write('JUNK',36); a.writeUInt32LE(4,40); a.write('test',44); a.write('data',48); a.writeUInt32LE(dataLen,52);
const result = ctx.prepareUiSound(a, 'select');
assert(result.trimmed); assert.equal(result.bytes.length, 44 + 24000);
assert.equal(Buffer.from(result.bytes).toString('ascii',36,40),'data');
assert.equal(new DataView(result.bytes.buffer).getUint32(40,true),24000);
assert.throws(()=>ctx.prepareUiSound(a,'unknown'));
a.writeUInt32LE(44100,24); assert.throws(()=>ctx.prepareUiSound(a,'select'),/48 kHz/);
a.writeUInt32LE(0xffffffff,52); assert.throws(()=>ctx.prepareUiSound(a,'find'),/incomplete/);
console.log('Browser WAV preparation regression tests passed');
