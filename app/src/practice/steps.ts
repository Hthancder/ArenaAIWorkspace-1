/**
 * Wait-mode step builder — research-piano/16.3.1:
 * `steps = groupNotesByOnset(song.notes, tolMs = 30)`. Each step is the
 * set of DISTINCT pitches at one onset cluster; repeated pitches inside
 * a cluster collapse (a chord containing two C4s is still satisfied by
 * one C4 press — the classic "nốt lặp lại cùng pitch" trap is handled
 * by tracking presses per step, not held keys).
 */
import type { NoteEvent } from '../midi/types'
import type { WaitStep } from './types'

export const ONSET_TOL_SEC = 0.03

export function groupNotesByOnset(
  notes: readonly NoteEvent[],
  tolSec: number = ONSET_TOL_SEC,
): WaitStep[] {
  const steps: WaitStep[] = []
  let clusterStart = -Infinity
  for (const n of [...notes].sort((a, b) => a.time - b.time)) {
    if (n.time - clusterStart > tolSec) {
      clusterStart = n.time
      steps.push({ time: n.time, pitches: [n.midi] })
    } else {
      const step = steps[steps.length - 1]
      if (!step.pitches.includes(n.midi)) step.pitches.push(n.midi)
    }
  }
  for (const s of steps) s.pitches.sort((a, b) => a - b)
  return steps
}

/**
 * Which step the flow should target when the playhead sits at
 * `fromMidi` (midi-seconds): the first step at/after the playhead,
 * grabbing a step the playhead sits just past by ≤ `grabEps`. Past the
 * loop end (or past the last step) it wraps to the loop head, else the
 * first step. Pure — the controller owns the store conversions.
 */
export function resolveStepIndex(
  steps: readonly WaitStep[],
  fromMidi: number,
  loop: { startMidi: number | null; endMidi: number | null },
  grabEps = 0.05,
): number {
  let index = steps.findIndex((s) => s.time >= fromMidi - grabEps)
  if (index >= 0 && loop.endMidi !== null && steps[index].time >= loop.endMidi) index = -1
  if (index < 0) {
    const from = loop.startMidi ?? 0
    const found = steps.findIndex((s) => s.time >= from - 1e-9)
    index = found >= 0 ? found : 0
  }
  return index
}
