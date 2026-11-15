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
import { boneDir, clamp, normalize, rotateAbout, rotateVec, shiftPose } from './geom'
import type { HandPose, HandPoses, Vec3 } from './types'

export type LiveHandsOpts = {
  playing: boolean
  /** 0..1 — strength of the per-press strike. */
  keystrike: number
  /**
   * 0..1 — expression layer ("có hồn", controlled): velocity-scaled
   * strike depth, forearm roll on accents, rolled chords, register
   * posture. Undefined/0 = exactly the neutral behaviour.
   */
  expression?: number
  /**
   * Velocity of the SONG note this (hand, finger) is playing right now,
   * or null. Lets the expression layer press harder on accents during
   * MIDI playback (the model's own articulation + a small extra dip).
   */
  expressAt?: (hand: 'L' | 'R', finger: number) => number | null
  /**
   * Natural fingering from the song's motion plan: for a pressed key,
   * the (hand, finger) planned for the nearest matching note. Returning
   * null falls back to reach-based assignment.
   */
  resolvePlan?: (midi: number) => { hand: 'L' | 'R'; finger: number } | null
  /** A realistic pose sample for a hand that is not on stage right now. */
  sampleHand?: (hand: 'L' | 'R') => HandPose | null
  /**
   * Imminent note per hand (anticipation): its key and the seconds until
   * it starts. The hand leans toward it a little before it is due — only
   * when not playing along with the motion (which already anticipates).
   */
  nextKey?: (hand: 'L' | 'R') => { keyX: number; in: number } | null
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

// ---- expression ("có hồn" — scaled by opts.expression, all clamped) -------------------------------------------------

/** Forearm roll around its own axis on accents (arm weight). */
const ACCENT_ROLL_MAX = 0.05
const ROLL_TAU_IN = 0.12
const ROLL_TAU_OUT = 0.5
/** Register posture (synth hands): a touch higher toward the treble. */
const POSTURE_Z = 0.02
/** Rolled chords: fingers of a near-simultaneous chord strike staggered. */
/** Idle fingers fan away from the playing ones (relaxed hand, never cramped). */
const RELAX_FAN = 0.09
/** Max hand travel speed (units/s) — drift glides, never snaps ("giật"). */
const DRIFT_RATE = 10
/** A far hand must not steal a key the near hand can take ("không tranh"). */
const CROSS_PENALTY = 2.2
/** The plan keeps its hand unless the other is this much nearer (slack). */
const PLAN_HAND_SLACK = 2.0
/** Recent-hand memory: a re-pressed key keeps its hand (no mid-key flip). */
const RECENT_HAND_SEC = 1.5
const RECENT_HAND_PENALTY = 0.8
/** Repetition scaling: windup ∝ recovery time (fast repeats = tight taps). */
const REPEAT_REF_SEC = 0.25
const REPEAT_MIN = 0.25
/** Release rebound: a small spring back past hover (rad, ~80 ms). */
const REBOUND_RAD = 0.02
const REBOUND_TAU = 0.35
/** Travel arc: the hand lifts while gliding to a new region (units, max). */
const ARC_LIFT = 0.04
/** Sympathetic coupling: idle neighbours breathe with the strike (rad). */
const COUPLE_AMP = 0.009
const COUPLE_TAU = 0.06
/** Deadzones: micro-tremor is never chased (units). */
const DRIFT_DEADZONE = 0.002
const ABDUCT_DEADZONE = 0.004
/** Anticipation: lean toward the next note when it is imminent. */
const ANTICIPATE_SEC = 0.4
const ANTICIPATE_W = 0.25

const CHORD_STAGGER = 0.02
const CHORD_WINDOW = 0.06
/** Model-press expression dip (playing case) smoothing. */
const DIP_TAU_IN = 0.06
const DIP_TAU_OUT = 0.22

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
  /** Velocity at the last key-down (0..1) — expression depth. */
  vel: number
  /** Rolled-chord stagger: this finger's peck starts after this delay. */
  peckDelay: number
  /** Model-press expression dip (playing case), rad, negative = deeper. */
  dip: number
  /** This strike's windup height (rad) — repetition-scaled (N1). */
  lift: number
  /** performance.now()/1000 of the previous key-down (repetition scale). */
  lastStrikeT: number
  /** Frozen hinge axis for the current strike (S3); null = recompute. */
  axis: Vec3 | null
  /** Release rebound impulse (rad, decaying). */
  rebound: number
  /** Sympathetic coupling depth (rad, smoothed, negative = flexion). */
  couple: number
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
  /** Smoothed accent roll around the forearm axis (rad). */
  roll: number
  /** Smoothed register posture z offset (synth hands). */
  posture: number
  /** performance.now()/1000 of the last key-down (chord grouping). */
  lastKeyT: number
  /** Running index within the current chord (rolled-chord stagger). */
  chordIdx: number
  /** Smoothed drift speed (units/s) — drives the travel arc (N2). */
  driftVel: number
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
  vel: 0.75,
  peckDelay: 0,
  dip: 0,
  lift: PECK_LIFT,
  lastStrikeT: -9,
  axis: null,
  rebound: 0,
  couple: 0,
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
  roll: 0,
  posture: 0,
  lastKeyT: -9,
  chordIdx: 0,
  driftVel: 0,
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
 * Pass `axis` to reuse a frozen strike axis (S3: one direction per press,
 * never wobbling with the humanizer's micro-noise).
 */
function swingFinger(p: HandPose, f: number, theta: number, axis?: Vec3 | null): void {
  if (Math.abs(theta) < 1e-5) return
  const chain = p.fingers[f]
  if (axis) {
    rotateAbout(chain[0], axis, theta, [chain[1], chain[2], chain[3]])
    if (f === 0) for (const t of p.thumbRef) rotateVec(t, axis, theta)
    return
  }
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
 * The hinge axis a strike would use right now (S3): `cross(tip − knuckle,
 * up)`, normalised; falls back to +x. Frozen at key-down so one press
 * rotates in ONE plane for its whole duration.
 */
function fingerAxis(p: HandPose, f: number): Vec3 {
  const chain = p.fingers[f]
  const r: Vec3 = [chain[3][0] - chain[0][0], chain[3][1] - chain[0][1], chain[3][2] - chain[0][2]]
  const out: Vec3 = [r[1], -r[0], 0]
  if (Math.hypot(out[0], out[1]) < 1e-6 || !Number.isFinite(out[0]) || !Number.isFinite(out[1])) {
    out[0] = 1
    out[1] = 0
    out[2] = 0
  } else normalize(out)
  return out
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
  /** midi → velocity of the last key-down (expression). */
  private heldVel = new Map<number, number>()
  /** midi → last (hand, t) that played it — repeat keeps its hand (S5). */
  private recent = new Map<number, { hand: 'L' | 'R'; t: number }>()
  private lastSec = 0
  private attached = false

  /** Per-hand visibility 0..1 (synth fade) for the mesh's opacity (S6). */
  visOf(hand: 'L' | 'R'): number {
    return this[hand].vis
  }

  /** Test/debug: a copy of one finger slot's motion state. */
  slotDebug(hand: 'L' | 'R', finger: number): { swing: number; abduct: number; axis: Vec3 | null; lift: number } {
    const s = this[hand].slots[finger]
    return { swing: s.swing, abduct: s.abduct, axis: s.axis ? ([...s.axis] as Vec3) : null, lift: s.lift }
  }

  attach(): () => void {
    if (this.attached) return () => {}
    this.attached = true
    const unsub = audioEngine.addLiveListener((e) => {
      if (e.type === 'noteOn') {
        this.held.set(e.midi, (this.held.get(e.midi) ?? 0) + 1)
        // One corrupt velocity (bad mapping, odd pointer event) must never
        // poison the overlay: a NaN would freeze that finger and collapse
        // the mesh for the rest of the session ("co rúm", "không bấm").
        this.heldVel.set(e.midi, Number.isFinite(e.velocity) ? clamp(e.velocity, 0, 1) : 0.75)
      } else if (e.type === 'noteOff') {
        const n = (this.held.get(e.midi) ?? 1) - 1
        if (n <= 0) {
          this.held.delete(e.midi)
          this.heldVel.delete(e.midi)
        } else this.held.set(e.midi, n)
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
    this.heldVel.clear()
    this.recent.clear()
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
    if (this.recent.size > 48) {
      for (const [midi, r] of this.recent) {
        if (nowSec - r.t > RECENT_HAND_SEC) this.recent.delete(midi)
      }
    }

    const wanted: { midi: number; keyX: number; vel: number }[] = []
    for (const midi of this.held.keys()) {
      const k = keyForMidi(midi)
      if (k) wanted.push({ midi, keyX: k.x, vel: this.heldVel.get(midi) ?? 0.75 })
    }
    const k = clamp(Number.isFinite(opts.keystrike) ? opts.keystrike : 1, 0, 1)
    const express = clamp(Number.isFinite(opts.expression) ? opts.expression! : 0, 0, 1)
    this.bind(wanted, poses, opts, nowSec, express)

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
      // Pre-pass on the FRESH pose (S1): drift takes the mean residual,
      // abduction only each finger's own DEVIATION from it — the two loops
      // never chase the same error (no landing wobble). `tapNow` is a
      // snapshot so neighbour reads are frame-order independent.
      const tapNow = [0, 1, 2, 3, 4].map((i) => st.slots[i].tap)
      const dResid = [0, 0, 0, 0, 0]
      let cx = 0
      let cw = 0
      let tx = 0
      let tw = 0
      let tipSum = 0
      for (let f = 0; f < 5; f++) {
        const s = st.slots[f]
        const tipX = pose.fingers[f][3][0]
        tipSum += tipX
        if (s.midi !== null && Number.isFinite(s.keyX) && Number.isFinite(tipX)) {
          dResid[f] = s.keyX - tipX
          if (s.held) {
            cx += dResid[f]
            cw += 1
          }
          tx += dResid[f]
          tw += 1
        }
      }
      const rawDrift = cw > 0 ? cx / cw : tw > 0 ? tx / tw : 0
      // Slot smoothing: press envelope + MCP swing + abduction targets.
      let rollAcc = 0
      let keySum = 0
      let keyN = 0
      for (let f = 0; f < 5; f++) {
        const s = st.slots[f]
        // Self-heal: one non-finite value must never freeze this finger for
        // the session — smoothing propagates NaN forever otherwise.
        if (!Number.isFinite(s.swing)) s.swing = 0
        if (!Number.isFinite(s.abduct)) s.abduct = 0
        if (!Number.isFinite(s.dip)) s.dip = 0
        if (!Number.isFinite(s.tap)) s.tap = 0
        if (!Number.isFinite(s.strikeT)) s.strikeT = 2
        if (!Number.isFinite(s.vel)) s.vel = 0.75
        if (!Number.isFinite(s.peckDelay)) s.peckDelay = 0
        if (!Number.isFinite(s.lift)) s.lift = PECK_LIFT
        if (!Number.isFinite(s.rebound)) s.rebound = 0
        if (!Number.isFinite(s.couple)) s.couple = 0
        if (!Number.isFinite(s.keyX)) {
          s.keyX = 0
          s.midi = null
          s.held = false
        }
        if (s.axis && !Number.isFinite(s.axis[0])) s.axis = null
        s.strikeT = Math.min(2, s.strikeT + dt)
        const held = s.held ? 1 : 0
        s.tap += (held - s.tap) * (1 - Math.exp(-dt / (s.held ? TAU_PRESS : TAU_RELEASE)))
        if (s.tap < 0.001 && !s.held && s.midi === null) s.tap = 0
        s.rebound *= Math.exp(-dt / REBOUND_TAU)

        // Swing target: at rest the finger hovers (synth hands) or keeps
        // the base articulation (song hands). Every key-down SWEEPS the
        // target windup → press over PECK_SEC — the finger visibly lifts
        // and strikes again even for millisecond repeats ("đừng để im 1
        // chỗ"); a held key stays pressed INTO the key. Expression: the
        // strike depth scales with the note's velocity (accents press
        // harder) and rolled chords stagger the fingers' strikes.
        const press = SWING_PRESS * k * (1 + express * 0.85 * (s.vel - 0.55))
        const idle = st.synth ? SWING_HOVER : 0
        const demand = !opts.playing && pose.press[f] > 0.5 && !(s.midi !== null && s.tap > 0.5)
        let target = s.held ? press : idle + (demand ? HOVER_EXTRA : 0)
        let pecking = false
        const u = (s.strikeT - s.peckDelay) / PECK_SEC
        if (u < 1) {
          // Windup first (waiting out the chord roll turn), then the sweep.
          // N1: the windup height scales with the recovery time — fast
          // repeats stay tight to the key, like a real repetition.
          const e = u <= 0 ? 0 : u * u * (3 - 2 * u)
          target = idle + s.lift * (1 - e) + (press - idle) * e + (demand ? HOVER_EXTRA * (1 - e) : 0)
          pecking = true
        }
        // Expression dip: during playback the song's own presses sink a
        // little deeper on loud notes ("bấm mạnh nốt cảm xúc").
        const rawVel = express > 0 && opts.expressAt ? opts.expressAt(hand, f) : null
        const mvel = rawVel !== null && Number.isFinite(rawVel) ? clamp(rawVel, 0, 1) : null
        const dipTarget =
          pose.press[f] > 0.5 && mvel !== null ? -express * clamp((mvel - 0.5) * 0.24, 0, 0.11) : 0
        s.dip += (dipTarget - s.dip) * (1 - Math.exp(-dt / (dipTarget < s.dip ? DIP_TAU_IN : DIP_TAU_OUT)))
        target += s.dip
        // N3 — release rebound: the finger springs a little past hover.
        if (!s.held && s.rebound > 0.001) target += s.rebound
        // N5 — sympathetic coupling: idle neighbours breathe with the
        // strike (≤0.02 rad flexion, lagged ~30 ms) — never when bound.
        if (s.midi === null) {
          let neigh = 0
          for (let i = 0; i < 5; i++) if (i !== f) neigh = Math.max(neigh, tapNow[i])
          const coupleTarget = -COUPLE_AMP * neigh
          s.couple += (coupleTarget - s.couple) * (1 - Math.exp(-dt / COUPLE_TAU))
          target += s.couple
        } else if (s.couple !== 0) {
          s.couple *= Math.exp(-dt / COUPLE_TAU)
          target += s.couple
        }
        target = Number.isFinite(target) ? clamp(target, SWING_MIN, SWING_MAX) : 0
        // The spring-back is a fast motion (like the strike); a normal
        // relaxed release is slow. `rebound > 0.004` lasts ~0.5 s (τ 0.35).
        const tau =
          pecking || target < s.swing || (s.rebound > 0.004 && target > s.swing) ? TAU_PRESS : TAU_RELEASE
        s.swing += (target - s.swing) * (1 - Math.exp(-dt / tau))

        // Abduction (S1): only the finger's deviation from what drift is
        // about to serve; deadzoned so micro-tremor is never chased.
        let abTarget = 0
        if (s.midi !== null && (s.held || s.tap > 0.1)) {
          const dev = dResid[f] - rawDrift
          abTarget =
            Number.isFinite(dev) && Math.abs(dev) > ABDUCT_DEADZONE
              ? clamp(dev * 0.6, -ABDUCT_MAX, ABDUCT_MAX)
              : 0
        } else if (s.midi === null && s.tap < 0.05) {
          // Idle fingers open up a little while the others work, so the
          // playing finger is never cramped ("quặp vào trong"): they fan
          // apart — the thumb opens outward — within human range.
          let busy = 0
          for (let i = 0; i < 5; i++) {
            if (i !== f) busy = Math.max(busy, tapNow[i])
          }
          if (busy > 0.3) {
            const fanDir = st.hand === 'R' ? -Math.sign(f - 2) : Math.sign(f - 2)
            abTarget = RELAX_FAN * fanDir * Math.min(1, (busy - 0.3) / 0.4)
          }
        }
        s.abduct += (abTarget - s.abduct) * (1 - Math.exp(-dt / TAU_ABDUCT))

        // Accent roll (arm weight): strong notes roll the hand around the
        // forearm axis — toward the thumb on thumb notes, the other way
        // on pinky notes. Bounded and centred.
        const av = s.held ? s.vel : mvel
        if (av !== null && av > 0.72) {
          rollAcc += express * ACCENT_ROLL_MAX * clamp((av - 0.72) / 0.28, 0, 1) * ((2 - f) / 2)
        }
        if (s.midi !== null) {
          keySum += s.keyX
          keyN += 1
        }
      }
      // On-stage hands only drift within reach; a travelling synthesised
      // hand goes all the way to its keys (it entered for exactly that).
      // N4 — anticipation: when not playing along (the motion already
      // leads there), lean toward the imminent note, bounded.
      let driftTarget = Number.isFinite(rawDrift) ? (onStage ? clamp(rawDrift, -REACH_X, REACH_X) : rawDrift) : 0
      if (!opts.playing && opts.nextKey) {
        const nk = opts.nextKey(hand)
        if (nk && Number.isFinite(nk.keyX) && nk.in > 0 && nk.in <= ANTICIPATE_SEC) {
          const lean = clamp(nk.keyX - tipSum / 5, -REACH_X, REACH_X)
          const w = ANTICIPATE_W * (1 - nk.in / ANTICIPATE_SEC)
          driftTarget = (1 - w) * driftTarget + w * lean
        }
      }
      const tauD = onStage ? TAU_DRIFT : TAU_DRIFT_TRAVEL
      if (!Number.isFinite(st.drift)) st.drift = 0
      const driftErr = driftTarget - st.drift
      // S2 — deadzone: the humanizer's micro-tremor is breathing, not
      // travel; do not chase it. Rate limit: glide, never snap ("giật").
      const driftStep =
        Math.abs(driftErr) > DRIFT_DEADZONE ? driftErr * (1 - Math.exp(-dt / tauD)) : 0
      const speed = driftStep / Math.max(dt, 1e-4)
      st.driftVel += (speed - st.driftVel) * (1 - Math.exp(-dt / 0.12))
      st.drift += clamp(driftStep, -DRIFT_RATE * dt, DRIFT_RATE * dt)

      // Accent roll smoothing (recovers slowly when the accents pass).
      if (!Number.isFinite(st.roll)) st.roll = 0
      const rollTarget = Number.isFinite(rollAcc) ? clamp(rollAcc, -ACCENT_ROLL_MAX, ACCENT_ROLL_MAX) : 0
      st.roll += (rollTarget - st.roll) * (1 - Math.exp(-dt / (Math.abs(rollTarget) > Math.abs(st.roll) ? ROLL_TAU_IN : ROLL_TAU_OUT)))

      // Register posture (synth hands only — the model hands already
      // carry their own): treble a touch higher, bass a touch heavier.
      if (!Number.isFinite(st.posture)) st.posture = 0
      const postureTarget = st.synth ? express * POSTURE_Z * Math.tanh(keyN ? keySum / keyN / 2.4 : 0) : 0
      st.posture += (postureTarget - st.posture) * (1 - Math.exp(-dt / 0.35))

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
    // Expression posture (register): a touch higher toward the treble.
    if (Math.abs(st.posture) > 0.0005) shiftPose(pose, 0, 0, st.posture)
    // Rigid travel toward the played keys.
    if (Math.abs(st.drift) > 0.0005) shiftPose(pose, st.drift, 0, 0)
    // N2 — travel arc: while the hand glides to a new region it lifts a
    // little (speed-proportional, ≤ 4 mm) and settles as it lands — a hand
    // that "flies" instead of sliding on rails.
    const arc = ARC_LIFT * clamp(Math.abs(st.driftVel) / DRIFT_RATE, 0, 1)
    if (arc > 0.0005) shiftPose(pose, 0, arc, 0)
    // Accent roll: the hand rolls around its forearm axis (arm weight on
    // strong notes). Rotation about the wrist on the forearm axis — bone
    // lengths exact.
    if (Math.abs(st.roll) > 1e-4 && boneDir(pose.elbow, pose.wrist, _axis) > 1e-6) {
      const pts: Vec3[] = [...pose.bases, ...pose.fingers.flat()]
      rotateAbout(pose.wrist, _axis, st.roll, pts)
      for (const t of pose.thumbRef) rotateVec(t, _axis, st.roll)
    }

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
      // S3 — one hinge axis per strike: frozen from the pose at key-down
      // (first active frame), freed between strikes.
      const active = s.held || s.strikeT < PECK_SEC
      if (active && !s.axis) s.axis = fingerAxis(pose, f)
      if (!active && s.axis) s.axis = null
      swingFinger(pose, f, clamp(s.swing + (s.midi === null ? flutter : 0), SWING_MIN, SWING_MAX), s.axis)
    }
    // Weight cue: the hand sinks slightly as the fingers press.
    const dip = WRIST_DIP * maxTap * clamp(Number.isFinite(opts.keystrike) ? opts.keystrike : 1, 0, 1)
    if (dip > 0.0005) shiftPose(pose, 0, 0, -dip, false)
  }

  /** Every key-down: peck reset + velocity capture + rolled-chord stagger. */
  private onKeyDown(st: HandState, s: Slot, vel: number, nowSec: number, express: number): void {
    s.strikeT = 0
    s.vel = Number.isFinite(vel) ? clamp(vel, 0, 1) : 0.75
    // N1 — repetition scaling: a fast repeat barely lifts (the key has not
    // recovered either); a slow one gets the full windup.
    const sincePrev = nowSec - s.lastStrikeT
    s.lastStrikeT = nowSec
    s.lift = PECK_LIFT * clamp(sincePrev / REPEAT_REF_SEC, REPEAT_MIN, 1)
    s.axis = null // S3 — freeze a fresh hinge axis for this strike
    s.rebound = 0 // the spring belongs to the previous release
    if (s.midi !== null) this.recent.set(s.midi, { hand: st.hand, t: nowSec })
    if (nowSec - st.lastKeyT < CHORD_WINDOW) st.chordIdx++
    else st.chordIdx = 0
    st.lastKeyT = nowSec
    s.peckDelay = Math.min(3, st.chordIdx) * CHORD_STAGGER * express
  }

  /** Bind keys to (hand, finger): plan fingering first, reach otherwise. */
  private bind(
    wanted: { midi: number; keyX: number; vel: number }[],
    poses: HandPoses,
    opts: LiveHandsOpts,
    nowSec: number,
    express: number,
  ): void {
    const newcomers: { midi: number; keyX: number; vel: number }[] = []
    for (const w of wanted) {
      let bound = false
      for (const h of [this.L, this.R]) {
        for (const s of h.slots) {
          if (s.midi === w.midi) {
            if (!s.held) this.onKeyDown(h, s, w.vel, nowSec, express) // every key-down pecks, even repeats
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
          s.rebound = REBOUND_RAD // N3 — the finger springs back a little
        }
      }
    }
    for (const w of newcomers) this.claim(w, poses, opts, nowSec, express)
  }

  private claim(
    w: { midi: number; keyX: number; vel: number },
    poses: HandPoses,
    opts: LiveHandsOpts,
    nowSec: number,
    express: number,
  ): void {
    // Where each hand actually is (its wrist + accumulated drift). Used
    // to keep each key on the NEAR hand — the far hand must not reach
    // over ("tay phải tranh xử lý nốt gần tay trái") and leave its own
    // keys unplayed.
    const palmOf = (hand: 'L' | 'R'): number => {
      const st = this[hand]
      const src0 = poses[hand] ?? st.synth
      // st.buf is a working copy at the origin until used — never trust it
      // for proximity; fall back to the hand's stand anchor instead.
      const src = src0 && src0 !== st.buf ? src0 : null
      return (src ? src.wrist[0] : hand === 'L' ? -1.5 : 1.5) + st.drift
    }
    const dL = Math.abs(palmOf('L') - w.keyX)
    const dR = Math.abs(palmOf('R') - w.keyX)
    const nearer: 'L' | 'R' = dL <= dR ? 'L' : 'R'

    // 1) The song's own fingering, when this key is a note near the
    //    playhead — unless that hand is clearly farther from the key
    //    than the other one (which is free to take it).
    const plan = opts.resolvePlan ? opts.resolvePlan(w.midi) : null
    if (plan && plan.finger >= 0 && plan.finger < 5) {
      const other = plan.hand === 'L' ? 'R' : 'L'
      const dPlan = Math.abs(palmOf(plan.hand) - w.keyX)
      const dOther = Math.abs(palmOf(other) - w.keyX)
      const otherFree = this[other].slots.some((o) => o.midi === null)
      if (dPlan <= dOther + PLAN_HAND_SLACK || !otherFree) {
        const st = this[plan.hand]
        const s = st.slots[plan.finger]
        s.midi = w.midi
        s.keyX = w.keyX
        s.held = true
        this.onKeyDown(st, s, w.vel, nowSec, express)
        // The planned finger takes over: free fading neighbours early so a
        // fingering change reads as a clean hand-off, not two stuck fingers.
        for (const o of st.slots) {
          if (o !== s && o.midi !== null && !o.held && Math.abs(o.keyX - w.keyX) < 1.4) o.freeAt = 0
        }
        return
      }
      // The plan's hand is clearly farther — fall through to the reach
      // claim so the nearer hand takes it instead.
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
        // The near hand owns its keys: the far hand only steps in when the
        // near one is genuinely busy ("không tranh, không giật").
        if (hand !== nearer) cost += CROSS_PENALTY
        // S5 — a repeat keeps its HAND: a key played moments ago stays on
        // the same side even at the midline (no flick between hands).
        const rec = this.recent.get(w.midi)
        if (rec && nowSec - rec.t < RECENT_HAND_SEC && rec.hand !== hand) cost += RECENT_HAND_PENALTY
        if (s.midi === w.midi) cost -= 0.7 // repeats keep their finger
        else if (s.midi !== null && !s.held && Math.abs(s.keyX - w.keyX) < 1.4) cost -= 0.45 // stepwise continuity
        if (f === 0) cost += 0.12 // keep the thumb in reserve a little
        if (f === 0 && keyForMidi(w.midi)?.isBlack) cost += 0.22 // thumbs prefer white keys
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
    this.onKeyDown(this[pick.hand], s, w.vel, nowSec, express)
  }
}

export const liveHands = new LiveHandsOverlay()
