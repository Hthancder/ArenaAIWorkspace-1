# 44 — Hợp đồng dữ liệu & kiến trúc module

> Chép các type dưới đây vào `src/types/` **gần như nguyên văn**. Mọi module khác phải dùng đúng các type này. Nếu cần thêm trường → thêm optional, không đổi tên trường cũ.

## 44.1. Cây thư mục chuẩn

```
src/
├── main.tsx
├── App.tsx
├── app/
│   ├── routes.tsx          # player | editor | practice (không dùng router nặng)
│   └── providers.tsx
├── types/
│   ├── midi.ts             # 44.2
│   ├── settings.ts         # 44.3
│   ├── project.ts          # 44.4
│   └── errors.ts           # 44.7
├── midi/
│   ├── parse.ts            # MIDI file -> ParsedSong
│   ├── write.ts            # ParsedSong -> MIDI file
│   ├── edit.ts             # 37: commands
│   ├── tempo.ts            # tick <-> second
│   └── limits.ts           # 27.2
├── audio/
│   ├── engine.ts           # 44.5
│   ├── clock.ts            # đồng hồ có thể mock
│   ├── sampler.ts          # tải + decode theo tầng
│   ├── pedal.ts
│   ├── scheduler.ts
│   └── exportAudio.ts      # OfflineAudioContext
├── timeline/
│   ├── speedMap.ts
│   └── keyframes.ts
├── practice/
│   ├── scoring.ts          # 16.3
│   ├── waitMode.ts
│   └── session.ts
├── render/
│   ├── Scene.tsx
│   ├── Keyboard.tsx
│   ├── FallingNotes.tsx
│   ├── Background.tsx
│   └── materials.ts
├── ui/
│   ├── kit/                # 43.7: Button, Slider, Panel...
│   ├── islands/
│   ├── panels/             # Customize, Timeline
│   ├── screens/            # 42: S0..S11
│   └── tokens.css          # sinh từ spec/design-tokens.json
├── store/
│   ├── song.ts             # ParsedSong + undo
│   ├── playback.ts         # vị trí, đang phát
│   ├── settings.ts
│   └── ui.ts
├── project/
│   ├── save.ts             # .nfz
│   ├── load.ts
│   └── migrate.ts
├── i18n/
│   ├── vi.ts
│   └── en.ts
└── workers/
    ├── midi.worker.ts
    └── transcribe.worker.ts
```

**Luật phụ thuộc (kiểm bằng ESLint `import/no-restricted-paths`):**
`ui` → `store` → `midi/audio/practice` → `types`. **Không** module nào import ngược lên `ui`. `render` chỉ đọc từ `store`/`song`, không gọi `audio` trực tiếp.

## 44.2. `types/midi.ts`

```ts
export type Seconds = number
export type Ticks = number
export type BPM = number

export interface TempoEvent { tick: Ticks; bpm: BPM }
export interface TimeSignature { tick: Ticks; numerator: number; denominator: number }

export interface NoteEvent {
  id: string             // uuid ổn định
  track: number          // index trong parsed.tracks
  channel: number        // 0..15, ch10 (index 9) = trống
  pitch: number          // 0..127
  startTick: Ticks
  durationTicks: Ticks   // > 0
  velocity: number       // 1..127
  hand?: 'L' | 'R'
  finger?: 1 | 2 | 3 | 4 | 5
  color?: string         // null/undefined = theo quy tắc settings
}

export interface PedalEvent {
  id: string
  track: number
  channel: number
  tick: Ticks
  value: number          // 0..127 (CC64)
}

export interface TrackInfo {
  index: number
  name: string
  channel: number
  noteCount: number
  isDrum: boolean
  instrument?: number    // GM program 0..127
}

export interface ParsedSong {
  id: string
  name: string
  ppq: number                    // ticks per quarter, thường 480/960
  durationTicks: Ticks
  durationSeconds: Seconds       // dẫn xuất
  tempos: TempoEvent[]           // luôn có ít nhất 1, tick 0
  timeSignatures: TimeSignature[]
  notes: NoteEvent[]             // đã sắp theo (startTick, pitch)
  pedals: PedalEvent[]
  tracks: TrackInfo[]
  source: { kind: 'midi' | 'musicxml' | 'recorded' | 'transcribed'; fileName?: string }
  warnings: ParseWarning[]
}

export interface ParseWarning {
  code: 'NOTE_LIMIT' | 'DURATION_LIMIT' | 'MISSING_TEMPO' | 'ORPHAN_NOTE_OFF'
      | 'OVERLAP_MERGED' | 'UNKNOWN_META' | 'DRUM_CHANNEL'
  message: string
  count?: number
}
```

**Hàm tempo (bắt buộc có, thuần, có test):**
```ts
export function tickToSeconds(song: ParsedSong, tick: Ticks): Seconds
export function secondsToTick(song: ParsedSong, s: Seconds): Ticks
// bất biến: |secondsToTick(tickToSeconds(t)) - t| <= 1 tick
```

## 44.3. `types/settings.ts`

```ts
export type NoteColorMode = 'hands' | 'pitchClass' | 'track' | 'single' | 'random'
export type FallDirection = 'down' | 'up'
export type NoteShape = 'gem' | 'round' | 'angled' | 'bar'
export type NoteNameSystem = 'letter' | 'solfeggio' | 'movableDo'
export type KeyboardRange = 25 | 49 | 61 | 76 | 88

export interface Settings {
  version: 1

  keyboard: {
    range: KeyboardRange
    keyWidthScale: number          // 0.6..1.4, default 1
    whiteKeyColor: string
    blackKeyColor: string
    woodColor: string
    brightness: number             // 0..2
    octaveLines: boolean
    glow: { enabled: boolean; followNoteColor: boolean; color: string; intensity: number; decayMs: number }
    labels: {
      enabled: boolean; mode: 'all' | 'cOnly'; system: NoteNameSystem
      accidentals: 'sharp' | 'flat'; size: number; opacity: number; offsetY: number
    }
  }

  notes: {
    enabled: boolean
    direction: FallDirection
    fallDurationSec: number        // 0.8..6, default 2.5
    widthScale: number
    minLengthSec: number
    cornerRadius: number
    shape: NoteShape
    fadeNearHitLine: boolean
    gapBetweenSameKey: number
  }

  colors: {
    mode: NoteColorMode
    single: string
    left: string
    right: string
    palette12: string[]            // 12 màu chroma
    brightness: number
    randomSeed: number
  }

  camera: {
    fov: number                    // default 32
    distance: number               // default 12
    tiltDeg: number
    follow: boolean
    shakeOnHit: boolean
    keyboardScreenY: number        // default -2.0 (world units)
  }

  scene: {
    background: { kind: 'solid' | 'gradient' | 'image' | 'video'; value: string; dim: number }
    vignette: number
    bloom: { enabled: boolean; strength: number; radius: number }
    particles: { enabled: boolean; count: number; speed: number }
    bloomEnabledByTier?: boolean   // ghi đè theo cấp đồ hoạ
  }

  audio: {
    masterVolume: number           // 0..1
    velocityCurve: 'linear' | 'soft' | 'hard' | 'custom'
    velocityCurvePoints: [number, number][]
    sampleSet: 'full' | 'lite'
    maxVoices: number              // 64..128
    releaseSamples: boolean
    pedalNoise: boolean
    reverb: { preset: 'off' | 'room' | 'hall' | 'studio' | 'custom'; mix: number; decaySec: number }
    limiter: boolean
    latencyOffsetMs: number        // từ calibrate
  }

  practice: {
    waitMode: boolean
    speed: number                  // 0.25..2
    countInBars: 0 | 1 | 2
    metronome: { enabled: boolean; volume: number; accent: boolean }
    scoring: { enabled: boolean; strictness: 'easy' | 'normal' | 'strict' }
    hideFallingNotes: boolean      // chống phụ thuộc
  }

  ui: {
    locale: 'vi' | 'en'
    reducedMotion: boolean
    showFps: boolean
    graphicsTier: 'auto' | 'high' | 'medium' | 'low' | 'battery'
    chromeAutoHideMs: number       // default 2000
  }
}
```

## 44.4. `types/project.ts`

```ts
export interface ProjectManifest {
  format: 'nfz'
  formatVersion: 1
  app: 'piano-app'
  appVersion: string
  createdAt: string             // ISO
  updatedAt: string
  title: string
  composer?: string
  songFile: 'song.mid'
  durationSec: number
  trackCount: number
  settings: Partial<Settings>    // chỉ khác default
  keyframes: Keyframe[]          // xem 44.6
  assets: ProjectAsset[]
  takes: TakeRef[]
  generator?: { ua?: string; gpu?: string }
}

export interface ProjectAsset { file: string; type: string; bytes: number }
export interface TakeRef { file: string; createdAt: string; notes: number }
```

## 44.5. `audio/engine.ts` — API công khai (không lộ chi tiết nội bộ)

```ts
export interface AudioEngine {
  init(opts: { sampleBaseUrl: string; set: 'full' | 'lite' }): Promise<void>
  isReady(): boolean
  readyLayers(): { loaded: number; total: number }

  resume(): Promise<void>           // gọi từ user gesture
  suspend(): void

  play(song: ParsedSong, fromSec?: Seconds): void
  pause(): void
  stop(): void
  seek(sec: Seconds): void

  setSpeed(speed: number): void
  setLoop(a: Seconds | null, b: Seconds | null): void
  setTrackVolume(track: number, v: number): void
  setTrackMute(track: number, muted: boolean): void
  setMasterVolume(v: number): void
  applySettings(s: Settings): void

  triggerKey(pitch: number, velocity: number, source: 'user' | 'midi' | 'onscreen'): void
  releaseKey(pitch: number, source: 'user' | 'midi' | 'onscreen'): void
  panic(): void

  addKeyListener(cb: (e: { pitch: number; velocity: number; on: boolean; source: string; atSec: Seconds }) => void): () => void
  addTickListener(cb: (t: Seconds) => void): () => void     // gọi mỗi frame, không phải mỗi nốt
  currentTime(): Seconds
  isPlaying(): boolean
  latencyMs(): number
}
```

**Bất biến:**
- `play` sau `stop` phải reset pedal về 0.
- `seek` khi đang phát: mọi nốt đang kêu bị tắt trong ≤ 20 ms.
- `panic` tắt **tất cả**, kể cả nốt do người dùng giữ.
- Không bao giờ ném lỗi ra ngoài; lỗi → `engine.lastError` + callback onError.

## 44.6. `timeline/keyframes.ts`

```ts
export interface Keyframe {
  id: string
  timeSec: Seconds
  property: 'speed' | 'masterVolume' | 'cameraDistance' | 'fallDurationSec' | 'bloomStrength'
  value: number
  easing: 'linear' | 'smooth'
}

export function valueAt(kfs: Keyframe[], prop: Keyframe['property'], t: Seconds, fallback: number): number
export function speedAt(kfs: Keyframe[], t: Seconds): number
// speed dùng tích phân (16.2): thời gian bài trôi = ∫ speed dt
```

## 44.7. `types/errors.ts`

```ts
export type AppErrorCode =
  | 'UNSUPPORTED_WEBGL' | 'AUDIO_BLOCKED' | 'SAMPLE_LOAD_FAILED'
  | 'MIDI_PARSE_FAILED' | 'MIDI_TOO_LARGE' | 'PROJECT_CORRUPT'
  | 'PROJECT_VERSION_NEWER' | 'QUOTA_EXCEEDED' | 'STORAGE_EVICTED'
  | 'EXPORT_UNSUPPORTED' | 'NO_VALID_NOTES'

export class AppError extends Error {
  code: AppErrorCode
  detail?: Record<string, unknown>
  userMessageKey: string   // key trong i18n, KHÔNG phải chuỗi tiếng Việt
}
```

## 44.8. Store (4 slice, không nhiều hơn)

| Slice | State | Action chính |
|---|---|---|
| `song` | `ParsedSong \| null`, `undoStack`, `redoStack`, `dirty` | `load`, `applyCommand`, `undo`, `redo`, `markSaved` |
| `playback` | `isPlaying`, `positionSec`, `loop`, `recording`, `speed` | `play`, `pause`, `seek`, `setLoop` |
| `settings` | `Settings` | `set(path, value)`, `reset(key?)`, `applyPreset` |
| `ui` | `activePanel`, `activeDialog`, `selection: string[]`, `toasts`, `banner` | `open`, `close`, `select`, `toast` |

**Luật:** `positionSec` cập nhật **tối đa 30 Hz** và **không** gây re-render component nặng (dùng subscribe trực tiếp cho HUD). `selection` lưu **id**, không lưu object.

## 44.9. Luồng dữ liệu (một chiều)

```
file.mid ──worker:parse──▶ ParsedSong ──▶ store.song
                                            │
        ┌───────────────────────────────────┼──────────────────────────┐
        ▼                                   ▼                          ▼
   render/FallingNotes               audio/engine.play            ui/Timeline, PianoRoll
   (đọc theo tick→sec)               (schedule theo giây)         (đọc trực tiếp notes)
        ▲                                   │
        └────── clock (một nguồn thời gian) ┘
```

**Quy tắc vàng:** chỉ **một** nguồn thời gian (`audio/clock`). Không component nào tự dùng `performance.now()` để tính vị trí nhạc.

## 44.10. Command (undo/redo) — đặc tả

```ts
export interface Command {
  label: string                    // hiện trong tooltip undo
  do(state: SongState): SongState
  undo(state: SongState): SongState
  coalesceKey?: string             // gộp khi kéo liên tục
}
```
- Stack giới hạn **200**; command chứa **diff** (id + trường), không chứa toàn bộ mảng.
- `coalesceKey` ví dụ `move:${ids.join(',')}` → kéo 1 giây = 1 command.
- Sau `undo`, `selection` giữ nguyên id nếu nốt còn tồn tại.

## 44.11. Worker protocol

```ts
// main -> worker
type Req =
  | { id: number; type: 'parseMidi'; buffer: ArrayBuffer; limits: ParseLimits }
  | { id: number; type: 'transcribe'; audio: Float32Array; sampleRate: number }

// worker -> main
type Res =
  | { id: number; type: 'progress'; done: number; total: number }
  | { id: number; type: 'ok'; payload: ParsedSong }
  | { id: number; type: 'error'; code: AppErrorCode; message: string }
```
- Mọi request có `id`; main giữ map `id → resolve/reject`; timeout 30 s (parse) / 10 phút (transcribe).
- Worker **không** import `three`, **không** chạm DOM.

## 44.12. i18n

```ts
// i18n/vi.ts
export const vi = {
  'app.title': 'Piano',
  's0.openMidi': 'Mở file MIDI',
  's0.tryDemo': 'Thử bài demo',
  's1.play': 'Phát',
  's1.pause': 'Tạm dừng',
  // ... đủ mọi chuỗi trong 42
} as const
export type I18nKey = keyof typeof vi
```
- **Không** nối chuỗi bằng `+`; dùng `t('key', {n})`.
- Số/ngày: `Intl.NumberFormat('vi-VN')`, thời gian `mm:ss.d`.

## 44.13. Bất biến toàn cục (viết test cho từng cái)

1. `notes` luôn sắp theo `(startTick, pitch)`; không có `durationTicks <= 0`.
2. Không 2 nốt cùng `pitch + track` chồng lấn **sau khi chuẩn hoá** (trừ khi người dùng tắt gộp).
3. `durationSeconds === tickToSeconds(durationTicks)` (sai số < 1 ms).
4. Mọi `id` duy nhất trong `notes` và `pedals`.
5. `pedals` sắp theo `tick`; giá trị 0..127.
6. `track` của mọi nốt tồn tại trong `tracks`.
7. Sau `parse → write → parse`: số nốt, pitch, startTick, duration, velocity **bằng nhau**; tempo map bằng nhau.
8. Settings sau `applySettings` phản ánh đúng ngay frame kế tiếp (không cần reload).
