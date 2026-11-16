/**
 * Determinism + sanity tests for the hand-motion humanizer
 * (src/hands/humanize.ts). The hard requirement is that the pass is a
 * PURE function of t — the exporter frame-steps the scene and must draw
 * exactly what the preview shows.
 *
 * Run: `npx tsx scripts/test-humanize.ts`
 */
import {
  createHumanizeScratch,
  humanizePoses,
  type HumanizeParams,
} from '../src/hands/humanize'
import { rotateAbout } from '../src/hands/geom'
import type { HandPose, HandPoses } from '../src/hands/types'

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

function makePose(hand: 'L' | 'R', x: number): HandPose {
  return {
    hand,
    elbow: [x, -3, 0.5],
    wrist: [x, -2, 0.6],
    bases: Array.from({ length: 5 }, (_, i) => [x + i * 0.1, -1.5, 0.7] as [number, number, number]),
    fingers: Array.from({ length: 5 }, (_, i) =>
      Array.from({ length: 4 }, (_, k) => [x + i * 0.1, -1 + k * 0.2, 0.8] as [number, number, number]),
    ),
    press: [0, 0, 0, 0, 0],
    // 3 twist references — mirrors the real runtime (fkThumbRefs = 9
    // floats; meshHand reads thumbRef[Math.min(ci, 2)]).
    thumbRef: [
      [x, -1.4, 0.7],
      [x, -1.2, 0.75],
      [x, -1.0, 0.8],
    ],
  }
}

// Source: right hand slides linearly at 1 unit/s along x; left absent.
const src = (t: number): HandPoses => ({ L: null, R: makePose('R', t) })

const p: HumanizeParams = { enabled: true, smoothness: 1, microMotion: 0 }

console.log('purity: same t → identical output')
{
  const s1 = createHumanizeScratch()
  const s2 = createHumanizeScratch()
  const a = humanizePoses(src, 3.7, p, s1)
  const b = humanizePoses(src, 3.7, p, s2)
  const va = JSON.stringify(a.R)
  const vb = JSON.stringify(b.R)
  check('bit-identical across scratch buffers', va === vb)
  const a2 = humanizePoses(src, 3.7, p, s1)
  check('bit-identical across repeated calls', JSON.stringify(a2.R) === va)
}

console.log('lag: humanized trail the source on a linear move')
{
  const s = createHumanizeScratch()
  const out = humanizePoses(src, 5, p, s)
  // Linear motion x(t)=t: B=5−τ, C=5−2τ (τ = 0.055); the settle overshoot
  // is CAPPED at 3 mm (SETTLE_CAP) so a fast arrival springs, not jumps —
  // net lag = τ − 0.003.
  check('wrist net lag ≈ τ − settle cap', Math.abs(out.R!.wrist[0] - (5 - 0.055 + 0.003)) < 0.005, `${out.R!.wrist[0]}`)
  check('finger joints stay fresher than wrist', out.R!.fingers[2][3][0] > out.R!.wrist[0])
}

console.log('micro-motion: bounded tremor, off = none')
{
  // NB: separate scratch buffers — humanizePoses returns scratch.out, so
  // two calls on ONE scratch alias the same object.
  let maxD = 0
  let allZero = true
  for (let t = 0; t <= 2; t += 0.1) {
    const off = humanizePoses(src, t, { enabled: true, smoothness: 1, microMotion: 0 }, createHumanizeScratch())
    const on = humanizePoses(src, t, { enabled: true, smoothness: 1, microMotion: 1 }, createHumanizeScratch())
    const d = Math.abs(on.R!.wrist[0] - off.R!.wrist[0])
    maxD = Math.max(maxD, d)
    if (d > 1e-4) allZero = false
    check(`tremor bounded at t=${t.toFixed(1)}`, d < 0.03, `${d}`)
  }
  check('tremor actually moves the wrist somewhere', !allZero, `maxD=${maxD}`)
}

console.log('pass-through: disabled copies the raw pose')
{
  const s = createHumanizeScratch()
  const out = humanizePoses(src, 2, { enabled: false, smoothness: 1, microMotion: 1 }, s)
  check('exact raw value', out.R!.wrist[0] === 2, `${out.R!.wrist[0]}`)
  check('left stays null', out.L === null)
}

console.log('smoothness 0 → no lag')
{
  const s = createHumanizeScratch()
  const out = humanizePoses(src, 5, { enabled: true, smoothness: 0, microMotion: 0 }, s)
  check('wrist at the raw position', Math.abs(out.R!.wrist[0] - 5) < 1e-9, `${out.R!.wrist[0]}`)
}

console.log('bone safety: fast motion never warps bone chains (2026-11-15 "méo mó")')
{
  // The source curls / uncurls every finger 18×/s around its base —
  // RIGID rotations, so its bone lengths are constant, but the two
  // configurations are very different 55 ms apart. The old per-joint
  // position blend warped chains badly here (average of curled+straight
  // is a shorter chain). The bone-safe blend keeps every segment at its
  // source length: directions blend, lengths do not.
  const snapSrc = (t: number): HandPoses => {
    const pose = makePose('R', 1)
    if (Math.floor(t * 18) % 2 === 0) {
      for (let f = 0; f < 5; f++) rotateAbout(pose.bases[f], [1, 0, 0], 0.45, pose.fingers[f])
    }
    return { L: null, R: pose }
  }
  const ref = makePose('R', 1)
  const s = createHumanizeScratch()
  let maxErr = 0
  for (let t = 0; t < 1; t += 0.007) {
    const out = humanizePoses(snapSrc, t, { enabled: true, smoothness: 1, microMotion: 0.5 }, s)
    const pose = out.R!
    for (let f = 0; f < 5; f++) {
      const segs: [number[], number[]][] = [
        [pose.wrist, pose.bases[f]],
        [pose.bases[f], pose.fingers[f][0]],
        [pose.fingers[f][0], pose.fingers[f][1]],
        [pose.fingers[f][1], pose.fingers[f][2]],
        [pose.fingers[f][2], pose.fingers[f][3]],
      ]
      const refSegs: [number[], number[]][] = [
        [ref.wrist, ref.bases[f]],
        [ref.bases[f], ref.fingers[f][0]],
        [ref.fingers[f][0], ref.fingers[f][1]],
        [ref.fingers[f][1], ref.fingers[f][2]],
        [ref.fingers[f][2], ref.fingers[f][3]],
      ]
      segs.forEach(([p0, p1], i) => {
        const [r0, r1] = refSegs[i]
        const len = Math.hypot(p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
        const refLen = Math.hypot(r1[0] - r0[0], r1[1] - r0[1], r1[2] - r0[2])
        maxErr = Math.max(maxErr, Math.abs(len - refLen))
      })
    }
  }
  check('every bone within 1 mm of its source length', maxErr < 0.01, `${maxErr}`)
}

console.log('meshHand contract: thumbRef must survive the pass')
{
  // meshHand reads p.thumbRef[Math.min(e.ci, 2)] — index 2! A shorter
  // array threw inside mesh.update and froze the whole frame loop
  // (2026-11-15 incident). Guard the contract on BOTH paths.
  for (const p of [
    { enabled: true, smoothness: 1, microMotion: 0.5 },
    { enabled: false, smoothness: 1, microMotion: 1 },
  ] as const) {
    const out = humanizePoses(src, 3.7, p, createHumanizeScratch())
    const tr = out.R!.thumbRef
    check(`thumbRef length 3 (enabled=${p.enabled})`, tr.length === 3, `${tr.length}`)
    check(`thumbRef[2] readable (enabled=${p.enabled})`, !!tr[2] && tr[2].length === 3)
    check(`press length 5 (enabled=${p.enabled})`, out.R!.press.length === 5)
  }
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
process.exit(failures === 0 ? 0 : 1)
