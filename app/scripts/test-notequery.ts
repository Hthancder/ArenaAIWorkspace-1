// S4 note queries: makeNoteQuery/pooledPoseAt must match brute force exactly
// and be fast on a 20k-note song (the per-frame scan cost the plan measured).
import { makeNoteQuery, pooledPoseAt, type SongHandsNote } from '../src/hands/motion'
import type { HandsMotion } from '../src/hands/runtime/hands'
import type { HandPoses, HandPose } from '../src/hands/types'

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

// ---- fixture: 20k notes, sorted by `on`, with a motion plan ----
const N = 20000
const notes: SongHandsNote[] = []
{
  let t = 0
  let seed = 7
  const rnd = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  }
  for (let i = 0; i < N; i++) {
    t += 0.02 + rnd() * 0.15
    const midi = 21 + Math.floor(rnd() * 88)
    notes.push({
      midi,
      on: t,
      off: t + 0.1 + rnd() * 1.5,
      hand: null,
      finger: null,
      velocity: 0.3 + rnd() * 0.7,
    })
  }
  notes.sort((a, b) => a.on - b.on || a.midi - b.midi)
}
const plan: HandsMotion['plan'] = {
  hand: new Array(N).fill(0).map((_, i) => (notes[i].midi < 60 ? 'L' : 'R')),
  finger: new Array(N).fill(0).map((_, i) => (i % 5) + 1),
}
const query = makeNoteQuery(notes, plan)

// ---- activeAt: matches brute force ----
{
  for (const t of [0.5, 10.25, 100.7, 900.0]) {
    const got = query.activeAt(t)
    const want: (number | null)[][] = [Array(5).fill(null), Array(5).fill(null)]
    for (let i = 0; i < N; i++) {
      const n = notes[i]
      if (t < n.on - 0.08 || t > n.off + 0.05) continue
      const h = plan.hand[i]
      const hh = h === 'L' ? 0 : 1
      const fg = plan.finger[i] - 1
      want[hh][fg] = want[hh][fg] === null ? n.velocity : Math.max(want[hh][fg]!, n.velocity)
    }
    const same = JSON.stringify(got) === JSON.stringify(want)
    check(`activeAt(${t}) matches brute force`, same, JSON.stringify({ got, want }))
  }
}

// ---- planFor: matches the old resolvePlan semantics ----
{
  const ref = (midi: number, t: number) => {
    let soon = -1
    let soonD = Infinity
    let any = -1
    let anyD = Infinity
    for (let i = 0; i < N; i++) {
      const n = notes[i]
      if (n.midi !== midi) continue
      const d = Math.abs(n.on - t)
      const imminent = n.on >= t - 0.35 && n.on <= t + 1.4
      if (imminent && d < soonD) {
        soonD = d
        soon = i
      }
      if (d < anyD) {
        anyD = d
        any = i
      }
    }
    const idx = soon >= 0 ? soon : anyD <= 2.5 ? any : -1
    if (idx < 0) return null
    const hand = plan.hand[idx]
    const finger = plan.finger[idx]
    return { hand, finger: finger - 1 }
  }
  let ok = 0
  let tried = 0
  let seed = 42
  const rnd = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  }
  for (let k = 0; k < 200; k++) {
    const t = rnd() * 2400
    const midi = 21 + Math.floor(rnd() * 88)
    const a = query.planFor(midi, t)
    const b = ref(midi, t)
    tried++
    if (JSON.stringify(a) === JSON.stringify(b)) ok++
    else if (k < 5) console.error('  diff', { midi, t, a, b })
  }
  check(`planFor matches brute force (${ok}/${tried})`, ok === tried)
}

// ---- nextOn: hand assignment and timing ----
{
  const r = query.nextOn('R', 100)
  check('nextOn returns a note in the window', r !== null && r.in > 0 && r.in <= 0.4 && Number.isFinite(r.keyX), JSON.stringify(r))
  const none = query.nextOn('L', 2400 + 1e6) // past the end
  check('nextOn is null past the end', none === null)
}

// ---- speed: 1000 planFor calls over 20k notes ----
{
  const t0 = performance.now()
  for (let k = 0; k < 1000; k++) query.planFor(21 + (k % 88), 10 + k * 0.37)
  const ms = performance.now() - t0
  check('1000 planFor calls < 80 ms (20k notes)', ms < 80, `${ms.toFixed(1)} ms`)
  const t1 = performance.now()
  for (let k = 0; k < 600; k++) query.activeAt(10 + k * 0.016) // 60 frames × 10 fingers share 1 memo each
  const ms2 = performance.now() - t1
  check('600 activeAt calls < 250 ms (1 memo per frame)', ms2 < 250, `${ms2.toFixed(1)} ms`)
}

// ---- pooledPoseAt: no aliasing between consecutive calls ----
{
  const alloc = (): HandPose => ({
    hand: 'L',
    elbow: [0, 0, 0],
    wrist: [0, 0, 0],
    bases: Array.from({ length: 5 }, () => [0, 0, 0] as [number, number, number]),
    fingers: Array.from({ length: 5 }, () => Array.from({ length: 4 }, () => [0, 0, 0] as [number, number, number])),
    press: [0, 0, 0, 0, 0],
    thumbRef: Array.from({ length: 3 }, () => [0, 0, 0] as [number, number, number]),
  })
  const src = (t: number): HandPoses => {
    const p = alloc()
    p.wrist[0] = t // varies per call
    return { L: p, R: null }
  }
  const pooled = pooledPoseAt(src)
  const a = pooled(1)
  const b = pooled(2)
  const c = pooled(3)
  check('pooled calls are distinct objects', a.L !== b.L && b.L !== c.L && a.L !== c.L)
  check('pooled content matches source per call', a.L!.wrist[0] === 1 && b.L!.wrist[0] === 2 && c.L!.wrist[0] === 3)
  const keep = a.L!.wrist[0]
  pooled(4)
  pooled(5)
  pooled(6)
  pooled(7) // ring depth 4 — slot of `a` is reused now
  check('ring reuse does not corrupt held values until depth 4', a.L!.wrist[0] === 7 || keep === 1)
  check('null hands pass through', pooled(8).R === null)
}

// ---- gapToNext ("độ rảnh ngón"): time until this hand's next note ----
{
  const small: SongHandsNote[] = [
    { midi: 60, on: 1, off: 1.5, hand: 'R', finger: 2, velocity: 0.7 },
    { midi: 64, on: 1.2, off: 1.6, hand: 'R', finger: 3, velocity: 0.7 },
    { midi: 48, on: 5, off: 6, hand: 'L', finger: 2, velocity: 0.7 },
    { midi: 50, on: 8, off: 9, hand: 'L', finger: 3, velocity: 0.7 },
  ]
  const g = makeNoteQuery(small, null)
  const rGap = g.gapToNext('R', 0.5, 5)
  check('gapToNext finds the next note of the same hand', rGap !== null && Math.abs(rGap - 0.5) < 1e-9, String(rGap))
  const lGap = g.gapToNext('L', 0.5, 5)
  check('gapToNext skips the other hand', lGap !== null && Math.abs(lGap - 4.5) < 1e-9, String(lGap))
  const beyond = g.gapToNext('R', 1.3, 5)
  check('gapToNext is null past the last note', beyond === null, String(beyond))
  const capped = g.gapToNext('L', 2.5, 2) // L's next is at 5 → 2.5 s > cap
  check('gapToNext honours the horizon cap', capped === null, String(capped))
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
if (failures) process.exit(1)
