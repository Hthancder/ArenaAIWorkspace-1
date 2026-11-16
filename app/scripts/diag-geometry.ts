/**
 * GĐ 0 — diagnostic: measure the RENDERED hand geometry on the real
 * playback chain (hands-worker.js + hands.wasm + the vendored motion DB)
 * and the overlay chain (humanize + liveHands) against the anatomical
 * targets from the pianism research:
 *   - wrist height above key tops (z=0): 2–5.5 cm is natural; 9.5 cm is "bay cao"
 *   - finger approach angle (MCP→tip vs key plane): 30–60°
 *   - fingertip at/near the key surface at hold (z ≤ 1.5 cm)
 *   - knuckle bridge: MCP z ≈ or above wrist z
 *   - tip x error at the keydown moment (symptom "hụt về nốt trước")
 *   - double-curl: overlay swing added on top of the DB's own press
 *   - inter-finger tip gaps (symptom "ngón chụm")
 *
 * Run: npx vite-node scripts/diag-geometry.ts
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
  else queue.push(m)
}
const nextReply = (match: (r: Reply) => boolean): Promise<Reply> => {
  const idx = queue.findIndex(match)
  if (idx >= 0) return Promise.resolve(queue.splice(idx, 1)[0])
  return new Promise((res) => waiters.push({ match, res }))
}
await import('../src/hands/runtime/hands-worker.js')
const dispatch = (globalThis as unknown as { self: { onmessage: (e: { data: unknown }) => void } }).self.onmessage

const wasmBytes = fs.readFileSync(path.resolve('src/hands/runtime/hands.wasm'))
const wasmModule = await WebAssembly.compile(wasmBytes as unknown as BufferSource)
dispatch({ data: { type: 'init', wasm: wasmModule } })

const dbBytes = fs.readFileSync(path.resolve('public/hands/motion.82cbd97028.bin'))
dispatch({
  data: {
    type: 'load',
    id: 'load',
    file: dbBytes.buffer.slice(dbBytes.byteOffset, dbBytes.byteOffset + dbBytes.byteLength),
  },
})
const ready = await nextReply((r) => r.type === 'ready' || (r.type === 'error' && r.id === 'load'))
if (ready.type === 'error') throw new Error(`load failed: ${ready.message}`)

// ---- a right-hand scale run: 6 notes, 300 ms apart ----
const RUN = [
  { midi: 62, on: 2.0, finger: 1 },
  { midi: 64, on: 2.3, finger: 2 },
  { midi: 65, on: 2.6, finger: 3 },
  { midi: 67, on: 2.9, finger: 1 },
  { midi: 69, on: 3.2, finger: 2 },
  { midi: 71, on: 3.5, finger: 3 },
]
dispatch({
  data: {
    type: 'synth',
    id: 1,
    notes: RUN.map((n) => ({ midi: n.midi, on: n.on, off: n.on + 0.25, hand: 'R', finger: n.finger })),
    S: { L: 0.92, R: 0.92 },
    lead: 2.8,
    tail: 2.6,
  },
})
const res = await nextReply((r) => (r.type === 'result' && r.id === 1) || (r.type === 'error' && r.id === 1))
if (res.type === 'error') throw new Error(`synth failed: ${res.message}`)
const motion = (res as unknown as { result: { fps: number; t0: number; frames: number; angles: Float32Array } }).result

// ---- FK a frame exactly like the client's handAt ----
const fkInst = (await WebAssembly.instantiate(wasmModule, {})) as unknown as WebAssembly.Instance
const x = fkInst.exports as unknown as Record<string, (...a: number[]) => number> & { memory: WebAssembly.Memory; c: (n: number) => number; u: (p: number, n: number) => void }
const withBuf = <T>(size: number, f: (ptr: number) => T): T => {
  const p = x.c(size)
  try {
    return f(p)
  } finally {
    x.u(p, size)
  }
}
const f64 = (ptr: number, n: number) => new Float64Array(x.memory.buffer, ptr, n)

type Pose = {
  wrist: number[]
  elbow: number[]
  bases: number[][]
  fingers: number[][][]
  thumbRef: number[][]
}
function poseAtTime(hand: 0 | 1, t: number): Pose {
  const S = 0.92
  const frame = Math.floor((t - motion.t0) * motion.fps)
  const frac = (t - motion.t0) * motion.fps - frame
  const row = (n: number) => motion.angles.subarray((n * 2 + hand) * 33, (n * 2 + hand) * 33 + 33)
  const a = row(frame)
  const b = row(frame + 1)
  const r = new Float64Array(33)
  for (let i = 0; i < 33; i++) r[i] = a[i] + (b[i] - a[i]) * frac
  return withBuf(864, (p) => {
    f64(p, 33).set(r)
    x.r(p, hand, S, p + 264)
    x.s(p, hand, S, p + 264 + 600)
    const y = f64(p + 264, 84)
    const i3 = (k: number) => [y[k], y[k + 1], y[k + 2]]
    const fingers: number[][][] = []
    for (let f = 0; f < 5; f++) fingers.push([i3(12 * f), i3(12 * f + 3), i3(12 * f + 6), i3(12 * f + 9)])
    const bases: number[][] = []
    for (let f = 0; f < 5; f++) bases.push(i3(60 + 3 * f))
    return { wrist: [r[0], r[1], r[2]], elbow: [r[3], r[4], r[5]], bases, fingers, thumbRef: [i3(75), i3(78), i3(81)] }
  })
}

// ---- measurement helpers (z = UP, key tops z=0; y along keys: front -2.0, back -0.525) ----
const keyForMidi = (await import('../src/keyboard/layout')).keyForMidi

console.log('diag-geometry: DB entries', (ready as unknown as { d: number }).d, 'run frames', motion.frames)

// ---- Part A: pure DB playback chain ----
console.log('\n== Part A: DB playback chain (what poseAt gives during a run) ==')
console.log('note | t   | wristZ | MCPZ | tipZ | approach° | tipY  | tipX-keyX | tip gaps (x)')
const angleDeg = (mcp: number[], tip: number[]) => {
  const dxy = Math.hypot(tip[0] - mcp[0], tip[1] - mcp[1])
  return (Math.atan2(mcp[2] - tip[2], dxy) * 180) / Math.PI
}
for (let i = 0; i < RUN.length; i++) {
  const n = RUN[i]
  for (const dt of [0.02, 0.15]) {
    const p = poseAtTime(1, n.on + dt)
    const f = n.finger - 1
    const mcp = p.fingers[f][0]
    const tip = p.fingers[f][3]
    const k = keyForMidi(n.midi)
    const gaps = []
    for (let g = 0; g < 4; g++) gaps.push(Math.abs(p.fingers[g + 1][3][0] - p.fingers[g][3][0]).toFixed(3))
    console.log(
      `${String(n.midi).padStart(3)} |${dt === 0.02 ? 'strk' : 'hold'} | ${p.wrist[2].toFixed(3)} | ${mcp[2].toFixed(3)} | ${tip[2].toFixed(3)} | ${angleDeg(mcp, tip).toFixed(1).padStart(6)} | ${tip[1].toFixed(3)} | ${(tip[0] - k!.x).toFixed(3).padStart(9)} | ${gaps.join(',')}`,
    )
  }
}

// ---- dump the run frames at 60 fps for the overlay diagnostic (diag-overlay.ts) ----
const dump: Pose[] = []
for (let i = 0; i < 120; i++) dump.push(poseAtTime(1, 2.0 + i / 60))
fs.writeFileSync(path.resolve('scripts/.diag-frames.json'), JSON.stringify({ fps: 60, t0: 2.0, frames: dump }))
console.log('\ndumped', dump.length, 'frames to scripts/.diag-frames.json')
