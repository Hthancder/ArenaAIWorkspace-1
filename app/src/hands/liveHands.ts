/**
 * Live-input hand overlay (v2) — the hands follow the user's MANUAL
 * playing: on-screen keys (mouse), PC keyboard and physical MIDI devices
 * all feed `audioEngine.triggerKey`, which emits on the live bus.
 *
 * v2 — 2026-11-15, following user feedback on v1 ("ngón tay bị kéo dãn,
 * không tự nhiên, bị force"; "bấm phím bên trái thì tay trái phải lên bấm"):
 *
 *  - RIGID-ONLY motion. v1 lerped individual finger joints toward the
 *    pressed key and sheared the palm (wrist ×1.0 vs bases ×0.18),
 *    stretching bone chains. Now every transform is a UNIFORM translation
 *    of a joint chain — bone lengths are preserved to within ~1 % (the
 *    tiny proximal-length change of a finger bob is dz²/2L, invisible).
 *    No joint is ever moved toward a target independently of its chain.
 *
 *  - Adaptive hand presence. A pressed key is played by the hand the
 *    SONG's motion plan assigns to the matching note (natural,
 *    professional fingering), else by the hand that can reach it with the
 *    least travel (the keyboard's left half belongs to the left hand).
 *    If that hand is NOT on stage (the runtime keeps a hand "in the lap"
 *    — poseAt returns null — outside its planned notes) it COMES UP from
 *    a cached pose sample of that hand: it fades in from above while
 *    travelling to the key, and lowers away again when the playing stops,
 *    mirroring the runtime's own enter/exit language.
 *
 *  - Every key-down kicks a short strike envelope on its finger, so a
 *    note pressed many times visibly taps every time ("phải có chuyển
 *    động trông như bấm chứ không phải giữ nguyên 1 chỗ").
 *
 *  - While the transport is NOT playing (Wait Mode / pause) the press
 *    flags are purely live-driven: a finger the frozen pose demands
 *    hovers just above its key until the user actually plays it.
 *
 * Export safety: `update`/`applyToPoses` no-op and reset while the
 * exporter's virtual clock owns the engine — live state is
 * history-dependent and must never enter the frame-stepped render.
 */
import { audioEngine } from '../audio/engine'
import { keyForMidi } from '../keyboard/layout'
import type { HandPose, HandPoses, Vec3 } from './types'

export type LiveHandsOpts = {
  playing: boolean
  /** 0..1 — strength of the per-press strike tap. */
  keystrike: number
  /**
   * Natural fingering from the song's motion plan: for a pressed key,
   * the (hand, finger) planned for the nearest matching note. Returning
   * null falls back to reach-based assignment.
   */
  resolvePlan?: (midi: number) => { hand: 'L' | 'R'; finger: number } | null
  /** A realistic pose sample for a hand that is not on stage right now. */
  sampleHand?: (hand: 'L' | 'R') => HandPose | null
}

/** Demand-cue lift above the key (Wait Mode: finger hovers until played). */
const HOVER_Z = 0.09
/** Per-press strike amplitude at keystrike = 1 (uniform on the chain). */
const STRIKE_Z = 0.06
const STRIKE_SEC = 0.13
/** Max rigid x travel of an on-stage hand toward extra keys. */
const REACH_X = 1.2
const TAU_ATTACK = 0.055
const TAU_RELEASE = 0.14
const TAU_DRIFT = 0.09
const TAU_DRIFT_TRAVEL = 0.2 // a synthesised hand glides in slower
const TAU_VIS_IN = 0.14
const TAU_VIS_OUT = 0.28
const RELEASE_FADE_SEC = 0.35
/** Synthesised-hand entrance: comes down from above and toward the player. */
const ENTER_Z = 0.55
const ENTER_Y = -0.25

type Slot = {
  /** Key bound to this finger while held / fading; null = free. */
  midi: number | null
  /** Key centre x of the bound key. */
  keyX: number
  /** Smoothed press amount, 0 (up) .. 1 (down). */
  tap: number
  /** Smoothed demand-hover lift (rigid on joints 1..3). */
  lift: number
  /** Seconds since the last key-down on this finger (strike envelope). */
  strikeT: number
  /** True while the physical key is down. */
  held: boolean
  /** performance.now()/1000 when a released binding expires. */
  freeAt: number
}

type HandState = {
  hand: 'L' | 'R'
  slots: [Slot, Slot, Slot, Slot, Slot]
  /** Smoothed rigid x translation toward the played keys. */
  drift: number
  /** 0..1 visibility of the synthesised (off-stage) hand. */
  vis: number
  /** Cached pose sample for the off-stage hand (never mutated). */
  synth: HandPose | null
  /** Working copy exposed in `poses` when the hand is synthesised. */
  buf: HandPose
}

const makeSlot = (): Slot => ({ midi: null, keyX: 0, tap: 0, lift: 0, strikeT: 9, held: false, freeAt: 0 })

function allocPose(hand: 'L' | 'R'): HandPose {
  return {
    hand,
    elbow: [0, 0, 0],
    wrist: [0, 0, 0],
    bases: Array.from({ length: 5 }, () => [0, 0, 0] as Vec3),
    fingers: Array.from({ length: 5 }, () => Array.from({ length: 4 }, () => [0, 0, 0] as Vec3)),
    press: [0, 0, 0, 0, 0],
    thumbRef: Array.from({ length: 3 }, () => [0, 0, 0] as Vec3),
  }
}

const makeHand = (hand: 'L' | 'R'): HandState => ({
  hand,
  slots: [makeSlot(), makeSlot(), makeSlot(), makeSlot(), makeSlot()],
  drift: 0,
  vis: 0,
  synth: null,
  buf: allocPose(hand),
})

function copyPose(src: HandPose, dst: HandPose): void {
  dst.hand = src.hand
  copyVec(src.elbow, dst.elbow)
  copyVec(src.wrist, dst.wrist)
  for (let i = 0; i < 5; i++) {
    copyVec(src.bases[i], dst.bases[i])
    for (let j = 0; j < 4; j++) copyVec(src.fingers[i][j], dst.fingers[i][j])
  }
  for (let i = 0; i < 3; i++) copyVec(src.thumbRef[i] ?? src.bases[Math.min(i, 4)], dst.thumbRef[i])
  for (let i = 0; i < 5; i++) dst.press[i] = src.press[i] ?? 0
}

const copyVec = (a: Vec3, b: Vec3) => {
  b[0] = a[0]
  b[1] = a[1]
  b[2] = a[2]
}

/** Uniform translation of every joint — bone lengths preserved exactly. */
function shiftHand(p: HandPose, dx: number, dy: number, dz: number): void {
  const s = (v: Vec3) => {
    v[0] += dx
    v[1] += dy
    v[2] += dz
  }
  s(p.elbow)
  s(p.wrist)
  for (const b of p.bases) s(b)
  for (const chain of p.fingers) for (const j of chain) s(j)
  for (const t of p.thumbRef) s(t)
}

/**
 * Finger bob: joints 1..3 move by the SAME dz (rigid on the proximal →
 * distal span; the metacarpal length changes by ~dz²/2L ≈ 1 %, invisible).
 */
function bobFinger(p: HandPose, f: number, dz: number): void {
  for (let k = 1; k < 4; k++) p.fingers[f][k][2] += dz
}

function clamp(v: number, m: number): number {
  return Math.max(-m, Math.min(m, v))
}

class LiveHandsOverlay {
  private L = makeHand('L')
  private R = makeHand('R')
  /** midi → how many sources hold it (a key can be pressed twice). */
  private held = new Map<number, number>()
  private lastSec = 0
  private attached = false

  attach(): () => void {
    if (this.attached) return () => {}
    this.attached = true
    const unsub = audioEngine.addLiveListener((e) => {
      if (e.type === 'noteOn') this.held.set(e.midi, (this.held.get(e.midi) ?? 0) + 1)
      else if (e.type === 'noteOff') {
        const n = (this.held.get(e.midi) ?? 1) - 1
        if (n <= 0) this.held.delete(e.midi)
        else this.held.set(e.midi, n)
      }
    })
    return () => {
      this.attached = false
      this.reset()
      unsub()
    }
  }

  reset(): void {
    this.held.clear()
    this.L = makeHand('L')
    this.R = makeHand('R')
    this.lastSec = 0
  }

  /**
   * Advance the overlay one frame and apply it to `poses` (in place).
   * Hands that are off stage but needed get synthesised into the state's
   * own buffer and assigned into `poses`.
   */
  update(poses: HandPoses, opts: LiveHandsOpts): void {
    if (audioEngine.isExporting()) {
      this.reset()
      return
    }
    const nowSec = performance.now() / 1000
    const dt = Math.min(0.1, Math.max(0, nowSec - (this.lastSec || nowSec)))
    this.lastSec = nowSec

    // Release expired bindings — only once the finger has visually settled.
    for (const h of [this.L, this.R]) {
      for (const s of h.slots) {
        if (s.midi !== null && !s.held && nowSec >= s.freeAt && s.tap < 0.02 && s.strikeT > STRIKE_SEC) {
          s.midi = null
          s.keyX = 0
        }
      }
    }

    const wanted: { midi: number; keyX: number }[] = []
    for (const midi of this.held.keys()) {
      const k = keyForMidi(midi)
      if (k) wanted.push({ midi, keyX: k.x })
    }
    this.bind(wanted, poses, opts, nowSec)

    for (const hand of ['L', 'R'] as const) {
      const st = this[hand]
      // A pose we assigned ourselves last frame (st.buf) is NOT a real
      // on-stage hand — the synth fade logic must keep owning it.
      const onStage = poses[hand] !== null && poses[hand] !== st.buf
      if (onStage) {
        st.vis = 1
        st.synth = null
      } else {
        const hasHeld = st.slots.some((s) => s.midi !== null && s.held)
        if (!st.synth && (hasHeld || st.slots.some((s) => s.midi !== null))) {
          st.synth = opts.sampleHand ? opts.sampleHand(hand) : null
        }
        const target = hasHeld ? 1 : 0
        const tau = target > st.vis ? TAU_VIS_IN : TAU_VIS_OUT
        st.vis += (target - st.vis) * (1 - Math.exp(-dt / tau))
        if (!st.synth || (st.vis < 0.015 && target === 0)) {
          st.synth = null
          st.vis = 0
          poses[hand] = null // the hand lowers away for good
          continue
        }
        copyPose(st.synth, st.buf)
        poses[hand] = st.buf
      }

      const pose = poses[hand]!
      // Slot smoothing: press tap, demand hover, strike envelope.
      let cx = 0
      let cw = 0
      let tx = 0
      let tw = 0
      for (let f = 0; f < 5; f++) {
        const s = st.slots[f]
        s.strikeT = Math.min(2, s.strikeT + dt)
        const target = s.held ? 1 : 0
        const tau = s.held ? TAU_ATTACK : TAU_RELEASE
        s.tap += (target - s.tap) * (1 - Math.exp(-dt / tau))
        if (s.tap < 0.001 && !s.held && s.midi === null) s.tap = 0
        const demandHover = !opts.playing && pose.press[f] > 0.5 && !(s.midi !== null && s.tap > 0.5)
        const liftTarget = demandHover ? HOVER_Z : 0
        s.lift += (liftTarget - s.lift) * (1 - Math.exp(-dt / TAU_ATTACK))
        if (s.midi !== null && s.held) {
          // Drift: bring the ASSIGNED FINGERS' tips toward their keys —
          // rigid, so a single press lands exactly, chords compromise at
          // the centroid.
          cx += s.keyX - pose.fingers[f][3][0]
          cw += 1
        }
        if (s.midi !== null) {
          tx += s.keyX - pose.fingers[f][3][0]
          tw += 1
        }
      }
      // On-stage hands only drift within reach; a travelling synthesised
      // hand goes all the way to its keys (it entered for exactly that).
      const raw = cw > 0 ? cx / cw : tw > 0 ? tx / tw : 0
      const driftTarget = onStage ? clamp(raw, REACH_X) : raw
      const tauD = onStage ? TAU_DRIFT : TAU_DRIFT_TRAVEL
      st.drift += (driftTarget - st.drift) * (1 - Math.exp(-dt / tauD))

      this.applyTo(pose, st, opts)
    }
  }

  /** Apply the current smoothed state to a full pose pair (blur sub-poses). */
  applyToPoses(poses: HandPoses, opts: LiveHandsOpts, buf?: { L: HandPose; R: HandPose }): void {
    for (const hand of ['L', 'R'] as const) {
      const st = this[hand]
      let pose = poses[hand]
      if (!pose && st.synth && st.vis > 0.015) {
        const b = buf ? buf[hand] : st.buf
        copyPose(st.synth, b)
        pose = b
        poses[hand] = pose
      }
      if (pose) this.applyTo(pose, st, opts)
    }
  }

  /** Rigid transforms + press flags. Never moves one joint alone. */
  private applyTo(pose: HandPose, st: HandState, opts: LiveHandsOpts): void {
    if (audioEngine.isExporting()) return
    // Synthesised-hand entrance (fade down from above, toward the player).
    if (st.synth) {
      const k = 1 - st.vis
      if (k > 0.001) shiftHand(pose, 0, ENTER_Y * k, ENTER_Z * k)
    }
    // Rigid travel toward the played keys.
    if (Math.abs(st.drift) > 0.0005) shiftHand(pose, st.drift, 0, 0)
    for (let f = 0; f < 5; f++) {
      const s = st.slots[f]
      const basePress = pose.press[f] > 0.5
      const live = s.midi !== null
      const press = opts.playing ? basePress || (live && s.tap > 0.5) : live && s.tap > 0.5
      pose.press[f] = press ? 1 : 0
      // Rigid finger bob: demand hover + per-press strike envelope.
      const u = s.strikeT / STRIKE_SEC
      const strike = u < 1 ? STRIKE_Z * (1 - u) * (1 - u) * Math.min(1, Math.max(0, opts.keystrike)) : 0
      const dz = s.lift + strike
      if (Math.abs(dz) > 0.0005) bobFinger(pose, f, dz)
    }
  }

  /** Bind keys to (hand, finger): plan fingering first, reach otherwise. */
  private bind(wanted: { midi: number; keyX: number }[], poses: HandPoses, opts: LiveHandsOpts, nowSec: number): void {
    const newcomers: { midi: number; keyX: number }[] = []
    for (const w of wanted) {
      let bound = false
      for (const h of [this.L, this.R]) {
        for (const s of h.slots) {
          if (s.midi === w.midi) {
            if (!s.held) s.strikeT = 0 // every key-down taps, even repeats
            s.held = true
            s.keyX = w.keyX
            bound = true
          }
        }
      }
      if (!bound) newcomers.push(w)
    }
    for (const h of [this.L, this.R]) {
      for (const s of h.slots) {
        if (s.midi !== null && !wanted.some((w) => w.midi === s.midi) && s.held) {
          s.held = false
          s.freeAt = nowSec + RELEASE_FADE_SEC
        }
      }
    }
    for (const w of newcomers) this.claim(w, poses, opts)
  }

  private claim(w: { midi: number; keyX: number }, poses: HandPoses, opts: LiveHandsOpts): void {
    // 1) The song's own fingering, when this key is a note near the playhead.
    const plan = opts.resolvePlan ? opts.resolvePlan(w.midi) : null
    if (plan && plan.finger >= 0 && plan.finger < 5) {
      const st = this[plan.hand]
      const s = st.slots[plan.finger]
      s.midi = w.midi
      s.keyX = w.keyX
      s.held = true
      s.strikeT = 0
      // The planned finger takes over: free fading neighbours early so a
      // fingering change reads as a clean hand-off, not two stuck fingers.
      for (const o of st.slots) {
        if (o !== s && o.midi !== null && !o.held && Math.abs(o.keyX - w.keyX) < 1.4) o.freeAt = 0
      }
      return
    }

    // 2) Reach-based: the hand that travels least. A hand that is off
    //    stage may still come up — cheap on its own half of the keyboard.
    type Cand = { hand: 'L' | 'R'; finger: number; cost: number }
    const cands: Cand[] = []
    for (const hand of ['L', 'R'] as const) {
      const st = this[hand]
      const onStage = poses[hand] !== null || st.synth !== null
      const side = hand === 'L' ? -1 : 1
      for (let f = 0; f < 5; f++) {
        const s = st.slots[f]
        const baseX = poses[hand] ? poses[hand]!.bases[f][0] : st.synth ? st.synth.bases[f][0] : 0
        let cost = onStage ? Math.abs(baseX - w.keyX) : 1.6 + Math.abs(w.keyX - side * 2.2) * 0.35
        if (s.midi === w.midi) cost -= 0.7 // repeats keep their finger
        else if (s.midi !== null && !s.held && Math.abs(s.keyX - w.keyX) < 1.4) cost -= 0.45 // stepwise continuity
        if (f === 0) cost += 0.12 // keep the thumb in reserve a little
        if (s.midi !== null && s.held) cost += 3 // never steal a held finger
        cands.push({ hand, finger: f, cost })
      }
    }
    cands.sort((a, b) => a.cost - b.cost)
    const pick = cands[0]
    if (!pick) return
    const s = this[pick.hand].slots[pick.finger]
    if (s.midi !== null && !s.held) s.freeAt = 0 // supersede the fading binding
    s.midi = w.midi
    s.keyX = w.keyX
    s.held = true
    s.strikeT = 0
  }
}

export const liveHands = new LiveHandsOverlay()
