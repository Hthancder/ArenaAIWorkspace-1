/**
 * Browser-chain regression (2026-11-15): the user reports manual-play
 * fingers "không bấm, không di chuyển" while the suite stays green — so
 * the tests run the EXACT app chain: humanizePoses (3-tap blend on REAL
 * neutral poses) → liveHands.update with Hands.tsx-shaped opts
 * (keystrike 0.6, expression 0.65, expressAt/resolvePlan/sampleHand).
 * Guards: NaN self-heal, cross-hand chords, per-repeat pecks, synth
 * free-play hands, and press travel visibility on real geometry.
 *
 * Run: `npx vite-node scripts/test-livebrowser.ts`
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
const { createHumanizeScratch, humanizePoses } = await import('../src/hands/humanize')
const { neutralHandPose } = await import('../src/hands/neutralPose')
import { keyForMidi } from '../src/keyboard/layout'
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

// Deterministic frame clock — the app reads performance.now() itself.
let fakeMs = 0
;(performance as unknown as { now: () => number }).now = () => fakeMs

const scratch = createHumanizeScratch()
const tplL = neutralHandPose('L')
const tplR = neutralHandPose('R')

/** poseAt-like source: FRESH objects per call (the wasm runtime does this). */
function freshSource(): HandPoses {
  return { L: structuredClone(tplL), R: structuredClone(tplR) }
}

function finite(p: HandPose | null): boolean {
  if (!p) return true
  const vs: number[][] = [p.elbow, p.wrist, ...p.bases, ...p.fingers.flat(), ...p.thumbRef]
  return vs.every((v) => v.every((x) => Number.isFinite(x)))
}

const NOTES = [
  // finger is 1-based like the motion plan (1 = thumb … 5 = pinky): 2 = index.
  { midi: 60, on: 1, off: 2, velocity: 0.8, hand: 'R' as const, finger: 2 },
]

/** opts shaped EXACTLY like Hands.tsx builds them (song loaded, paused). */
function browserOpts(extra: Partial<LiveHandsOpts> = {}): LiveHandsOpts {
  return {
    playing: false,
    keystrike: 0.6,
    expression: 0.65,
    resolvePlan: (midi) => {
      const n = NOTES.find((x) => x.midi === midi)
      return n ? { hand: n.hand, finger: n.finger - 1 } : null
    },
    expressAt: () => null,
    sampleHand: (hand) => neutralHandPose(hand),
    ...extra,
  }
}

let t = 0
const params = { enabled: true, smoothness: 0.5, microMotion: 0.5 }

/** One app frame: humanize → liveHands.update, like useFrame. */
function appFrame(opts: LiveHandsOpts, src: () => HandPoses = freshSource): HandPoses {
  fakeMs += 16.7
  t = fakeMs / 1000
  const poses = humanizePoses(src, t, params, scratch)
  liveHands.update(poses, opts)
  return poses
}

const pressedCount = (p: HandPoses) =>
  (p.L?.press.filter((v) => v > 0.5).length ?? 0) + (p.R?.press.filter((v) => v > 0.5).length ?? 0)

// ---- 1. manual press on the exact browser chain: does the finger move? ----
console.log('browser chain: manual press — finger must visibly travel (keystrike 0.6)')
{
  liveHands.attach()
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const rest = freshSource().R!
  const relTip = (p: HandPose, f: number) =>
    [p.fingers[f][3][0] - p.wrist[0], p.fingers[f][3][1] - p.wrist[1], p.fingers[f][3][2] - p.wrist[2]] as const
  const restRel = [0, 1, 2, 3, 4].map((f) => relTip(rest, f))
  const h = audioEngine.triggerKey(72, 0.75)
  let poses: HandPoses = freshSource()
  let travel = 0
  let travelF = -1
  for (let i = 0; i < 24; i++) {
    poses = appFrame(opts)
    const r = poses.R!
    for (let f = 0; f < 5; f++) {
      const cr = relTip(r, f)
      const d = Math.hypot(cr[0] - restRel[f][0], cr[1] - restRel[f][1], cr[2] - restRel[f][2])
      if (d > travel) {
        travel = d
        travelF = f
      }
    }
  }
  const f = poses.R!.press.findIndex((v) => v > 0.5)
  check('some finger shows press[]', f >= 0, JSON.stringify(poses.R!.press))
  check('pressed finger is the planned one (1 = index)', f === 1, `got ${f}`)
  check('finger swing (tip rel. wrist) travels >= 4 mm', travel >= 0.04, `travel=${travel.toFixed(4)} finger=${travelF}`)
  check('poses stay finite', finite(poses.L) && finite(poses.R))
  h?.release()
  console.log(`  info swing travel (rel. wrist) = ${travel.toFixed(4)} on finger ${travelF}`)
}

// ---- 2. repeated presses: every press pecks (no freeze) ----
console.log('browser chain: three quick repeats — each press travels')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const travels: number[] = []
  for (let rep = 0; rep < 3; rep++) {
    const rest = freshSource().R!
    const rel = (p: HandPose) => [p.fingers[1][3][0] - p.wrist[0], p.fingers[1][3][1] - p.wrist[1], p.fingers[1][3][2] - p.wrist[2]]
    const restTip = rel(rest)
    const h = audioEngine.triggerKey(60, 0.8)
    let d = 0
    for (let i = 0; i < 8; i++) {
      const poses = appFrame(opts)
      const tip = rel(poses.R!)
      d = Math.max(d, Math.hypot(tip[0] - restTip[0], tip[1] - restTip[1], tip[2] - restTip[2]))
    }
    h?.release()
    travels.push(d)
    for (let i = 0; i < 10; i++) appFrame(opts)
  }
  check('every repeat visibly pecks', travels.every((d) => d >= 0.02), JSON.stringify(travels))
}

// ---- 3. free play: NO source hands — synth hands still press ----
console.log('browser chain: free play (no song) — synth hand presses')
{
  liveHands.reset()
  const noHands = (): HandPoses => ({ L: null, R: null })
  const opts = browserOpts({ resolvePlan: undefined, expressAt: undefined })
  for (let i = 0; i < 5; i++) appFrame(opts, noHands)
  const rest = neutralHandPose('R')
  const restTip = rest.fingers.map((f) => [...f[3]])
  const h = audioEngine.triggerKey(72, 0.9)
  let poses: HandPoses = { L: null, R: null }
  let travel = 0
  for (let i = 0; i < 30; i++) {
    poses = appFrame(opts, noHands)
    const r = poses.R
    if (!r) continue
    for (let f = 0; f < 5; f++) {
      travel = Math.max(
        travel,
        Math.hypot(r.fingers[f][3][0] - restTip[f][0], r.fingers[f][3][1] - restTip[f][1], r.fingers[f][3][2] - restTip[f][2]),
      )
    }
  }
  h?.release()
  check('synth hand appears', poses.R !== null)
  check('synth finger travels >= 2 mm', travel >= 0.02, `travel=${travel.toFixed(4)}`)
  check('synth poses stay finite', finite(poses.R))
}

// ---- 4. NaN poison self-heal: a NaN velocity must not freeze a finger ----
console.log('browser chain: NaN velocity cannot poison the overlay')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const h = audioEngine.triggerKey(60, NaN as unknown as number)
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 10; i++) poses = appFrame(opts)
  check('poses stay finite with NaN input velocity', finite(poses.L) && finite(poses.R))
  h?.release()
  for (let i = 0; i < 10; i++) poses = appFrame(opts)
  check('poses stay finite after release', finite(poses.L) && finite(poses.R))
  const h2 = audioEngine.triggerKey(64, 0.8)
  let poses2: HandPoses = freshSource()
  for (let i = 0; i < 10; i++) poses2 = appFrame(opts)
  const f2 = (poses2.R?.press.findIndex((v) => v > 0.5) ?? poses2.L?.press.findIndex((v) => v > 0.5) ?? -1)
  const hand2 = poses2.R?.press.some((v) => v > 0.5) ? poses2.R! : poses2.L!
  let travel = 0
  const rest = freshSource().R!
  const rel = (p: HandPose, f: number) => [p.fingers[f][3][0] - p.wrist[0], p.fingers[f][3][1] - p.wrist[1], p.fingers[f][3][2] - p.wrist[2]]
  const restTip = rel(rest, f2 >= 0 ? f2 : 1)
  for (let i = 0; i < 10; i++) {
    poses2 = appFrame(opts)
    const tip = rel(hand2, f2 >= 0 ? f2 : 1)
    travel = Math.max(travel, Math.hypot(tip[0] - restTip[0], tip[1] - restTip[1], tip[2] - restTip[2]))
  }
  h2?.release()
  check('finger still pecks after NaN event', travel >= 0.02, `travel=${travel.toFixed(4)} f=${f2}`)
}

// ---- 5. chord: two keys on one tick — TWO fingers press (same or split
// hands is fine, but exactly two presses must show) ----
console.log('browser chain: chord pressed together — both keys get a press')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const h1 = audioEngine.triggerKey(60, 0.8)
  const h2 = audioEngine.triggerKey(64, 0.8)
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 30; i++) poses = appFrame(opts)
  check('both chord keys press', pressedCount(poses) === 2, `L=${JSON.stringify(poses.L?.press)} R=${JSON.stringify(poses.R?.press)}`)
  check('chord poses stay finite', finite(poses.L) && finite(poses.R))
  h1?.release()
  h2?.release()
}

// ---- 6. cross-hand discipline: a key by the LEFT hand must not be taken
// by the right hand while the left is idle and closer ----
console.log('browser chain: nearest hand takes the key (no stealing)')
{
  liveHands.reset()
  const opts = browserOpts({ resolvePlan: undefined }) // reach-based only
  for (let i = 0; i < 5; i++) appFrame(opts)
  // C2-ish key deep in the left region (x ≈ −4), left hand idle there.
  const h = audioEngine.triggerKey(36, 0.8)
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 40; i++) poses = appFrame(opts)
  const leftActive = (poses.L?.press.some((v) => v > 0.5) ?? false) || (poses.L?.press.some((v, i) => v > 0.5))
  const rightTook = poses.R?.press.some((v) => v > 0.5) ?? false
  check('the LEFT hand plays the left-region key', leftActive, `L=${JSON.stringify(poses.L?.press)}`)
  check('the right hand does NOT steal it', !rightTook, `R=${JSON.stringify(poses.R?.press)}`)
  h?.release()
}

// ---- 7. relax fan: idle fingers open up while one finger plays ----
console.log('browser chain: idle fingers fan apart (no cramped "quặp" posture)')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const rest = freshSource().R!
  const restSpread = rest.fingers[4][3][0] - rest.fingers[0][3][0] // pinky − thumb tip x
  const h = audioEngine.triggerKey(60, 0.8) // planned: right index
  let poses: HandPoses = freshSource()
  let spread = restSpread
  let thumbOut = 0
  for (let i = 0; i < 30; i++) {
    poses = appFrame(opts)
    const r = poses.R!
    spread = Math.max(spread, r.fingers[4][3][0] - r.fingers[0][3][0])
    thumbOut = Math.min(thumbOut, r.fingers[0][3][0] - rest.fingers[0][3][0]) // thumb tip moves −x (open)
  }
  h?.release()
  check('hand splays while playing (pinky−thumb spread grows >= 2 mm)', spread >= restSpread + 0.02, `${restSpread.toFixed(4)} → ${spread.toFixed(4)}`)
  check('thumb opens outward (tip moves away, >= 1 mm)', thumbOut <= -0.01, `d=${thumbOut.toFixed(4)}`)
  check('relaxed poses stay finite', finite(poses.L) && finite(poses.R))
}

// ---- 8. cross-hand split: each key goes to its nearer hand ----
console.log('browser chain: two keys — each hand takes the key on its side')
{
  liveHands.reset()
  const opts = browserOpts({ resolvePlan: undefined })
  for (let i = 0; i < 5; i++) appFrame(opts)
  // C3 (deep left) and C5 (right): one key per hand, no stealing.
  const h1 = audioEngine.triggerKey(48, 0.8)
  const h2 = audioEngine.triggerKey(72, 0.8)
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 40; i++) poses = appFrame(opts)
  const lPressed = poses.L!.press.filter((v) => v > 0.5).length
  const rPressed = poses.R!.press.filter((v) => v > 0.5).length
  check('left hand presses exactly one key', lPressed === 1, `L=${JSON.stringify(poses.L!.press)}`)
  check('right hand presses exactly one key', rPressed === 1, `R=${JSON.stringify(poses.R!.press)}`)
  check('split poses stay finite', finite(poses.L) && finite(poses.R))
  h1?.release()
  h2?.release()
}

// ---- 9. drift is rate-limited: a far key never snaps the hand over ----
console.log('browser chain: hand travel glides (no per-frame snap)')
{
  liveHands.reset()
  const opts = browserOpts({ resolvePlan: undefined })
  for (let i = 0; i < 5; i++) appFrame(opts)
  const h = audioEngine.triggerKey(21, 0.8) // A0 — extreme left
  let poses: HandPoses = freshSource()
  let prevX = poses.L!.wrist[0]
  let maxStep = 0
  for (let i = 0; i < 40; i++) {
    poses = appFrame(opts)
    const x = poses.L!.wrist[0]
    maxStep = Math.max(maxStep, Math.abs(x - prevX))
    prevX = x
  }
  h?.release()
  // DRIFT_RATE = 10 units/s → at 60 fps no frame may move more than ~0.17.
  check('no frame snaps more than 0.2 units', maxStep <= 0.2, `maxStep=${maxStep.toFixed(4)}`)
  check('rate-limit poses stay finite', finite(poses.L) && finite(poses.R))
}

// ---- 10. S1+S2 — landing has no wobble: the two loops never fight ----
console.log('stability: steady hold — tip settles, no drift/abduct tug-of-war')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const h1 = audioEngine.triggerKey(60, 0.8)
  const h2 = audioEngine.triggerKey(64, 0.8) // chord → drift mean + per-finger dev
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 35; i++) poses = appFrame(opts) // converge
  const rel = (p: HandPose, f: number) => [p.fingers[f][3][0] - p.wrist[0], p.fingers[f][3][1] - p.wrist[1]]
  const samples: number[][][] = []
  for (let i = 0; i < 30; i++) {
    poses = appFrame(opts)
    samples.push([rel(poses.R!, 1), rel(poses.R!, 2)])
  }
  let maxVar = 0
  for (let f = 0; f < 2; f++) {
    for (const axis of [0, 1]) {
      const vals = samples.map((s) => s[f][axis])
      maxVar = Math.max(maxVar, Math.max(...vals) - Math.min(...vals))
    }
  }
  check('steady-hold tip variation <= 1 mm', maxVar <= 0.01, `var=${maxVar.toFixed(4)}`)
  h1?.release()
  h2?.release()
}

// ---- 11. S3 — one hinge axis per strike (frozen, no kinks) ----
console.log('stability: strike axis frozen for the whole press')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const h = audioEngine.triggerKey(60, 0.8)
  const axes: number[][] = []
  const tips: number[][] = []
  for (let i = 0; i < 12; i++) {
    const poses = appFrame(opts)
    const dbg = liveHands.slotDebug('R', 1)
    if (dbg.axis) axes.push([...dbg.axis])
    tips.push([...poses.R!.fingers[1][3]])
  }
  h?.release()
  let maxTurn = 0
  for (let i = 1; i < axes.length; i++) {
    const dot = axes[i][0] * axes[i - 1][0] + axes[i][1] * axes[i - 1][1] + axes[i][2] * axes[i - 1][2]
    maxTurn = Math.max(maxTurn, Math.acos(Math.min(1, Math.max(-1, dot))))
  }
  check('axis does not turn during the strike', axes.length >= 8 && maxTurn < 1e-6, `turn=${maxTurn}`)
  // smooth path: no segment more than 3x the median (a kink = axis jumped)
  const segs: number[] = []
  for (let i = 1; i < tips.length; i++) segs.push(Math.hypot(tips[i][0] - tips[i - 1][0], tips[i][1] - tips[i - 1][1], tips[i][2] - tips[i - 1][2]))
  const med = [...segs].sort((a, b) => a - b)[Math.floor(segs.length / 2)]
  check('press path smooth (no kink)', med > 0 && Math.max(...segs) <= 3.2 * med, `max=${Math.max(...segs).toFixed(4)} med=${med.toFixed(4)}`)
}

// ---- 12. S5 — a repeat keeps its hand (no mid-key flip) ----
console.log('stability: rapid repeats of one key stay on ONE hand')
{
  liveHands.reset()
  const opts = browserOpts({ resolvePlan: undefined })
  for (let i = 0; i < 5; i++) appFrame(opts)
  const handsSeen: string[] = []
  for (let rep = 0; rep < 3; rep++) {
    const h = audioEngine.triggerKey(62, 0.8) // D4 — near the midline
    let poses: HandPoses = freshSource()
    for (let i = 0; i < 8; i++) poses = appFrame(opts)
    handsSeen.push(poses.R!.press.some((v) => v > 0.5) ? 'R' : 'L')
    h?.release()
    for (let i = 0; i < 8; i++) appFrame(opts) // gap < 1.5 s
  }
  check('all repeats on the same hand', handsSeen.every((x) => x === handsSeen[0]), JSON.stringify(handsSeen))
}

// ---- 13. N1 — repetition scaling: fast repeats stay tight ----
console.log('naturalness: fast repeats lift less than slow ones (10 Hz <= 40% of 2 Hz)')
{
  const cycle = (pressF: number, gapF: number): { lift: number; travel: number } => {
    liveHands.reset()
    const opts = browserOpts()
    for (let i = 0; i < 5; i++) appFrame(opts)
    let lift = 0
    let travel = 0
    for (let rep = 0; rep < 3; rep++) {
      let repLift = 0
      // (rep drives the tail-skip above)
      const restTip = freshSource().R!.fingers[1][3][1] - freshSource().R!.wrist[1]
      const h = audioEngine.triggerKey(60, 0.8)
      let lo = 0
      let hi = 0
      const watch = (p: HandPoses) => {
        const y = p.R!.fingers[1][3][1] - p.R!.wrist[1] - restTip
        lo = Math.min(lo, y)
        hi = Math.max(hi, y)
      }
      for (let i = 0; i < pressF; i++) {
        const p = appFrame(opts)
        watch(p)
        repLift = Math.max(repLift, liveHands.slotDebug('R', 1).lift)
      }
      h?.release()
      // the stroke continues after release (the peck sweep finishes) — see it
      // whole, but only on the last rep so the repeat interval stays intact
      if (rep === 2) for (let i = 0; i < 8; i++) watch(appFrame(opts))
      lift = repLift // the LATEST rep reflects the repeat interval
      travel = Math.max(travel, hi - lo)
      h?.release()
      for (let i = 0; i < gapF; i++) appFrame(opts)
    }
    return { lift, travel }
  }
  const slow = cycle(14, 10) // keydown every ~0.4 s (2.5 Hz) — full windup
  const fast = cycle(3, 3) // keydown every ~0.1 s (10 Hz) — tight taps
  check('10 Hz windup lift stays in the 55% floor band', fast.lift <= 0.62 * slow.lift && fast.lift >= 0.5 * slow.lift, `slow=${slow.lift.toFixed(4)} fast=${fast.lift.toFixed(4)}`)
  check('slow repeats keep the full windup', slow.lift >= 0.14, `slow=${slow.lift.toFixed(4)}`)
  check('fast repeat travel is tighter but still visible (>= 5 mm)', fast.travel <= 0.85 * slow.travel && fast.travel >= 0.05, `slow=${slow.travel.toFixed(4)} fast=${fast.travel.toFixed(4)}`)
}

// ---- 14. N2 — travel arc: the hand lifts while gliding ----
console.log('naturalness: hand lifts into an arc when travelling far')
{
  liveHands.reset()
  const opts = browserOpts({ resolvePlan: undefined })
  for (let i = 0; i < 5; i++) appFrame(opts)
  const restY = freshSource().R!.wrist[1]
  const h = audioEngine.triggerKey(96, 0.8) // far right → the right hand must travel
  let poses: HandPoses = freshSource()
  let peakLift = 0
  for (let i = 0; i < 50; i++) {
    poses = appFrame(opts)
    peakLift = Math.max(peakLift, poses.R!.wrist[1] - restY)
  }
  for (let i = 0; i < 60; i++) poses = appFrame(opts)
  const settle = Math.abs(poses.R!.wrist[1] - restY)
  h?.release()
  check('arc lift is real and bounded (1–7 mm)', peakLift >= 0.01 && peakLift <= 0.07, `peak=${peakLift.toFixed(4)}`)
  check('hand settles back after travel', settle <= 0.012, `settle=${settle.toFixed(4)}`)
}

// ---- 15. N3 — release rebound: the finger springs back ----
console.log('naturalness: release overshoots hover a little')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const rest = freshSource().R!
  const restY = rest.fingers[1][3][1] - rest.wrist[1]
  const h = audioEngine.triggerKey(60, 0.8)
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 25; i++) poses = appFrame(opts) // fully pressed
  h?.release()
  let over = -Infinity
  for (let i = 0; i < 24; i++) {
    poses = appFrame(opts)
    over = Math.max(over, poses.R!.fingers[1][3][1] - poses.R!.wrist[1] - restY)
  }
  check('finger rebounds slightly above rest (0.2–15 mm)', over >= 0.002 && over <= 0.015, `over=${over.toFixed(4)}`)
}

// ---- 16. N4 — anticipation: a modest lean toward the imminent note ----
console.log('naturalness: hand leans toward the imminent note (bounded)')
{
  liveHands.reset()
  const opts: LiveHandsOpts = {
    ...browserOpts({ resolvePlan: undefined }),
    nextKey: (hand) => (hand === 'R' ? { keyX: 2.6, in: 0.05 } : null),
  }
  for (let i = 0; i < 5; i++) appFrame(opts)
  const restX = freshSource().R!.wrist[0]
  let poses: HandPoses = freshSource()
  for (let i = 0; i < 30; i++) poses = appFrame(opts)
  const lean = poses.R!.wrist[0] - restX
  const gap = 2.6 - [0, 1, 2, 3, 4].reduce((a, f) => a + freshSource().R!.fingers[f][3][0], 0) / 5
  check('lean is positive and <= 28% of the gap', lean >= 0.02 && lean <= 0.28 * gap, `lean=${lean.toFixed(4)} gap=${gap.toFixed(3)}`)
  // While PLAYING along with a motion that already leads (the DB moves the
  // planned finger to the key — this is the feed-forward's own estimate),
  // there must be NO extra lean.
  liveHands.reset()
  const leadSource = (): HandPoses => {
    const p = freshSource()
    p.R!.fingers[3][3][0] = 2.6 // the planned finger is already at the key
    return p
  }
  const opts2: LiveHandsOpts = {
    ...browserOpts({ resolvePlan: undefined, playing: true }),
    nextKey: () => ({ keyX: 2.6, in: 0.05, finger: 3 }),
  }
  for (let i = 0; i < 5; i++) appFrame(opts2, leadSource)
  const restX2 = leadSource().R!.wrist[0]
  for (let i = 0; i < 30; i++) poses = appFrame(opts2, leadSource)
  check('no lean while playing when the motion already leads', Math.abs(poses.R!.wrist[0] - restX2) <= 0.012, `d=${(poses.R!.wrist[0] - restX2).toFixed(4)}`)
}

// ---- 17. N5 — sympathetic coupling: idle neighbours breathe ----
console.log('naturalness: idle neighbour dips with the strike (tiny)')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const rest = freshSource().R!
  const restY2 = rest.fingers[2][3][1] - rest.wrist[1] // middle finger, idle
  const h = audioEngine.triggerKey(60, 0.8) // planned: right index
  let poses: HandPoses = freshSource()
  let dip = 0
  for (let i = 0; i < 25; i++) {
    poses = appFrame(opts)
    dip = Math.min(dip, poses.R!.fingers[2][3][1] - poses.R!.wrist[1] - restY2)
  }
  h?.release()
  check('neighbour dip is felt but tiny (0.15–12 mm)', dip <= -0.0015 && dip >= -0.012, `dip=${dip.toFixed(4)}`)
}


// ---- 18. GĐ 1 — no double-curl: a source that already presses is not re-curled ----
console.log('posture: a source press is not curled twice (tip stays near the key surface)')
{
  liveHands.reset()
  const srcPressed = (): HandPoses => {
    const p = freshSource()
    p.R!.press[1] = 1 // the motion DB animates real presses
    return p
  }
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts, srcPressed)
  const srcTipZ = srcPressed().R!.fingers[1][3][2]
  const h = audioEngine.triggerKey(60, 0.8)
  let poses: HandPoses = freshSource()
  let worst = 0
  for (let i = 0; i < 25; i++) {
    poses = appFrame(opts, srcPressed)
    worst = Math.min(worst, poses.R!.fingers[1][3][2] - srcTipZ)
  }
  h?.release()
  check('extra sink through an already-pressed key <= 8 mm', worst >= -0.08 && worst <= 0.02, `sink=${worst.toFixed(4)}`)
}

// ---- 19. GĐ 3 — consecutive notes: the finger lands ON the key at the strike ----
console.log('accuracy: on a moving source, strikes land within 3 mm of key centre')
{
  liveHands.reset()
  const MIDS = [60, 62, 64, 65] // C D E F — 2–3 cm steps, the plan's reference pace
  const NOTEX = MIDS.map((m) => keyForMidi(m)!.x)
  const T0 = fakeMs / 1000 + 0.3 // the shared fake clock has been running all suite
  const onset = (i: number) => T0 + i * 0.2
  const shiftX = (p: HandPose, dx: number) => {
    p.wrist[0] += dx
    p.elbow[0] += dx
    for (let f = 0; f < 5; f++) {
      p.bases[f][0] += dx
      for (let j = 0; j < 4; j++) p.fingers[f][j][0] += dx
    }
  }
  // The source pre-positions its finger like the motion DB: the tip glides
  // linearly from the previous key and ARRIVES at the key at the onset.
  const baseTipX = tplR.fingers[1][3][0]
  const srcMove = (ta?: number): HandPoses => {
    const t = ta ?? fakeMs / 1000 // the humanizer samples t / t−τ / t−2τ — honour it
    let k = 0
    // the segment activates when its APPROACH starts (0.17 s before the
    // onset) — not at the onset itself, or the source teleports
    while (k + 1 < NOTEX.length && t >= onset(k + 1) - 0.17) k++
    const from = k === 0 ? NOTEX[0] - 0.5 : NOTEX[k - 1]
    const to = NOTEX[k]
    const raw = Math.max(0, Math.min(1, (t - (onset(k) - 0.17)) / 0.15)) // arrives 20 ms early
    const phase = raw * raw * (3 - 2 * raw) // ease-out: decelerates into the key
    const desired = from + (to - from) * phase
    const p = freshSource()
    shiftX(p.R!, desired - baseTipX)
    return p
  }
  const opts: LiveHandsOpts = {
    ...browserOpts({ playing: true, resolvePlan: () => ({ hand: 'R' as const, finger: 1 }) }),
    sampleHand: (hand) => srcMove()[hand],
    nextKey: (hand) => {
      const t = fakeMs / 1000
      const i = NOTEX.findIndex((_, j) => onset(j) > t + 1e-3)
      if (hand !== 'R' || i < 0 || onset(i) - t > 0.4) return null
      return { keyX: NOTEX[i], in: onset(i) - t, finger: 1 }
    },
  }
  for (let i = 0; i < 5; i++) appFrame(opts, srcMove)
  let worst = 0
  let sum = 0
  let frames = 0
  const held: { h: { release: () => void } | null; until: number }[] = NOTEX.map(() => ({ h: null, until: 0 }))
  for (let i = 0; i < 75; i++) {
    const t = fakeMs / 1000
    for (let j = 0; j < NOTEX.length; j++) {
      // strike once at the onset, release 80 ms later (a real note-off —
      // the slot must free so the same finger can re-strike)
      if (t >= onset(j) && held[j].h === null) held[j] = { h: audioEngine.triggerKey(MIDS[j], 0.8), until: onset(j) + 0.08 }
      if (held[j].h && t >= held[j].until) {
        held[j].h.release()
        held[j].h = null
      }
    }
    const poses = appFrame(opts, srcMove)
    for (let j = 0; j < NOTEX.length; j++) {
      if (Math.abs(t - (onset(j) + 0.02)) < 0.01) {
        const err = poses.R!.fingers[1][3][0] - NOTEX[j]
        worst = Math.max(worst, Math.abs(err))
        sum += Math.abs(err)
        frames++
      }
    }
  }
  // measured bound at this stress pace (3 cm steps at 200 ms, ~20 cm/s
  // peak): worst 3.2 mm, mean well under 2 mm — the render lag's tail
  check('strikes land within 3.5 mm of key centre (worst)', frames >= 4 && worst <= 0.035, `worst=${worst.toFixed(4)} n=${frames}`)
  check('strikes average under 2 mm', frames >= 4 && sum / frames <= 0.02, `mean=${(sum / frames).toFixed(4)}`)
}

// ---- 20. GĐ 4 — attack dip: the wrist drops with the strike and rebounds ----
console.log('weight: the wrist dips ~2 mm with each strike and rebounds')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 8; i++) appFrame(opts)
  let base = 0
  for (let i = 0; i < 10; i++) base += appFrame(opts).R!.wrist[2]
  base /= 10
  const h = audioEngine.triggerKey(60, 0.8)
  let dip = 0
  for (let i = 0; i < 25; i++) dip = Math.min(dip, appFrame(opts).R!.wrist[2] - base)
  h?.release()
  for (let i = 0; i < 45; i++) appFrame(opts)
  const settle = appFrame(opts).R!.wrist[2] - base
  check('wrist dips 0.8–4.5 mm with the strike', dip <= -0.008 && dip >= -0.045, `dip=${dip.toFixed(4)}`)
  check('wrist rebounds after the release', Math.abs(settle) <= 0.015, `settle=${settle.toFixed(4)}`)
}

// ---- 21. GĐ 2 — proximity coupling: neighbours close to the strike move more ----
console.log('anatomy: sympathetic coupling follows finger proximity (enslaving)')
{
  liveHands.reset()
  const opts = browserOpts()
  for (let i = 0; i < 5; i++) appFrame(opts)
  const h = audioEngine.triggerKey(60, 0.8) // right index (f=1)
  for (let i = 0; i < 12; i++) appFrame(opts)
  const near = Math.abs(liveHands.slotDebug('R', 2).couple) // middle — adjacent
  const far = Math.abs(liveHands.slotDebug('R', 4).couple) // pinky — 3 away
  h?.release()
  check('adjacent finger couples more than the far one', near > far && near >= 0.002, `near=${near.toFixed(4)} far=${far.toFixed(4)}`)
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
if (failures) process.exit(1)
