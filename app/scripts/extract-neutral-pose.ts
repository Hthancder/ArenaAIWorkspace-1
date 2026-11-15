/**
 * One-off dev script: bake the neutral hand pose from the REAL hands
 * pipeline — hands-worker.js + hands.wasm + the vendored motion DB —
 * in-process (node has DecompressionStream / MessageChannel / Blob).
 * Synthesises a two-note hold, then FKs a mid-run frame per hand exactly
 * like the client's `handAt` does. The numbers go into
 * src/hands/neutralPose.ts (free-play hands, "bấm tự do").
 *
 * Run: npx vite-node scripts/extract-neutral-pose.ts
 */
import fs from 'node:fs'
import path from 'node:path'

// ---- drive hands-worker.js as a library: shim `self` / `postMessage` ----
type Reply = { type: string; id?: number | string; [k: string]: unknown }
const queue: Reply[] = []
const waiters: { match: (r: Reply) => boolean; res: (r: Reply) => void }[] = []
;(globalThis as unknown as { self: unknown }).self = globalThis
;(globalThis as unknown as { postMessage: (m: Reply) => void }).postMessage = (m: Reply) => {
  const i = waiters.findIndex((w) => w.match(m))
  if (i >= 0) waiters.splice(i, 1)[0].res(m)
  else queue.push(m) // no waiter registered yet (bounded: we register immediately)
}
const nextReply = (match: (r: Reply) => boolean): Promise<Reply> => {
  const idx = queue.findIndex(match)
  if (idx >= 0) return Promise.resolve(queue.splice(idx, 1)[0])
  return new Promise((res) => waiters.push({ match, res }))
}
await import('../src/hands/runtime/hands-worker.js')
const dispatch = (globalThis as unknown as { self: { onmessage: (e: { data: unknown }) => void } }).self.onmessage

// ---- init with the compiled wasm module ----
const wasmBytes = fs.readFileSync(path.resolve('src/hands/runtime/hands.wasm'))
const wasmModule = await WebAssembly.compile(wasmBytes as unknown as BufferSource)
dispatch({ data: { type: 'init', wasm: wasmModule } })

// ---- load the vendored motion DB (21.7 MB) ----
const dbBytes = fs.readFileSync(path.resolve('public/hands/motion.82cbd97028.bin'))
const t0 = Date.now()
dispatch({ data: { type: 'load', id: 'load', file: dbBytes.buffer.slice(dbBytes.byteOffset, dbBytes.byteOffset + dbBytes.byteLength) } })
const ready = await nextReply((r) => r.type === 'ready' || (r.type === 'error' && r.id === 'load'))
if (ready.type === 'error') throw new Error(`load failed: ${ready.message}`)
console.log('DB loaded in', Date.now() - t0, 'ms', 'entries:', (ready as unknown as { d: number }).d)

// ---- synthesise one held note per hand (centre of the keyboard) ----
dispatch({
  data: {
    type: 'synth',
    id: 1,
    notes: [
      { midi: 62, on: 2, off: 3, hand: 'R', finger: 3 },
      { midi: 50, on: 2, off: 3, hand: 'L', finger: 3 },
    ],
    S: { L: 0.92, R: 0.92 },
    lead: 2.8,
    tail: 2.6,
  },
})
const res = await nextReply((r) => (r.type === 'result' && r.id === 1) || (r.type === 'error' && r.id === 1))
if (res.type === 'error') throw new Error(`synth failed: ${res.message}`)
const motion = (res as unknown as { result: { fps: number; t0: number; frames: number; angles: Float32Array } }).result
console.log('synth: frames', motion.frames, 'fps', motion.fps, 't0', motion.t0)

// ---- FK a frame exactly like the client's handAt (own instance) ----
// (instantiate(module) resolves to the Instance itself.)
const fkInst = (await WebAssembly.instantiate(wasmModule, {})) as unknown as WebAssembly.Instance
const x = fkInst.exports as unknown as Record<string, (...a: number[]) => number> & {
  memory: WebAssembly.Memory
  c: (n: number) => number
  u: (p: number, n: number) => void
}
const withBuf = <T>(size: number, f: (ptr: number) => T): T => {
  const p = x.c(size)
  try {
    return f(p)
  } finally {
    x.u(p, size)
  }
}
const f64 = (ptr: number, n: number) => new Float64Array(x.memory.buffer, ptr, n)

function poseAtFrame(hand: 0 | 1, frame: number, frac: number) {
  const S = 0.92
  const row = (n: number) => {
    const h = (n * 2 + hand) * 33
    return motion.angles.subarray(h, h + 33)
  }
  const a = row(frame)
  const b = row(frame + 1)
  const r = new Float64Array(33)
  for (let i = 0; i < 33; i++) r[i] = a[i] + (b[i] - a[i]) * frac
  return withBuf(864, (t) => {
    f64(t, 33).set(r)
    x.r(t, hand, S, t + 264)
    x.s(t, hand, S, t + 264 + 600)
    const y = f64(t + 264, 84)
    const i3 = (k: number) => [y[k], y[k + 1], y[k + 2]].map((v) => Math.round(v * 1e4) / 1e4)
    const fingers = []
    for (let f = 0; f < 5; f++) fingers.push([i3(12 * f), i3(12 * f + 3), i3(12 * f + 6), i3(12 * f + 9)])
    const bases = []
    for (let f = 0; f < 5; f++) bases.push(i3(60 + 3 * f))
    return {
      wrist: [r[0], r[1], r[2]].map((v) => Math.round(v * 1e4) / 1e4),
      elbow: [r[3], r[4], r[5]].map((v) => Math.round(v * 1e4) / 1e4),
      bases,
      fingers,
      thumbRef: [i3(75), i3(78), i3(81)],
    }
  })
}

// Print candidates across the held span so the nicest can be baked.
for (const hand of [1, 0] as const) {
  for (const t of [2.2, 2.5, 2.8]) {
    const frame = Math.floor((t - motion.t0) * motion.fps)
    const p = poseAtFrame(hand, frame, 0)
    console.log(`\n== ${hand === 1 ? 'R' : 'L'} t=${t} (frame ${frame}) ==`)
    console.log(JSON.stringify(p))
  }
}
