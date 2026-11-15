/**
 * Live-input hands overlay tests (src/hands/liveHands.ts).
 *
 * NOTE: importing the audio engine pulls browser-only globals at module
 * scope (smoothRelease touches AudioParam.prototype), so this test shims
 * the minimal Web Audio surface and uses dynamic imports.
 *
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
// dev/mode.ts reads localStorage — enable dev tools + no-audio so
// triggerKey proceeds without the sampler.
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
// Type-only import — erased at compile time, so it loads no modules
// before the shims above.
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

// Deterministic frame clock: the overlay smooths with real dt, and these
// loops run in microseconds — step a fake performance.now() per frame.
let fakeMs = 0
;(performance as unknown as { now: () => number }).now = () => fakeMs

const frames = (p: HandPoses, n: number, playing = false, refresh?: () => void): void => {
  for (let i = 0; i < n; i++) {
    fakeMs += 16.7
    // The app re-copies the raw press flags every frame (humanize); the
    // test must too — applyTo consumes the base flags it just wrote.
    refresh?.()
    liveHands.update(p, playing)
  }
}

console.log('idle: no presses → poses untouched')
{
  liveHands.attach() // the app attaches in Hands.tsx's effect
  liveHands.reset()
  const p = posesOf()
  const before = JSON.stringify(p)
  frames(p, 5)
  check('pose unchanged', JSON.stringify(p) === before)
}

console.log('press: finger taps the key, wrist drifts toward it')
{
  liveHands.reset()
  const h = audioEngine.triggerKey(72, 0.8) // held key, right side
  check('triggerKey fires without the sampler (devNoAudio)', h !== null)
  const p = posesOf()
  frames(p, 60) // ~1 s
  const r = p.R!
  const f = r.press.findIndex((v) => v > 0.5)
  const keyX = keyForMidi(72)!.x
  check('some right finger presses', f >= 0, JSON.stringify(r.press))
  check('left hand untouched', p.L!.press.every((v) => v === 0))
  check('wrist drifts onto the pressed key', Math.abs(r.wrist[0] - keyX) < 0.2, `${r.wrist[0]} vs ${keyX}`)
  check('drift stays within reach', r.wrist[0] <= 1 + 1.1 + 1e-9, `${r.wrist[0]}`)
  if (f >= 0) check('tip pulled down to the key', r.fingers[f][3][2] < 0.5, `${r.fingers[f][3][2]}`)

  console.log('release: smooth return, no jumps')
  h?.release()
  let prev = r.wrist[0]
  let maxJump = 0
  for (let i = 0; i < 90; i++) {
    fakeMs += 16.7
    liveHands.update(p, false)
    maxJump = Math.max(maxJump, Math.abs(p.R!.wrist[0] - prev))
    prev = p.R!.wrist[0]
  }
  check('wrist returns toward base', Math.abs(p.R!.wrist[0] - 1) < 0.25, `${p.R!.wrist[0]}`)
  check('no per-frame jump > 0.1', maxJump < 0.1, `${maxJump}`)
  check('press flags cleared', p.R!.press.every((v) => v === 0))
}

console.log('wait-mode demand: pressed pose hovers until the user plays')
{
  liveHands.reset()
  const p = posesOf()
  const r = p.R!
  // The frozen step pose demands finger 2 (press=1) but nobody has played
  // it yet — refreshed each frame like the humanize pass does.
  const demand = () => {
    r.press[2] = 1
  }
  frames(p, 60, false, demand)
  check('demanded finger hovers up', r.fingers[2][3][2] > 0.8 + 0.05, `${r.fingers[2][3][2]}`)
  check('press flag stays live-driven (off)', r.press[2] === 0)

  // The user presses a key on the right-hand side.
  const h = audioEngine.triggerKey(72, 0.8)
  frames(p, 60, false, demand)
  check('pressed → some finger comes down', r.press.some((v) => v > 0.5), JSON.stringify(r.press))
  h?.release()
  frames(p, 120, false, demand)
  check('released → demand hover returns', r.fingers[2][3][2] > 0.8, `${r.fingers[2][3][2]}`)
  check('press flags cleared', r.press.every((v) => v === 0))
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
process.exit(failures === 0 ? 0 : 1)
