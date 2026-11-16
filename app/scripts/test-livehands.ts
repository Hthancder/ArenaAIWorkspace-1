/**
 * Live-input hands overlay v2 tests (src/hands/liveHands.ts).
 *
 * v2 contract (2026-11-15 user feedback): motion must be RIGID (no bone
 * stretching, "kéo dãn, force"), an off-stage hand must COME UP for keys
 * on its side of the keyboard, repeated presses must visibly tap, and the
 * song plan's fingering must win when available.
 *
 * NOTE: the audio engine pulls browser-only globals at module scope, so
 * this test shims the minimal Web Audio surface and uses dynamic imports.
 * Run: `npx vite-node scripts/test-livehands.ts`
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
// dev/mode.ts reads localStorage — dev tools + no-audio so triggerKey
// proceeds without the sampler.
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
const { keyForMidi } = await import('../src/keyboard/layout')
// Type-only import — erased at compile time, loads no modules early.
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

function makePose(hand: 'L' | 'R', x: number): HandPose {
  return {
    hand,
    elbow: [x - 0.3, -3, 0.5],
    wrist: [x, -2, 0.6],
    bases: Array.from({ length: 5 }, (_, i) => [x + (i - 2) * 0.18, -1.5, 0.7] as [number, number, number]),
    fingers: Array.from({ length: 5 }, (_, i) =>
      Array.from({ length: 4 }, (_, k) => [x + (i - 2) * 0.18, -1.2 + k * 0.18, 0.8] as [number, number, number]),
    ),
    press: [0, 0, 0, 0, 0],
    thumbRef: [
      [x, -1.4, 0.7],
      [x, -1.2, 0.75],
      [x, -1.0, 0.8],
    ],
  }
}

const posesOf = (): HandPoses => ({ L: makePose('L', -1), R: makePose('R', 1) })

/**
 * Restore the working pose's GEOMETRY from a pristine template — exactly
 * what the app's humanize does every frame (applyTo writes into the given
 * pose; fresh input, never accumulated).
 */
function refreshPose(dst: HandPose, tpl: HandPose): void {
  dst.elbow = [...tpl.elbow] as HandPose['elbow']
  dst.wrist = [...tpl.wrist] as HandPose['wrist']
  for (let i = 0; i < 5; i++) {
    dst.bases[i] = [...tpl.bases[i]] as HandPose['bases'][number]
    for (let k = 0; k < 4; k++) dst.fingers[i][k] = [...tpl.fingers[i][k]] as HandPose['fingers'][number][number]
  }
  for (let i = 0; i < 3; i++) dst.thumbRef[i] = [...tpl.thumbRef[i]] as HandPose['thumbRef'][number]
}

// Deterministic frame clock — these loops run in microseconds.
let fakeMs = 0
;(performance as unknown as { now: () => number }).now = () => fakeMs

const baseOpts = (extra: Partial<LiveHandsOpts> = {}): LiveHandsOpts => ({ playing: false, keystrike: 1, ...extra })

const frames = (p: HandPoses, n: number, opts: LiveHandsOpts = baseOpts(), refresh?: () => void): void => {
  for (let i = 0; i < n; i++) {
    fakeMs += 16.7
    // The app re-copies the raw poses every frame (humanize); the test
    // must too — applyTo writes into whatever pose it is handed.
    refresh?.()
    liveHands.update(p, opts)
  }
}

/** All bone lengths of one hand: elbow→wrist, base→MCP, and the finger chains. */
function boneLengths(p: HandPose): number[] {
  const d = (a: number[], b: number[]) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])
  const out: number[] = [d(p.elbow, p.wrist)]
  for (let f = 0; f < 5; f++) {
    out.push(d(p.bases[f], p.fingers[f][0]))
    for (let k = 0; k < 3; k++) out.push(d(p.fingers[f][k], p.fingers[f][k + 1]))
  }
  return out
}

console.log('idle: no presses → poses untouched')
{
  liveHands.attach()
  liveHands.reset()
  const p = posesOf()
  const tpl = posesOf()
  const before = JSON.stringify(p)
  frames(p, 5, baseOpts(), () => {
    refreshPose(p.L!, tpl.L!)
    refreshPose(p.R!, tpl.R!)
  })
  check('pose unchanged', JSON.stringify(p) === before)
}

console.log('press: rigid reach — the finger tip lands on the key, no stretching')
{
  liveHands.reset()
  const tpl = posesOf()
  const p = posesOf()
  const r = p.R!
  const h = audioEngine.triggerKey(72, 0.8)
  check('triggerKey fires without the sampler (devNoAudio)', h !== null)
  const refresh = () => {
    refreshPose(p.L!, tpl.L!)
    refreshPose(r, tpl.R!)
  }
  const bonesBefore = boneLengths(tpl.R!)
  frames(p, 60, baseOpts(), refresh) // ~1 s
  refresh()
  liveHands.update(p, baseOpts())
  const f = r.press.findIndex((v) => v > 0.5)
  const keyX = keyForMidi(72)!.x
  check('some right finger presses', f >= 0, JSON.stringify(r.press))
  check('left hand untouched', p.L!.press.every((v) => v === 0))
  if (f >= 0) {
    check('assigned finger tip lands on the key x', Math.abs(r.fingers[f][3][0] - keyX) < 0.2, `${r.fingers[f][3][0]} vs ${keyX}`)
  }
  const bonesAfter = boneLengths(r)
  let maxStretch = 0
  bonesBefore.forEach((b, i) => {
    maxStretch = Math.max(maxStretch, Math.abs(bonesAfter[i] - b) / b)
  })
  // v3 rotates joints (Rodrigues) — lengths are preserved EXACTLY.
  check('bone lengths preserved exactly (rotations only)', maxStretch < 0.01, `${(maxStretch * 100).toFixed(2)}%`)

  console.log('press articulation: the finger presses DOWN into the key')
  {
    const zRest = tpl.R!.fingers[f][3][2]
    // While held, the tip must sit BELOW its rest height (v2 bobbed UP).
    check('tip dips below rest while held', r.fingers[f][3][2] < zRest - 0.01, `${r.fingers[f][3][2]} vs rest ${zRest}`)
  }

  console.log('release: smooth return, no jumps')
  h?.release()
  let prev = r.wrist[0]
  let maxJump = 0
  for (let i = 0; i < 90; i++) {
    fakeMs += 16.7
    refresh()
    liveHands.update(p, baseOpts())
    maxJump = Math.max(maxJump, Math.abs(r.wrist[0] - prev))
    prev = r.wrist[0]
  }
  check('drift returns toward base', Math.abs(r.wrist[0] - 1) < 0.25, `${r.wrist[0]}`)
  check('no per-frame jump > 0.1', maxJump < 0.1, `${maxJump}`)
  check('press flags cleared', r.press.every((v) => v === 0))
}

console.log('repeat presses: every key-down visibly taps ("không giữ nguyên 1 chỗ")')
{
  liveHands.reset()
  const tpl = posesOf()
  const p = posesOf()
  const r = p.R!
  const refresh = () => refreshPose(r, tpl.R!)
  const h1 = audioEngine.triggerKey(72, 0.8)
  frames(p, 20, baseOpts(), refresh)
  let f = 0
  for (let i = 0; i < 5; i++) if (r.press[i] > 0.5) f = i
  h1?.release()
  frames(p, 12, baseOpts(), refresh) // short gap — finger not fully settled
  const h2 = audioEngine.triggerKey(72, 0.8) // repeat!
  let zMin = Infinity
  let zMax = -Infinity
  for (let i = 0; i < 16; i++) {
    fakeMs += 16.7
    refresh()
    liveHands.update(p, baseOpts())
    const z = r.fingers[f][3][2]
    zMin = Math.min(zMin, z)
    zMax = Math.max(zMax, z)
  }
  h2?.release()
  check('second press shows a visible tap', zMax - zMin > 0.02, `${(zMax - zMin).toFixed(3)}`)

  console.log('fast repeats: every key-down pecks even mid-press')
  {
    // Down → 3 frames → up → 3 frames → down again while still low.
    liveHands.reset()
    const tpl2 = posesOf()
    const p2 = posesOf()
    const r2 = p2.R!
    const refresh2 = () => refreshPose(r2, tpl2.R!)
    const hA = audioEngine.triggerKey(72, 0.8)
    frames(p2, 3, baseOpts(), refresh2)
    let f2 = 0
    for (let i = 0; i < 5; i++) if (r2.press[i] > 0.5) f2 = i
    hA?.release()
    frames(p2, 3, baseOpts(), refresh2) // barely recovered — finger still low
    const zBefore = r2.fingers[f2][3][2]
    const hB = audioEngine.triggerKey(72, 0.8) // immediate repeat
    let lo = Infinity
    let hi = -Infinity
    for (let i = 0; i < 14; i++) {
      fakeMs += 16.7
      refresh2()
      liveHands.update(p2, baseOpts())
      const z = r2.fingers[f2][3][2]
      lo = Math.min(lo, z)
      hi = Math.max(hi, z)
    }
    hB?.release()
    // The peck sweep lifts the finger up before striking again: the tip
    // must travel visibly even though it started mid-press.
    // scaled to this fixture's small hand — the real-geometry bound lives
    // in test-livebrowser (N1: fast stroke 12.6 mm ≥ 5 mm floor)
    check('repeat peck travels the tip', hi - lo > 0.02, `${(hi - lo).toFixed(3)}`)
    check('peck lifts before striking', hi > zBefore + 0.005, `${hi} vs ${zBefore}`)
  }
}

console.log('adaptive hands: the left hand comes up for left-side keys')
{
  liveHands.reset()
  // Only the RIGHT hand is on stage.
  const tplR = makePose('R', 2)
  const p: HandPoses = { L: null, R: makePose('R', 2) }
  const opts = baseOpts({
    sampleHand: (hand) => (hand === 'L' ? makePose('L', -3) : null),
  })
  const refresh = () => refreshPose(p.R!, tplR)
  frames(p, 30, opts, refresh)
  check('no presses → left hand stays off stage', p.L === null)

  const leftX = keyForMidi(40)!.x // far-left key
  const h = audioEngine.triggerKey(40, 0.8)
  frames(p, 90, opts, refresh)
  check('left hand materialises for the left key', p.L !== null)
  if (p.L) {
    const f = p.L.press.findIndex((v) => v > 0.5)
    if (f >= 0) {
      // Tight: the synth hand travels all the way (value-target drift).
      check('left finger lands on the key', Math.abs(p.L.fingers[f][3][0] - leftX) < 0.25, `${p.L.fingers[f][3][0]} vs ${leftX}`)
    } else check('left finger presses', false, JSON.stringify(p.L.press))
  }
  check('right hand does not stretch across', Math.abs(p.R!.wrist[0] - 2) <= 1.2 + 1e-9, `${p.R!.wrist[0]}`)

  console.log('adaptive hands: the left hand lowers away after playing')
  h?.release()
  frames(p, 120, opts, refresh)
  check('left hand is gone again', p.L === null)
}

console.log('plan fingering wins when the song plan knows the note')
{
  liveHands.reset()
  const tpl = posesOf()
  const p = posesOf()
  const opts = baseOpts({
    resolvePlan: (midi) => (midi === 72 ? { hand: 'R', finger: 2 } : null),
  })
  const refresh = () => {
    refreshPose(p.L!, tpl.L!)
    refreshPose(p.R!, tpl.R!)
  }
  const h = audioEngine.triggerKey(72, 0.8)
  frames(p, 40, opts, refresh)
  check('planned finger (index 2) presses', p.R!.press[2] === 1, JSON.stringify(p.R!.press))
  check('no other finger steals it', p.R!.press.filter((v) => v > 0.5).length === 1)
  h?.release()
}

console.log('wait-mode demand: pressed pose hovers until the user plays')
{
  liveHands.reset()
  const tpl = posesOf()
  const p = posesOf()
  const r = p.R!
  const demand = () => {
    refreshPose(p.L!, tpl.L!)
    refreshPose(r, tpl.R!)
    r.press[2] = 1
  }
  const opts = baseOpts()
  frames(p, 60, opts, demand)
  check('demanded finger hovers up', r.fingers[2][3][2] > 0.8 + 0.03, `${r.fingers[2][3][2]}`)
  check('press flag stays live-driven (off)', r.press[2] === 0)

  const h = audioEngine.triggerKey(72, 0.8)
  frames(p, 60, opts, demand)
  check('pressed → some finger comes down', r.press.some((v) => v > 0.5), JSON.stringify(r.press))
  h?.release()
  frames(p, 120, opts, demand)
  check('released → demand hover returns', r.fingers[2][3][2] > 0.8, `${r.fingers[2][3][2]}`)
  check('press flags cleared', r.press.every((v) => v === 0))
}

console.log('free play: neutral pose hands appear with no motion at all')
{
  liveHands.reset()
  const { neutralHandPose } = await import('../src/hands/neutralPose')
  // Sanity: the baked pose is complete and finite.
  for (const hand of ['L', 'R'] as const) {
    const np = neutralHandPose(hand)
    const vecs = [np.elbow, np.wrist, ...np.bases, ...np.fingers.flat(), ...np.thumbRef]
    check(`neutral ${hand} pose is finite`, vecs.every((v) => v.length === 3 && v.every(Number.isFinite)))
  }
  // No motion: every base pose is null; the overlay synthesises on demand.
  const p: HandPoses = { L: null, R: null }
  const opts = baseOpts({ sampleHand: (hand) => neutralHandPose(hand) })
  frames(p, 5, opts)
  check('nothing pressed → no hands', p.L === null && p.R === null)

  const hR = audioEngine.triggerKey(72, 0.8) // right side
  frames(p, 60, opts)
  check('right hand appears in free play', p.R !== null && p.R.press.some((v) => v > 0.5))
  check('left hand stays out', p.L === null)
  hR?.release()

  const hL = audioEngine.triggerKey(40, 0.8) // far left
  frames(p, 60, opts)
  check('left hand appears in free play', p.L !== null && p.L.press.some((v) => v > 0.5))
  hL?.release()

  frames(p, 150, opts)
  check('hands leave when idle', p.L === null && p.R === null)
}

console.log('expression: velocity depth, accent roll, rolled chords (opts.expression)')
{
  liveHands.reset()
  const tpl = posesOf()
  const p = posesOf()
  const r = p.R!
  const refresh = () => {
    refreshPose(p.L!, tpl.L!)
    refreshPose(r, tpl.R!)
  }
  const ex = baseOpts({ expression: 1 })
  const zOfPressed = () => {
    let f = -1
    for (let i = 0; i < 5; i++) if (r.press[i] > 0.5) f = i
    return f >= 0 ? r.fingers[f][3][2] : NaN
  }

  // Velocity depth: a soft press sinks less than a hard press.
  const soft = audioEngine.triggerKey(72, 0.25)
  frames(p, 30, ex, refresh)
  const zSoft = zOfPressed()
  soft?.release()
  frames(p, 70, ex, refresh)
  const hard = audioEngine.triggerKey(72, 0.95)
  frames(p, 30, ex, refresh)
  const zHard = zOfPressed()
  hard?.release()
  check('hard press sinks deeper than soft', zHard < zSoft - 0.014, `${zHard} vs ${zSoft}`)

  // Accent roll: on a strong note the palm rotates around the forearm
  // axis (bases move relative to the wrist; lengths unchanged).
  frames(p, 70, ex, refresh)
  const wrist0 = [...r.wrist]
  const rel0 = [tpl.R!.bases[2][0] - tpl.R!.wrist[0], tpl.R!.bases[2][1] - tpl.R!.wrist[1], tpl.R!.bases[2][2] - tpl.R!.wrist[2]]
  const acc = audioEngine.triggerKey(72, 0.95)
  frames(p, 14, ex, refresh)
  const rel1 = [r.bases[2][0] - wrist0[0], r.bases[2][1] - wrist0[1], r.bases[2][2] - wrist0[2]]
  acc?.release()
  const dot = rel0[0] * rel1[0] + rel0[1] * rel1[1] + rel0[2] * rel1[2]
  const m0 = Math.hypot(...rel0)
  const m1 = Math.hypot(...rel1)
  check('accent rolls the hand (palm rotates)', Math.abs(dot / (m0 * m1) - 1) > 1e-5 && m1 > 0.5 * m0, `cos=${dot / (m0 * m1)}`)
  const bonesA = boneLengths(r)
  let rollErr = 0
  bonesA.forEach((b, i) => {
    const ref = boneLengths(tpl.R!)[i]
    rollErr = Math.max(rollErr, Math.abs(b - ref) / ref)
  })
  check('roll preserves bone lengths', rollErr < 0.01, `${(rollErr * 100).toFixed(2)}%`)

  // Rolled chord: the second finger of a near-simultaneous pair strikes later.
  liveHands.reset()
  const p2 = posesOf()
  const r2 = p2.R!
  const refresh2 = () => {
    refreshPose(p2.L!, tpl.L!)
    refreshPose(r2, tpl.R!)
  }
  const c1 = audioEngine.triggerKey(67, 0.8)
  const c2 = audioEngine.triggerKey(72, 0.8) // same tick → rolled
  frames(p2, 3, ex, refresh2)
  const deep = r2.press.map((v, i) => (v > 0.5 ? r2.fingers[i][3][2] : NaN))
  const pressed = deep.filter((z) => Number.isFinite(z)).sort((a, b) => a - b)
  c1?.release()
  c2?.release()
  check('rolled chord: two fingers strike', pressed.length === 2, JSON.stringify(deep))
  if (pressed.length === 2) {
    check('second finger strikes after the first', pressed[1] - pressed[0] > 0.015, `${pressed[1] - pressed[0]}`)
  }

  // Playback expression: the model's own press dips deeper on loud notes.
  liveHands.reset()
  const p3 = posesOf()
  const r3 = p3.R!
  const demand = () => {
    refreshPose(p3.L!, tpl.L!)
    refreshPose(r3, tpl.R!)
    r3.press[2] = 1 // the model plays finger 2
  }
  const loud = baseOpts({ playing: true, expression: 1, expressAt: () => 0.95 })
  frames(p3, 40, loud, demand)
  const zLoud = r3.fingers[2][3][2]
  liveHands.reset()
  const p4 = posesOf()
  const r4 = p4.R!
  const demand4 = () => {
    refreshPose(p4.L!, tpl.L!)
    refreshPose(r4, tpl.R!)
    r4.press[2] = 1
  }
  const softPlay = baseOpts({ playing: true, expression: 1, expressAt: () => 0.2 })
  frames(p4, 40, softPlay, demand4)
  const zSoftPlay = r4.fingers[2][3][2]
  check('playback accent presses deeper', zLoud < zSoftPlay - 0.02, `${zLoud} vs ${zSoftPlay}`)
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
process.exit(failures === 0 ? 0 : 1)
