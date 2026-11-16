/**
 * GĐ 0, Part B — how the overlay (humanize + liveHands) transforms the DB
 * playback motion. Uses the frames dumped by diag-geometry.ts.
 * Compares each measure against the raw DB value to isolate what the
 * overlay layer adds (double-curl, height change, landing error).
 *
 * Run: npx vite-node scripts/diag-overlay.ts
 */
import fs from 'node:fs'
import path from 'node:path'

// ---- minimal WebAudio shims (same as test-livebrowser) ----
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
const storeMap = new Map<string, string>([
  ['nf:dev', '1'],
  ['nf:dev:noaudio', '1'],
])
;(globalThis as unknown as { localStorage: unknown }).localStorage = {
  getItem: (k: string) => storeMap.get(k) ?? null,
  setItem: (k: string, v: string) => void storeMap.set(k, v),
  removeItem: (k: string) => void storeMap.delete(k),
}

const { audioEngine } = await import('../src/audio/engine')
const { liveHands } = await import('../src/hands/liveHands')
const { humanizePoses, createHumanizeScratch } = await import('../src/hands/humanize')
const { neutralHandPose } = await import('../src/hands/neutralPose')
const { keyForMidi } = await import('../src/keyboard/layout')
type HandPoses = import('../src/hands/types').HandPoses
type HandPose = import('../src/hands/types').HandPose

const dump = JSON.parse(fs.readFileSync(path.resolve('scripts/.diag-frames.json'), 'utf8')) as {
  fps: number
  t0: number
  frames: {
    wrist: number[]
    elbow: number[]
    bases: number[][]
    fingers: number[][][]
    thumbRef: number[][]
  }[]
}

const RUN = [
  { midi: 62, on: 2.0, finger: 1 },
  { midi: 64, on: 2.3, finger: 2 },
  { midi: 65, on: 2.6, finger: 3 },
  { midi: 67, on: 2.9, finger: 1 },
  { midi: 69, on: 3.2, finger: 2 },
  { midi: 71, on: 3.5, finger: 3 },
]

let fakeMs = 0
;(performance as unknown as { now: () => number }).now = () => fakeMs
const scratch = createHumanizeScratch()
const params = { enabled: true, smoothness: 0.5, microMotion: 0.5 }

const toHandPose = (p: (typeof dump.frames)[number]): HandPose => ({
  hand: 'R',
  elbow: p.elbow as [number, number, number],
  wrist: p.wrist as [number, number, number],
  bases: p.bases as [number, number, number][],
  fingers: p.fingers as [number, number, number][][],
  press: [0, 0, 0, 0, 0],
  thumbRef: p.thumbRef as [number, number, number][],
})

const srcAt = (t: number): HandPoses => {
  const i = Math.max(0, Math.min(dump.frames.length - 1, Math.round((t - dump.t0) * dump.fps)))
  const r = toHandPose(dump.frames[i])
  // the runtime fills `press` per sounding note — mirror that here
  for (const n of RUN) {
    if (t >= n.on && t <= n.on + 0.25) r.press[n.finger - 1] = 1
  }
  return { L: structuredClone(neutralHandPose('L')), R: r }
}

const opts = {
  playing: true,
  keystrike: 0.6,
  expression: 0.65,
  resolvePlan: (midi: number) => {
    const n = RUN.find((r) => r.midi === midi)
    return n ? { hand: 'R' as const, finger: n.finger - 1 } : null
  },
  expressAt: () => null,
  sampleHand: (hand: 'L' | 'R') => srcAt(fakeMs / 1000)[hand]!, // the REAL source: the DB frames
  nextKey: (hand: 'L' | 'R') => {
    if (hand !== 'R') return null
    const now = fakeMs / 1000
    const n = RUN.find((r) => r.on > now + 1e-3 && r.on - now <= 0.4)
    return n ? { keyX: keyForMidi(n.midi)!.x, in: n.on - now, finger: n.finger - 1 } : null
  },
}

const angleDeg = (mcp: number[], tip: number[]) =>
  (Math.atan2(mcp[2] - tip[2], Math.hypot(tip[0] - mcp[0], tip[1] - mcp[1])) * 180) / Math.PI

const runOnce = (keystrike: number, label: string, humanizeOn = true) => {
  console.log(`\n== ${label} ==`)
  console.log('note | phase | srcWristZ | wristZ | srcTipZ | tipZ  | ΔtipZ | swing  | approach° | tipX-keyX | gaps')
  liveHands.attach()
  liveHands.reset()
  const held: { midi: number; rel: () => void }[] = []
  let nextIdx = 0
  for (let i = 0; i < 120; i++) {
    const t = dump.t0 + i / dump.fps
    fakeMs = t * 1000
    while (nextIdx < RUN.length && t >= RUN[nextIdx].on) {
      const n = RUN[nextIdx]
      const off = audioEngine.triggerKey(n.midi, 0.8)
      held.push({ midi: n.midi, rel: () => off?.release() })
      nextIdx++
    }
    for (let j = held.length - 1; j >= 0; j--) {
      const n = RUN.find((r) => r.midi === held[j].midi)!
      if (t >= n.on + 0.25) {
        held[j].rel()
        held.splice(j, 1)
      }
    }
    const src = srcAt(t)
    const srcR = src.R!
    const poses = humanizeOn ? humanizePoses(srcAt, t, params, scratch) : srcAt(t)
    liveHands.update(poses, { ...opts, keystrike })
    for (let ni = 0; ni < RUN.length; ni++) {
      const n = RUN[ni]
      for (const [dt, phase] of [
        [0.02, 'strk'],
        [0.15, 'hold'],
      ] as const) {
        if (Math.abs(t - (n.on + dt)) < 1 / 120) {
          const f = n.finger - 1
          const p = poses.R!
          const srcTip = srcR.fingers[f][3]
          const tip = p.fingers[f][3]
          const mcp = p.fingers[f][0]
          const k = keyForMidi(n.midi)
          const gaps = []
          for (let g = 0; g < 4; g++) gaps.push(Math.abs(p.fingers[g + 1][3][0] - p.fingers[g][3][0]).toFixed(3))
          console.log(
            `${String(n.midi).padStart(3)} |${phase} | ${srcR.wrist[2].toFixed(3)} | ${p.wrist[2].toFixed(3)} | ${srcTip[2].toFixed(3)} | ${tip[2].toFixed(3)} | ${(tip[2] - srcTip[2]).toFixed(3)} | ${liveHands.slotDebug('R', f).swing.toFixed(3)} | ${phase === 'hold' ? angleDeg(mcp, tip).toFixed(1).padStart(6) : '    -'} | ${(tip[0] - k!.x).toFixed(3).padStart(9)} | ${gaps.join(',')}`,
          )
        }
      }
    }
    void src
  }
}

runOnce(0.6, 'config: keystrike 0.6 (current)')
runOnce(0, 'config: keystrike 0 (isolate the swing layer)')
runOnce(0, 'config: keystrike 0 + NO humanize (isolate the lag)', false)
console.log('\ndone')
process.exit(0)
