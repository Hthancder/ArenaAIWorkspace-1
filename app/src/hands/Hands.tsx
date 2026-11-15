import { useFrame, useThree } from '@react-three/fiber'
import { EffectComposerContext } from '@react-three/postprocessing'
import { useContext, useEffect, useMemo, useRef } from 'react'
import * as THREE from 'three'
import { audioEngine } from '../audio/engine'
import { getResolvedSettings } from '../scene/automatedSettings'
import { buildSpeedMap } from '../midi/speedMap'
import { useSettingsSlice, useStore } from '../store'
import { createMeshHands } from './meshHand'
import { retainHandsRuntime, songHandNotes, synthHandMotion, trackHandsWork, type ReadyMotion } from './motion'
import {
  createHumanizeScratch,
  humanizePoses,
  type HumanizeParams,
  type HumanizeScratch,
} from './humanize'
import { liveHands, type LiveHandsOpts } from './liveHands'
import { neutralHandPose } from './neutralPose'
import { getExportFps } from '../scene/exportBridge'
import {
  BLUR_MIN_PX, BLUR_PX_STEP, BLUR_SHUTTER, HandsBlurPass, PREVIEW_FRAME_SECONDS, blurBridge, blurOffsets, getMotionBlur, handBounds,
  maxJointShift,
} from './motionBlur'
import type { HandPoses } from './types'

// Virtual piano hands (beta). The motion comes from the hand runtime (motion.ts) and is remade (debounced, in its Worker)
// when the song or the timeline mapping changes; until the new one is ready the previous one keeps playing (edits), or
// no hands show (another song). Poses come from `poseAt(motion, audioEngine.currentSongTime())` — the same clock
// FallingNotes uses, routed through `audio/clock.ts` — so the offline exporter's frame-stepped render draws the same
// hands as the live preview (it waits for `handsSettled()` first).

const HAND_KEYS = [
  'handsBrightness',
  'handsFlashLight',
  'handsMotionBlur',
  'handsBlurSamples',
  'handsHumanizeEnabled',
  'handsSmoothness',
  'handsMicroMotion',
  'handsFollowInput',
  'handsKeystrike',
  'handsExpression',
  'bloomEnabled',
  'midiOffsetSec',
  'midiSpeedAutomation',
  'midiTrimStartSec',
  'midiTrimEndSec',
  'transpose',
] as const

/** Edits / clip drags change the inputs many times per second; rebuild once they settle. */
const REBUILD_DEBOUNCE_MS = 150

const SIZE = new THREE.Vector2()

/** Free play: no motion, the live overlay synthesises hands on demand. */
const NO_HANDS: HandPoses = { L: null, R: null }

function resetBlurFrame() {
  blurBridge.plan = null
  if (blurBridge.renderPass) blurBridge.renderPass.enabled = true
  if (blurBridge.pass) blurBridge.pass.enabled = false
}

export function Hands() {
  const s = useSettingsSlice(HAND_KEYS)
  const song = useStore((st) => st.song)
  const invalidate = useThree((st) => st.invalidate)
  const gl = useThree((st) => st.gl)
  const camera = useThree((st) => st.camera)
  const group = useMemo(() => {
    const g = new THREE.Group()
    g.name = 'hands'
    return g
  }, [])
  const meshRef = useRef<ReturnType<typeof createMeshHands> | null>(null)
  const motionRef = useRef<(ReadyMotion & { song: string; notes: ReturnType<typeof songHandNotes> }) | null>(null)
  // Humanize scratch pool — slot 0 = main pose, 1–2 = blur probes, 3+ =
  // blur sub-poses. Reused across frames (the blur plan is consumed
  // within the same frame it is built).
  const scratchRef = useRef<HumanizeScratch[]>([])
  const scratchAt = (slot: number): HumanizeScratch => {
    const pool = scratchRef.current
    while (pool.length <= slot) pool.push(createHumanizeScratch())
    return pool[slot]
  }

  useEffect(() => retainHandsRuntime(), [])
  useEffect(() => liveHands.attach(), [])

  useEffect(() => {
    const mesh = createMeshHands(group)
    meshRef.current = mesh
    trackHandsWork(mesh.loaded)
    // Hands must never take part in picking (editor clicks / key presses go through them).
    mesh.loaded.then(() => group.traverse((o) => { o.raycast = () => {} })).catch(() => {})
    return () => {
      meshRef.current = null
      mesh.dispose()
    }
  }, [group])

  const speedMap = useMemo(() => buildSpeedMap(s.midiSpeedAutomation), [s.midiSpeedAutomation])
  useEffect(() => {
    if (!song) {
      motionRef.current = null
      return
    }
    // Edits keep the song's name: the previous motion plays on until the new one is ready. Another song: no hands meanwhile.
    if (motionRef.current && motionRef.current.song !== song.name) motionRef.current = null
    const ctl = new AbortController()
    const run = () => {
      const notes = songHandNotes(song, {
        speedMap,
        midiOffsetSec: s.midiOffsetSec,
        trimStartSec: s.midiTrimStartSec,
        trimEndSec: s.midiTrimEndSec ?? song.duration,
        transpose: s.transpose,
      })
      if (!notes.length) {
        motionRef.current = null
        invalidate()
        return
      }
      synthHandMotion(notes, ctl.signal)
        .then((m) => {
          motionRef.current = { ...m, song: song.name, notes }
          invalidate()
        })
        .catch(() => {}) // cancelled by a newer request, or failed (the status says so)
    }
    const id = window.setTimeout(run, motionRef.current ? REBUILD_DEBOUNCE_MS : 0)
    return () => {
      window.clearTimeout(id)
      ctl.abort()
    }
  }, [song, speedMap, s.midiOffsetSec, s.midiTrimStartSec, s.midiTrimEndSec, s.transpose, invalidate])

  useFrame(() => {
    resetBlurFrame()
    const mesh = meshRef.current
    if (!mesh) return
    const ready = motionRef.current
    mesh.setLighting(getResolvedSettings().keyboardBrightness, s.handsBrightness, s.handsFlashLight)
    if (!mesh.ready) {
      mesh.setVisible(false)
      return
    }
    // Free play ("đánh tự do"): with no song motion at all the hands still
    // show up and follow the user's input from neutral poses. Exports of a
    // motionless timeline draw nothing (pure motion contract).
    if (!ready && (!s.handsFollowInput || audioEngine.isExporting())) {
      mesh.setVisible(false)
      return
    }
    mesh.setVisible(true)
    const src = ready ? (tt: number) => ready.poseAt(ready.motion, tt) : () => NO_HANDS
    const t = audioEngine.currentSongTime()
    // Humanized poses — a PURE function of t (see humanize.ts) so the
    // exporter's frame-stepped render matches this preview exactly.
    const params: HumanizeParams = {
      enabled: s.handsHumanizeEnabled,
      smoothness: s.handsSmoothness,
      microMotion: s.handsMicroMotion,
    }
    // Last-resort guard: a throw inside this callback kills every
    // useFrame subscriber that mounts after us (falling notes freeze, keys
    // stop glowing) while the background audio ticker keeps the song
    // playing — the 2026-11-15 incident (meshHand crashed on the
    // humanizer's short thumbRef array). Degrade to raw poses instead of
    // freezing the whole visual layer.
    try {
      const poses = humanizePoses(src, t, params, scratchAt(0))
      // Live-input overlay: the hands follow the user's manual playing
      // (mouse / PC keyboard / MIDI). Live-only state — no-op on exports.
      const playing = audioEngine.isPlaying()
      const opts: LiveHandsOpts = {
        playing,
        keystrike: s.handsKeystrike,
        expression: s.handsExpression,
        // Natural fingering: the motion plan's (hand, finger) for the
        // matching song note. Falls are adapted to — an IMMINENT note
        // ("nốt đang rơi") wins over one just passed, so the fingers
        // prepare for what is coming.
        resolvePlan: (midi) => {
          const rm = motionRef.current
          if (!rm || !rm.motion.plan) return null
          let soon = -1
          let soonD = Infinity
          let any = -1
          let anyD = Infinity
          for (let i = 0; i < rm.notes.length; i++) {
            const n = rm.notes[i]
            if (n.midi !== midi) continue
            const d = Math.abs(n.on - t)
            const imminent = n.on >= t - 0.35 && n.on <= t + 1.4
            if (imminent && d < soonD) {
              soonD = d
              soon = i
            }
            if (d < anyD) {
              anyD = d
              any = i
            }
          }
          const idx = soon >= 0 ? soon : anyD <= 2.5 ? any : -1
          if (idx < 0) return null
          const hand = rm.motion.plan.hand[idx]
          const finger = rm.motion.plan.finger[idx]
          if (!hand || !(finger >= 1 && finger <= 5)) return null
          return { hand, finger: finger - 1 }
        },
        // Expression: the velocity of the song note this finger plays
        // right now — accents press deeper, with a touch of arm roll.
        expressAt: (hand, finger) => {
          const rm = motionRef.current
          if (!rm) return null
          let best: number | null = null
          for (let i = 0; i < rm.notes.length; i++) {
            const n = rm.notes[i]
            if (t < n.on - 0.08 || t > n.off + 0.05) continue
            const h = rm.motion.plan.hand[i] ?? n.hand
            const fg = rm.motion.plan.finger[i] ?? n.finger
            if (h !== hand || fg !== finger + 1) continue
            best = best === null ? n.velocity : Math.max(best, n.velocity)
          }
          return best
        },
        // A hand that is off stage (runtime: "rests in the lap") comes up
        // from a mid-run pose sample of that hand when the user needs it.
        // No motion at all (free play) or no runs for this hand: the baked
        // neutral pose — the hand still shows up and plays.
        sampleHand: (hand) => {
          const rm = motionRef.current
          if (rm) {
            const runs = rm.motion.runs?.[hand] ?? []
            for (const [a, b] of runs) {
              const tm = rm.motion.t0 + (a + b) / 2 / rm.motion.fps
              const p = rm.poseAt(rm.motion, tm)[hand]
              if (p) return p
            }
          }
          return neutralHandPose(hand)
        },
      }
      if (s.handsFollowInput) liveHands.update(poses, opts)
      mesh.update(poses, false)

      // Motion blur: sub-poses at trailing times of ONE nominal frame of song time (export: 1/fps, preview: 1/60 s, times the
      // playback rate; never the real frame delta), so the picture is a pure function of t. Sample 0 = t.
      if (!s.handsMotionBlur || blurBridge.consumers < 1 || s.handsBlurSamples < 2) return
      const dt = (getExportFps() ? 1 / getExportFps()! : PREVIEW_FRAME_SECONDS) * (useStore.getState().settings.playbackRate || 1)
      const far = humanizePoses(src, Math.max(0, t - BLUR_SHUTTER * dt), params, scratchAt(1))
      const mid = humanizePoses(src, Math.max(0, t - 0.5 * BLUR_SHUTTER * dt), params, scratchAt(2))
      const shift = Math.max(maxJointShift(poses, far), maxJointShift(poses, mid))
      const persp = camera as THREE.PerspectiveCamera
      const wr = poses.L?.wrist ?? poses.R?.wrist
      const dist = wr ? camera.position.distanceTo(new THREE.Vector3(wr[0], wr[1], wr[2])) : camera.position.length()
      gl.getDrawingBufferSize(SIZE)
      const px = shift * (SIZE.y / (2 * dist * Math.tan(THREE.MathUtils.degToRad(persp.fov) / 2)))
      if (px < BLUR_MIN_PX) return
      const n = Math.min(Math.round(s.handsBlurSamples), Math.max(2, Math.ceil(px / BLUR_PX_STEP)))
      const sub: HandPoses[] = blurOffsets(n, BLUR_SHUTTER, dt).map((o, i) => {
        if (o === 0) return poses
        const sp = humanizePoses(src, Math.max(0, t + o), params, scratchAt(3 + i))
        if (s.handsFollowInput) liveHands.applyToPoses(sp, opts, { L: scratchAt(3 + i).L.pose, R: scratchAt(3 + i).R.pose })
        return sp
      })
      camera.updateMatrixWorld()
      blurBridge.plan = {
        count: n,
        rectsFor: (w, h) => handBounds(sub, persp, w, h, 0.5),
        handsRoot: group,
        drawAt: (i) => mesh.update(sub[i], false),
      }
      if (blurBridge.renderPass) blurBridge.renderPass.enabled = false
      if (blurBridge.pass) blurBridge.pass.enabled = true
    } catch (err) {
      console.warn('[hands] pose pass failed — falling back to raw poses', err)
      resetBlurFrame()
      mesh.update(src(t), false)
    }
  })

  // Hands leaving the tree (or blur turned off) must hand rendering back to the default pipeline.
  useEffect(() => resetBlurFrame, [])

  return (
    <>
      <primitive object={group} />
      {!s.bloomEnabled && s.handsMotionBlur && <HandsBlurPlainRender />}
    </>
  )
}

/** Child of `<EffectComposer>` (before Bloom): the composer-path consumer of `blurBridge.plan`. */
export function HandsBlurComposerPass() {
  const ctx = useContext(EffectComposerContext)
  const pass = useMemo(() => (ctx ? new HandsBlurPass(ctx.scene, ctx.camera) : null), [ctx])
  useEffect(() => {
    if (!ctx || !pass) return
    // The composer's own scene pass is the first one; this pass replaces it on blurred frames.
    blurBridge.renderPass = ctx.composer.passes[0] ?? null
    blurBridge.pass = pass
    blurBridge.consumers++
    return () => {
      if (blurBridge.renderPass === ctx.composer.passes[0]) { blurBridge.renderPass.enabled = true; blurBridge.renderPass = null }
      if (blurBridge.pass === pass) blurBridge.pass = null
      blurBridge.consumers--
      blurBridge.plan = null
    }
  }, [ctx, pass])
  return pass ? <primitive object={pass} /> : null
}

/** Bloom-off consumer: takes over the canvas render (R3F skips its own once a priority > 0 subscriber exists). */
export function HandsBlurPlainRender() {
  const gl = useThree((st) => st.gl)
  useEffect(() => {
    blurBridge.consumers++
    return () => { blurBridge.consumers--; blurBridge.plan = null }
  }, [])
  useFrame(({ scene, camera }) => {
    const plan = blurBridge.plan
    if (plan) getMotionBlur(gl).render(scene, camera, plan.handsRoot, plan.rectsFor, plan.count, plan.drawAt, null)
    else gl.render(scene, camera)
  }, 1)
  return null
}
