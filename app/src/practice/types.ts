/**
 * Practice engine data types — research-piano/16.6 (subset actually used).
 *
 * Two clocks never mix: `*Ms` fields are `performance.now()`-anchored
 * wall time (16.1) converted into MIDI-song time at the moment of the
 * event; song note `time`/`duration` stay in MIDI-seconds like the rest
 * of the app.
 */

/** How a played line matched the expected notes (16.4.3 B2 / 16.6). */
export type Verdict = 'perfect' | 'good' | 'early' | 'late' | 'miss' | 'extra'

export type PracticeMode = 'off' | 'wait' | 'rhythm'

/** Per-note outcome of a scored run. */
export type NoteResult = {
  expectedId?: number
  pitch: number
  expectedOnMs?: number
  playedOnMs?: number
  deltaMs?: number
  verdict: Verdict
}

export type Totals = {
  expected: number
  perfect: number
  good: number
  early: number
  late: number
  miss: number
  extra: number
}

export const emptyTotals = (): Totals => ({
  expected: 0,
  perfect: 0,
  good: 0,
  early: 0,
  late: 0,
  miss: 0,
  extra: 0,
})

/** Per-bar aggregation (16.4.3 B5). `bar` is 1-based. */
export type BarReport = {
  bar: number
  expected: number
  correct: number
  onTime: number
  avgDeltaMs: number
}

export type SessionResult = {
  mode: 'wait' | 'rhythm'
  startedAt: number
  durationMs: number
  /** Calibration offset applied to every delta (16.2). */
  offsetMs: number
  windows: { goodMs: number; windowMs: number }
  totals: Totals
  /** Empty when the MIDI carried no usable tempo/time-signature map (TODO(spec)). */
  perBar: BarReport[]
  /** Trimmed for very long songs. */
  notes: NoteResult[]
}

/**
 * Wait-mode step: a chord/onset cluster — the set of distinct pitches
 * sharing an onset within `tolMs` (16.3.1). `time` is MIDI-seconds.
 */
export type WaitStep = {
  time: number
  pitches: number[]
}

/** Wait-mode outcome — counts, not timing (16.4.2 "Wait / Melody"). */
export type WaitSummary = {
  mode: 'wait'
  startedAt: number
  durationMs: number
  steps: number
  /** Steps completed with the first press covering every required pitch. */
  firstTry: number
  /** Extra presses of required pitches beyond the first per step. */
  retries: number
  /** Presses of pitches not in the current step. */
  wrong: number
  /** Steps passed via Skip / auto-advance. */
  skipped: number
  offsetMs: number
}

export type Summary = SessionResult | WaitSummary

/** Live HUD counters for the rhythm matcher. */
export type HudState = {
  combo: number
  bestCombo: number
  totals: Totals
}
