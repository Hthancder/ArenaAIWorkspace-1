/**
 * GĐ 7 end-to-end: run the REAL motion planner (hands-worker.js + hands.wasm)
 * on the adversarial songs, with the auto hand split applied — the ngưỡng
 * đo the plan was approved with:
 *   - the planner KEEPS our hands (pin) on 100% of notes;
 *   - 0 mid-run hand switches on wide-span figures (raw planner: 6);
 *   - fingers (the "đổi ngón giữa chừng" complaint): no same-finger on
 *     consecutive different pitches; measure a-b-a-b alternation and
 *     thumb-on-black, before (raw) vs after (split pinned).
 *
 * Run: `npx tsx scripts/test-autosplit-plan.ts` (node, not vite-node —
 * this drives the module worker directly).
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { splitHands, type SplittableNote } from '../src/hands/autoSplit'

const here = dirname(fileURLToPath(import.meta.url))
const runtimeDir = join(here, '..', 'src', 'hands', 'runtime')

// ---- shims so the module worker's top level runs in node ----
;(globalThis as unknown as { self: unknown }).self = globalThis
const wasmModule = await WebAssembly.compile(readFileSync(join(runtimeDir, 'hands.wasm')))
const dbBytes = new Uint8Array(readFileSync(join(here, '..', 'public', 'hands', 'motion.82cbd97028.bin')))
await import(join(runtimeDir, 'hands-worker.js'))

const send = (data: unknown) => {
  ;(globalThis as unknown as { onmessage: (e: { data: unknown }) => void }).onmessage({ data })
}
function nextMessage(match: (m: { type: string }) => boolean): Promise<{ type: string; [k: string]: unknown }> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout waiting for worker')), 120_000)
    const g = globalThis as unknown as { postMessage: (m: unknown) => void }
    const prev = g.postMessage
    g.postMessage = (m: unknown) => {
      const msg = m as { type: string }
      if (match(msg)) {
        g.postMessage = prev
        clearTimeout(t)
        resolve(msg)
      } else if (msg.type === 'progress') {
        /* keep waiting */
      } else {
        g.postMessage = prev
        clearTimeout(t)
        reject(new Error('unexpected message ' + JSON.stringify(msg).slice(0, 200)))
      }
    }
  })
}

send({ type: 'init', wasm: wasmModule })
let p = nextMessage((m) => m.type === 'ready')
send({ type: 'load', id: 'load', file: dbBytes })
await p

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

const N = (midi: number, on: number, dur = 0.2): SplittableNote => ({ midi, on, off: on + dur, hand: null })

type Plan = { hand: (string | null)[]; finger: number[] }
async function planOf(notes: SplittableNote[]): Promise<Plan> {
  const p = nextMessage((m) => m.type === 'result' || m.type === 'error')
  send({
    type: 'synth',
    id: 1,
    notes: notes.map((n) => ({ midi: n.midi, on: n.on, off: n.off, hand: n.hand ?? null, finger: null })),
    S: { L: 0.92, R: 0.92 },
    lead: 2.8,
    tail: 2.6,
  })
  const m = await p
  if (m.type === 'error') throw new Error(String(m.message))
  return m.plan as unknown as Plan
}

function midRunSwitches(notes: SplittableNote[], hands: (string | null)[]): number {
  let n = 0
  for (let i = 1; i < notes.length; i++) {
    const step = Math.abs(notes[i].midi - notes[i - 1].midi)
    if (hands[i] !== hands[i - 1] && step > 0 && step <= 7 && Math.abs(notes[i].on - notes[i - 1].on) < 0.3) n++
  }
  return n
}

/** Hand switches INSIDE one monotonic pass (a run's own notes only). */
function passSwitches(pass: number[], hands: (string | null)[]): number {
  let n = 0
  for (let i = 1; i < pass.length; i++) if (hands[pass[i]] !== hands[pass[i - 1]]) n++
  return n
}

/** Finger awkwardness: same-finger repeats + sustained a-b-a-b alternation
 * (stepwise runs ≤ 3 AND all same-hand consecutive pairs — the 2-note
 * ostinato pattern that produced the f2121 signature). */
function fingerStats(notes: SplittableNote[], plan: Plan): {
  sameFingerStep: number
  sameFingerLeap: number
  leapExamples: string[]
  flipRuns: number
  runs: number
  notes: number
  altRuns: number
  altTotal: number
  altNotes: number
} {
  let sameFingerStep = 0
  let sameFingerLeap = 0
  const leapExamples: string[] = []
  let flipRuns = 0
  let runs = 0
  let stepNotes = 0
  let altRuns = 0
  let altTotal = 0
  let altNotes = 0
  let seq: number[] = []
  let aseq: number[] = []
  let last: { midi: number; finger: number; hand: string; on: number } | null = null
  const flush = () => {
    if (seq.length >= 4) {
      runs++
      let flips = 0
      for (let i = 2; i < seq.length; i++) if (seq[i] === seq[i - 2] && seq[i] !== seq[i - 1]) flips++
      if (flips >= Math.max(2, seq.length - 3)) flipRuns // a-b-a-b sustained across the run
    }
    seq = []
    if (aseq.length >= 4) {
      altTotal++
      altNotes += aseq.length
      let flips = 0
      for (let i = 2; i < aseq.length; i++) if (aseq[i] === aseq[i - 2] && aseq[i] !== aseq[i - 1]) flips++
      if (flips >= Math.max(2, aseq.length - 3)) altRuns // the f2121 signature
    }
    aseq = []
  }
  for (let i = 0; i < notes.length; i++) {
    const f = plan.finger[i]
    const h = plan.hand[i]
    if (!h || !f) continue
    const cur = { midi: notes[i].midi, finger: f, hand: h, on: notes[i].on }
    const close = last !== null && h === last.hand && cur.midi !== last.midi && cur.on - last.on <= 0.35
    if (close && last) {
      const step = Math.abs(cur.midi - last.midi)
      if (f === last.finger) {
        if (step <= 3) sameFingerStep++
        else {
          sameFingerLeap++
          if (leapExamples.length < 6) leapExamples.push(`${last.midi}(f${last.finger})→${cur.midi}(f${f}) +${(cur.on - last.on).toFixed(2)}s`)
        }
      }
      if (aseq.length === 0) aseq.push(last.finger)
      aseq.push(f)
      if (step <= 3) {
        if (seq.length === 0) seq.push(last.finger)
        seq.push(f)
        stepNotes++
      } else flush()
    } else flush()
    last = cur
  }
  flush()
  return { sameFingerStep, sameFingerLeap, leapExamples, flipRuns, runs, notes: stepNotes, altRuns, altTotal, altNotes }
}

// ---- the adversarial songs -------------------------------------------
function caseWideSpan(): SplittableNote[] {
  const out: SplittableNote[] = []
  for (let bar = 0; bar < 6; bar++) {
    const t0 = bar * 2
    ;[36, 43, 48, 52, 55, 60, 64, 67].forEach((m, i) => out.push(N(m, t0 + 0.25 + i * 0.22)))
    out.push({ midi: 72, on: t0, off: t0 + 1.8, hand: null }, { midi: 76, on: t0 + 1, off: t0 + 1.9, hand: null })
  }
  return out
}
function caseInterlock(): { notes: SplittableNote[]; passes: number[][] } {
  // Sequential passes (an arpeggio étude: up, then down) — musically valid.
  const out: SplittableNote[] = []
  const passes: number[][] = []
  const up = [36, 48, 52, 55, 60, 64, 67, 72, 76, 79, 84, 88]
  for (let bar = 0; bar < 4; bar++) {
    const t0 = bar * 4
    const p1: number[] = []
    up.forEach((m, i) => {
      p1.push(out.length)
      out.push(N(m, t0 + i * 0.16, 0.15))
    })
    passes.push(p1)
    const p2: number[] = []
    ;[...up].reverse().forEach((m, i) => {
      p2.push(out.length)
      out.push(N(m, t0 + 1.95 + i * 0.16, 0.15))
    })
    passes.push(p2)
  }
  return { notes: out, passes }
}

function caseCrossed(): { notes: SplittableNote[]; passes: number[][] } {
  // Two sweeps in opposite directions AT ONCE (12 notes/s combined) — the
  // hard "giao nhau" texture; a pass may hand over ONCE at the crossing.
  const out: SplittableNote[] = []
  const passes: number[][] = []
  const up = [36, 48, 52, 55, 60, 64, 67, 72, 76, 79, 84, 88]
  for (let bar = 0; bar < 3; bar++) {
    const t0 = bar * 2
    const p1: number[] = []
    up.forEach((m, i) => {
      p1.push(out.length)
      out.push(N(m, t0 + i * 0.16, 0.15))
    })
    passes.push(p1)
    const p2: number[] = []
    ;[...up].reverse().forEach((m, i) => {
      p2.push(out.length)
      out.push(N(m, t0 + 1.95 + i * 0.16, 0.15))
    })
    passes.push(p2)
  }
  return { notes: out, passes }
}
function caseTenor(): SplittableNote[] {
  const out: SplittableNote[] = []
  for (let bar = 0; bar < 6; bar++) {
    const t0 = bar * 2
    ;[48, 50, 52, 55, 57, 55, 52, 50].forEach((m, i) => out.push(N(m, t0 + i * 0.25, 0.22)))
    out.push({ midi: 72, on: t0, off: t0 + 1.2, hand: null }, { midi: 76, on: t0, off: t0 + 1.2, hand: null })
  }
  return out
}

function caseScale(): SplittableNote[] {
  // classic melodic material — the "đổi ngón" complaint shows here
  const out: SplittableNote[] = []
  const scale = [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62]
  for (let bar = 0; bar < 4; bar++) {
    const t0 = bar * 3
    scale.forEach((m, i) => out.push(N(m, t0 + i * 0.22, 0.2)))
    out.push({ midi: 36, on: t0, off: t0 + 2.8, hand: null }, { midi: 43, on: t0, off: t0 + 2.8, hand: null })
  }
  return out
}

function caseOstinato(): SplittableNote[] {
  // 2-note alternation (the historical f2121 source) + chords
  const out: SplittableNote[] = []
  for (let bar = 0; bar < 6; bar++) {
    const t0 = bar * 2
    for (let i = 0; i < 8; i++) {
      out.push(N(i % 2 === 0 ? 60 : 67, t0 + i * 0.25, 0.22))
    }
    out.push({ midi: 48, on: t0, off: t0 + 1.8, hand: null }, { midi: 52, on: t0, off: t0 + 1.8, hand: null }, { midi: 55, on: t0, off: t0 + 1.8, hand: null })
  }
  return out
}

// ---- 1. raw planner baseline (no split) + 2. split-pinned -------------
async function runCase(
  name: string,
  build: () => SplittableNote[],
  passes?: (notes: SplittableNote[]) => number[][],
  passLimit = 0,
): Promise<void> {
  const raw = build()
  const rawPlan = await planOf(raw)
  const rawStats = fingerStats(raw, rawPlan)
  console.log(`\n=== ${name} ===`)
  console.log(`  raw planner: mid-run switches ${midRunSwitches(raw, rawPlan.hand)}  same-finger ${rawStats.sameFinger}  a-b-a-b runs ${rawStats.flipRuns}/${rawStats.runs}  thumb-on-black ${rawStats.thumbBlack}`)

  const pinned = build()
  for (let i = 0; i < pinned.length; i++) pinned[i].hand = null
  const ours = splitHands(pinned)
  for (let i = 0; i < pinned.length; i++) pinned[i].hand = ours[i]
  const plan = await planOf(pinned)
  const kept = pinned.filter((n, i) => plan.hand[i] === n.hand).length
  const stats = fingerStats(pinned, plan)
  check(`${name}: the planner keeps our hands (pin)`, kept === pinned.length, `${kept}/${pinned.length}`)
  if (passes) {
    const ps = passes(pinned)
    const worst = Math.max(0, ...ps.map((p) => passSwitches(p, plan.hand)))
    check(`${name}: ≤ ${passLimit} hand switch(es) per monotonic pass`, worst <= passLimit, `worst=${worst}`)
  } else {
    check(`${name}: 0 mid-run hand switches`, midRunSwitches(pinned, plan.hand) === 0, String(midRunSwitches(pinned, plan.hand)))
  }
  check(`${name}: no same-finger on stepwise pairs`, stats.sameFingerStep === 0, String(stats.sameFingerStep))
  const flipPct = stats.runs ? (100 * stats.flipRuns) / stats.runs : 0
  check(`${name}: a-b-a-b alternation ≤ 2% of stepwise runs`, flipPct <= 2, `${stats.flipRuns}/${stats.runs} = ${flipPct.toFixed(1)}%`)
  const altPct = stats.altTotal ? (100 * stats.altRuns) / stats.altTotal : 0
  check(`${name}: f2121 signature ≤ 2% of all same-hand runs`, altPct <= 2, `${stats.altRuns}/${stats.altTotal} = ${altPct.toFixed(1)}%`)
  console.log(
    `  split-pinned: same-finger step ${stats.sameFingerStep} leap ${stats.sameFingerLeap} [${stats.leapExamples.join('; ')}]  stepwise a-b-a-b ${stats.flipRuns}/${stats.runs}  all-runs f2121 ${stats.altRuns}/${stats.altTotal}`,
  )
}

const interlockBuild = () => caseInterlock().notes
await runCase('wide-span', caseWideSpan)
await runCase('interlock (sequential passes)', interlockBuild, (n) => caseInterlock().passes, 0)
await runCase('crossed sweeps (2 streams at once)', () => caseCrossed().notes, (n) => caseCrossed().passes, 1)
await runCase('tenor-melody', caseTenor)
await runCase('scale-with-bass', caseScale)
await runCase('2-note-ostinato', caseOstinato)

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
process.exit(failures ? 1 : 0)
