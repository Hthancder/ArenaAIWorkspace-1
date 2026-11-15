/**
 * Practice-mode session state + HUD counters.
 *
 * Kept OUTSIDE the main `store.ts` on purpose:
 *  - session counters must never dirty the project document hash
 *    (main store hashes all of `Settings` — see `hashSettings`);
 *  - the user prefs here (mode, calibration offset, auto-advance) are
 *    per-setup, not per-song, so they persist to `localStorage`
 *    (browser-local; no backend — docs/41 rule).
 */
import { create } from 'zustand'
import {
  emptyTotals,
  type PracticeMode,
  type Summary,
  type Totals,
  type Verdict,
  type WaitStep,
} from './types'

const LS_KEY = 'piano.practice.v1'

type Persisted = {
  mode: PracticeMode
  scoringOffsetMs: number
  waitAutoAdvanceMs: number
}

function loadPersisted(): Persisted {
  const base: Persisted = { mode: 'off', scoringOffsetMs: 0, waitAutoAdvanceMs: 5000 }
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (!raw) return base
    const p = JSON.parse(raw) as Partial<Persisted>
    return {
      mode: p.mode === 'wait' || p.mode === 'rhythm' ? p.mode : 'off',
      scoringOffsetMs: typeof p.scoringOffsetMs === 'number' ? p.scoringOffsetMs : 0,
      waitAutoAdvanceMs: typeof p.waitAutoAdvanceMs === 'number' ? p.waitAutoAdvanceMs : 5000,
    }
  } catch {
    return base
  }
}

function persist(p: Persisted): void {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(p))
  } catch {
    /* private mode / quota — prefs just won't survive reload */
  }
}

export type WaitProgress = {
  active: boolean
  stepIndex: number
  stepCount: number
  required: number[]
  satisfied: number[]
  /** Presses of required pitches on the current step (first covers it). */
  attempts: number
  wrong: number
  firstTrySteps: number
  retrySteps: number
  skippedSteps: number
  done: boolean
  startedAt: number
}

export type CalibrationState = {
  status: 'idle' | 'running' | 'done' | 'failed'
  /** 1-based beat currently sounding (0 = none). */
  beat: number
  resultMs: number | null
}

type PracticeState = {
  // ── persisted prefs ──
  mode: PracticeMode
  scoringOffsetMs: number
  /** 0 = never auto-advance (wait mode). */
  waitAutoAdvanceMs: number

  // ── live session ──
  sessionActive: boolean
  combo: number
  bestCombo: number
  totals: Totals
  lastVerdict: { verdict: Verdict; deltaMs: number | null; at: number } | null
  wait: WaitProgress
  summary: Summary | null
  calibration: CalibrationState

  setMode: (m: PracticeMode) => void
  setScoringOffsetMs: (ms: number) => void
  setWaitAutoAdvanceMs: (ms: number) => void

  startSession: () => void
  endSession: () => void
  noteVerdict: (verdict: Verdict, deltaMs: number | null) => void

  waitBegin: (steps: WaitStep[]) => void
  waitSetStep: (index: number, step: WaitStep) => void
  waitSatisfy: (midi: number) => void
  waitAddAttempt: () => void
  waitWrong: () => void
  waitSkipStep: () => void
  waitFinish: () => void
  waitEnd: (summary: Summary) => void

  setSummary: (s: Summary | null) => void

  calibrationStart: () => void
  calibrationBeat: (beat: number) => void
  calibrationFinish: (resultMs: number | null) => void
  calibrationCancel: () => void
}

const emptyWait: WaitProgress = {
  active: false,
  stepIndex: 0,
  stepCount: 0,
  required: [],
  satisfied: [],
  attempts: 0,
  wrong: 0,
  firstTrySteps: 0,
  retrySteps: 0,
  skippedSteps: 0,
  done: false,
  startedAt: 0,
}

export const usePractice = create<PracticeState>()((set, get) => {
  const persisted = loadPersisted()
  const save = (patch: Partial<Persisted>) => {
    persist({
      mode: get().mode,
      scoringOffsetMs: get().scoringOffsetMs,
      waitAutoAdvanceMs: get().waitAutoAdvanceMs,
      ...patch,
    })
  }
  return {
    mode: persisted.mode,
    scoringOffsetMs: persisted.scoringOffsetMs,
    waitAutoAdvanceMs: persisted.waitAutoAdvanceMs,

    sessionActive: false,
    combo: 0,
    bestCombo: 0,
    totals: emptyTotals(),
    lastVerdict: null,
    wait: emptyWait,
    summary: null,
    calibration: { status: 'idle', beat: 0, resultMs: null },

    setMode: (m) => {
      save({ mode: m })
      set({ mode: m })
    },
    setScoringOffsetMs: (ms) => {
      save({ scoringOffsetMs: ms })
      set({ scoringOffsetMs: ms })
    },
    setWaitAutoAdvanceMs: (ms) => {
      save({ waitAutoAdvanceMs: ms })
      set({ waitAutoAdvanceMs: ms })
    },

    startSession: () =>
      set({
        sessionActive: true,
        combo: 0,
        bestCombo: 0,
        totals: emptyTotals(),
        lastVerdict: null,
      }),
    endSession: () => set({ sessionActive: false }),

    noteVerdict: (verdict, deltaMs) =>
      set((s) => {
        const totals = { ...s.totals }
        totals[verdict]++
        const matched = verdict !== 'extra'
        const combo = matched ? s.combo + 1 : 0
        return {
          totals,
          combo,
          bestCombo: Math.max(s.bestCombo, combo),
          lastVerdict: { verdict, deltaMs, at: performance.now() },
        }
      }),

    waitBegin: (steps) =>
      set({
        wait: {
          ...emptyWait,
          active: true,
          stepCount: steps.length,
          startedAt: performance.now(),
        },
      }),
    waitSetStep: (index, step) =>
      set((s) => ({
        wait: {
          ...s.wait,
          stepIndex: index,
          required: [...step.pitches],
          satisfied: [],
          attempts: 0,
        },
      })),
    waitSatisfy: (midi) =>
      set((s) => {
        const satisfied = s.wait.satisfied.includes(midi)
          ? s.wait.satisfied
          : [...s.wait.satisfied, midi]
        return {
          wait: {
            ...s.wait,
            satisfied,
            attempts: s.wait.attempts + 1,
          },
        }
      }),
    waitAddAttempt: () =>
      set((s) => ({
        wait: {
          ...s.wait,
          attempts: s.wait.attempts + 1,
          retrySteps: s.wait.retrySteps, // counted at step close
        },
      })),
    waitWrong: () => set((s) => ({ wait: { ...s.wait, wrong: s.wait.wrong + 1 } })),
    /** Close the current step's stats (first-try vs retry). Called on advance. */
    waitSkipStep: () =>
      set((s) => ({
        wait: {
          ...s.wait,
          skippedSteps: s.wait.skippedSteps + 1,
        },
      })),
    waitFinish: () => set((s) => ({ wait: { ...s.wait, done: true } })),
    waitEnd: (summary) => set({ wait: { ...emptyWait }, summary }),

    setSummary: (s) => set({ summary: s }),

    calibrationStart: () =>
      set({ calibration: { status: 'running', beat: 0, resultMs: null } }),
    calibrationBeat: (beat) =>
      set((s) => ({ calibration: { ...s.calibration, beat } })),
    calibrationFinish: (resultMs) =>
      set((s) => {
        if (resultMs !== null) {
          persist({
            mode: s.mode,
            scoringOffsetMs: resultMs,
            waitAutoAdvanceMs: s.waitAutoAdvanceMs,
          })
        }
        return {
          calibration: {
            status: resultMs === null ? 'failed' : 'done',
            beat: 0,
            resultMs,
          },
          scoringOffsetMs: resultMs ?? s.scoringOffsetMs,
        }
      }),
    calibrationCancel: () =>
      set({ calibration: { status: 'idle', beat: 0, resultMs: null } }),
  }
})

/** Steps whose first press covered everything (call when advancing a step). */
export function waitCloseStep(firstTry: boolean): void {
  usePractice.setState((s) => ({
    wait: {
      ...s.wait,
      firstTrySteps: s.wait.firstTrySteps + (firstTry ? 1 : 0),
      retrySteps: s.wait.retrySteps + (firstTry ? 0 : 1),
    },
  }))
}
