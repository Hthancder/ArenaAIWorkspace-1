/**
 * Live-input hand overlay (v3) — the hands follow the user's MANUAL
 * playing: on-screen keys (mouse), PC keyboard and physical MIDI devices
 * all feed `audioEngine.triggerKey`, which emits on the live bus.
 *
 * v3 — 2026-11-15, after user feedback on v2 ("tay đơ ra, ngón không
 * nhấn vào phím như khi phát MIDI"; "bấm lặp 1 nốt phải trông như đang
 * bấm thật, không im 1 chỗ"; "hạn chế chuyển động quá đà và ảo của các
 * khớp"):
 *
 *  - REAL KEY-PRESS ARTICULATION. A press is an MCP swing of the finger
 *    around its knuckle (Rodrigues rotation — bone lengths preserved
 *    EXACTLY): the finger lifts at rest, sweeps down INTO the key on
 *    every key-down, stays pressed while held, and lifts back on
 *    release. v2's up-bob (a +z nudge) is gone — that read as a twitch,
 *    never as pressing a key.
 *
 *  - EVERY key-down pecks, even millisecond repeats: for PECK_SEC after
 *    a key-down the swing target SWEEPS hover → press, so a finger that
 *    is already down visibly lifts and strikes again ("đừng để im 1
 *    chỗ"). The whole hand dips ~1.4 mm on presses (weight) and the
 *    mesh's press squash fires at contact.
 *
 *  - HUMAN JOINT LIMITS. Every rotation is clamped (swing ∈ [-0.30,
 *    0.25] rad, abduction ±0.12 rad) and every motion is a rotation at
 *    a real joint or a rigid translation — joints never move alone, so
 *    nothing stretches ("méo mó", "mềm oặt", "ảo"). Nearby keys are
 *    reached by a limited MCP abduction (fingers fan toward their keys)
 *    plus whole-hand drift — never by stretching a finger.
 *
 *  - Adaptive hand presence (v2): a hand that is off stage comes up from
 *    a pose sample (mid-run of the song's motion, else the baked neutral
 *    pose), fades in from above and lowers away when the playing stops.
 *    Synthesised hands breathe (slow sway + per-finger flutter) so a
 *    free-play hand is never frozen ("tay đơ ra").
 *
 *  - Fingering: the song motion plan first (professional fingering),
 *    else the finger whose tip is naturally closest to the key. Wait
 *    Mode demand hover keeps its cue (the demanded finger lifts higher).
 *
 * Export safety: `update`/`applyToPoses` no-op and reset while the
 * exporter's virtual clock owns the engine — live state is
 * history-dependent and must never enter the frame-stepped render.
 */
import { audioEngine } from '../audio/engine'
import { keyForMidi } from '../keyboard/layout'
import { clamp, normalize, rotateAbout, rotateVec, shiftPose } from './geom'
import type { HandPose, HandPoses, Vec3 } from './types'

export type LiveHandsOpts = {
  playing: boolean
  /** 0..1 — strength of the per-press strike. */
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

// ---- artistic constants (world units: 1 mm = 0.01; angles in rad) ---------------------------------------------------

/** Swing at rest: the finger hovers, knuckle visibly raised. */
const SWING_HOVER = 0.12
/** Swing at contact, keystrike = 1: pressed INTO the key (negative = down). */
const SWING_PRESS = -0.34
/** Human MCP flexion limits — "hạn chế chuyển động quá đà" (still < a fist). */
const SWING_MIN = -0.55
const SWING_MAX = 0.35
/** MCP abduction limit (fingers fan toward nearby keys). */
const ABDUCT_MAX = 0.14
/** Each key-down sweeps lift → press over this window (visible peck). */
const PECK_SEC = 0.1
/** Windup: the finger visibly lifts before every strike (even repeats). */
const PECK_LIFT = 0.16
/** Wait Mode: the demanded finger lifts this much extra. */
const HOVER_EXTRA = 0.14
/** Weight cue: the whole hand sinks this far on presses (no elbow). */
const WRIST_DIP = 0.03
/** Max rigid x travel of an on-stage hand toward extra keys. */
const REACH_X = 1.2

const TAU_PRESS = 0.04
const TAU_RELEASE = 0.15
const TAU_ABDUCT = 0.08
const TAU_DRIFT = 0.09
const TAU_DRIFT_TRAVEL = 0.2 // a synthesised hand glides in slower
const TAU_VIS_IN = 0.14
const TAU_VIS_OUT = 0.28
const RELEASE_FADE_SEC = 0.35
/** Synthesised-hand entrance: comes down from above and toward the player. */
const ENTER_Z = 0.55
const ENTER_Y = -0.25
/** Synthesised-hand idle life ("không đơ"): slow sway + finger flutter. */
const SWAY_AMP = [0.008, 0.005, 0.006] as const
const FLUTTER = 0.012

type Slot = {
  /** Key bound to this finger while held / fading; null = free. */
  midi: number | null
  /** Key centre x of the bound key. */
  keyX: number
  /** Smoothed press amount, 0 (up) .. 1 (down) — drives the press flag. */
  tap: number
  /** Smoothed MCP swing angle (rad): + = lifted, − = pressed down. */
  swing: number
  /** Smoothed MCP abduction (rad): lateral fan toward the key. */
  abduct: number
  /** Seconds since the last key-down on this finger (peck window). */
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
  /** Per-hand phase for the idle sway (stable). */
  seed: number
}

const makeSlot = (): Slot => ({
  midi: null,
  keyX: 0,
  tap: 0,
  swing: 0,
  abduct: 0,
  strikeT: 9,
  held: false,
  freeAt: 0,
})

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
  seed: hand === 'L' ? 17.3 : 42.7,
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

const _axis: Vec3 = [0, 0, 0]

/**
 * MCP swing: rotate the finger chain (joints 1..3) around its knuckle
 * (joint 0). The hinge axis comes from the finger's own geometry —
 * `cross(tip − knuckle, up)` — so a positive angle lifts the tip and a
 * negative one presses it down toward the player. Bone lengths exact.
 * The thumb's twist references rotate with it (they are directions).
 */
function swingFinger(p: HandPose, f: number, theta: number): void {
  if (Math.abs(theta) < 1e-5) return
  const chain = p.fingers[f]
  const r: Vec3 = [chain[3][0] - chain[0][0], chain[3][1] - chain[0][1], chain[3][2] - chain[0][2]]
  // cross(r, (0,0,1)) = (r.y, −r.x, 0)
  _axis[0] = r[1]
  _axis[1] = -r[0]
  _axis[2] = 0
  if (Math.hypot(_axis[0], _axis[1]) < 1e-6) {
    _axis[0] = 1
    _axis[1] = 0
    _axis[2] = 0
  } else normalize(_axis)
  rotateAbout(chain[0], _axis, theta, [chain[1], chain[2], chain[3]])
  if (f === 0) for (const t of p.thumbRef) rotateVec(t, _axis, theta)
}

/**
 * MCP abduction: the finger chain fans sideways around its knuckle
 * (axis = up) toward a nearby key. Clamped by the caller to human range.
 */
function abductFinger(p: HandPose, f: number, phi: number): void {
  if (Math.abs(phi) < 1e-5) return
  const chain = p.fingers[f]
  _axis[0] = 0
  _axis[1] = 0
  _axis[2] = 1
  rotateAbout(chain[0], _axis, phi, [chain[1], chain[2], chain[3]])
  if (f === 0) for (const t of p.thumbRef) rotateVec(t, _axis, phi)
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
        if (s.midi !== null && !s.held && nowSec >= s.freeAt && s.tap < 0.02 && s.strikeT > PECK_SEC) {
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

    const k = clamp(Number.isFinite(opts.keystrike) ? opts.keystrike : 1, 0, 1)

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
      // Slot smoothing: press envelope + MCP swing + abduction targets.
      let cx = 0
      let cw = 0
      let tx = 0
      let tw = 0
      for (let f = 0; f < 5; f++) {
        const s = st.slots[f]
        s.strikeT = Math.min(2, s.strikeT + dt)
        const held = s.held ? 1 : 0
        s.tap += (held - s.tap) * (1 - Math.exp(-dt / (s.held ? TAU_PRESS : TAU_RELEASE)))
        if (s.tap < 0.001 && !s.held && s.midi === null) s.tap = 0

        // Swing target: at rest the finger hovers (synth hands) or keeps
        // the base articulation (song hands). Every key-down SWEEPS the
        // target windup → press over PECK_SEC — the finger visibly lifts
        // and strikes again even for millisecond repeats ("đừng để im 1
        // chỗ"); a held key stays pressed INTO the key.
        const press = SWING_PRESS * k
        const idle = st.synth ? SWING_HOVER : 0
        const demand = !opts.playing && pose.press[f] > 0.5 && !(s.midi !== null && s.tap > 0.5)
        let target = s.held ? press : idle + (demand ? HOVER_EXTRA : 0)
        let pecking = false
        if (s.strikeT < PECK_SEC) {
          const u = s.strikeT / PECK_SEC
          const e = u * u * (3 - 2 * u)
          target = idle + PECK_LIFT * (1 - e) + (press - idle) * e + (demand ? HOVER_EXTRA * (1 - e) : 0)
          pecking = true
        }
        target = clamp(target, SWING_MIN, SWING_MAX)
        const tau = pecking || target < s.swing ? TAU_PRESS : TAU_RELEASE
        s.swing += (target - s.swing) * (1 - Math.exp(-dt / tau))

        // Abduction: the finger fans toward its key; the whole-hand drift
        // below takes the mean, this absorbs the per-finger residual.
        let abTarget = 0
        if (s.midi !== null && (s.held || s.tap > 0.1)) {
          const resid = s.keyX - (pose.fingers[f][3][0] + st.drift)
          abTarget = clamp(resid * 0.6, -ABDUCT_MAX, ABDUCT_MAX)
        }
        s.abduct += (abTarget - s.abduct) * (1 - Math.exp(-dt / TAU_ABDUCT))

        if (s.midi !== null && s.held) {
          // Drift: bring the ASSIGNED FINGERS' tips toward their keys —
          // rigid, so a single press lands exactly, chords compromise at
          // the centroid. The pose is fresh each frame (no drift baked
          // in), so `keyX − tipX` is the TOTAL offset for st.drift.
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
      const driftTarget = onStage ? clamp(raw, -REACH_X, REACH_X) : raw
      const tauD = onStage ? TAU_DRIFT : TAU_DRIFT_TRAVEL
      st.drift += (driftTarget - st.drift) * (1 - Math.exp(-dt / tauD))

      this.applyTo(pose, st, opts, nowSec)
    }
  }

  /** Apply the current smoothed state to a full pose pair (blur sub-poses). */
  applyToPoses(poses: HandPoses, opts: LiveHandsOpts, buf?: { L: HandPose; R: HandPose }): void {
    const nowSec = performance.now() / 1000
    for (const hand of ['L', 'R'] as const) {
      const st = this[hand]
      let pose = poses[hand]
      if (!pose && st.synth && st.vis > 0.015) {
        const b = buf ? buf[hand] : st.buf
        copyPose(st.synth, b)
        pose = b
        poses[hand] = pose
      }
      if (pose) this.applyTo(pose, st, opts, nowSec)
    }
  }

  /**
   * Rigid transforms (translations / joint rotations — bone lengths
   * exact) + press flags. Nothing here ever moves a joint alone.
   */
  private applyTo(pose: HandPose, st: HandState, opts: LiveHandsOpts, nowSec: number): void {
    if (audioEngine.isExporting()) return
    // Synthesised-hand entrance (fade down from above, toward the player).
    if (st.synth) {
      const k = 1 - st.vis
      if (k > 0.001) shiftPose(pose, 0, ENTER_Y * k, ENTER_Z * k)
      // Idle life: slow sway so a free-play hand is never frozen.
      const t = nowSec
      shiftPose(
        pose,
        SWAY_AMP[0] * Math.sin(0.63 * t + st.seed),
        SWAY_AMP[1] * Math.sin(0.47 * t + st.seed * 1.7),
        SWAY_AMP[2] * Math.sin(0.71 * t + st.seed * 0.9),
      )
    }
    // Rigid travel toward the played keys.
    if (Math.abs(st.drift) > 0.0005) shiftPose(pose, st.drift, 0, 0)

    let maxTap = 0
    for (let f = 0; f < 5; f++) {
      const s = st.slots[f]
      const basePress = pose.press[f] > 0.5
      const live = s.midi !== null
      const press = opts.playing ? basePress || (live && s.tap > 0.5) : live && s.tap > 0.5
      pose.press[f] = press ? 1 : 0
      if (s.tap > maxTap) maxTap = s.tap
      // Finger flutter (synth hands only) keeps idle fingers alive.
      const flutter = st.synth ? FLUTTER * Math.sin(0.55 * nowSec + f * 1.31 + st.seed) : 0
      abductFinger(pose, f, s.abduct)
      swingFinger(pose, f, clamp(s.swing + (s.midi === null ? flutter : 0), SWING_MIN, SWING_MAX))
    }
    // Weight cue: the hand sinks slightly as the fingers press.
    const dip = WRIST_DIP * maxTap * clamp(Number.isFinite(opts.keystrike) ? opts.keystrike : 1, 0, 1)
    if (dip > 0.0005) shiftPose(pose, 0, 0, -dip, false)
  }

  /** Bind keys to (hand, finger): plan fingering first, reach otherwise. */
  private bind(wanted: { midi: number; keyX: number }[], poses: HandPoses, opts: LiveHandsOpts, nowSec: number): void {
    const newcomers: { midi: number; keyX: number }[] = []
    for (const w of wanted) {
      let bound = false
      for (const h of [this.L, this.R]) {
        for (const s of h.slots) {
          if (s.midi === w.midi) {
            if (!s.held) s.strikeT = 0 // every key-down pecks, even repeats
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

    // 2) Reach-based: the finger whose TIP is naturally closest to the
    //    key plays it ("hạn chế ngón vươn ra không tự nhiên") — the hand
    //    travels as a whole instead. A hand that is off stage may still
    //    come up — cheap on its own half of the keyboard.
    type Cand = { hand: 'L' | 'R'; finger: number; cost: number }
    const cands: Cand[] = []
    for (const hand of ['L', 'R'] as const) {
      const st = this[hand]
      const onStage = poses[hand] !== null || st.synth !== null
      const side = hand === 'L' ? -1 : 1
      const src = poses[hand] ?? st.synth
      for (let f = 0; f < 5; f++) {
        const s = st.slots[f]
        const tipX = src ? src.fingers[f][3][0] : side * 1.5
        let cost = onStage ? Math.abs(tipX - w.keyX) : 1.6 + Math.abs(w.keyX - side * 2.2) * 0.35
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
