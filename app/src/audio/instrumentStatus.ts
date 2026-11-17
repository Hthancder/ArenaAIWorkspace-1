/**
 * Instrument-switch load status — a tiny external store (the same
 * pattern as `hands/motion.ts`'s hands status) so two consumers can
 * watch a sample download without going through the main store:
 *
 * - `LoadingIsland` shows a "loading instrument" row (its own row,
 *   deliberately NOT `store.loadStatus` — that one gates playback
 *   while the FIRST piano loads, and a mid-session instrument switch
 *   must not block play: the old sampler keeps sounding until the
 *   swap).
 * - The Inspector's instrument picker shows inline progress.
 *
 * Written only by `AudioEngine.setInstrument` (which guards emissions
 * with its rebuild generation so a superseded build goes quiet).
 */

export type InstrumentLoadState =
  | { state: 'idle' }
  | { state: 'loading'; loaded: number; total: number }
  | { state: 'ready' }
  | { state: 'error'; message: string }

let state: InstrumentLoadState = { state: 'idle' }
const subs = new Set<(s: InstrumentLoadState) => void>()

export function getInstrumentLoad(): InstrumentLoadState {
  return state
}

export function subscribeInstrumentLoad(
  fn: (s: InstrumentLoadState) => void,
): () => void {
  subs.add(fn)
  return () => subs.delete(fn)
}

/** For the engine (and tests) only — not a UI setter. */
export function setInstrumentLoad(next: InstrumentLoadState): void {
  state = next
  for (const fn of [...subs]) fn(next)
}
