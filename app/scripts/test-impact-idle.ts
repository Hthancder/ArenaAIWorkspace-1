/**
 * GĐ 6 — press impact + idle life ("tay chân thực hơn"), measured against
 * the ngưỡng đo the plan was approved with:
 *
 *   impact (defaults: handsImpact 0.5, expression 0.65, vel 0.75):
 *     - wrist jerk peak 2.0–3.2 mm DOWN within the first ~80 ms
 *     - rebound lobe ≤ 1.2 mm UP at 60–180 ms
 *     - settled |pulse| < 0.3 mm by 350 ms
 *   joint grip ("khớp co co"):
 *     - swing overshoot 0.02–0.045 rad past the press angle within 80 ms
 *     - decayed < 0.005 rad by 350 ms
 *   contact wobble ("vị trí nhấn dao động nhỏ"):
 *     - per-finger swing jitter std 0.001–0.0045 rad (≈0.06–0.28 mm tip)
 *       while the key is held, oscillating (tremor band), absent at impact 0
 *   idle life ("độ rảnh", defaults: handsIdleLife 0.5):
 *     - free ≥1 s: wrist breath 1.0–3.0 mm peak-to-peak, slow (≥1.2 s period)
 *     - free ≥1 s: finger lift travel 2.0–4.0 mm (3D span, tip rel. wrist),
 *       no idle component beyond 4 mm
 *     - fast presses (< 0.5 s apart): idleW stays ≈ 0 (≤ 0.1)
 *     - a fresh key-down kills idle within 0.3 s (idleW ≤ 0.15)
 *     - a FROZEN look-ahead (Wait gate / pause) must not suppress idle —
 *       the wait itself is the user's free time (wall clock wins)
 *   plus: rigid bone lengths, repeat presses each get their own jerk.
 *
 * Run: `npx vite-node scripts/test-impact-idle.ts`
 */

// ---- minimal browser shims (module scope runs before dynamic imports) ----
class FakeParam {
  value = 0
  setValueAtTime() {}
  linearRampToValueAtTime() {}
  exponentialRampToValueAtTime() {}
  setTargetAtTime() {}
  cancelScheduledValues() {}
  cancelAndHoldAtTime() {}
}
;(globalThis as unknown as { AudioParam: unknown }).AudioParam = FakeParam
class FakeScheduledSource {
  start() {}
  stop() {}
  connect() {}
  disconnect() {}
}
;(globalThis as unknown as { AudioScheduledSourceNode: unknown }).AudioScheduledSourceNode = FakeScheduledSource
class FakeCtx {
  state = 'running'
  currentTime = 0
  baseLatency = 0
  outputLatency = 0
  destination = {}
  sampleRate = 48000
  resume() {
    return Promise.resolve()
  }
  suspend() {
    return Promise.resolve()
  }
  close() {
    return Promise.resolve()
  }
  createGain() {
    return {
      gain: { value: 1, setValueAtTime() {}, linearRampToValueAtTime() {}, setTargetAtTime() {}, cancelScheduledValues() {}, cancelAndHoldAtTime() {} },
      connect() {},
      disconnect() {},
    }
  }
  createBuffer() {
    return { getChannelData: () => new Float32Array(1), duration: 0 }
  }
  createBufferSource() {
    return { start() {}, stop() {}, connect() {}, disconnect() {}, buffer: null, playbackRate: { value: 1 } }
  }
}
;(globalThis as unknown as { AudioContext: unknown }).AudioContext = FakeCtx
;(globalThis as unknown as { webkitAudioContext: unknown }).webkitAudioContext = FakeCtx
;(globalThis as unknown as { OfflineAudioContext: unknown }).OfflineAudioContext = FakeCtx
if (typeof (globalThis as unknown as { window?: unknown }).window === 'undefined') {
  ;(globalThis as unknown as { window: unknown }).window = globalThis
}
const store = new Map<string, string>([
  ['nf:dev', '1'],
  ['nf:dev:noaudio', '1'],
])
;(globalThis as unknown as { localStorage: unknown }).localStorage = {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => void store.set(k, v),
  removeItem: (k: string) => void store.delete(k),
}

const { audioEngine } = await import('../src/audio/engine')
const { liveHands } = await import('../src/hands/liveHands')
const { neutralHandPose } = await import('../src/hands/neutralPose')
import type { HandPose, HandPoses } from '../src/hands/types'
import type { LiveHandsOpts } from '../src/hands/liveHands'

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

// Deterministic frame clock — liveHands reads performance.now() itself.
let fakeMs = 0
;(performance as unknown as { now: () => number }).now = () => fakeMs

const tplL = neutralHandPose('L')
const tplR = neutralHandPose('R')
function freshSource(): HandPoses {
  return { L: structuredClone(tplL), R: structuredClone(tplR) }
}

function opts(extra: Partial<LiveHandsOpts> = {}): LiveHandsOpts {
  return {
    playing: false,
    keystrike: 0.6,
    expression: 0.65,
    resolvePlan: (midi) => (midi === 72 ? { hand: 'R', finger: 1 } : null),
    expressAt: () => null,
    sampleHand: (hand) => neutralHandPose(hand),
    ...extra,
  }
}

/** One 60 fps frame on raw poses (no humanizer — measure liveHands alone). */
function frame(o: LiveHandsOpts): HandPoses {
  fakeMs += 16.7
  const poses = freshSource()
  liveHands.update(poses, o)
  return poses
}

const relTip = (p: HandPose, f: number) =>
  [p.fingers[f][3][0] - p.wrist[0], p.fingers[f][3][1] - p.wrist[1], p.fingers[f][3][2] - p.wrist[2]] as const

const boneSpread = (p: HandPose): number => {
  let s = 0
  const d = (a: number[], b: number[]) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])
  s += d(p.elbow, p.wrist)
  for (const ch of p.fingers) {
    for (let j = 1; j < 4; j++) s += d(ch[j - 1], ch[j])
  }
  return s
}

liveHands.attach()
liveHands.reset()

// ---- 1. press impact: the wrist jerks down and rebounds once ----------
console.log('press impact: wrist dip 2.0–3.2 mm, rebound ≤ 1.2 mm, settled by 350 ms')
{
  liveHands.reset()
  const o = opts({ idle: 0 }) // isolate impact
  for (let i = 0; i < 4; i++) frame(o)
  const h = audioEngine.triggerKey(72, 0.75)
  const wrist: number[] = []
  for (let i = 0; i < 24; i++) {
    frame(o)
    wrist.push(liveHands.impactDebug('R').wrist * 100) // units → mm
  }
  h?.release()
  const dip = Math.min(...wrist.slice(0, 5)) // first ~80 ms
  const rebound = Math.max(...wrist.slice(5, 11)) // ~80–190 ms
  const settled = Math.abs(wrist[21]) // ~350 ms
  check('dip peak is 2.0–3.2 mm DOWN', dip <= -2.0 && dip >= -3.2, `${dip.toFixed(2)} mm`)
  check('rebound lobe is 0–1.2 mm UP', rebound > 0 && rebound <= 1.2, `${rebound.toFixed(2)} mm`)
  check('pulse settled < 0.3 mm by 350 ms', settled < 0.3, `${settled.toFixed(3)} mm`)
}

// ---- 2. joint grip: swing curls past the press angle, then eases ------
console.log('joint grip: overshoot 0.02–0.045 rad within 80 ms, < 0.005 rad by 350 ms')
{
  liveHands.reset()
  const o = opts({ idle: 0 })
  for (let i = 0; i < 4; i++) frame(o)
  const h = audioEngine.triggerKey(72, 0.75)
  const grip: number[] = []
  for (let i = 0; i < 24; i++) {
    frame(o)
    grip.push(liveHands.impactDebug('R').grip[1]) // finger 1 = the planned finger
  }
  h?.release()
  const peak = Math.min(...grip.slice(0, 5)) // negative = curl past press
  const settled = Math.abs(grip[21])
  check('grip overshoot 0.02–0.045 rad', peak <= -0.02 && peak >= -0.045, `${peak.toFixed(4)} rad`)
  check('grip decayed < 0.005 rad by 350 ms', settled < 0.005, `${settled.toFixed(4)} rad`)
}

// ---- 3. contact wobble: the press point shivers while held ------------
console.log('contact wobble: std 0.001–0.0045 rad while held, oscillating, off at impact 0')
{
  liveHands.reset()
  const o = opts({ idle: 0 })
  for (let i = 0; i < 4; i++) frame(o)
  const h = audioEngine.triggerKey(72, 0.75)
  const wob: number[] = []
  for (let i = 0; i < 60; i++) {
    frame(o)
    if (i >= 12) wob.push(liveHands.impactDebug('R').wob[1]) // after the impact pulse
  }
  h?.release()
  const mean = wob.reduce((a, b) => a + b, 0) / wob.length
  const std = Math.sqrt(wob.reduce((a, b) => a + (b - mean) ** 2, 0) / wob.length)
  let flips = 0
  for (let i = 1; i < wob.length; i++) if (Math.sign(wob[i] - mean) !== Math.sign(wob[i - 1] - mean)) flips++
  check('wobble std 0.001–0.0045 rad (≈0.06–0.28 mm at tip)', std >= 0.001 && std <= 0.0045, `${std.toFixed(5)} rad`)
  check('wobble oscillates (≥ 4 sign flips over 0.8 s)', flips >= 4, `${flips}`)

  // Control: impact = 0 must remove the wobble entirely.
  liveHands.reset()
  const o0 = opts({ idle: 0, impact: 0 })
  for (let i = 0; i < 4; i++) frame(o0)
  const h0 = audioEngine.triggerKey(72, 0.75)
  let wobMax = 0
  for (let i = 0; i < 24; i++) {
    frame(o0)
    wobMax = Math.max(wobMax, Math.abs(liveHands.impactDebug('R').wob[1]), Math.abs(liveHands.impactDebug('R').grip[1]), Math.abs(liveHands.impactDebug('R').wrist))
  }
  h0?.release()
  check('impact 0 removes jerk, grip AND wobble', wobMax < 1e-5, `${wobMax.toExponential(2)}`)
}

// ---- 4. repeat presses: each key-down gets its own jerk ---------------
console.log('repeat presses: every key-down jerks (no dead repeats)')
{
  liveHands.reset()
  const o = opts({ idle: 0 })
  for (let i = 0; i < 4; i++) frame(o)
  const dips: number[] = []
  for (let r = 0; r < 3; r++) {
    const h = audioEngine.triggerKey(72, 0.75)
    let d = 0
    for (let i = 0; i < 8; i++) {
      frame(o)
      d = Math.min(d, liveHands.impactDebug('R').wrist * 100)
    }
    h?.release()
    dips.push(d)
    for (let i = 0; i < 10; i++) frame(o) // settle between repeats
  }
  check('each repeat dips ≥ 2.0 mm', dips.every((d) => d <= -2.0), dips.map((d) => d.toFixed(2)).join(', '))
}

// ---- 5. idle life: breathing + slow finger lifts while free ----------
console.log('idle life: breath 1–3 mm pp, finger lifts 2–4 mm, nothing beyond 4 mm')
{
  liveHands.reset()
  // A DECLINING look-ahead reads as an advancing playhead (real playback).
  const t0 = fakeMs / 1000
  const o = opts({ impact: 0, gapToNext: () => Math.max(0, 3.5 - (fakeMs / 1000 - t0)) })
  const wristY: number[] = []
  const relY: number[] = []
  const dev: number[] = []
  const rels: [number, number, number][] = []
  for (let i = 0; i < 360; i++) {
    const p = frame(o)
    const r = p.R!
    if (i >= 60) {
      // last 5 s — the idle weight has settled
      wristY.push(r.wrist[1] * 100)
      const rt = relTip(r, 1)
      rels.push(rt)
      relY.push(rt[1] * 100)
    }
  }
  const pp = (xs: number[]) => Math.max(...xs) - Math.min(...xs)
  check('wrist breath peak-to-peak 1.0–3.0 mm', pp(wristY) >= 1.0 && pp(wristY) <= 3.0, `${pp(wristY).toFixed(2)} mm`)
  // breath period ≥ 1.2 s: count local maxima of wristY over the 5 s window
  let peaks = 0
  for (let i = 1; i < wristY.length - 1; i++) if (wristY[i] > wristY[i - 1] && wristY[i] >= wristY[i + 1]) peaks++
  check('breath is slow (≤ 4 peaks over 5 s → ≥ 1.2 s period)', peaks <= 4, `${peaks} peaks`)
  // The lift is a joint rotation — measure its 3D travel span (mm), not
  // one axis: the swing arc carries the tip along the finger's plane.
  let span = 0
  for (const a of rels) for (const b of rels) span = Math.max(span, Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]) * 100)
  check('finger lift travel 2.0–4.0 mm (3D span, tip rel. wrist)', span >= 2.0 && span <= 4.0, `${span.toFixed(2)} mm`)
  const meanRel = [0, 1, 2].map((k) => rels.reduce((a, b) => a + b[k], 0) / rels.length)
  const maxDev = Math.max(
    ...rels.map((rt) => Math.hypot(rt[0] - meanRel[0], rt[1] - meanRel[1], rt[2] - meanRel[2]) * 100),
  )
  check('no idle motion beyond 4 mm (max deviation from mean)', maxDev <= 4.0, `${maxDev.toFixed(2)} mm`)
}

// ---- 6. idle stays OFF while the hand is busy (fast presses) ---------
console.log('fast presses (< 0.5 s apart): idle stays off')
{
  liveHands.reset()
  const t0 = fakeMs / 1000
  const o = opts({ impact: 0, gapToNext: () => Math.max(0, 0.3 - (fakeMs / 1000 - t0)) })
  let idleMax = 0
  for (let i = 0; i < 18; i++) {
    const h = audioEngine.triggerKey(72, 0.75)
    frame(o)
    idleMax = Math.max(idleMax, liveHands.impactDebug('R').idleW)
    frame(o)
    h?.release()
    frame(o)
  }
  check('idleW stays ≤ 0.1 during a fast passage', idleMax <= 0.1, `${idleMax.toFixed(3)}`)
}

// ---- 7. a fresh key-down kills idle fast (press reads clean) ---------
console.log('key-down fades idle out within 0.3 s')
{
  liveHands.reset()
  const t0 = fakeMs / 1000
  const o = opts({ impact: 0, gapToNext: () => Math.max(0, 3.5 - (fakeMs / 1000 - t0)) })
  for (let i = 0; i < 120; i++) frame(o) // 2 s of free time → idle on
  const before = liveHands.impactDebug('R').idleW
  check('idle is up after 2 s free (idleW > 0.3)', before > 0.3, `${before.toFixed(3)}`)
  const h = audioEngine.triggerKey(72, 0.75)
  for (let i = 0; i < 18; i++) frame(o) // 0.3 s
  const after = liveHands.impactDebug('R').idleW
  h?.release()
  check('idleW ≤ 0.15 within 0.3 s of the key-down', after <= 0.15, `${after.toFixed(3)}`)
}

// ---- 8. frozen look-ahead (Wait gate / pause): wall clock wins --------
console.log('frozen look-ahead at a Wait gate: the wait itself is free time')
{
  liveHands.reset()
  const o = opts({ impact: 0, gapToNext: () => 0.05 }) // CONSTANT = frozen playhead
  for (let i = 0; i < 180; i++) frame(o) // 3 s of waiting
  const idleW = liveHands.impactDebug('R').idleW
  check('idle still activates (idleW > 0.4) despite the frozen gap', idleW > 0.4, `${idleW.toFixed(3)}`)
}

// ---- 9. rigid: rotations never bend or stretch a bone -----------------
console.log('rigid: bone lengths exact through impact + idle')
{
  liveHands.reset()
  const t0 = fakeMs / 1000
  const o = opts({ gapToNext: () => Math.max(0, 3.5 - (fakeMs / 1000 - t0)) })
  for (let i = 0; i < 4; i++) frame(o)
  const before = boneSpread(freshSource().R!) // the template, not the pose
  const h = audioEngine.triggerKey(72, 0.75)
  let worst = 0
  for (let i = 0; i < 240; i++) {
    const p = frame(o)
    worst = Math.max(worst, Math.abs(boneSpread(p.R!) - before))
  }
  h?.release()
  check('bone-length sum drift < 1e-6 units', worst < 1e-6, `${worst.toExponential(2)}`)
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
if (failures) process.exit(1)
process.exit(0)
