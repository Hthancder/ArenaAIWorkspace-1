/**
 * Practice engine wiring — research-piano/16.3.1 (Wait Mode) + 16.4
 * (scoring). One controller drives three concerns:
 *
 *  - Wait Mode (flow-and-pause redesign, 2026-11-15): steps = onset
 *    clusters (steps.ts). The notes FALL CONTINUOUSLY — a flow loop
 *    advances the playhead at the playback rate toward the current
 *    step's onset and STOPS exactly on it ("dừng chờ đánh"); when the
 *    player covers the step's pitch set the flow resumes toward the
 *    next onset. No teleporting between steps (the old seek-per-step
 *    model was visually jarring and laggy — `engine.seek()` rescans the
 *    whole note list and re-triggers sustained voices every step).
 *    Presses arrive via `audioEngine.addLiveListener` (the same bus the
 *    recorder uses — PC keyboard / on-screen / MIDI device all feed
 *    it). The play window opens EARLY_TL before the onset so natural
 *    anticipation counts; earlier presses are ignored. Wrong pitches
 *    are counted, never blocked (16.3.1 "Bấm sai" row). Optional
 *    auto-advance (default OFF — pure wait) and a Skip action rescue
 *    stuck players.
 *  - Rhythm scoring: play-along against the song; each live note-on is
 *    matched greedily (match.ts); HUD totals stream into the practice
 *    store. Finalize on song end or manually.
 *  - Calibration (16.2): 12 clicks, taps collected the same way.
 *
 * Clock discipline (16.1): scoring converts the playhead to "what the
 * user is hearing" by subtracting output latency, then subtracts the
 * calibration offset in the matcher.
 */
import { useEffect } from 'react'
import { audioEngine } from '../audio/engine'
import { pauseSong } from '../audio/playback'
import { timelineToMidi } from '../midi/speedMap'
import { outputLatencySec } from './latency'
import { RhythmMatcher } from './match'
import { groupNotesByOnset, resolveStepIndex } from './steps'
import type { TempoPoint } from './windows'
import {
  beginCalibration,
  finishCalibration,
  type CalibrationRun,
} from './calibration'
import { usePractice, waitCloseStep } from './practiceStore'
import type { PracticeMode, WaitStep, WaitSummary } from './types'
import { useStore } from '../store'

/**
 * The play window opens this long (TL-seconds, ≈ song seconds without
 * speed automation) before the step's onset: presses in the last
 * approach count as the step's play ("giai đoạn cần đánh"); earlier
 * presses are ignored so long-range mashing can't skip the stops.
 * TODO(spec) — artistic constant.
 */
const EARLY_TL = 0.75

class PracticeController {
  private matcher: RhythmMatcher | null = null
  private steps: WaitStep[] = []
  private waitTimer: number | null = null
  private calibrationRun: CalibrationRun | null = null
  private calibrationTaps: number[] = []
  /** True while we trigger preview notes — their live events must not count. */
  private suppressInput = false
  private rafEndCheck = 0

  // ── wait-mode flow clock (TL_audio) ────────────────────────────────
  // The flow loop owns the playhead while wait mode is active: it glides
  // toward the current step's onset and freezes exactly on it. Writes
  // go through `audioEngine.flowSet` (two field writes — no seek cost).
  private flowRaf = 0
  private flowT = 0
  private flowTargetT = 0
  private flowFrozen = false
  private flowLastWall = 0

  // ── mode transitions ──────────────────────────────────────────────

  setMode(m: PracticeMode): void {
    const prev = usePractice.getState().mode
    if (prev === m) return
    if (prev === 'wait') this.stopWait(false)
    if (prev === 'rhythm') this.finishRhythm(true)
    usePractice.getState().setMode(m)
    this.reconcile(m)
  }

  cycleMode(): void {
    const order: PracticeMode[] = ['off', 'wait', 'rhythm']
    const cur = usePractice.getState().mode
    this.setMode(order[(order.indexOf(cur) + 1) % order.length])
  }

  /** Re-initialize the current mode against the current song. */
  reconcile(mode: PracticeMode = usePractice.getState().mode): void {
    const song = useStore.getState().song
    if (mode === 'wait') {
      this.steps = song ? groupNotesByOnset(song.notes) : []
      if (this.steps.length === 0) return
      usePractice.getState().waitBegin(this.steps)
      // Wait mode drives the playhead itself — keep the transport quiescent.
      if (useStore.getState().transport === 'playing') pauseSong()
      // Flow starts from wherever the playhead is — no teleport back to 0.
      this.flowT = audioEngine.currentSongTime()
      this.flowFrozen = false
      this.beginStepAt(resolveStepIndex(this.steps, audioEngine.currentMidiTime(), this.loopMidi()))
      this.startFlow()
    } else if (mode === 'rhythm') {
      const s = usePractice.getState()
      s.startSession()
      this.buildMatcher()
      this.startEndCheck()
    }
  }

  private buildMatcher(): void {
    const song = useStore.getState().song
    const ps = usePractice.getState()
    if (!song) {
      this.matcher = null
      return
    }
    const tempos: TempoPoint[] | undefined = song.tempos
    this.matcher = new RhythmMatcher(
      song.notes,
      tempos,
      song.barTimes,
      ps.scoringOffsetMs,
    )
  }

  // ── wait mode ─────────────────────────────────────────────────────

  /** Loop A–B points converted from TL_audio to MIDI-time (null = unset). */
  private loopMidi(): { startMidi: number | null; endMidi: number | null } {
    const st = useStore.getState()
    const toMidi = (tl: number | null): number | null =>
      tl === null
        ? null
        : timelineToMidi(audioEngine.getSpeedMap(), tl - st.settings.midiOffsetSec)
    return { startMidi: toMidi(st.loopStart), endMidi: toMidi(st.loopEnd) }
  }

  /**
   * Arm step `i` as the flow target. The flow glides from the current
   * position toward the step's onset and freezes there. The ONLY
   * intentional jump is a backwards snap — loop A–B wrap (B → A) or a
   * same-onset step — which mirrors normal loop behaviour.
   */
  private beginStepAt(i: number): void {
    let index = i
    const loop = this.loopMidi()
    if (loop.endMidi !== null && this.steps[index] && this.steps[index].time >= loop.endMidi) {
      const from = loop.startMidi ?? 0
      const found = this.steps.findIndex((s) => s.time >= from - 1e-9)
      index = found >= 0 ? found : 0
    }
    if (index >= this.steps.length) {
      this.finishWait()
      return
    }
    const step = this.steps[index]
    const targetT = audioEngine.midiTimeToTimeline(step.time)
    if (targetT < this.flowT - 1e-9) {
      this.flowT = targetT
      audioEngine.flowSet(this.flowT)
    }
    this.flowTargetT = targetT
    this.flowFrozen = false
    usePractice.getState().waitSetStep(index, step)
    useStore.getState().setCurrentTime(this.flowT)
  }

  /**
   * The flow loop: advance the playhead at the playback rate toward the
   * current step's onset, freeze exactly on it, resume when the step is
   * played. One float write per frame — no note scans, no audio
   * re-triggers, no React state churn (the old seek-per-step model did
   * all three per step and stuttered hard).
   */
  private startFlow(): void {
    this.stopFlow()
    this.flowLastWall = performance.now()
    const tick = () => {
      this.flowRaf = requestAnimationFrame(tick)
      const ps = usePractice.getState()
      if (ps.mode !== 'wait' || !ps.wait.active || ps.wait.done) return
      // The exporter's virtual clock owns the engine while rendering.
      if (audioEngine.isExporting()) return
      // Wait mode owns the playhead: if the user hits Play, quiesce it.
      if (audioEngine.isPlaying()) {
        pauseSong()
        this.flowLastWall = performance.now()
        return
      }
      // External seek (seek bar / shortcuts): adopt the new position.
      const cur = audioEngine.currentSongTime()
      if (Math.abs(cur - this.flowT) > 1e-4) {
        this.reanchor(cur)
        return
      }
      const wall = performance.now()
      const dt = Math.min(0.1, (wall - this.flowLastWall) / 1000)
      this.flowLastWall = wall
      if (!this.flowFrozen) {
        this.flowT = Math.min(this.flowT + dt * audioEngine.getRate(), this.flowTargetT)
        if (this.flowT >= this.flowTargetT - 1e-9) {
          this.flowT = this.flowTargetT
          this.freezeStep()
        }
      }
      audioEngine.flowSet(this.flowT)
    }
    this.flowRaf = requestAnimationFrame(tick)
  }

  private stopFlow(): void {
    if (this.flowRaf) cancelAnimationFrame(this.flowRaf)
    this.flowRaf = 0
  }

  /** Flow reached the step's onset: stop here and wait for the play. */
  private freezeStep(): void {
    this.flowFrozen = true
    audioEngine.flowSet(this.flowT)
    // "Nghe trước": softly sound the required pitches as the stop cue
    // (the keys also glow via the engine's key listeners).
    this.suppressInput = true
    for (const midi of usePractice.getState().wait.required) audioEngine.triggerKey(midi, 0.12)
    this.suppressInput = false
    this.armAutoAdvance()
  }

  /** External seek detected — re-anchor the flow at the new playhead. */
  private reanchor(tl: number): void {
    const midiNow = audioEngine.currentMidiTime()
    this.flowT = tl
    this.flowFrozen = false
    audioEngine.flowSet(tl)
    this.beginStepAt(resolveStepIndex(this.steps, midiNow, this.loopMidi()))
  }

  private armAutoAdvance(): void {
    this.clearAutoAdvance()
    const ms = usePractice.getState().waitAutoAdvanceMs
    if (ms <= 0) return // default OFF — pure "dừng chờ đánh"
    this.waitTimer = window.setTimeout(() => {
      const ps = usePractice.getState()
      if (!ps.wait.active) return
      ps.waitSkipStep()
      this.advanceStep(false)
    }, ms)
  }

  private clearAutoAdvance(): void {
    if (this.waitTimer !== null) {
      window.clearTimeout(this.waitTimer)
      this.waitTimer = null
    }
  }

  skipStep(): void {
    const ps = usePractice.getState()
    if (ps.mode !== 'wait' || !ps.wait.active) return
    ps.waitSkipStep()
    this.advanceStep(false)
  }

  private advanceStep(_firstTry: boolean): void {
    const ps = usePractice.getState()
    // Classify the step just finished (first-try = one press per pitch,
    // no wrong presses). Skip-path passes via waitSkipStep instead.
    if (_firstTry) {
      const firstTry =
        ps.wait.attempts === ps.wait.required.length && ps.wait.satisfied.length === ps.wait.required.length
      waitCloseStep(firstTry)
    }
    this.clearAutoAdvance()
    this.beginStepAt(ps.wait.stepIndex + 1)
  }

  private stopWait(makeSummary: boolean): void {
    this.stopFlow()
    this.clearAutoAdvance()
    const ps = usePractice.getState()
    if (!ps.wait.active) return
    if (makeSummary) this.finishWait()
    else usePractice.setState({ wait: { ...usePractice.getState().wait, active: false, done: true } })
  }

  private finishWait(): void {
    this.stopFlow()
    this.clearAutoAdvance()
    const w = usePractice.getState().wait
    const summary: WaitSummary = {
      mode: 'wait',
      startedAt: w.startedAt,
      durationMs: performance.now() - w.startedAt,
      steps: w.stepCount,
      firstTry: w.firstTrySteps,
      retries: w.retrySteps,
      wrong: w.wrong,
      skipped: w.skippedSteps,
      offsetMs: usePractice.getState().scoringOffsetMs,
    }
    usePractice.getState().waitEnd(summary)
  }

  /** Handle one live note-on (user input). */
  handleNoteOn(midi: number): void {
    if (this.suppressInput) return

    // Calibration capture outranks everything else.
    if (this.calibrationRun) {
      this.calibrationTaps.push(performance.now())
      return
    }

    const ps = usePractice.getState()

    if (ps.mode === 'wait' && ps.wait.active && !ps.wait.done) {
      // The play window opens EARLY_TL before the onset and extends
      // through the freeze. Presses before the window are ignored —
      // too early to count towards this step (not "wrong").
      if (!this.flowFrozen && this.flowT < this.flowTargetT - EARLY_TL) return
      const required = ps.wait.required
      if (required.includes(midi)) {
        if (!ps.wait.satisfied.includes(midi)) {
          ps.waitSatisfy(midi)
          const now = usePractice.getState().wait
          if (now.satisfied.length >= now.required.length) {
            this.advanceStep(true)
          } else if (this.flowFrozen) {
            this.armAutoAdvance() // progress keeps the waiting step alive
          }
        } else {
          // Repeated pitch before advancing — counts as a retry press.
          ps.waitAddAttempt()
        }
      } else {
        ps.waitWrong()
      }
      return
    }

    if (ps.mode === 'rhythm' && ps.sessionActive && this.matcher) {
      // Only score against a moving playhead — while paused every press
      // would pile up at the frozen cursor.
      if (!audioEngine.isPlaying()) return
      // "What the user is hearing" = playhead minus output latency (16.1).
      const playedMs = (audioEngine.currentMidiTime() - outputLatencySec()) * 1000
      const { verdict, deltaMs } = this.matcher.playOn(midi, playedMs)
      ps.noteVerdict(verdict, deltaMs)
    }
  }

  // ── rhythm session lifecycle ──────────────────────────────────────

  private startEndCheck(): void {
    this.stopEndCheck()
    const tick = () => {
      const ps = usePractice.getState()
      if (ps.mode !== 'rhythm' || !ps.sessionActive) return
      const st = useStore.getState()
      if (st.transport === 'playing' && !audioEngine.isPlaying()) {
        // Engine auto-stopped at end of song → close the session.
        this.finishRhythm(false)
        return
      }
      this.rafEndCheck = requestAnimationFrame(tick)
    }
    this.rafEndCheck = requestAnimationFrame(tick)
  }

  private stopEndCheck(): void {
    if (this.rafEndCheck) cancelAnimationFrame(this.rafEndCheck)
    this.rafEndCheck = 0
  }

  /** finish=true discards silently (mode switched away); false → summary. */
  finishRhythm(silent: boolean): void {
    this.stopEndCheck()
    const ps = usePractice.getState()
    if (!ps.sessionActive) return
    ps.endSession()
    if (silent) {
      this.matcher = null
      return
    }
    const summary = this.matcher?.finalize() ?? null
    this.matcher = null
    if (summary) ps.setSummary(summary)
  }

  finishNow(): void {
    const ps = usePractice.getState()
    if (ps.mode === 'rhythm') this.finishRhythm(false)
    else if (ps.mode === 'wait' && ps.wait.active) this.finishWait()
  }

  // ── calibration (16.2) ────────────────────────────────────────────

  startCalibration(): void {
    if (this.calibrationRun) return
    this.calibrationTaps = []
    const ps = usePractice.getState()
    ps.calibrationStart()
    this.calibrationRun = beginCalibration((beat) => {
      usePractice.getState().calibrationBeat(beat + 1)
    })
    // scheduleCountIn fires onComplete after the last click's decay.
    // Re-schedule completion via the handle's own lifecycle: poll taps
    // lazily at completion time instead of relying on its callback
    // (the handle was created without one).
    const run = this.calibrationRun
    window.setTimeout(
      () => {
        if (this.calibrationRun !== run) return // cancelled
        const offset = finishCalibration(this.calibrationTaps, run.clickWallMs)
        this.calibrationRun = null
        usePractice.getState().calibrationFinish(offset)
      },
      (12 * (60 / 80) + 1) * 1000,
    )
  }

  cancelCalibration(): void {
    this.calibrationRun?.handle.cancel()
    this.calibrationRun = null
    usePractice.getState().calibrationCancel()
  }

  /** Song swapped under us — rebuild for the new note list. */
  onSongChanged(): void {
    this.stopFlow()
    this.clearAutoAdvance()
    this.stopEndCheck()
    this.matcher = null
    usePractice.setState({
      summary: null,
      wait: { ...usePractice.getState().wait, active: false },
    })
    const mode = usePractice.getState().mode
    if (mode !== 'off') this.reconcile(mode)
  }
}

export const practiceController = new PracticeController()

/**
 * Mount once (Layout): live-input subscription + song-change reconcile.
 * The controller owns all logic; the hook only bridges React lifetime.
 */
export function usePracticeEngine(): void {
  useEffect(() => {
    const unsub = audioEngine.addLiveListener((e) => {
      if (e.type === 'noteOn') practiceController.handleNoteOn(e.midi)
    })
    return unsub
  }, [])

  const song = useStore((s) => s.song)
  useEffect(() => {
    practiceController.onSongChanged()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [song])
}
