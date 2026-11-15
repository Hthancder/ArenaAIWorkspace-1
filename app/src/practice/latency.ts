/**
 * Latency helpers for scoring — research-piano/16.1.
 *
 * `AudioContext.getOutputTimestamp()` is the only trustworthy anchor
 * between `performance.now()` and the moment a sample leaves the
 * speakers. Scoring converts the playhead ("what the user is hearing",
 * i.e. playhead minus output latency) and the calibration clicks both
 * go through this anchor.
 */
import * as Tone from 'tone'

type OutputTimestamp = { contextTime: number; performanceTime: number }

function rawCtx(): AudioContext {
  return Tone.getContext().rawContext as unknown as AudioContext
}

/** baseLatency + outputLatency in seconds (0 when the browser reports none). */
export function outputLatencySec(): number {
  const ctx = rawCtx()
  return (ctx.baseLatency ?? 0) + (ctx.outputLatency ?? 0)
}

/**
 * Wall-clock time (ms, `performance.now()` domain) at which the audio
 * scheduled for AudioContext time `ctxTime` is heard. Falls back to
 * subtracting reported latency when `getOutputTimestamp` is missing.
 */
export function audibleWallMs(ctxTime: number): number {
  const ctx = rawCtx()
  const ts = ctx.getOutputTimestamp?.() as OutputTimestamp | undefined
  if (ts && ts.contextTime != null && ts.performanceTime != null) {
    return ts.performanceTime + (ctxTime - ts.contextTime) * 1000
  }
  return performance.now() + (ctxTime - ctx.currentTime) * 1000 - outputLatencySec() * 1000
}
