/**
 * GĐ 7 — auto hand split ("chia tay tự động", line-aware): pre-assign a
 * hand to every unassigned note BEFORE the motion runtime plans, so each
 * melodic line / figure stays whole on ONE hand and the register split
 * follows the music's own gaps (not a fixed C4 wall).
 *
 * Root cause it fixes (measured on the real planner, 2026-11-16): the
 * runtime optimises per note, so on wide-span pieces it CUTS a continuous
 * LH figure mid-run and hands its top to the right hand ("tay phải tranh
 * đánh phần của tay trái", "đổi tay giữa chừng đường nốt"). Explicit
 * assignments (selection card / .nfz manifest) always win — the runtime's
 * `pin` keeps whatever hand we set and only plans fingers inside it
 * (verified 144/144).
 *
 * Pure and deterministic: same input → same split (exports and previews
 * agree). Handled here:
 *   - onset clusters (≤ 40 ms) become "units"; a cluster wider than a
 *     hand-span splits at its largest pitch gaps (a too-wide chord is
 *     shared by the two hands, a playable one stays atomic);
 *   - units chain into lines by nearest pitch continuation (≤ octave,
 *     stepwise preferred) with legato overlap tolerance — sustained
 *     accompaniment never swallows a melody note;
 *   - lines cluster into two hands by mean pitch (k-means, k = 2, fixed
 *     init at the extreme means); one line alone follows the C4 default;
 *     a line the user pinned takes its hand and anchors the rest.
 */

export type SplittableNote = {
  midi: number
  on: number
  off: number
  hand?: 'L' | 'R' | null
}

/** Onsets within this form one struck event (a chord / a near-unison). */
const CLUSTER_GAP = 0.04
/** A line may continue through up to this much note overlap (legato MIDI). */
const LINK_OVERLAP_TOL = 0.12
/** Pitch gaps above this split one struck event into separate units. */
const UNIT_GAP = 7
/** One hand's simultaneous reach (semitones) — wider chords share hands. */
const UNIT_SPAN = 12
/**
 * A simultaneous note followed by another note within this window is the
 * start of a FIGURE (melody/ostinato), not part of the held chord — it must
 * separate, or the figure would drag the chord along (measured: the 2-note
 * ostinato's first note merged into the accompaniment chord and the
 * alternation got split between hands).
 */
const FIG_WINDOW = 0.4
/** The largest pitch step that still continues the same line (an octave). */
const LINK_STEP = 12
/** Gaps shorter than this cost nothing when continuing a line. */
const LINK_TAU = 0.3
/**
 * Semitones of pitch-indifference per second of staleness: a line whose
 * last note ended long ago must be MUCH closer in pitch to steal a note
 * from the fresh local figure (measured fix — a dead line 1.6 s old used
 * to win by 1 semitone and scatter a run across three hands' worth of
 * lines).
 */
const LINK_STALE = 3
/** Single-line fallback boundary (the architecture doc's C4 default). */
const SINGLE_LINE_BOUNDARY = 60

type Unit = {
  idx: number[] // note indices, by ascending pitch
  on: number
  off: number
  mean: number
  forced: 'L' | 'R' | null
}

type Line = {
  units: Unit[]
  lastOff: number
  lastMean: number
  mean: number
  forced: 'L' | 'R' | null
}

const meanOf = (idx: number[], notes: SplittableNote[]): number =>
  idx.reduce((a, i) => a + notes[i].midi, 0) / Math.max(1, idx.length)

function forcedHandOf(idx: number[], notes: SplittableNote[]): 'L' | 'R' | null {
  let l = 0
  let r = 0
  for (const i of idx) {
    if (notes[i].hand === 'L') l++
    else if (notes[i].hand === 'R') r++
  }
  if (l === 0 && r === 0) return null
  return l >= r ? 'L' : 'R'
}

/** Split one struck event into units: playable groups, at the largest gaps. */
function clusterToUnits(cluster: number[], notes: SplittableNote[]): Unit[] {
  const byPitch = [...cluster].sort((a, b) => notes[a].midi - notes[b].midi)
  const units: Unit[] = []
  // figure starts: notes with a near-in-time continuation OUTSIDE the cluster
  const isFigStart = (i: number): boolean =>
    notes.some(
      (m, j) =>
        cluster.indexOf(j) < 0 &&
        m.on > notes[i].on &&
        m.on - notes[i].on <= FIG_WINDOW &&
        Math.abs(m.midi - notes[i].midi) <= LINK_STEP,
    )
  let cur: number[] = []
  for (const i of byPitch) {
    if (isFigStart(i)) {
      if (cur.length) units.push(makeUnit(cur, notes))
      units.push(makeUnit([i], notes))
      cur = []
      continue
    }
    const p = notes[i].midi
    const prev = cur.length ? notes[cur[cur.length - 1]].midi : null
    const span = cur.length ? p - notes[cur[0]].midi : 0
    if (prev !== null && (p - prev > UNIT_GAP || span > UNIT_SPAN)) {
      units.push(makeUnit(cur, notes))
      cur = []
    }
    cur.push(i)
  }
  if (cur.length) units.push(makeUnit(cur, notes))
  return units
}

function makeUnit(idx: number[], notes: SplittableNote[]): Unit {
  return {
    idx,
    on: Math.min(...idx.map((i) => notes[i].on)),
    off: Math.max(...idx.map((i) => notes[i].off)),
    mean: meanOf(idx, notes),
    forced: forcedHandOf(idx, notes),
  }
}

/**
 * Per-note hand for the song: `null` only where the note already carries an
 * explicit hand (those are kept). Deterministic; see the module comment for
 * the algorithm and the measured failure it fixes.
 */
export function splitHands(notes: SplittableNote[]): ('L' | 'R' | null)[] {
  const out: ('L' | 'R' | null)[] = notes.map((n) => n.hand ?? null)
  if (notes.length <= 1) return out

  // 1) struck events → units
  const order = notes.map((_, i) => i).sort((a, b) => notes[a].on - notes[b].on || notes[a].midi - notes[b].midi)
  const units: Unit[] = []
  let cluster: number[] = []
  let clusterOn = -Infinity
  for (const i of order) {
    if (cluster.length && notes[i].on - clusterOn > CLUSTER_GAP) {
      units.push(...clusterToUnits(cluster, notes))
      cluster = []
    }
    if (!cluster.length) clusterOn = notes[i].on
    cluster.push(i)
  }
  if (cluster.length) units.push(...clusterToUnits(cluster, notes))
  // Units of one event share its onset order deterministically (pitch asc).
  units.sort((a, b) => a.on - b.on || a.mean - b.mean)

  // 2) units → lines (nearest pitch continuation; legato overlap tolerated;
  //    a stale line must be much closer in pitch to take the note)
  const lines: Line[] = []
  for (const u of units) {
    let best: Line | null = null
    let bestScore = Infinity
    for (const ln of lines) {
      if (ln.lastOff > u.on + LINK_OVERLAP_TOL) continue // still sounding: another voice
      const d = Math.abs(u.mean - ln.lastMean)
      if (d > LINK_STEP) continue
      const stale = Math.max(0, u.on - ln.lastOff - LINK_TAU)
      const score = d + LINK_STALE * stale
      if (score < bestScore - 1e-9) {
        bestScore = score
        best = ln
      }
    }
    if (best) {
      best.units.push(u)
      best.lastOff = Math.max(best.lastOff, u.off)
      best.lastMean = u.mean
    } else {
      lines.push({ units: [u], lastOff: u.off, lastMean: u.mean, mean: 0, forced: null })
    }
  }
  for (const ln of lines) {
    const all: number[] = []
    for (const u of ln.units) all.push(...u.idx)
    ln.mean = meanOf(all, notes)
    ln.forced = forcedHandOf(all, notes) // majority of the line's pinned notes
  }

  // 3) lines → hands: pinned lines anchor; the rest cluster by mean pitch
  const free = lines.filter((ln) => !ln.forced)
  const pinned = lines.filter((ln) => ln.forced)
  let handOf: Map<Line, 'L' | 'R'>
  if (free.length === 0) {
    handOf = new Map(lines.map((ln) => [ln, ln.forced!]))
  } else if (free.length === 1) {
    const h: 'L' | 'R' = free[0].mean < SINGLE_LINE_BOUNDARY ? 'L' : 'R'
    handOf = new Map(lines.map((ln) => [ln, ln.forced ?? h]))
  } else {
    // Deterministic k-means (k = 2) on line means; pinned lines vote the
    // labelling so a user-pinned low line makes the lower cluster "L".
    let cL = Math.min(...free.map((ln) => ln.mean))
    let cR = Math.max(...free.map((ln) => ln.mean))
    const clusterOf = new Map<Line, 0 | 1>()
    for (let it = 0; it < 20; it++) {
      let changed = false
      for (const ln of free) {
        const side: 0 | 1 = Math.abs(ln.mean - cL) <= Math.abs(ln.mean - cR) ? 0 : 1
        if (clusterOf.get(ln) !== side) {
          clusterOf.set(ln, side)
          changed = true
        }
      }
      const g0 = free.filter((ln) => clusterOf.get(ln) === 0)
      const g1 = free.filter((ln) => clusterOf.get(ln) === 1)
      if (g0.length) cL = g0.reduce((a, ln) => a + ln.mean, 0) / g0.length
      if (g1.length) cR = g1.reduce((a, ln) => a + ln.mean, 0) / g1.length
      if (!changed) break
    }
    // Labelling: the lower centre is the left hand (the piano's natural
    // convention); pinned lines override their own line individually.
    handOf = new Map()
    for (const ln of free) {
      const side = clusterOf.get(ln) ?? (ln.mean < SINGLE_LINE_BOUNDARY ? 0 : 1)
      handOf.set(ln, side === 0 ? 'L' : 'R')
    }
    for (const ln of pinned) handOf.set(ln, ln.forced!)
  }

  // 4) write back (explicit hands stay untouched)
  for (const ln of lines) {
    const h = handOf.get(ln)!
    for (const u of ln.units) for (const i of u.idx) if (out[i] == null) out[i] = h
  }
  return out
}

/** Fill `hand` on every unassigned note (in place). */
export function autoSplitHands(notes: SplittableNote[]): void {
  const hands = splitHands(notes)
  for (let i = 0; i < notes.length; i++) {
    if (notes[i].hand == null && hands[i]) notes[i].hand = hands[i]
  }
}
