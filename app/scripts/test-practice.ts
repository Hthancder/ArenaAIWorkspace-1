/**
 * Headless smoke tests for the practice engine (research-piano/16.7,
 * cases 1–8 minus fingering). Pure logic only — no audio, no DOM.
 *
 * Run: `npx tsx scripts/test-practice.ts`
 */
import { timingWindows, onsetStepBeats, bpmAt } from '../src/practice/windows'
import { groupNotesByOnset, resolveStepIndex } from '../src/practice/steps'
import { RhythmMatcher, barIndexAt } from '../src/practice/match'
import type { NoteEvent } from '../src/midi/types'

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

const note = (id: number, midi: number, time: number, duration = 0.5): NoteEvent => ({
  id,
  midi,
  time,
  duration,
  velocity: 0.8,
  track: 0,
})

console.log('16.4.1 windows formula')
{
  // 60 BPM quarter notes → 400/140 ms (doc table)
  const w1 = timingWindows(1000, 1)
  check('60 BPM quarter', w1.windowMs === 400 && w1.goodMs === 140, JSON.stringify(w1))
  // 120 BPM eighths → 125/75 ms
  const w2 = timingWindows(500, 0.5)
  check('120 BPM eighth', w2.windowMs === 125 && w2.goodMs === 75, JSON.stringify(w2))
}

console.log('onset density')
{
  // Chord partners share an onset — must NOT collapse the window.
  const beats = onsetStepBeats([0, 0, 0, 1.0], [{ time: 0, bpm: 120 }])
  check('chord keeps neighbour gap', Math.abs(beats[0] - 1) < 1e-9, JSON.stringify(beats))
  check('bpmAt fallback', bpmAt(undefined, 5) === 120)
}

console.log('16.7.1 perfect session')
{
  const notes = [note(0, 60, 1), note(1, 62, 2), note(2, 64, 3)]
  const m = new RhythmMatcher(notes, undefined, undefined, 0)
  m.playOn(60, 1000)
  m.playOn(62, 2000)
  m.playOn(64, 3000)
  const r = m.finalize()
  check(
    'all perfect, 0 extra/miss',
    r.totals.perfect === 3 && r.totals.extra === 0 && r.totals.miss === 0,
    JSON.stringify(r.totals),
  )
}

console.log('16.7.2 uniform +30 ms with 30 ms calibration')
{
  const notes = [note(0, 60, 1), note(1, 64, 2)]
  const m = new RhythmMatcher(notes, undefined, undefined, 30)
  m.playOn(60, 1030) // Δ after offset = 0
  m.playOn(64, 2030)
  const r = m.finalize()
  check('late 0 after offset', r.totals.late === 0 && r.totals.miss === 0, JSON.stringify(r.totals))
  check('perfect/good only', r.totals.perfect + r.totals.good === 2)
}

console.log('16.7.3 skipped note → miss')
{
  const notes = [note(0, 60, 1), note(1, 62, 2), note(2, 64, 3)]
  const m = new RhythmMatcher(notes, undefined, undefined, 0)
  m.playOn(60, 1000)
  m.playOn(64, 3000) // 62 never played
  const r = m.finalize()
  check('exactly 1 miss', r.totals.miss === 1, JSON.stringify(r.totals))
  check('miss is pitch 62', r.notes.some((n) => n.verdict === 'miss' && n.pitch === 62))
}

console.log('16.7.4 extra note')
{
  const notes = [note(0, 60, 1)]
  const m = new RhythmMatcher(notes, undefined, undefined, 0)
  m.playOn(60, 1000)
  m.playOn(72, 1100) // no expected within window
  const r = m.finalize()
  check('1 extra, 0 miss', r.totals.extra === 1 && r.totals.miss === 0, JSON.stringify(r.totals))
}

console.log('16.7.5 repeated pitch needs two presses')
{
  const notes = [note(0, 60, 1, 0.2), note(1, 60, 1.5, 0.2)]
  const m = new RhythmMatcher(notes, undefined, undefined, 0)
  m.playOn(60, 1000) // only the first C4
  const r = m.finalize()
  check('1 matched + 1 miss', r.totals.perfect === 1 && r.totals.miss === 1, JSON.stringify(r.totals))
  const m2 = new RhythmMatcher(notes, undefined, undefined, 0)
  m2.playOn(60, 1000)
  m2.playOn(60, 1500)
  const r2 = m2.finalize()
  check('two presses → 2 matched', r2.totals.perfect + r2.totals.good === 2 && r2.totals.miss === 0)
}

console.log('16.7.6 chord within tolerance')
{
  const notes = [note(0, 60, 1), note(1, 64, 1), note(2, 67, 1)]
  const m = new RhythmMatcher(notes, undefined, undefined, 0)
  m.playOn(60, 1000)
  m.playOn(64, 1050) // 50 ms apart
  m.playOn(67, 1060)
  const r = m.finalize()
  check('chord matched', r.totals.miss === 0 && r.totals.extra === 0, JSON.stringify(r.totals))
}

console.log('16.7.7 tempo map tightens the window')
{
  // 200 BPM, onsets 150 ms apart (= 0.5 beat) → window = 300*0.5*0.5 = 75 ms
  const notes = [note(0, 60, 1), note(1, 62, 1.15)]
  const m = new RhythmMatcher(notes, [{ time: 0, bpm: 200 }], undefined, 0)
  const late = m.playOn(60, 1000 + 100) // 100 ms late > 75 ms window → extra
  check('out-of-window press is extra at 200 BPM', late.verdict === 'extra', late.verdict)
  const on = m.playOn(62, 1150)
  check('in-window press still matches', on.verdict !== 'extra', on.verdict)
}

console.log('16.7.8 wait-mode steps')
{
  const notes = [note(0, 60, 1), note(1, 64, 1.01), note(2, 62, 1.5), note(3, 62, 3)]
  const steps = groupNotesByOnset(notes)
  check('3 steps (chord + 2 singles)', steps.length === 3, JSON.stringify(steps))
  check('chord pitches', steps[0].pitches.join() === '60,64')
  check('repeated pitch = separate steps', steps[1].pitches.join() === '62' && steps[2].pitches.join() === '62')
}

console.log('per-bar aggregation')
{
  const notes = [note(0, 60, 0.5), note(1, 62, 2.5), note(2, 64, 4.5)]
  // barTimes: bar1 at 0s, bar2 at 2s, bar3 at 4s
  const m = new RhythmMatcher(notes, undefined, [0, 2, 4], 0)
  m.playOn(60, 500)
  m.playOn(62, 2500)
  // 64 missed
  const r = m.finalize()
  check('barIndexAt', barIndexAt([0, 2, 4], 2.5) === 2)
  check('3 bars reported', r.perBar.length === 3, JSON.stringify(r.perBar))
  check('bar3 has the miss', r.perBar[2].correct === 0 && r.perBar[2].expected === 1)
}

console.log('flow-and-pause step targeting (2026-11-15 redesign)')
{
  const steps = groupNotesByOnset([note(0, 60, 1), note(1, 62, 2), note(2, 64, 3), note(3, 65, 5)])
  const none = { startMidi: null, endMidi: null }
  check('playhead before a step targets it', resolveStepIndex(steps, 0.2, none) === 0)
  check('playhead mid-gap targets the next step', resolveStepIndex(steps, 2.5, none) === 2)
  check('just past an onset grabs that step', resolveStepIndex(steps, 3.03, none) === 2)
  check('past the end restarts at step 0', resolveStepIndex(steps, 9, none) === 0)
  const loop = { startMidi: 2, endMidi: 3.5 }
  check('past the end wraps to the loop head', resolveStepIndex(steps, 9, loop) === 1)
  check('next step past B wraps to A', resolveStepIndex(steps, 3.1, loop) === 1)
  check('playhead before B targets the in-range step', resolveStepIndex(steps, 2.2, loop) === 2)
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
process.exit(failures === 0 ? 0 : 1)
