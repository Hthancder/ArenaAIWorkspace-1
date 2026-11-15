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
    thumbRef: [
      [x, -1.4, 0.7],
      [x, -1.2, 0.75],
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
  // Linear motion x(t)=t: B=5−τ, C=5−2τ (τ = 0.055), settle adds
  // 0.45·(B−C) = 0.45·τ → net lag = τ·(1−0.45) ≈ 0.03025.
  check('wrist net lag ≈ τ·(1−settle)', Math.abs(out.R!.wrist[0] - (5 - 0.055 * 0.55)) < 0.005, `${out.R!.wrist[0]}`)
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

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
process.exit(failures === 0 ? 0 : 1)
