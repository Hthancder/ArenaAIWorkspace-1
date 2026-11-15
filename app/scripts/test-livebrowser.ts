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

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
if (failures) process.exit(1)
