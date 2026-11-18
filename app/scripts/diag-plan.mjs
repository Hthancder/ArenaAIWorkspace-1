/**
 * Diagnostic: drive the REAL hands planner (hands-worker.js + hands.wasm)
 * in node and dump how it allocates hands/fingers on synthetic songs —
 * the "phân bổ xử lý" the user reports as unreasonable (R steals L's part
 * on wide-span pieces). Also verifies the pin semantics (explicit hand
 * assignments are kept). Analysis only — not part of the app build.
 *
 * Run: node scripts/diag-plan.mjs
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const runtimeDir = join(here, '..', 'src', 'hands', 'runtime')

// ---- shims so the module worker's top level runs in node ----
globalThis.self = globalThis
const wasmBytes = readFileSync(join(runtimeDir, 'hands.wasm'))
const wasmModule = await WebAssembly.compile(wasmBytes)
const dbBytes = new Uint8Array(readFileSync(join(here, '..', 'public', 'hands', 'motion.82cbd97028.bin')))

await import(join(runtimeDir, 'hands-worker.js')) // sets self.onmessage

const send = (data) => self.onmessage({ data })

function nextMessage(match) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout waiting for ' + JSON.stringify(match))), 120_000)
    const prev = self.postMessage
    self.postMessage = (m) => {
      if (match(m)) {
        self.postMessage = prev
        clearTimeout(t)
        resolve(m)
      } else if (m && m.type === 'progress') {
        // keep waiting
      } else {
        self.postMessage = prev
        clearTimeout(t)
        reject(new Error('unexpected message ' + JSON.stringify(m).slice(0, 200)))
      }
    }
  })
}

// ---- boot + load the motion DB ----
send({ type: 'init', wasm: wasmModule })
let p = nextMessage((m) => m.type === 'ready')
send({ type: 'load', id: 'load', file: dbBytes })
await p
console.log('runtime loaded')

// ---- synthetic songs (midi/on/off in seconds) ----
const N = (midi, on, dur = 0.3) => ({ midi, on, off: on + dur, hand: null, finger: null })

function songWideSpan() {
  // LH bass octaves + Alberti rising into E4, RH melody C4–C6 dipping to
  // G3 — an overlapping, wide-coverage texture ("bài phủ nốt rộng").
  const out = []
  for (let bar = 0; bar < 8; bar++) {
    const t0 = bar * 2
    // LH: octave bass then a rising figure crossing C4
    out.push(N(36, t0, 0.9), N(48, t0, 0.9))
    const lhFig = [40, 43, 48, 52, 55, 59, 60, 64] // C2-region → E4
    lhFig.forEach((m, i) => out.push(N(m, t0 + 0.25 + i * 0.22, 0.2)))
    // RH: melody C5–G5 with dips to G3/B3
    const rhFig = [72, 74, 76, 79, 67, 71, 74, 77]
    rhFig.forEach((m, i) => out.push(N(m, t0 + 0.25 + i * 0.22, 0.2)))
  }
  return out.sort((a, b) => a.on - b.on || a.midi - b.midi)
}

function songSingleTrackPop() {
  // One-track pop texture: chords C3–C4 + melody E4–E5, wide total span.
  const out = []
  for (let bar = 0; bar < 8; bar++) {
    const t0 = bar * 2
    for (const ch of [[48, 52, 55], [45, 48, 52], [41, 45, 48], [43, 47, 50]]) {
      ch.forEach((m) => out.push(N(m, t0, 0.9)))
      const mel = [64, 67, 69, 72, 71, 67, 64, 62]
      mel.forEach((m, i) => out.push(N(m, t0 + 0.25 + i * 0.22, 0.2)))
      break // one chord per bar
    }
  }
  return out.sort((a, b) => a.on - b.on || a.midi - b.midi)
}

function songScaleBothHands() {
  // Sanity: C major scale up (RH) and down (LH) — should split cleanly.
  const out = []
  for (let i = 0; i < 8; i++) out.push(N(60 + i, i * 0.3, 0.25)) // C4→C5
  for (let i = 0; i < 8; i++) out.push(N(48 + (7 - i), 2.6 + i * 0.3, 0.25)) // C3→C3 down
  return out
}

function songPinProbe() {
  // Pin semantics: low notes FORCED to L, high forced to R.
  const out = []
  for (let i = 0; i < 16; i++) out.push(N(36 + (i % 12), i * 0.25, 0.2))
  return out
}

async function planOf(notes, planOpts) {
  const p = nextMessage((m) => m.type === 'result' || m.type === 'error')
  send({ type: 'synth', id: 1, notes, S: { L: 0.92, R: 0.92 }, lead: 2.8, tail: 2.6, ...(planOpts ? { plan: planOpts } : {}) })
  const m = await p
  if (m.type === 'error') throw new Error(m.message)
  return m.plan
}

function report(name, notes, plan) {
  const rows = notes.map((n, i) => ({ midi: n.midi, on: n.on, hand: plan.hand[i], finger: plan.finger[i], want: n.hand }))
  const L = rows.filter((r) => r.hand === 'L')
  const R = rows.filter((r) => r.hand === 'R')
  const drop = rows.filter((r) => !r.hand)
  const midis = rows.map((r) => r.midi)
  const med = [...midis].sort((a, b) => a - b)[Math.floor(midis.length / 2)]
  const lowToR = rows.filter((r) => r.hand === 'R' && r.midi < med).length
  const highToL = rows.filter((r) => r.hand === 'L' && r.midi > med).length
  const maxL = Math.max(...L.map((r) => r.midi), -1)
  const minR = Math.min(...R.map((r) => r.midi), 999)
  const overlap = maxL - minR // >0 = the hands' pitch ranges overlap
  const thumbBlack = rows.filter((r) => r.finger === 1 && [1, 3, 6, 8, 10].includes(r.midi % 12)).length
  console.log(`\n=== ${name} (${rows.length} notes) ===`)
  console.log(`  split: L=${L.length} R=${R.length} dropped=${drop.length}  (median pitch ${med})`)
  console.log(`  cross-over: notes below median → R: ${lowToR}, above median → L: ${highToL}`)
  console.log(`  pitch overlap Lmax−Rmin = ${overlap} semitones  (maxL=${maxL} minR=${minR})`)
  console.log(`  thumb-on-black: ${thumbBlack}   fingers used: L=${[...new Set(L.map((r) => r.finger))].join(',')} R=${[...new Set(R.map((r) => r.finger))].join(',')}`)
  // sample of the first 12 assignments
  console.log('  first notes:', rows.slice(0, 12).map((r) => `${r.midi}:${r.hand}${r.finger}`).join(' '))
}

// ---- 1. what does the runtime planner do today (no pre-assignment)? ----
for (const [name, fn] of [['wide-span', songWideSpan], ['single-track pop', songSingleTrackPop], ['both-hands scale', songScaleBothHands]]) {
  const notes = fn()
  const plan = await planOf(notes)
  report(name, notes, plan)
}

// ---- 2. pin probe: do explicit hands survive planning? ----
{
  const notes = songPinProbe().map((n, i) => ({ ...n, hand: i % 2 ? 'R' : 'L', finger: null }))
  const plan = await planOf(notes)
  const kept = notes.filter((n, i) => plan.hand[i] === n.hand).length
  console.log(`\n=== pin probe: explicit hands kept = ${kept}/${notes.length} ===`)
  console.log('  want:', notes.slice(0, 8).map((n) => n.hand).join(''), ' got:', plan.hand.slice(0, 8).join(''))
}

// ---- 3. pin probe 2: explicit hand WITHOUT finger on a wide-span song ----
{
  const notes = songWideSpan().map((n) => ({ ...n, hand: n.midi < 60 ? 'L' : 'R' }))
  const plan = await planOf(notes)
  const kept = notes.filter((n, i) => plan.hand[i] === n.hand).length
  console.log(`\n=== pin probe (hands only, fingers planned): kept = ${kept}/${notes.length} ===`)
  const rows = notes.map((n, i) => `${n.midi}:${plan.hand[i]}${plan.finger[i]}`)
  console.log('  first notes:', rows.slice(0, 12).join(' '))
}

process.exit(0)
