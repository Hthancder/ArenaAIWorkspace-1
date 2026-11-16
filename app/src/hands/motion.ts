// Hand motion for the loaded song, from the hand runtime in ./runtime (a WebAssembly module, its Worker and a small client;
// built artifacts, see runtime/README.md). The motion data is a separate ~22 MB download, fetched by the Worker only while
// hands are on and kept in Cache Storage, like the piano samples.
import { keyForMidi, MIDI_MAX, MIDI_MIN } from '../keyboard/layout'
import { midiToTimeline, type SpeedMap } from '../midi/speedMap'
import type { ParsedSong } from '../midi/types'
import { HandsRuntime, type HandsMotion, type HandsNote } from './runtime/hands'
import type { HandPose, HandPoses } from './types'
import workerUrl from './runtime/hands-worker.js?url'
import wasmUrl from './runtime/hands.wasm?url'

export type { HandsMotion }

/**
 * The motion data under a content-hashed name (immutable). Self-hosted
 * in `public/hands/` — the upstream `samples.notefall.app` CDN is off
 * limits (its bucket CORS only allows notefall.app itself, and the
 * project rule is no CDN dependency; the file is vendored into the repo
 * by `.github/workflows/fetch-hands-db.yml`). `VITE_HANDS_DB_URL`
 * overrides for experiments.
 */
const DB_FILE = 'motion.82cbd97028.bin'
const DB_URL =
  (import.meta.env.VITE_HANDS_DB_URL as string | undefined) ??
  `${import.meta.env.BASE_URL}hands/${DB_FILE}`

/** How the app places the song on the timeline (the same inputs FallingNotes uses). */
export type HandsTimeMap = {
  speedMap: SpeedMap
  midiOffsetSec: number
  trimStartSec: number
  trimEndSec: number
  transpose: number
}

/**
 * The song's notes on the TIMELINE clock (`audioEngine.currentSongTime()`): note times go through the speed map and the
 * clip offset, notes outside the trim window are dropped, pitches get the global transpose. A note's own hand / finger
 * (selection card) is passed on and kept; the rest are planned by the runtime. Velocity rides along for the expression
 * layer (accents press harder) — the runtime's synth ignores it.
 */
export type SongHandsNote = HandsNote & { velocity: number }

export function songHandNotes(song: ParsedSong, map: HandsTimeMap): SongHandsNote[] {
  const tl = (t: number) => map.midiOffsetSec + midiToTimeline(map.speedMap, t)
  const notes: SongHandsNote[] = []
  for (const n of song.notes) {
    if (n.time < map.trimStartSec || n.time >= map.trimEndSec) continue
    const midi = n.midi + map.transpose
    if (midi < MIDI_MIN || midi > MIDI_MAX) continue
    const on = tl(n.time)
    const off = Math.max(on, tl(Math.min(n.time + n.duration, map.trimEndSec)))
    notes.push({ midi, on, off, hand: n.hand ?? null, finger: n.finger ?? null, velocity: n.velocity })
  }
  notes.sort((a, b) => a.on - b.on || a.midi - b.midi)
  return notes
}

// ---- fast queries over the note list (S4 — no per-frame scans) ------------------------------------------------------

/**
 * Queries over a song's notes (sorted by `on` — see `songHandNotes`).
 * Binary search + windows replace the old full-list scans that ran per
 * finger per frame (`expressAt`) and per claim (`resolvePlan`).
 */
export type NoteQuery = {
  /**
   * Max velocity per (hand 0 = L / 1 = R, finger 0..4) of the notes
   * sounding at `t` (the liveHands expression window), null = none.
   * Memoised per `t`: one pass serves all ten fingers of a frame.
   */
  activeAt(t: number): (number | null)[][]
  /** The motion plan's (hand, finger 0..4) for the note near this key around `t` (imminent first). */
  planFor(midi: number, t: number): { hand: 'L' | 'R'; finger: number } | null
  /** The nearest note starting on `hand` within the next 0.4 s (anticipation). */
  nextOn(hand: 'L' | 'R', t: number): { keyX: number; in: number; finger?: number } | null
}

export function makeNoteQuery(notes: SongHandsNote[], plan?: HandsMotion['plan'] | null): NoteQuery {
  // notes is sorted by `on` ascending.
  const lowerBound = (t: number): number => {
    let lo = 0
    let hi = notes.length
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (notes[mid].on < t) lo = mid + 1
      else hi = mid
    }
    return lo
  }
  let memoT = NaN
  let memo: (number | null)[][] | null = null
  return {
    activeAt(t) {
      if (memo && t === memoT) return memo
      const out: (number | null)[][] = [Array(5).fill(null), Array(5).fill(null)]
      for (let i = 0; i < notes.length; i++) {
        const n = notes[i]
        if (t < n.on - 0.08 || t > n.off + 0.05) continue
        const h = plan ? plan.hand[i] : null
        const hh = h === 'L' ? 0 : h === 'R' ? 1 : null
        if (hh === null) continue
        const fg = plan ? plan.finger[i] - 1 : -1
        if (!(fg >= 0 && fg < 5)) continue
        const v = Number.isFinite(n.velocity) ? n.velocity : 0.75
        const prev = out[hh][fg]
        out[hh][fg] = prev === null ? v : Math.max(prev, v)
      }
      memoT = t
      memo = out
      return out
    },
    planFor(midi, t) {
      // Same semantics as the old resolvePlan: the imminent note (within
      // [t−0.35, t+1.4]) wins; else the nearest within ±2.5 s.
      let soon = -1
      let soonD = Infinity
      let any = -1
      let anyD = Infinity
      for (let i = lowerBound(t - 2.5); i < notes.length && notes[i].on <= t + 2.5; i++) {
        const n = notes[i]
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
      if (idx < 0 || !plan) return null
      const hand = plan.hand[idx]
      const finger = plan.finger[idx]
      if (!hand || !(finger >= 1 && finger <= 5)) return null
      return { hand, finger: finger - 1 }
    },
    nextOn(hand, t) {
      // Only the next 0.4 s matters (the caller bounds the lean) — a
      // bounded forward window, never a full scan.
      for (let i = lowerBound(t); i < notes.length && notes[i].on <= t + 0.4; i++) {
        const n = notes[i]
        const h = plan ? plan.hand[i] ?? n.hand : n.hand
        const eff = h ?? ((keyForMidi(n.midi)?.x ?? 0) < 0 ? 'L' : 'R')
        if (eff !== hand) continue
        const k = keyForMidi(n.midi)
        if (!k) continue
        const fg = plan ? plan.finger[i] : n.finger
        return { keyX: k.x, in: n.on - t, finger: fg !== null && fg !== undefined && fg >= 1 && fg <= 5 ? fg - 1 : undefined }
      }
      return null
    },
  }
}

/**
 * Ring-pooled wrapper for `poseAt` (S4): the runtime allocates ~30 fresh
 * arrays per call, and with motion blur the app asks ~18 times per frame —
 * that is GC churn and micro-jank. The pool hands out pre-allocated poses;
 * callers (the humanizer's A/B/C taps) hold at most three at a time.
 */
export function pooledPoseAt(get: (t: number) => HandPoses): (t: number) => HandPoses {
  const alloc = (): HandPose => ({
    hand: 'L',
    elbow: [0, 0, 0],
    wrist: [0, 0, 0],
    bases: Array.from({ length: 5 }, () => [0, 0, 0] as [number, number, number]),
    fingers: Array.from({ length: 5 }, () => Array.from({ length: 4 }, () => [0, 0, 0] as [number, number, number])),
    press: [0, 0, 0, 0, 0],
    thumbRef: Array.from({ length: 3 }, () => [0, 0, 0] as [number, number, number]),
  })
  const copy = (src: HandPose, dst: HandPose): HandPose => {
    dst.hand = src.hand
    for (const key of ['elbow', 'wrist'] as const) {
      dst[key][0] = src[key][0]
      dst[key][1] = src[key][1]
      dst[key][2] = src[key][2]
    }
    for (let f = 0; f < 5; f++) {
      for (let c = 0; c < 3; c++) dst.bases[f][c] = src.bases[f][c]
      for (let j = 0; j < 4; j++) for (let c = 0; c < 3; c++) dst.fingers[f][j][c] = src.fingers[f][j][c]
      dst.press[f] = src.press[f]
    }
    for (let i = 0; i < 3; i++) for (let c = 0; c < 3; c++) dst.thumbRef[i][c] = src.thumbRef[i][c]
    return dst
  }
  const ring: { L: HandPose; R: HandPose }[] = Array.from({ length: 4 }, () => ({ L: alloc(), R: alloc() }))
  let i = 0
  return (t) => {
    const slot = ring[i]
    i = (i + 1) % ring.length
    const p = get(t)
    return {
      L: p.L ? copy(p.L, slot.L) : null,
      R: p.R ? copy(p.R, slot.R) : null,
    }
  }
}

// ---- status, for the Inspector -------------------------------------------------------------------------------------

export type HandsStatus =
  | { state: 'idle' }
  /** downloading / unpacking the motion data (fraction 0..1 of that stage) */
  | { state: 'loading'; stage: 'download' | 'prepare'; fraction: number }
  /** making the motion for the song */
  | { state: 'working'; fraction: number }
  | { state: 'ready' }
  | { state: 'error' }

let status: HandsStatus = { state: 'idle' }
const listeners = new Set<() => void>()
function setStatus(s: HandsStatus): void {
  status = s
  for (const l of listeners) l()
}
export const getHandsStatus = (): HandsStatus => status
export function subscribeHandsStatus(l: () => void): () => void {
  listeners.add(l)
  return () => listeners.delete(l)
}

// ---- the runtime: one per page, created on first use, released a while after hands are turned off ------------------

let runtime: Promise<HandsRuntime> | null = null
let users = 0
let releaseTimer = 0
/** The Worker holds ~300 MB once the data is loaded; keep it through quick off / on toggles, free it after this. */
const RELEASE_AFTER_MS = 20_000

function startRuntime(): Promise<HandsRuntime> {
  const p = (async () => {
    setStatus({ state: 'loading', stage: 'download', fraction: 0 })
    const rt = await HandsRuntime.create({ worker: workerUrl, wasm: wasmUrl })
    try {
      await rt.load(DB_URL, (stage, f) =>
        setStatus({ state: 'loading', stage: stage === 'download' ? 'download' : 'prepare', fraction: f }), // (decode and build report one 0..1 between them)
      )
    } catch (e) {
      rt.dispose()
      throw e
    }
    return rt
  })()
  p.catch((e) => {
    console.error('hands: the motion runtime failed to load', e)
    if (runtime === p) runtime = null // a later attempt starts over
    setStatus({ state: 'error' })
  })
  return p
}

/** Hands mounted: keeps the runtime alive. Returns the release function. */
export function retainHandsRuntime(): () => void {
  users++
  window.clearTimeout(releaseTimer)
  return () => {
    users--
    if (users > 0) return
    releaseTimer = window.setTimeout(() => {
      const r = runtime
      runtime = null
      r?.then((rt) => rt.dispose()).catch(() => {})
      setStatus({ state: 'idle' })
    }, RELEASE_AFTER_MS)
  }
}

export type ReadyMotion = { motion: HandsMotion; poseAt: HandsRuntime['poseAt'] }

/** Work the export must wait for: motion being made, the hand meshes loading. */
const pending = new Set<Promise<unknown>>()
/** Registers `p` as work `handsSettled` waits for. */
export function trackHandsWork(p: Promise<unknown>): void {
  const q = p.catch(() => {}).finally(() => pending.delete(q))
  pending.add(q)
}

/** The motion of `notes`; rejects with an AbortError when `signal` aborts (a newer request replaced it). */
export function synthHandMotion(notes: HandsNote[], signal: AbortSignal): Promise<ReadyMotion> {
  const job = (async () => {
    runtime ??= startRuntime()
    const rt = await runtime
    if (signal.aborted) throw new DOMException('aborted', 'AbortError')
    setStatus({ state: 'working', fraction: 0 })
    try {
      const motion = await rt.synth(notes, { signal, onProgress: (_stage, f) => setStatus({ state: 'working', fraction: f }) })
      setStatus({ state: 'ready' })
      return { motion, poseAt: rt.poseAt.bind(rt) }
    } catch (e) {
      if ((e as Error).name === 'AbortError') {
        if (status.state === 'working') setStatus({ state: 'ready' }) // a newer request sets its own
      } else {
        console.error('hands: making the motion failed', e)
        setStatus({ state: 'error' })
      }
      throw e
    }
  })()
  trackHandsWork(job)
  return job
}

/** Resolves once no hand work is in flight (the export waits for it, so the video has the current song's hands). */
export async function handsSettled(): Promise<void> {
  while (pending.size) await Promise.all(pending)
}
