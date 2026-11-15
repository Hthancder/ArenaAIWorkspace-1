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
      thumbRef: Array.from({ length: 2 }, () => [0, 0, 0] as Vec3),
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
  if (!p.enabled || (p.smoothness <= 0 && p.microMotion <= 0)) {
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

  const sm = Math.min(1, Math.max(0, p.smoothness))
  const microAmt = Math.min(1, Math.max(0, p.microMotion))
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
  for (let i = 0; i < 2; i++) copyVec(src.thumbRef[i], dst.thumbRef[i])
  for (let i = 0; i < 5; i++) dst.press[i] = src.press[i]
}

const copyVec = (a: Vec3, b: Vec3) => {
  b[0] = a[0]
  b[1] = a[1]
  b[2] = a[2]
}

/**
 * Per-joint blend: `v = vB + settle·(vB − vC) + micro(t)`, where the
 * settle term is what turns linear tracking into a move that overshoots
 * and eases in, and lags differ per group (τ already folded into the
 * taps — fingers pick more of the fresh tap A to stay crisp).
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

  // Elbow — heaviest: pure B + settle, tiny micro.
  lagged(b.elbow, c.elbow, pose.elbow, settleW * 0.8)
  micro(t, 101, AMP_ELBOW * microAmt, dst.noise)
  addVec(pose.elbow, dst.noise)

  // Wrist.
  lagged(b.wrist, c.wrist, pose.wrist, settleW)
  micro(t, 211, AMP_WRIST * microAmt, dst.noise)
  addVec(pose.wrist, dst.noise)

  // Finger joints — lighter lag: blend toward A so attacks stay close
  // to the strike (fully raw at smoothness 0), plus settle and the
  // loudest micro band.
  const wA = 0.35 + 0.65 * (1 - sm) // 1 at sm=0 (snappy) → 0.35 at sm=1
  for (let f = 0; f < 5; f++) {
    for (let k = 0; k < 4; k++) {
      mixLagged(a.fingers[f][k], b.fingers[f][k], c.fingers[f][k], pose.fingers[f][k], wA, settleF)
      micro(t, 300 + f * 10 + k, AMP_FINGER * microAmt * (0.55 + 0.11 * k), dst.noise)
      addVec(pose.fingers[f][k], dst.noise)
    }
    mixLagged(a.bases[f], b.bases[f], c.bases[f], pose.bases[f], wA * 0.6 + 0.4, settleF * 0.7)
    micro(t, 400 + f, AMP_FINGER * microAmt * 0.7, dst.noise)
    addVec(pose.bases[f], dst.noise)
  }
  // Thumb twist references: exactly 2 entries.
  for (let i = 0; i < 2; i++) {
    const at = a.thumbRef[i] ?? a.bases[i]
    const bt = b.thumbRef[i] ?? b.bases[i]
    const ct = c.thumbRef[i] ?? c.bases[i]
    mixLagged(at, bt, ct, pose.thumbRef[i], wA, settleF)
  }
}

const lagged = (b: Vec3, c: Vec3, out: Vec3, settle: number) => {
  out[0] = b[0] + settle * (b[0] - c[0])
  out[1] = b[1] + settle * (b[1] - c[1])
  out[2] = b[2] + settle * (b[2] - c[2])
}

const mixLagged = (a: Vec3, b: Vec3, c: Vec3, out: Vec3, wA: number, settle: number) => {
  const wB = 1 - wA
  out[0] = wA * a[0] + wB * b[0] + settle * (b[0] - c[0])
  out[1] = wA * a[1] + wB * b[1] + settle * (b[1] - c[1])
  out[2] = wA * a[2] + wB * b[2] + settle * (b[2] - c[2])
}

const addVec = (v: Vec3, n: Vec3) => {
  v[0] += n[0]
  v[1] += n[1]
  v[2] += n[2]
}
