/**
 * Humanize the hand motion — make the planned poses read as a person
 * playing rather than a robot arm.
 *
 * HARD RULE: the result must stay a PURE function of `t`. The exporter
 * frame-steps the scene with a virtual clock and the motion-blur path
 * samples poses at `t + o`; any frame-history filter (EMA, spring state)
 * would make exported frames diverge from the preview. Everything here
 * is therefore expressed as deterministic taps of the source stream:
 *
 *   lag      — evaluate the source slightly in the past (τ per joint
 *              group: fingers light, wrist heavier, elbow heaviest)
 *   settle   — add a velocity term β·(v(t−τ) − v(t−2τ)) so fast moves
 *              overshoot a touch and ease in, instead of tracking linearly
 *   micro    — deterministic physiological tremor + slow drift (~0.3 Hz
 *              breathing, ~8 Hz tremor band), scaled per joint group
 *
 * The three source taps are shared by both hands (poseAt returns both),
 * so the whole pass costs 3 pose queries per frame.
 *
 * Tunables (`Settings`): handsHumanizeEnabled / handsSmoothness /
 * handsMicroMotion. The numeric constants below are ARTISTIC parameters
 * chosen for feel (world units: 1 mm = 0.01), not spec figures — they
 * are exposed as sliders so the user owns the final word.
 */
import { boneDir, normalize, rotateAbout, rotateVec } from './geom'
import type { HandPose, HandPoses, Vec3 } from './types'

export type HumanizeParams = {
  enabled: boolean
  /** 0..1 — more lag + settle ("floaty"), less = snappy. */
  smoothness: number
  /** 0..1 — tremor / drift amplitude scale. */
  microMotion: number
}

/** Base lag (seconds) of the wrist at smoothness 1. Fingers/elbow scale via tap choice. */
const LAG_WRIST = 0.055
/** Settle (overshoot) gain at smoothness 1. */
const SETTLE_WRIST = 0.45
const SETTLE_FINGER = 0.3
/** Micro-motion amplitudes at microMotion 1 (world units). */
const AMP_FINGER = 0.011
const AMP_WRIST = 0.007
const AMP_ELBOW = 0.004

// ---- deterministic noise --------------------------------------------------------------------------------------------

/**
 * Smooth pseudo-noise in [-1, 1] from three sine bands (slow drift,
 * sway, physiological tremor) with per-joint phases from an integer
 * hash — no RNG state, so the same t always gives the same value.
 */
function band(t: number, seed: number, bandHz: number): number {
  const h1 = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
  const h2 = Math.sin(seed * 39.3468 + 11.135) * 24634.6345
  const p1 = (h1 - Math.floor(h1)) * Math.PI * 2
  const p2 = (h2 - Math.floor(h2)) * Math.PI * 2
  return 0.6 * Math.sin(2 * Math.PI * bandHz * t + p1) + 0.4 * Math.sin(2 * Math.PI * bandHz * 2.13 * t + p2)
}

function micro(t: number, seed: number, amp: number, out: Vec3): void {
  if (amp <= 0) {
    out[0] = 0
    out[1] = 0
    out[2] = 0
    return
  }
  out[0] = amp * 0.6 * band(t, seed + 1, 0.31)
  out[1] = amp * 0.6 * band(t, seed + 2, 0.27)
  out[2] = amp * (0.7 * band(t, seed + 3, 8.2) + 0.3 * band(t, seed + 4, 1.6))
}

// ---- scratch geometry ------------------------------------------------------------------------------------------------

/** One humanized hand's output buffer + per-joint noise scratch. */
export type HumanizedHand = {
  pose: HandPose
  noise: Vec3
}

function allocHand(hand: HandPose['hand']): HumanizedHand {
  return {
    pose: {
      hand,
      elbow: [0, 0, 0],
      wrist: [0, 0, 0],
      bases: Array.from({ length: 5 }, () => [0, 0, 0] as Vec3),
      fingers: Array.from({ length: 5 }, () =>
        Array.from({ length: 4 }, () => [0, 0, 0] as Vec3),
      ),
      press: [0, 0, 0, 0, 0],
      // 3 entries — the runtime emits `fkThumbRefs` = 9 floats and
      // meshHand reads `thumbRef[Math.min(ci, 2)]` (index 2!). A shorter
      // array makes meshHand crash the whole frame loop (2026-11-15 bug).
      thumbRef: Array.from({ length: 3 }, () => [0, 0, 0] as Vec3),
    },
    noise: [0, 0, 0],
  }
}

export type HumanizeScratch = {
  L: HumanizedHand
  R: HumanizedHand
  out: HandPoses
  tapT: number[] // tap times used on the previous call (for tests / debug)
}

export function createHumanizeScratch(): HumanizeScratch {
  const L = allocHand('L')
  const R = allocHand('R')
  return { L, R, out: { L: null, R: null }, tapT: [0, 0, 0] }
}

// ---- the pure pass ---------------------------------------------------------------------------------------------------

/**
 * Humanized poses at `t`. `src` is the raw pose query (already bound to
 * a motion). Writes into `scratch` and returns `scratch.out` — copy it
 * if you need to keep more than one instant alive (the blur plan does).
 */
export function humanizePoses(
  src: (t: number) => HandPoses,
  t: number,
  p: HumanizeParams,
  scratch: HumanizeScratch,
): HandPoses {
  const out = scratch.out
  out.L = null
  out.R = null
  // Tolerate missing/NaN settings (older persisted state) — a NaN here
  // would poison every joint position and nuke the WebGL draw.
  const sm = Number.isFinite(p.smoothness) ? Math.min(1, Math.max(0, p.smoothness)) : 0.5
  const microAmt = Number.isFinite(p.microMotion) ? Math.min(1, Math.max(0, p.microMotion)) : 0.5
  if (!p.enabled || (sm <= 0 && microAmt <= 0)) {
    // Pass-through still goes through the buffer so callers can keep the
    // reference; deep-copy the raw pose.
    const raw = src(t)
    for (const hand of ['L', 'R'] as const) {
      const h = raw[hand]
      if (!h) continue
      copyPose(h, scratch[hand].pose)
      out[hand] = scratch[hand].pose
    }
    return out
  }

  const tau = LAG_WRIST * sm // 0 at sm=0 → taps collapse, zero lag

  // Three deterministic taps of the source stream (both hands each).
  const t1 = Math.max(0, t - tau)
  const t2 = Math.max(0, t - 2 * tau)
  const A = src(t)
  const B = src(t1)
  const C = src(t2)
  scratch.tapT[0] = t
  scratch.tapT[1] = t1
  scratch.tapT[2] = t2

  for (const hand of ['L', 'R'] as const) {
    const a = A[hand]
    const b = B[hand]
    const c = C[hand]
    if (!a || !b || !c) {
      // Hand entering / leaving mid-tap: fall back to the raw pose so no
      // phantom limb lingers; micro-motion still applies below.
      if (!a) continue
      copyPose(a, scratch[hand].pose)
      out[hand] = scratch[hand].pose
      continue
    }
    blendHand(a, b, c, scratch[hand], sm, microAmt, t)
    out[hand] = scratch[hand].pose
  }
  return out
}

function copyPose(src: HandPose, dst: HandPose): void {
  dst.hand = src.hand
  copyVec(src.elbow, dst.elbow)
  copyVec(src.wrist, dst.wrist)
  for (let i = 0; i < 5; i++) {
    copyVec(src.bases[i], dst.bases[i])
    for (let j = 0; j < 4; j++) copyVec(src.fingers[i][j], dst.fingers[i][j])
  }
  for (let i = 0; i < 3; i++) copyVec(src.thumbRef[i] ?? src.bases[i], dst.thumbRef[i])
  for (let i = 0; i < 5; i++) dst.press[i] = src.press[i] ?? 0
}

const copyVec = (a: Vec3, b: Vec3) => {
  b[0] = a[0]
  b[1] = a[1]
  b[2] = a[2]
}

/**
 * Per-BONE blend (2026-11-15: the old per-joint position blend warped
 * bone chains on fast passages — "méo mó, mềm oặt, ảo"). Bone LENGTHS
 * come from the centre tap and never change; only the bone DIRECTIONS
 * blend across taps (weighted unit vectors + settle overshoot). Micro-
 * motion is a whole-hand tremor translation plus tiny per-finger
 * rotations around their bases — again length-preserving.
 */
function blendHand(
  a: HandPose,
  b: HandPose,
  c: HandPose,
  dst: HumanizedHand,
  sm: number,
  microAmt: number,
  t: number,
): void {
  const pose = dst.pose
  pose.hand = a.hand
  // Press stays RAW (from A): key lights / held keys must not lag audio.
  for (let i = 0; i < 5; i++) pose.press[i] = a.press[i]

  const settleW = SETTLE_WRIST * sm
  const settleF = SETTLE_FINGER * sm
  const wA = 0.35 + 0.65 * (1 - sm) // 1 at sm=0 (snappy) → 0.35 at sm=1

  // Wrist — the chain root: its own position blend is safe (translation).
  lagged(b.wrist, c.wrist, pose.wrist, settleW)

  // Forearm: the elbow hangs off the wrist at its true length.
  buildBone(pose.wrist, pose.elbow, a.wrist, a.elbow, b.wrist, b.elbow, c.wrist, c.elbow, 1 - sm * 0.8, settleW * 0.8)

  for (let f = 0; f < 5; f++) {
    // Metacarpal: wrist → base at its true length.
    buildBone(pose.wrist, pose.bases[f], a.wrist, a.bases[f], b.wrist, b.bases[f], c.wrist, c.bases[f], wA * 0.6 + 0.4, settleF * 0.7)
    // Finger chain: each phalanx keeps its length, directions blend.
    buildBone(pose.bases[f], pose.fingers[f][0], a.bases[f], a.fingers[f][0], b.bases[f], b.fingers[f][0], c.bases[f], c.fingers[f][0], wA, settleF)
    for (let k = 0; k < 3; k++) {
      buildBone(pose.fingers[f][k], pose.fingers[f][k + 1], a.fingers[f][k], a.fingers[f][k + 1], b.fingers[f][k], b.fingers[f][k + 1], c.fingers[f][k], c.fingers[f][k + 1], wA, settleF)
    }
  }

  // Thumb twist references are DIRECTIONS — blend on the sphere.
  for (let i = 0; i < 3; i++) {
    const out = pose.thumbRef[i]
    const at = a.thumbRef[i] ?? a.bases[i]
    const bt = b.thumbRef[i] ?? b.bases[i]
    const ct = c.thumbRef[i] ?? c.bases[i]
    out[0] = wA * at[0] + (1 - wA) * bt[0] + settleF * (bt[0] - ct[0])
    out[1] = wA * at[1] + (1 - wA) * bt[1] + settleF * (bt[1] - ct[1])
    out[2] = wA * at[2] + (1 - wA) * bt[2] + settleF * (bt[2] - ct[2])
    normalize(out)
  }

  // Micro-motion, length-safe: one whole-hand tremor translation …
  micro(t, 211, AMP_WRIST * microAmt, dst.noise)
  const n = dst.noise
  translateJoints(pose, n)
  // … plus a tiny per-finger rotation around its base (alive, not warped).
  if (microAmt > 0) {
    const amp = AMP_FINGER * microAmt
    for (let f = 0; f < 5; f++) {
      micro(t, 300 + f, amp, n)
      _axis[0] = 0
      _axis[1] = 0
      _axis[2] = 1
      rotateAbout(pose.bases[f], _axis, n[0] * 1.1, [pose.fingers[f][0], pose.fingers[f][1], pose.fingers[f][2], pose.fingers[f][3]])
      _axis[0] = 1
      _axis[1] = 0
      _axis[2] = 0
      rotateAbout(pose.bases[f], _axis, n[2] * 1.1, [pose.fingers[f][0], pose.fingers[f][1], pose.fingers[f][2], pose.fingers[f][3]])
    }
    // Forearm breathes around the wrist.
    micro(t, 101, AMP_ELBOW * microAmt * 2, n)
    _axis[0] = 1
    _axis[1] = 0
    _axis[2] = 0
    rotateAbout(pose.wrist, _axis, n[2] * 0.45, [pose.elbow])
    _axis[0] = 0
    _axis[1] = 1
    _axis[2] = 0
    rotateAbout(pose.wrist, _axis, n[0] * 0.45, [pose.elbow])
    // The thumb's twist refs follow its own rotations above (f = 0).
    micro(t, 300, amp, n)
    _axis[0] = 0
    _axis[1] = 0
    _axis[2] = 1
    for (const tr of pose.thumbRef) rotateVec(tr, _axis, n[0] * 1.1)
    _axis[0] = 1
    _axis[1] = 0
    _axis[2] = 0
    for (const tr of pose.thumbRef) rotateVec(tr, _axis, n[2] * 1.1)
  }
}

const _axis: Vec3 = [0, 0, 0]
const _dirA: Vec3 = [0, 0, 0]
const _dirB: Vec3 = [0, 0, 0]
const _dirC: Vec3 = [0, 0, 0]

/**
 * Place `out1` at its true distance from `out0` along a blend of the
 * three taps' bone directions (settle overshoots the rotation slightly).
 */
function buildBone(
  out0: Vec3,
  out1: Vec3,
  a0: Vec3,
  a1: Vec3,
  b0: Vec3,
  b1: Vec3,
  c0: Vec3,
  c1: Vec3,
  wA: number,
  settle: number,
): void {
  const la = boneDir(a0, a1, _dirA)
  const lb = boneDir(b0, b1, _dirB)
  const lc = boneDir(c0, c1, _dirC)
  const len = lb > 1e-9 ? lb : la > 1e-9 ? la : lc
  if (!(len > 1e-9)) {
    out1[0] = out0[0]
    out1[1] = out0[1]
    out1[2] = out0[2]
    return
  }
  const wB = 1 - wA
  _mix[0] = wA * _dirA[0] + wB * _dirB[0] + settle * (_dirB[0] - _dirC[0])
  _mix[1] = wA * _dirA[1] + wB * _dirB[1] + settle * (_dirB[1] - _dirC[1])
  _mix[2] = wA * _dirA[2] + wB * _dirB[2] + settle * (_dirB[2] - _dirC[2])
  normalize(_mix)
  out1[0] = out0[0] + _mix[0] * len
  out1[1] = out0[1] + _mix[1] * len
  out1[2] = out0[2] + _mix[2] * len
}

const _mix: Vec3 = [0, 0, 0]

const lagged = (b: Vec3, c: Vec3, out: Vec3, settle: number) => {
  out[0] = b[0] + settle * (b[0] - c[0])
  out[1] = b[1] + settle * (b[1] - c[1])
  out[2] = b[2] + settle * (b[2] - c[2])
}

function translateJoints(p: HandPose, n: Vec3): void {
  const add = (v: Vec3) => {
    v[0] += n[0]
    v[1] += n[1]
    v[2] += n[2]
  }
  add(p.elbow)
  add(p.wrist)
  for (const b of p.bases) add(b)
  for (const chain of p.fingers) for (const j of chain) add(j)
}
