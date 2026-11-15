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
