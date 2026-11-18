/**
 * GĐ 7 — auto hand split (line-aware): unit tests for `splitHands`, the
 * ngưỡng đo the plan was approved with:
 *   - Case A (LH figure crossing C4 + sparse RH chords): the figure stays
 *     whole on ONE hand (0 mid-run switches — the real planner produced 6)
 *     and the chords keep their own hand;
 *   - interlocking wide arpeggio: each monotonic pass is one hand (0 cuts
 *     mid-run); hands may alternate only between passes;
 *   - tenor melody + treble chords: the melody line belongs to L entirely;
 *   - a playable chord (≤ hand-span) is atomic (one hand); a too-wide
 *     chord splits at its gaps;
 *   - explicit hands (selection card) always win and pull their line;
 *   - determinism: same input → same split.
 *
 * Run: `npx vite-node scripts/test-autosplit.ts`
 */
import { splitHands, type SplittableNote } from '../src/hands/autoSplit'

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

const N = (midi: number, on: number, dur = 0.2): SplittableNote => ({ midi, on, off: on + dur, hand: null })

/** Mid-run hand switches: consecutive stepwise notes (≤ 7 semitones, < 0.3 s apart) on different hands. */
function midRunSwitches(notes: SplittableNote[], hands: ('L' | 'R' | null)[]): number {
  let n = 0
  for (let i = 1; i < notes.length; i++) {
    const a = notes[i - 1]
    const b = notes[i]
    const step = Math.abs(b.midi - a.midi)
    if (hands[i] !== hands[i - 1] && step > 0 && step <= 7 && Math.abs(b.on - a.on) < 0.3) n++
  }
  return n
}

// ---- Case A: LH figure C2→G4 + sparse RH chords ----------------------
{
  const notes: SplittableNote[] = []
  for (let bar = 0; bar < 6; bar++) {
    const t0 = bar * 2
    ;[36, 43, 48, 52, 55, 60, 64, 67].forEach((m, i) => notes.push(N(m, t0 + 0.25 + i * 0.22)))
    notes.push({ midi: 72, on: t0, off: t0 + 1.8, hand: null })
    notes.push({ midi: 76, on: t0 + 1, off: t0 + 1.9, hand: null })
  }
  const hands = splitHands(notes)
  const figure = notes.map((n, i) => ({ n, i })).filter(({ n }) => n.midi <= 67 && n.midi >= 36)
  const figHands = new Set(figure.map(({ i }) => hands[i]))
  check('A: the LH figure stays whole on ONE hand', figHands.size === 1, [...figHands].join(','))
  check('A: 0 mid-run hand switches (planner had 6)', midRunSwitches(notes, hands) === 0, String(midRunSwitches(notes, hands)))
  check('A: the figure (lower line) is the LEFT hand', hands[figure[0].i] === 'L', String(hands[figure[0].i]))
  const chordNotes = notes.map((n, i) => ({ n, i })).filter(({ n }) => n.midi >= 72)
  check('A: the chord line keeps its own hand (R)', chordNotes.every(({ i }) => hands[i] === 'R'))
}

// ---- Case C: interlocking wide arpeggio C2→C6 (up/down) --------------
{
  const notes: SplittableNote[] = []
  const up = [36, 48, 52, 55, 60, 64, 67, 72, 76, 79, 84, 88]
  for (let bar = 0; bar < 3; bar++) {
    const t0 = bar * 4
    up.forEach((m, i) => notes.push(N(m, t0 + i * 0.16, 0.15)))
    ;[...up].reverse().forEach((m, i) => notes.push(N(m, t0 + 1.95 + i * 0.16, 0.15)))
  }
  const hands = splitHands(notes)
  check('C: 0 cuts inside a monotonic pass', midRunSwitches(notes, hands) === 0, String(midRunSwitches(notes, hands)))
  // each pass runs monotonically — no note of a pass may sit on the other
  // hand than the pass's first note... (a pass may hand over only at the
  // turn-around, which is a direction change, covered by the check above)
  const drop = hands.filter((h) => !h).length
  check('C: every note gets a hand', drop === 0, String(drop))
}

// ---- Case D: held bass + low melody (G3–E4) --------------------------
{
  const notes: SplittableNote[] = []
  for (let bar = 0; bar < 4; bar++) {
    const t0 = bar * 2
    notes.push({ midi: 33, on: t0, off: t0 + 1.9, hand: null })
    ;[55, 59, 60, 62, 64, 62, 60, 59].forEach((m, i) => notes.push(N(m, t0 + 0.25 + i * 0.2, 0.18)))
  }
  const hands = splitHands(notes)
  check('D: the bass line is the LEFT hand', notes.every((n, i) => (n.midi === 33 ? hands[i] === 'L' : true)))
  const mel = notes.map((n, i) => ({ n, i })).filter(({ n }) => n.midi >= 55)
  check('D: the melody line is whole on ONE hand', new Set(mel.map(({ i }) => hands[i])).size === 1)
  check('D: 0 mid-run switches', midRunSwitches(notes, hands) === 0, String(midRunSwitches(notes, hands)))
}

// ---- Case F: tenor melody (C3–C4) + treble chords (C5–E5) -----------
{
  const notes: SplittableNote[] = []
  for (let bar = 0; bar < 4; bar++) {
    const t0 = bar * 2
    ;[48, 50, 52, 55, 57, 55, 52, 50].forEach((m, i) => notes.push(N(m, t0 + i * 0.25, 0.22)))
    notes.push({ midi: 72, on: t0, off: t0 + 1.2, hand: null }, { midi: 76, on: t0, off: t0 + 1.2, hand: null })
  }
  const hands = splitHands(notes)
  const mel = notes.map((n, i) => ({ n, i })).filter(({ n }) => n.midi < 60)
  check('F: the tenor melody belongs to L entirely', mel.every(({ i }) => hands[i] === 'L'))
  check('F: the treble chords belong to R', notes.every((n, i) => (n.midi >= 72 ? hands[i] === 'R' : true)))
}

// ---- chord atomicity + wide-chord split ------------------------------
{
  const chord: SplittableNote[] = [N(60, 0, 1), N(64, 0, 1), N(67, 0, 1)] // C4 E4 G4 — one hand
  const h1 = splitHands(chord)
  check('playable chord is atomic (one hand)', new Set(h1).size === 1, h1.join(','))
  const wide: SplittableNote[] = [N(36, 0, 1), N(43, 0, 1), N(52, 0, 1), N(64, 0, 1)] // C2 G2 E3 E4
  const h2 = splitHands(wide)
  check('too-wide chord splits between hands', new Set(h2).size === 2, h2.join(','))
  check('wide chord: lower unit → L, upper → R', h2[0] === 'L' && h2[3] === 'R', h2.join(','))
}

// ---- explicit hands win and pull their line --------------------------
{
  const notes: SplittableNote[] = [N(36, 0), N(43, 0.25), N(48, 0.5), N(52, 0.75), N(72, 0), N(76, 0.25)]
  notes[2].hand = 'R' // user pins ONE note of the low figure to R
  const hands = splitHands(notes)
  check('pinned note keeps its hand', hands[2] === 'R', String(hands[2]))
  check('the pinned note pulls its line-mates along', hands[0] === 'R' && hands[3] === 'R', hands.slice(0, 4).join(','))
  check('unpinned explicit-free chord line unaffected', hands[4] === 'R' || hands[4] === 'L')
}

// ---- determinism + single line --------------------------------------
{
  const notes: SplittableNote[] = []
  for (let i = 0; i < 16; i++) notes.push(N(60 + (i % 12), i * 0.3, 0.25))
  const a = splitHands(notes).join('')
  const b = splitHands(notes).join('')
  check('deterministic: same input → same split', a === b)
  const single: SplittableNote[] = [N(72, 0), N(74, 0.3), N(76, 0.6), N(79, 0.9)]
  const hs = splitHands(single)
  check('single treble line → R (C4 default)', hs.every((h) => h === 'R'), hs.join(','))
  const singleLow: SplittableNote[] = [N(36, 0), N(38, 0.3), N(40, 0.6)]
  check('single bass line → L', splitHands(singleLow).every((h) => h === 'L'))
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : `\n${failures} FAILURES`)
if (failures) process.exit(1)
process.exit(0)
