/**
 * Settings persistence — everything the user tunes survives a reload.
 *
 * Requirement (2026-11-15): "cài đặt các thứ mình đã tùy chỉnh — được lưu
 * lại TẤT CẢ các cài đặt đó, để khi nào cần vào trang web mà không phải
 * chỉnh lại". Sound SAMPLES are deliberately NOT persisted by default —
 * that policy lives in `audio/sampleCache.ts` (opt-in), while every
 * preference does persist.
 *
 * Storage: one versioned JSON envelope in localStorage under
 * `nf:settings` (same `nf:` namespace as `nf:lang`, `nf:dev`, …).
 *
 *   { v: 1, settings, practice, customTexture }
 *
 * - `settings` — the whole zustand `Settings` object (all Inspector
 *   tunables, keyframes, …). Saved on every change, debounced.
 * - `practice` — the practice store's *prefs* only (mode, scoring
 *   offset, wait auto-advance, measured calibration latency). Live
 *   session state (combo, totals, wait progress) is never persisted.
 * - `customTexture` — the user-picked note-texture image (base64),
 *   size-guarded; restored through the same `setFromBytes` entry point
 *   project loading uses.
 *
 * Loading is lenient by design: a missing key fills from
 * `defaultSettings`, unknown keys drop silently, corrupted JSON is
 * ignored outright. That is what makes adding/renaming a settings key a
 * free change — the same merge rule `projects/actions.ts` applies to
 * saved projects (kept duplicated here on purpose: that module imports
 * the store, so importing it from a store-boot module would cycle).
 *
 * Restore runs once at boot, BEFORE React renders (main.tsx), so the
 * Layout engine-sync effect and every Inspector control read the
 * restored values as their initial state — no engine-side "apply
 * restored settings" pass is needed.
 */
import { defaultSettings, useStore, type Settings } from './store'
import { usePractice } from './practice/practiceStore'
import { useCustomTexture } from './notes/customTexture'
import {
  getSampleCacheMode,
  setSampleCacheMode,
} from './audio/sampleCache'

const STORAGE_KEY = 'nf:settings'
const SCHEMA_VERSION = 1
/** Custom-texture payloads above this are skipped (localStorage budget). */
const MAX_TEXTURE_B64 = 2_500_000 // ~1.8 MB of file bytes

type PersistedPractice = {
  mode?: string
  scoringOffsetMs?: number
  waitAutoAdvanceMs?: number
  calibrationResultMs?: number | null
}

type PersistShape = {
  v: number
  settings?: Partial<Settings>
  practice?: PersistedPractice
  customTexture?: { data: string; mime: string; fileName: string }
}

// ── merge helpers ───────────────────────────────────────────────────

/**
 * Lenient merge of a saved partial onto current defaults: copy only
 * keys this build knows, then fill the rest from `defaultSettings`.
 */
function mergeSettings(saved: Partial<Settings> | undefined): Settings {
  const known: Partial<Settings> = {}
  for (const key of Object.keys(saved ?? {}) as (keyof Settings)[]) {
    if (key in defaultSettings) {
      ;(known as Record<string, unknown>)[key] = saved![key]
    }
  }
  return { ...defaultSettings, ...known }
}

function readEnvelope(): PersistShape | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as PersistShape
    if (!parsed || typeof parsed !== 'object') return null
    if (typeof parsed.v !== 'number' || parsed.v > SCHEMA_VERSION) return null
    return parsed
  } catch {
    // Corrupted / unavailable storage — defaults win, app still runs.
    return null
  }
}

function writeEnvelope(env: PersistShape): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(env))
  } catch {
    // Quota exceeded (huge keyframes + texture) — drop the texture part
    // and retry once; if that fails too, persistence is simply off for
    // this session (never crash the app over a save).
    try {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({ ...env, customTexture: undefined }),
      )
    } catch {
      /* give up silently */
    }
  }
}

// ── save (debounced subscription) ───────────────────────────────────

let saveTimer: ReturnType<typeof setTimeout> | null = null
let booted = false

function buildEnvelope(): PersistShape {
  const s = useStore.getState().settings
  const p = usePractice.getState()
  const tex = useCustomTexture.getState()
  const env: PersistShape = {
    v: SCHEMA_VERSION,
    settings: s,
    practice: {
      mode: p.mode,
      scoringOffsetMs: p.scoringOffsetMs,
      waitAutoAdvanceMs: p.waitAutoAdvanceMs,
      calibrationResultMs: p.calibration.resultMs,
    },
  }
  if (tex.fileBytes && tex.fileMime) {
    const bytes = new Uint8Array(tex.fileBytes)
    // base64 encode without blowing the stack on big buffers.
    let bin = ''
    const CHUNK = 0x8000
    for (let i = 0; i < bytes.length; i += CHUNK) {
      bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK))
    }
    const data = btoa(bin)
    if (data.length <= MAX_TEXTURE_B64) {
      env.customTexture = {
        data,
        mime: tex.fileMime,
        fileName: tex.fileName ?? 'custom',
      }
    }
  }
  return env
}

function saveNow(): void {
  if (saveTimer) {
    clearTimeout(saveTimer)
    saveTimer = null
  }
  writeEnvelope(buildEnvelope())
}

function scheduleSave(): void {
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = setTimeout(saveNow, 400)
}

// ── boot + subscribe ────────────────────────────────────────────────

/**
 * Restore saved settings/practice/texture and start the change
 * subscription. Idempotent; call once from `main.tsx` before render.
 */
export function bootSettingsPersistence(): void {
  if (booted) return
  booted = true

  const env = readEnvelope()

  // Settings: merge onto defaults BEFORE the first render so every
  // consumer (Inspector rows, Layout engine sync, viewport) starts from
  // the restored state.
  if (env?.settings) {
    const merged = mergeSettings(env.settings)
    // The cache policy module reads its own key at import time — keep
    // the Settings field authoritative when present.
    if (merged.sampleCacheMode !== getSampleCacheMode()) {
      setSampleCacheMode(merged.sampleCacheMode)
    }
    useStore.setState({ settings: merged })
  }

  if (env?.practice) {
    const p = env.practice
    const cur = usePractice.getState()
    usePractice.setState({
      mode:
        p.mode === 'wait' || p.mode === 'rhythm' || p.mode === 'off'
          ? p.mode
          : cur.mode,
      scoringOffsetMs:
        typeof p.scoringOffsetMs === 'number'
          ? p.scoringOffsetMs
          : cur.scoringOffsetMs,
      waitAutoAdvanceMs:
        typeof p.waitAutoAdvanceMs === 'number'
          ? p.waitAutoAdvanceMs
          : cur.waitAutoAdvanceMs,
      calibration: {
        status: typeof p.calibrationResultMs === 'number' ? 'done' : 'idle',
        beat: 0,
        resultMs:
          typeof p.calibrationResultMs === 'number'
            ? p.calibrationResultMs
            : null,
      },
    })
  }

  if (env?.customTexture?.data) {
    try {
      const bin = atob(env.customTexture.data)
      const bytes = new Uint8Array(bin.length)
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
      // setFromBytes is the project-load entry point (no dirty mark).
      void useCustomTexture
        .getState()
        .setFromBytes(
          bytes.buffer,
          env.customTexture.mime,
          env.customTexture.fileName,
        )
    } catch {
      /* corrupt texture payload — skip it */
    }
  }

  // Persist on change. zustand's subscribe gets (state, prevState).
  useStore.subscribe((state, prev) => {
    if (state.settings !== prev.settings) scheduleSave()
  })
  usePractice.subscribe((state, prev) => {
    if (
      state.mode !== prev.mode ||
      state.scoringOffsetMs !== prev.scoringOffsetMs ||
      state.waitAutoAdvanceMs !== prev.waitAutoAdvanceMs ||
      state.calibration.resultMs !== prev.calibration.resultMs
    ) {
      scheduleSave()
    }
  })
  // Custom texture swaps re-decode async — subscribe to the store
  // fields, and also flush on pagehide below.
  useCustomTexture.subscribe((state, prev) => {
    if (
      state.fileBytes !== prev.fileBytes ||
      state.fileMime !== prev.fileMime
    ) {
      scheduleSave()
    }
  })

  // Flush pending writes when the tab goes away (debounce would lose
  // the last slider drag on a fast close).
  if (typeof window !== 'undefined') {
    window.addEventListener('pagehide', saveNow)
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') saveNow()
    })
  }
}

// ── UI actions (Inspector "Dữ liệu" section) ────────────────────────

/** Download everything that persists as a JSON file. */
export function exportSettingsFile(): void {
  const blob = new Blob([JSON.stringify(buildEnvelope(), null, 2)], {
    type: 'application/json',
  })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'notefall-settings.json'
  a.click()
  URL.revokeObjectURL(url)
}

/**
 * Import a previously exported file. Lenient: any subset of the
 * envelope is accepted; unknown fields drop. Returns false when the
 * file isn't a settings envelope at all.
 */
export async function importSettingsFile(file: File): Promise<boolean> {
  let parsed: PersistShape
  try {
    parsed = JSON.parse(await file.text()) as PersistShape
  } catch {
    return false
  }
  if (!parsed || typeof parsed !== 'object' || typeof parsed.v !== 'number') {
    return false
  }
  if (parsed.settings) {
    const merged = mergeSettings(parsed.settings)
    if (merged.sampleCacheMode !== getSampleCacheMode()) {
      setSampleCacheMode(merged.sampleCacheMode)
    }
    // updateSettings merges the patch, marks the document dirty and
    // drives the Layout engine-sync subscription (same path the
    // Inspector controls use).
    useStore.getState().updateSettings(merged)
  }
  if (parsed.practice) {
    usePractice.setState({
      mode:
        parsed.practice.mode === 'wait' ||
        parsed.practice.mode === 'rhythm' ||
        parsed.practice.mode === 'off'
          ? parsed.practice.mode
          : usePractice.getState().mode,
    })
    if (typeof parsed.practice.scoringOffsetMs === 'number') {
      usePractice.setState({ scoringOffsetMs: parsed.practice.scoringOffsetMs })
    }
    if (typeof parsed.practice.waitAutoAdvanceMs === 'number') {
      usePractice.setState({
        waitAutoAdvanceMs: parsed.practice.waitAutoAdvanceMs,
      })
    }
    if (typeof parsed.practice.calibrationResultMs === 'number') {
      usePractice.setState({
        calibration: {
          status: 'done',
          beat: 0,
          resultMs: parsed.practice.calibrationResultMs,
        },
      })
    }
  }
  if (parsed.customTexture?.data) {
    try {
      const bin = atob(parsed.customTexture.data)
      const bytes = new Uint8Array(bin.length)
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
      await useCustomTexture
        .getState()
        .setFromBytes(
          bytes.buffer,
          parsed.customTexture.mime,
          parsed.customTexture.fileName,
        )
    } catch {
      /* skip bad texture */
    }
  }
  saveNow()
  return true
}

/** Reset every persisted preference to the built-in defaults. */
export function resetAllSettings(): void {
  useStore.getState().updateSettings({ ...defaultSettings })
  usePractice.setState({
    mode: 'off',
    scoringOffsetMs: 0,
    waitAutoAdvanceMs: 0,
    calibration: { status: 'idle', beat: 0, resultMs: null },
  })
  useCustomTexture.getState().clearFromLoad()
  if (getSampleCacheMode() !== 'off') setSampleCacheMode('off')
  saveNow()
}
