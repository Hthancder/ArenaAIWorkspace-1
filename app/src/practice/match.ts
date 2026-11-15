/**
 * Real-time play-along matcher — research-piano/16.4.3 (greedy, B1–B3):
 *
 *  B1. For each played note, pick the unmatched expected note with the
 *      same pitch and |Δ| ≤ windowMs, smallest |Δ| first. Greedy is
 *      sufficient for piano music (16.4.3 "Vì sao greedy là đủ").
 *  B2. |Δ| ≤ goodMs → perfect/good (split at PERFECT_FRACTION, TODO(spec));
 *      beyond goodMs → early/late by sign.
 *  B3. A played note matching nothing = "extra".
 *      Expected notes never matched = "miss" (both "wrong moment" and
 *      "never pressed" fold into one category, per B2's last two rows).
 *
 * Windows are computed ONCE per expected note from its local tempo and
 * onset density (16.4.1); the matcher only compares numbers.
 */
import type { NoteEvent } from '../midi/types'
import {
  bpmAt,
  onsetStepBeats,
  PERFECT_FRACTION,
  timingWindows,
  type TempoPoint,
  type TimingWindows,
} from './windows'
import {
  emptyTotals,
  type BarReport,
  type NoteResult,
  type SessionResult,
  type Totals,
  type Verdict,
} from './types'

const MAX_NOTE_RESULTS = 2000

type Prepared = {
  id: number
  pitch: number
  onMs: number
  windows: TimingWindows
  matched: boolean
  /** 1-based bar index from `barTimes`; 0 = unknown. */
  bar: number
}

/** 1-based bar of MIDI-time `t`; 0 when the map is unknown. */
export function barIndexAt(barTimes: readonly number[] | undefined, t: number): number {
  if (!barTimes || barTimes.length === 0) return 0
  // barTimes[i] = start time of bar i+1
  let lo = 0
  let hi = barTimes.length - 1
  let ans = 0
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    if (barTimes[mid] <= t + 1e-9) {
      ans = mid + 1
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  return ans === 0 ? 1 : ans
}

export class RhythmMatcher {
  private expected: Prepared[] = []
  private results: NoteResult[] = []
  private totals: Totals = emptyTotals()
  private startedAt = 0

  constructor(
    notes: readonly NoteEvent[],
    private tempos: readonly TempoPoint[] | undefined,
    private barTimes: readonly number[] | undefined,
    /** Calibration offset (ms) subtracted from every played time (16.2). */
    private offsetMs: number,
    private windowsSummary: TimingWindows = { goodMs: 0, windowMs: 0 },
  ) {
    this.reset(notes)
  }

  reset(notes: readonly NoteEvent[]): void {
    const sorted = [...notes].sort((a, b) => a.time - b.time)
    const onsetTimes: number[] = []
    const onsetIdx: number[] = [] // per-note index into onsetTimes
    for (const n of sorted) {
      if (onsetTimes.length === 0 || Math.abs(n.time - onsetTimes[onsetTimes.length - 1]) > 1e-9) {
        onsetTimes.push(n.time)
      }
      onsetIdx.push(onsetTimes.length - 1)
    }
    const stepBeats = onsetStepBeats(onsetTimes, this.tempos)
    this.expected = sorted.map((n, i) => {
      const oi = onsetIdx[i]
      const msPerBeat = 60000 / bpmAt(this.tempos, n.time)
      const windows = timingWindows(msPerBeat, stepBeats[oi] ?? 1)
      if (windows.windowMs > this.windowsSummary.windowMs) this.windowsSummary = windows
      return {
        id: n.id,
        pitch: n.midi,
        onMs: n.time * 1000,
        windows,
        matched: false,
        bar: barIndexAt(this.barTimes, n.time),
      }
    })
    this.totals.expected = this.expected.length
    this.results = []
    this.totals.perfect = this.totals.good = this.totals.early = 0
    this.totals.late = this.totals.miss = this.totals.extra = 0
    this.startedAt = performance.now()
  }

  /**
   * Score one played note-on. `playedOnMs` is MIDI-song time in ms at
   * the moment of the press (already latency-corrected); the calibration
   * offset is subtracted here.
   */
  playOn(pitch: number, playedOnMs: number): { verdict: Verdict; deltaMs: number | null } {
    const adj = playedOnMs - this.offsetMs
    let best: Prepared | null = null
    let bestAbs = Number.POSITIVE_INFINITY
    for (const e of this.expected) {
      if (e.matched || e.pitch !== pitch) continue
      const d = Math.abs(adj - e.onMs)
      if (d <= e.windows.windowMs && d < bestAbs) {
        best = e
        bestAbs = d
      }
    }
    if (!best) {
      this.totals.extra++
      this.push({ pitch, playedOnMs: adj, verdict: 'extra' })
      return { verdict: 'extra', deltaMs: null }
    }
    best.matched = true
    const deltaMs = adj - best.onMs
    const abs = Math.abs(deltaMs)
    let verdict: Verdict
    if (abs <= best.windows.goodMs * PERFECT_FRACTION) verdict = 'perfect'
    else if (abs <= best.windows.goodMs) verdict = 'good'
    else verdict = deltaMs < 0 ? 'early' : 'late'
    this.totals[verdict]++
    this.push({
      expectedId: best.id,
      pitch,
      expectedOnMs: best.onMs,
      playedOnMs: adj,
      deltaMs,
      verdict,
    })
    return { verdict, deltaMs }
  }

  private push(r: NoteResult): void {
    if (this.results.length < MAX_NOTE_RESULTS) this.results.push(r)
  }

  /** Close the session: sweep unmatched expected notes as misses and aggregate. */
  finalize(): SessionResult {
    for (const e of this.expected) {
      if (e.matched) continue
      this.totals.miss++
      this.push({ expectedId: e.id, pitch: e.pitch, expectedOnMs: e.onMs, verdict: 'miss' })
    }
    return {
      mode: 'rhythm',
      startedAt: this.startedAt,
      durationMs: performance.now() - this.startedAt,
      offsetMs: this.offsetMs,
      windows: this.windowsSummary,
      totals: { ...this.totals },
      perBar: this.buildPerBar(),
      notes: this.results,
    }
  }

  private buildPerBar(): BarReport[] {
    if (!this.barTimes || this.barTimes.length === 0) return []
    const byBar = new Map<number, { expected: number; correct: number; onTime: number; sumDelta: number; n: number }>()
    const resById = new Map<number, NoteResult>()
    for (const r of this.results) if (r.expectedId !== undefined) resById.set(r.expectedId, r)
    for (const e of this.expected) {
      const slot = byBar.get(e.bar) ?? { expected: 0, correct: 0, onTime: 0, sumDelta: 0, n: 0 }
      slot.expected++
      const r = resById.get(e.id)
      if (r && r.verdict !== 'miss') {
        slot.correct++
        if (r.verdict === 'perfect' || r.verdict === 'good') slot.onTime++
        if (r.deltaMs !== undefined) {
          slot.sumDelta += r.deltaMs
          slot.n++
        }
      }
      byBar.set(e.bar, slot)
    }
    return [...byBar.entries()]
      .filter(([bar]) => bar > 0)
      .sort((a, b) => a[0] - b[0])
      .map(([bar, s]) => ({
        bar,
        expected: s.expected,
        correct: s.correct,
        onTime: s.onTime,
        avgDeltaMs: s.n > 0 ? s.sumDelta / s.n : 0,
      }))
  }
}
