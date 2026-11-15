/**
 * Timing windows for play-along scoring — research-piano/16.4.1 (the
 * Keystair-derived formula, verbatim semantics):
 *
 *   step     = min(1, stepBeats)                 // stepBeats = shortest
 *                                                 // gap between onsets,
 *                                                 // in beats
 *   windowMs = min(400, msPerBeat * 0.5 * step)  // outer "counts as hit"
 *   goodMs   = min(140, max(70, msPerBeat * 0.18), windowMs * 0.6)
 *
 * Reference checks from the doc: 60 BPM quarter notes → 400/140 ms;
 * 120 BPM eighths → 125/75 ms.
 */

export type TimingWindows = { goodMs: number; windowMs: number }

export function timingWindows(msPerBeat: number, stepBeats: number): TimingWindows {
  const step = Math.min(1, Math.max(0, stepBeats))
  const windowMs = Math.min(400, msPerBeat * 0.5 * step)
  const goodMs = Math.min(140, Math.max(70, msPerBeat * 0.18), windowMs * 0.6)
  return { goodMs, windowMs }
}

/**
 * Boundary between "perfect" and "good" inside `goodMs`. The research
 * doc (16.4.3 B2) names both verdicts for `|Δ| ≤ goodMs` without
 * splitting them, so the midpoint is a chosen heuristic.
 * TODO(spec): confirm the perfect/good split point.
 */
export const PERFECT_FRACTION = 0.5

export type TempoPoint = { time: number; bpm: number }

/** BPM in effect at MIDI-time `t` (last tempo event at or before t; 120 fallback). */
export function bpmAt(tempos: readonly TempoPoint[] | undefined, t: number): number {
  if (!tempos || tempos.length === 0) return 120
  let bpm = tempos[0].bpm
  for (const p of tempos) {
    if (p.time <= t + 1e-9) bpm = p.bpm
    else break
  }
  return bpm
}

/**
 * Per-onset `stepBeats` for the whole note list: the shortest gap to a
 * DIFFERENT onset (chord partners share the onset and must not collapse
 * the window to 0), converted to beats at the tempo of that onset.
 * Isolated onsets (no neighbour on one side) use the side that exists.
 */
export function onsetStepBeats(
  onsetTimes: readonly number[],
  tempos: readonly TempoPoint[] | undefined,
): number[] {
  // Gaps walk to the nearest DIFFERENT onset: duplicate times (a chord
  // accidentally passed un-deduped) must not collapse the window to 0.
  const gapTo = (i: number, dir: -1 | 1): number => {
    const t = onsetTimes[i]
    for (let j = i + dir; j >= 0 && j < onsetTimes.length; j += dir) {
      const d = Math.abs(t - onsetTimes[j])
      if (d > 1e-9) return d
    }
    return Number.POSITIVE_INFINITY
  }
  return onsetTimes.map((t, i) => {
    const gap = Math.min(gapTo(i, -1), gapTo(i, 1))
    if (!isFinite(gap)) return 1
    const msPerBeat = 60000 / bpmAt(tempos, t)
    return Math.min(1, (gap * 1000) / msPerBeat)
  })
}
