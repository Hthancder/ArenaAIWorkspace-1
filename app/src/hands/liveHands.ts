/**
 * Live-input hand overlay — the hands follow the user's MANUAL playing
 * (mouse clicks on the on-screen keys, PC keyboard, physical MIDI device:
 * all of them go through `audioEngine.triggerKey`, which emits on the
 * live bus). Wanted behaviour (2026-11-15): "bàn tay chơi theo nút người
 * dùng tự bấm … chuyển mượt mà … kể cả chế độ chờ nốt".
 *
 * Layered on top of the song-driven pose (motion.ts / humanize.ts):
 *  - every held key claims a (hand, finger) slot — sticky while held;
 *  - the finger TAPS: presses down (tip toward the key top) while the key
 *    is held, lifts to a hover above it otherwise;
 *  - the wrist drifts toward the centroid of the keys being played
 *    (clamped, so distant keys reach but never teleport), the elbow
 *    follows at a reduced gain;
 *  - `press[]` flags follow the live keys — while the transport is NOT
 *    playing (wait mode / pause) they are purely live-driven, so a
 *    "demanded" finger hovers until the user actually plays it; while
 *    playing they are `song || live`.
 *
 * Everything is smoothed frame-rate-independently (1 − exp(−dt/τ)), so
 * bursts, chords and mid-song improvisation all read as one fluid motion.
 *
 * NOT part of the export path: exports must render the pure song motion,
 * so `update`/`applyTo` no-op (and reset) while `audioEngine.isExporting()`.
 * Live state is inherently history-dependent — keeping it out of the
 * render pipeline is what keeps exported frames pure-in-t.
 */
import { audioEngine } from '../audio/engine'
import { keyForMidi } from '../keyboard/layout'
import type { HandPose, HandPoses, Vec3 } from './types'

/** Finger lifts this far above the key while "demanded" but not pressed. */
const HOVER_Z = 0.11
/** How far the fingertip leans toward the pressed key (0..1 of the gap). */
const TIP_PULL = 0.55
/** Max lateral wrist drift toward the pressed-key centroid (world units). */
const WRIST_REACH = 1.1
const TAU_ATTACK = 0.055 // finger follows a press quickly
const TAU_RELEASE = 0.14 // and lifts a touch slower
const TAU_WRIST = 0.09
/** A released binding lingers this long so the finger can fade out. */
const RELEASE_FADE_SEC = 0.35

type Slot = {
  /** Key bound to this finger while held / fading; null = free. */
  midi: number | null
  /** Key centre x of the bound key (0 when free). */
  keyX: number
  /** Smoothed press amount, 0 (hover) .. 1 (down). */
  tap: number
  /** Smoothed hover-lift height above the key (wait-mode "demand" cue). */
  lift: number
  /** True while the physical key is down. */
  held: boolean
  /** performance.now()/1000 when a released binding expires. */
  freeAt: number
}

type HandState = {
  slots: [Slot, Slot, Slot, Slot, Slot]
  /** Smoothed lateral wrist offset toward the played keys. */
  drift: number
}

const makeSlot = (): Slot => ({ midi: null, keyX: 0, tap: 0, lift: 0, held: false, freeAt: 0 })
const makeHand = (): HandState => ({
  slots: [makeSlot(), makeSlot(), makeSlot(), makeSlot(), makeSlot()],
  drift: 0,
})

class LiveHandsOverlay {
  private L = makeHand()
  private R = makeHand()
  /** midi → how many sources hold it (a key can be pressed twice). */
  private held = new Map<number, number>()
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
    this.L = makeHand()
    this.R = makeHand()
  }

  /** performance.now()/1000 of the previous update (frame-rate-independent smoothing). */
  private lastSec = 0

  /**
   * Advance the overlay by one frame and apply it to `poses` in place.
   * `playing` selects the press semantics (song keeps its planned presses
   * while playing; purely live-driven otherwise — see header).
   */
  update(poses: HandPoses, playing: boolean): void {
    if (audioEngine.isExporting()) {
      this.reset()
      return
    }
    const nowSec = performance.now() / 1000
    const dt = Math.min(0.1, Math.max(0, nowSec - (this.lastSec || nowSec)))
    this.lastSec = nowSec

    // Release expired bindings — only once the finger has visually settled,
    // so the tip pull can't snap off mid-fade.
    for (const h of [this.L, this.R]) {
      for (const s of h.slots) {
        if (s.midi !== null && !s.held && nowSec >= s.freeAt && s.tap < 0.02) {
          s.midi = null
          s.keyX = 0
        }
      }
    }

    // Which keys need a finger: everything held, plus fading bindings.
    const wanted: { midi: number; keyX: number }[] = []
    for (const midi of this.held.keys()) {
      const k = keyForMidi(midi)
      if (k) wanted.push({ midi, keyX: k.x })
    }
    this.bind(wanted, poses, nowSec)

    // Smooth taps + drift per hand, then apply.
    for (const hand of ['L', 'R'] as const) {
      const pose = poses[hand]
      const h = this[hand]
      if (!pose) continue
      let cx = 0
      let w = 0
      for (let f = 0; f < 5; f++) {
        const s = h.slots[f]
        const target = s.held ? 1 : 0
        const tau = s.held ? TAU_ATTACK : TAU_RELEASE
        s.tap += (target - s.tap) * (1 - Math.exp(-dt / tau))
        if (s.tap < 0.001 && !s.held && s.midi === null) s.tap = 0
        // Hover cue: a finger the pose demands but nobody has pressed yet
        // (wait mode / pause) floats just above its key until played.
        const demandHover = !playing && pose.press[f] > 0.5 && !(s.midi !== null && s.tap > 0.5)
        const liftTarget = demandHover ? HOVER_Z : 0
        s.lift += (liftTarget - s.lift) * (1 - Math.exp(-dt / TAU_ATTACK))
        if (s.midi !== null && s.held) {
          cx += s.keyX
          w += 1
        }
      }
      const driftTarget = w > 0 ? clamp(cx / w - pose.wrist[0], WRIST_REACH) : 0
      h.drift += (driftTarget - h.drift) * (1 - Math.exp(-dt / TAU_WRIST))
    }
    this.applyToPoses(poses, playing)
  }

  /** Apply the current smoothed state to a full pose pair (blur sub-poses too). */
  applyToPoses(poses: HandPoses, playing: boolean): void {
    for (const hand of ['L', 'R'] as const) {
      const pose = poses[hand]
      if (pose) this.applyTo(pose, hand, playing)
    }
  }

  /**
   * Apply the current smoothed state to one pose (the blur path re-applies
   * to its sub-poses so the trail matches). Pure given the state — no
   * state mutation here.
   */
  applyTo(pose: HandPose, hand: 'L' | 'R', playing: boolean): void {
    if (audioEngine.isExporting()) return
    const h = this[hand]
    // Wrist drift toward the played keys; elbow follows, palm a little.
    if (h.drift !== 0) {
      pose.wrist[0] += h.drift
      pose.elbow[0] += h.drift * 0.35
      for (let f = 0; f < 5; f++) {
        pose.bases[f][0] += h.drift * 0.18
        for (let k = 0; k < 4; k++) pose.fingers[f][k][0] += h.drift * 0.18
      }
    }
    for (let f = 0; f < 5; f++) {
      const s = h.slots[f]
      const basePress = pose.press[f] > 0.5
      const live = s.midi !== null
      const press = playing ? basePress || (live && s.tap > 0.5) : live && s.tap > 0.5
      pose.press[f] = press ? 1 : 0
      if (s.lift > 0.001) {
        for (let k = 1; k < 4; k++) pose.fingers[f][k][2] += s.lift * (0.5 + 0.25 * k)
      }
      if (live && s.tap > 0.001) {
        // Lean the fingertip toward the key top (tip strongest, DIP/MCP less).
        const k = keyForMidi(s.midi!)
        const tipY = k && k.isBlack ? -1.05 : -1.35
        const tipZ = k ? (k.isBlack ? k.zCenter + k.thickness * 0.5 + 0.02 : 0.03) : 0.03
        const pull = TIP_PULL * s.tap
        const tip = pose.fingers[f][3] as Vec3
        tip[0] += (s.keyX - tip[0]) * pull
        tip[1] += (tipY - tip[1]) * pull
        tip[2] += (tipZ - tip[2]) * pull
        const dip = pose.fingers[f][2] as Vec3
        dip[0] += (s.keyX - dip[0]) * pull * 0.45
        dip[2] += (tipZ - dip[2]) * pull * 0.3
      }
    }
  }

  /** Bind unbound keys to the nearest free (hand, finger); keep held bindings sticky. */
  private bind(wanted: { midi: number; keyX: number }[], poses: HandPoses, nowSec: number): void {
    // Mark currently-held bindings; collect the rest as newcomers.
    const newcomers: { midi: number; keyX: number }[] = []
    for (const w of wanted) {
      let bound = false
      for (const h of [this.L, this.R]) {
        for (const s of h.slots) {
          if (s.midi === w.midi) {
            s.held = true
            s.keyX = w.keyX
            bound = true
          }
        }
      }
      if (!bound) newcomers.push(w)
    }
    // A released key whose binding is fading keeps `held = false`.
    for (const h of [this.L, this.R]) {
      for (const s of h.slots) {
        if (s.midi !== null && !wanted.some((w) => w.midi === s.midi)) {
          if (s.held) {
            s.held = false
            s.freeAt = nowSec + RELEASE_FADE_SEC
          }
        }
      }
    }
    for (const w of newcomers) this.claim(w, poses)
  }

  private claim(w: { midi: number; keyX: number }, poses: HandPoses): void {
    // Hand: the one whose wrist is nearer the key (missing hand = far).
    const dL = poses.L ? Math.abs(poses.L.wrist[0] - w.keyX) : Infinity
    const dR = poses.R ? Math.abs(poses.R.wrist[0] - w.keyX) : Infinity
    const order: ('L' | 'R')[] = dL <= dR ? ['L', 'R'] : ['R', 'L']
    for (const hand of order) {
      const pose = poses[hand]
      if (!pose) continue
      const h = this[hand]
      // Finger: nearest free one by key-x; fall back to nearest overall.
      let best = -1
      let bestD = Infinity
      let fallback = -1
      let fallbackD = Infinity
      for (let f = 0; f < 5; f++) {
        const s = h.slots[f]
        const d = Math.abs(pose.bases[f][0] - w.keyX)
        if (s.midi === null && d < bestD) {
          bestD = d
          best = f
        }
        if (d < fallbackD) {
          fallbackD = d
          fallback = f
        }
      }
      const f = best >= 0 ? best : fallback
      if (f < 0) continue
      const s = h.slots[f]
      s.midi = w.midi
      s.keyX = w.keyX
      s.held = true
      return
    }
  }
}

function clamp(v: number, m: number): number {
  return Math.max(-m, Math.min(m, v))
}

export const liveHands = new LiveHandsOverlay()
