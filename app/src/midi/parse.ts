import { Midi } from '@tonejs/midi'
import { KEPT_CONTROLS, type ControlEvent, type ParsedSong, type NoteEvent, type PedalEvent, type TrackInfo } from './types'

export async function parseMidi(file: ArrayBuffer, name: string): Promise<ParsedSong> {
  const midi = new Midi(file)
  const notes: NoteEvent[] = []
  const pedals: PedalEvent[] = []
  const controls: ControlEvent[] = []
  const tracks: TrackInfo[] = []
  let id = 0

  midi.tracks.forEach((track, trackIdx) => {
    track.notes.forEach((n) => {
      notes.push({
        id: id++,
        midi: n.midi,
        time: n.time,
        duration: n.duration,
        velocity: n.velocity,
        track: trackIdx,
      })
    })
    const cc64 = track.controlChanges[64]
    if (cc64) {
      cc64.forEach((cc) => {
        pedals.push({ time: cc.time, value: cc.value })
      })
    }
    for (const number of KEPT_CONTROLS) {
      for (const cc of track.controlChanges[number] ?? []) {
        controls.push({ number, time: cc.time, value: cc.value })
      }
    }
    // SMF track names are often empty or whitespace; fall back to a
    // synthetic "Track N" label so the per-track UI has something to
    // render. The index stays in lockstep with `NoteEvent.track`.
    const rawName = (track.name ?? '').trim()
    tracks.push({
      name: rawName.length > 0 ? rawName : `Track ${trackIdx + 1}`,
      hasNotes: track.notes.length > 0,
    })
  })

  notes.sort((a, b) => a.time - b.time)
  pedals.sort((a, b) => a.time - b.time)
  controls.sort((a, b) => a.time - b.time)

  // Tempo map for practice scoring (research 16.4.1). @tonejs/midi
  // always reports at least the default 120 BPM event.
  const tempos = [...midi.header.tempos]
    .sort((a, b) => a.ticks - b.ticks)
    .map((tp) => ({ time: tp.time ?? midi.header.ticksToSeconds(tp.ticks), bpm: tp.bpm }))

  // Bar boundary times from the time-signature map (research 16.4.4
  // per-bar report). Each signature starts a run of bars of
  // (num * 4/denom) quarter-beats; boundaries are converted through
  // the header's tick→second mapping so tempo changes stay exact.
  const barTimes: number[] = []
  try {
    const ppq = midi.header.ppq
    const sigs = [...midi.header.timeSignatures].sort((a, b) => a.ticks - b.ticks)
    const totalTicks = midi.duration > 0 ? midi.header.secondsToTicks(midi.duration) : 0
    const list =
      sigs.length > 0
        ? sigs
        : [{ ticks: 0, timeSignature: [4, 4] as [number, number], time: 0 }]
    for (let si = 0; si < list.length; si++) {
      const ev = list[si]
      const endTicks = si + 1 < list.length ? list[si + 1].ticks : totalTicks
      const [num, den] = ev.timeSignature
      const barTicks = (num * 4) / den * ppq
      if (!(barTicks > 0)) continue
      for (let tick = ev.ticks; tick < endTicks && barTimes.length < 20000; tick += barTicks) {
        barTimes.push(midi.header.ticksToSeconds(tick))
      }
    }
  } catch {
    // Malformed header — per-bar reporting degrades to totals only.
  }

  return {
    name,
    duration: midi.duration,
    notes,
    pedals,
    controls,
    tracks,
    tempos,
    barTimes,
  }
}
