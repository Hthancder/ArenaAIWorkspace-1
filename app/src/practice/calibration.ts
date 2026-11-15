/**
 * Latency calibration — research-piano/16.2 (verbatim procedure):
 *
 *   12 clicks at 80 BPM (750 ms/click); drop the first 4 (count-in),
 *   measure over the remaining 8; for each click take the nearest tap
 *   within ±375 ms; offset = median(t_note − t_click).
 *
 * Every later score subtracts this offset (see RhythmMatcher).
 * |offset| > 120 ms → the UI warns to check speakers/headphones.
 */
import { scheduleCountIn, type CountInHandle } from '../audio/click'
import { audibleWallMs } from './latency'

export const CALIBRATION_CLICKS = 12
export const CALIBRATION_SKIP = 4
export const CALIBRATION_BPM = 80
export const CALIBRATION_WINDOW_MS = 375
/** TODO(spec): minimum usable taps is not fixed by 16.2; 3 of 8 chosen. */
export const CALIBRATION_MIN_TAPS = 3
export const CALIBRATION_WARN_MS = 120

export type CalibrationRun = {
  /** Audible wall time of each click (ms, performance.now domain). */
  clickWallMs: number[]
  handle: CountInHandle
}

/**
 * Schedule the 12 calibration clicks. `onBeat(beatIndex)` fires per
 * click for the countdown UI. Click wall times are computed through the
 * getOutputTimestamp anchor (16.1) — the measured offset must not be
 * poisoned by speaker latency.
 */
export function beginCalibration(onBeat?: (beatIndex: number) => void): CalibrationRun {
  const clickWallMs: number[] = []
  const handle = scheduleCountIn(
    CALIBRATION_CLICKS,
    CALIBRATION_BPM,
    (beatNumber, ctxTime) => {
      // scheduleCountIn reports beats 1-indexed; keep this array 0-indexed.
      clickWallMs[beatNumber - 1] = audibleWallMs(ctxTime)
      onBeat?.(beatNumber - 1)
    },
  )
  return { clickWallMs, handle }
}

/**
 * Median of (tap − click) over the measured clicks. Each tap serves at
 * most one click; clicks without a tap in the window are skipped.
 * Returns null when fewer than CALIBRATION_MIN_TAPS clicks matched.
 */
export function finishCalibration(
  tapWallMs: readonly number[],
  clickWallMs: readonly number[],
): number | null {
  const used = new Set<number>()
  const deltas: number[] = []
  for (let i = CALIBRATION_SKIP; i < clickWallMs.length; i++) {
    const click = clickWallMs[i]
    if (click === undefined) continue
    let bestIdx = -1
    let bestAbs = Number.POSITIVE_INFINITY
    for (let j = 0; j < tapWallMs.length; j++) {
      if (used.has(j)) continue
      const d = Math.abs(tapWallMs[j] - click)
      if (d <= CALIBRATION_WINDOW_MS && d < bestAbs) {
        bestAbs = d
        bestIdx = j
      }
    }
    if (bestIdx >= 0) {
      used.add(bestIdx)
      deltas.push(tapWallMs[bestIdx] - click)
    }
  }
  if (deltas.length < CALIBRATION_MIN_TAPS) return null
  deltas.sort((a, b) => a - b)
  const mid = deltas.length >> 1
  return deltas.length % 2 === 1 ? deltas[mid] : (deltas[mid - 1] + deltas[mid]) / 2
}
