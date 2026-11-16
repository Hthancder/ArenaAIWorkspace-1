import { Scheduler } from 'smplr'

/**
 * Offline dispatch mode — makes EVERY smplr scheduler dispatch events
 * synchronously while an offline render is in flight.
 *
 * Why: smplr's instrument wrappers (Soundfont, ElectricPiano, Mallet,
 * SplendidGrandPiano…) build their own internal `Smplr` with the
 * DEFAULT Scheduler and do not forward a custom `scheduler` option.
 * The default defers events beyond ~100 ms to a setInterval dispatcher
 * that never runs during `OfflineAudioContext.startRendering()` (one
 * synchronous burst from the caller's perspective) — so any instrument
 * other than the ones we build as `new Smplr(json, { scheduler })`
 * would silently render only its first ~100 ms during WAV/MP4 export.
 *
 * Rather than replicating each class's internal JSON plumbing to force
 * a scheduler through, patch the scheduler's dispatch rule itself for
 * the duration of an offline render (ref-counted): every `schedule()`
 * behaves like the "within lookahead" branch — call the callback now
 * and return a no-op StopFn — which is exactly what the export's own
 * `lookaheadMs: Infinity` scheduler does. Voices still land at their
 * absolute audio times (`source.start(time)` is sample-accurate on
 * offline contexts), so the render is unchanged.
 *
 * Side-effect module — import once, before any instrument is created
 * (sampler.ts does this alongside `smoothRelease`).
 */

let offlinePianoRefs = 0

/**
 * Called when an offline piano is created. Returns the release
 * function — call it from `dispose()` (idempotent).
 */
export function retainOfflineDispatch(): () => void {
  offlinePianoRefs += 1
  let released = false
  return () => {
    if (released) return
    released = true
    offlinePianoRefs = Math.max(0, offlinePianoRefs - 1)
  }
}

type ScheduleFn = Scheduler['schedule']

const originalSchedule: ScheduleFn = Scheduler.prototype.schedule

Scheduler.prototype.schedule = function (
  this: Scheduler,
  ...args: Parameters<ScheduleFn>
): ReturnType<ScheduleFn> {
  if (offlinePianoRefs > 0) {
    // Mirror the "within lookahead" sync-dispatch branch.
    const [event, callback] = args
    callback(event)
    return () => {}
  }
  return originalSchedule.apply(this, args)
}
