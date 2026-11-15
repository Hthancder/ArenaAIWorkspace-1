import * as Tone from 'tone'

/**
 * Standalone metronome for free play / practice (research-piano/06: web
 * pianos ship a 40–240 BPM metronome; the range matches toolv's spec).
 *
 * Same sound identity as the record count-in (`click.ts`): a short sine
 * pulse, ~70 ms exponential decay, higher pitch on the downbeat so bar 1
 * is audible. Wired straight to the AudioContext output — bypassing the
 * sampler chain so the click stays dry and never colours exports.
 *
 * Scheduling uses the standard Web Audio lookahead pattern (25 ms tick,
 * ~120 ms horizon): beat times are computed in AudioContext clock from a
 * start anchor, so the grid never drifts with timer jitter.
 *
 * Deliberately NOT synced to the song tempo map yet — this is a practice
 * click at a user-chosen tempo (TODO(spec): follow song tempo when a MIDI
 * file is loaded).
 */

const DOWNBEAT_HZ = 1500
const UPBEAT_HZ = 1000
const PEAK_GAIN = 0.3
const ATTACK_S = 0.005
const DECAY_S = 0.07

export const METRONOME_BPM_MIN = 40
export const METRONOME_BPM_MAX = 240

const TICK_MS = 25
const LOOKAHEAD_S = 0.12

class MetronomeScheduler {
  private timer: ReturnType<typeof setInterval> | null = null
  private nextBeatTime = 0
  private beatIndex = 0
  private bpm = 100
  private beatsPerBar = 4

  get running(): boolean {
    return this.timer !== null
  }

  start(bpm: number, beatsPerBar: number): void {
    this.bpm = clampBpm(bpm)
    this.beatsPerBar = Math.max(1, Math.round(beatsPerBar))
    if (this.timer !== null) return
    const ctx = Tone.getContext().rawContext as unknown as AudioContext
    // Small lead so the first click lands cleanly on a buffer boundary.
    this.nextBeatTime = ctx.currentTime + 0.05
    this.beatIndex = 0
    this.timer = setInterval(() => this.tick(), TICK_MS)
    this.tick()
  }

  stop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  /** Live-update tempo/meter while running; no-op when stopped. */
  update(bpm: number, beatsPerBar: number): void {
    this.bpm = clampBpm(bpm)
    this.beatsPerBar = Math.max(1, Math.round(beatsPerBar))
  }

  private tick(): void {
    const ctx = Tone.getContext().rawContext as unknown as AudioContext
    const beatSec = 60 / this.bpm
    while (this.nextBeatTime < ctx.currentTime + LOOKAHEAD_S) {
      const isDownbeat = this.beatIndex % this.beatsPerBar === 0
      this.scheduleClick(this.nextBeatTime, isDownbeat)
      this.nextBeatTime += beatSec
      this.beatIndex++
    }
  }

  private scheduleClick(time: number, downbeat: boolean): void {
    const ctx = Tone.getContext().rawContext as unknown as AudioContext
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.frequency.value = downbeat ? DOWNBEAT_HZ : UPBEAT_HZ
    osc.connect(gain).connect(ctx.destination)
    gain.gain.setValueAtTime(0.0001, time)
    gain.gain.exponentialRampToValueAtTime(PEAK_GAIN, time + ATTACK_S)
    gain.gain.exponentialRampToValueAtTime(0.0001, time + DECAY_S)
    osc.start(time)
    osc.stop(time + DECAY_S + 0.01)
  }
}

function clampBpm(bpm: number): number {
  return Math.min(METRONOME_BPM_MAX, Math.max(METRONOME_BPM_MIN, bpm))
}

export const metronome = new MetronomeScheduler()
