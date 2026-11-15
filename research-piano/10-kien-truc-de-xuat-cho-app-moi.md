# 10 — Kiến trúc đề xuất cho app mới

> Nguyên tắc: **không build from scratch**. Lấy NoteFall làm lõi (visualizer + audio + editor + export), rồi **bọc thêm các lớp còn thiếu**. File này mô tả chính xác lớp nào, đặt ở đâu, nối vào hook nào của NoteFall.

## 10.1. Chiến lược giấy phép (quyết định trước khi code)

| Phương án | Cách làm | Ưu | Nhược |
|---|---|---|---|
| **A. Dùng cá nhân / học tập** | Fork NoteFall, giữ LICENSE, dùng private | Nhanh nhất, đúng yêu cầu "bê y nguyên" | Không được phân phối bản cạnh tranh |
| **B. Xin phép tác giả** | Email/GitHub issue xin license thương mại hoặc ngoại lệ | Có thể công bố hợp pháp | Phụ thuộc phản hồi |
| **C. Viết lại (clean-room)** | Chỉ dùng NoteFall để học kiến trúc, tự viết code | Toàn quyền | Tốn thời gian, mất "đẹp sẵn" |
| **D. Base MIT** | Lấy `RenCheng0525/WebGL-Piano` (MIT) hoặc `worldwiderad/pianoroll` làm nền, port dần phần đẹp của NoteFall bằng cách viết lại | Hợp pháp, vẫn nhanh | Phải tự làm phần shader/3D đẹp — rất nhiều công |
| **E. Hybrid** | NoteFall cho phần *học cá nhân*; khi publish thì thay các module bằng bản tự viết (shader, engine) | Cân bằng | Quản lý 2 nhánh phức tạp |

**Đề xuất:** Giai đoạn 1 dùng **A** (đúng yêu cầu hiện tại, tốc độ cao nhất). Trước khi publish, chuyển sang **B** hoặc **D/E**. Ghi rõ trong README: "Dựa trên NoteFall của ekkx — PolyForm Shield 1.0.0".

## 10.2. Kiến trúc tổng thể

```
┌──────────────────────────────────────────────────────────────┐
│  UI shell (react-aria + Tailwind + tokens)                    │
│  Toolbar · Inspector(schema-driven) · Timeline · Dialogs      │
├──────────────────────────────────────────────────────────────┤
│  Feature layers (mới)                                         │
│  practice/   wait mode · scoring · report · exercises         │
│  notation/   MusicXML (OSMD) · sheet-from-MIDI (VexFlow)      │
│  sound/      instruments · soundfont · presets · EQ/effects   │
│  library/    songs · takes · presets · recent · flags         │
│  input/      pc-keymap(remap) · midi-devices · bluetooth warn │
│  learn/      chords · scales · finger hints · difficulty      │
├──────────────────────────────────────────────────────────────┤
│  Core (giữ nguyên từ NoteFall)                                │
│  audio/engine (scheduler, pedal, live)                        │
│  midi/parse|serialize|edit                                    │
│  notes/ keyboard/ scene/ (R3F + shaders)                      │
│  export/ (offline audio + video, codecs, muxer)               │
│  projects/ (.nfz zip, FSA)                                    │
│  store.ts (zustand)                                           │
└──────────────────────────────────────────────────────────────┘
```

## 10.3. Điểm nối (hook) có sẵn trong NoteFall — dùng để thêm tính năng

| Cần làm | Hook trong NoteFall | Cách nối |
|---|---|---|
| **Wait Mode** | `audioEngine.addKeyListener()` (sự kiện `on/off` có `songTime`, `track`, `id`), `audioEngine.pause()`, `audioEngine.seek(tlAudio)`, `audioEngine.triggerKey()` | Khi `transport=playing` và mode=wait: mỗi lần engine định phát note ở hit line → pause engine, chờ `addLiveListener` báo đúng pitch → `seek(songTime của note kế)` + resume. Chord: chờ đủ tập pitch trong cửa sổ ±50ms. |
| **Chấm điểm** | `addLiveListener` (input người chơi) + `addKeyListener` (note đúng) + `currentSongTime()` | So khớp theo cửa sổ thời gian (mặc định ±120ms), tính accuracy/timing/length, ghi vào `practice/session.ts`. |
| **Sheet music** | `addKeyListener` / `currentSongTime()` | OSMD cursor seek theo `songTime`; map note index → MusicXML note id khi import. |
| **Finger hints** | `NoteEvent.finger` (đã có) | Sinh tự động bằng DP khi import; ghi vào `noteHands` sidecar (đã có cơ chế). |
| **Auto hand split** | `NoteEvent.track`, `NoteEvent.midi` | Chia theo pitch threshold (mặc định C4/60) + track; cho phép sửa tay trong selection card (đã có). |
| **Transpose** | `settings.transpose` (đã có) | Đã hoạt động; thêm UI đổi key có tên (C, D…) + hiển thị. |
| **Loop A-B** | `audioEngine.setLoop`, `setMidiTrim` | Thêm `loopStartSec/loopEndSec` vào settings, sửa `computeExportTimeline` để render đúng vùng loop. |
| **SoundFont / multi-instrument** | `audio/engine.ts` (`PianoInstrument` interface), `audio/sampler.ts` | Thêm `SoundFontInstrument` implement cùng interface (noteOn/noteOff/setVolume/pedal), chọn theo instrument id. |
| **Chord detection** | `addKeyListener` + `getLiveNotes()` | Tập pitch đang giữ → so với bảng hợp âm (12 root × 12 quality × inversion). |
| **Scale highlight** | `keyboard/Keyboard.tsx` (uniform màu phím) | Thêm uniform `uDimmed` per key theo scale. |
| **Preset JSON** | `Settings` object | Serialize subset `pickAnimatable` + toàn bộ look/sound; import thì merge lenient. |
| **Remap phím tắt / PC keyboard** | `keyboard/pcInput.ts` (mapping cố định), `useGlobalShortcuts` | Đưa mapping vào settings (`pcKeymap: Record<code, semitone>`), preset QWERTY/AZERTY/Dvorak. |
| **Vertical export (9:16)** | `export/timeline.ts`, `renderVideo.ts` (width/height), `scene/cameraLimits.ts` | Thêm `aspect` setting; tính lại `viewTopScale` cho camera; render video theo aspect. |
| **Camera preset** | `cameraPos/cameraLookAt/cameraFov` | Preset là 1 bộ 3 giá trị + có thể gắn vào keyframe. |
| **Metronome đầy đủ** | `audio/click.ts` (count-in) | Mở rộng thành scheduler click theo BPM/time signature, accent. |
| **MIDI output / lighted keyboard** | `audio/midiInput.ts` (chỉ input) | Thêm `midiOutput.ts`: `access.outputs`, gửi note sắp tới. |
| **Mic detection** | — | Module mới `audio/mic/`: AudioWorklet + pitch/onset; so với expectation từ practice layer. |

## 10.4. Mô hình dữ liệu mở rộng

Giữ `ParsedSong` của NoteFall, thêm các trường **optional** (tương thích ngược với `.nfz` cũ):

```ts
type SongExt = ParsedSong & {
  meta?: { title?, composer?, key?, timeSignature?, bpm? }
  tracksMeta?: Array<{ instrument?: number; muted?: boolean; volume?: number; pan?: number }>
  loop?: { startSec: number; endSec: number; enabled: boolean; count?: number }
  markers?: Array<{ timeSec: number; name: string; color?: string }>
  notation?: { musicXmlRef?: string; sourceRef?: string }  // asset trong .nfz
  fingering?: { auto: boolean; source: 'dp' | 'user' | 'musicxml' }
}
```

`PracticeSession` (mới, lưu local IndexedDB, không cần trong project):
```ts
type PracticeSession = {
  id: string; songHash: string; startedAt: number; mode: 'wait'|'rhythm'|'recital'|'free'
  hand: 'L'|'R'|'both'; range?: { startSec: number; endSec: number }
  score: { notes: number; timing: number; length: number; total: number }
  errors: Array<{ songTime: number; midi: number; kind: 'miss'|'wrong'|'late'|'early' }>
  perBar: Array<{ bar: number; accuracy: number }>
}
```

`.nfz` mở rộng (giữ tương thích):
```
project.nfz
├ manifest.json      (settings, noteHands, loop, markers, fingering meta)
└ assets/
   ├ song.mid
   ├ score.musicxml   (nếu có)
   ├ note-texture.png
   ├ background.mp4   (nếu có, P2)
   └ audio.mp3        (accompaniment)
```

## 10.5. Inspector schema-driven (để "tùy chỉnh hầu hết thông số")

Hiện NoteFall viết UI tay trong `ui/Inspector.tsx` + `ui/controls.tsx`. Để mở rộng lên 400+ thông số mà không phình code:

```ts
type SettingDef =
  | { key: string; kind: 'number'; min: number; max: number; step: number; unit?: string; tab: Tab; section: string; label: string; detail?: boolean; animatable?: boolean }
  | { key: string; kind: 'color'; tab: Tab; section: string; label: string }
  | { key: string; kind: 'boolean'; tab: Tab; section: string; label: string; enabledKey?: string }
  | { key: string; kind: 'select'; options: Array<{value:string;label:string}>; ... }
  | { key: string; kind: 'curve'; ... }  // velocity curve, EQ
  | { key: string; kind: 'vector3'; ... }

const SETTINGS_SCHEMA: SettingDef[] = [ /* ~400 dòng khai báo */ ]
```

- Render tự động: `<SchemaInspector schema={SETTINGS_SCHEMA} />` dùng lại component kit của NoteFall.
- Search tự có (đã có ở Inspector).
- "Advanced mode" hiện cả key kỹ thuật + giá trị thô.
- Keyframe: `isAnimatableKey` sinh từ schema (`animatable: true`).

→ Thêm 1 thông số = thêm 1 dòng schema + 1 default, không sửa UI.

## 10.6. Cấu trúc thư mục app mới (dự kiến)

```
src/
├ app/            khởi tạo, routing màn hình (Play / Practice / Edit / Export / Settings)
├ core/           (từ NoteFall) audio/, midi/, notes/, keyboard/, scene/, export/, projects/
├ practice/       waitMode.ts, scoring.ts, session.ts, report.ts, exercises.ts
├ notation/       musicxml.ts (OSMD), sheetFromMidi.ts (VexFlow), cursor.ts
├ sound/          instruments.ts, soundfont.ts, presets.ts, effects.ts
├ learn/          chords.ts, scales.ts, fingering.ts, difficulty.ts
├ library/        songs.ts, takes.ts, presets.ts, recent.ts, flags.ts
├ input/          keymap.ts (remap), midiDevices.ts, midiOutput.ts, mic/
├ ui/             shell/, kit/, inspector/(schema-driven), timeline/, dialogs/
├ i18n/           vi, en, ja
└ store/         settings.ts, song.ts, transport.ts, practice.ts, library.ts
```

## 10.7. Thứ tự build kỹ thuật (theo phụ thuộc)

1. **Fork + chạy được** NoteFall local, `npm install && npm run dev`, thay branding, thêm tiếng Việt.
2. **Sample hosting**: NoteFall tải Salamander từ R2 CDN của tác giả → phải **tự host** (`scripts/fetch-salamander.sh` + `prepare-salamander.mjs` → `public/`). Nếu không, app sẽ phụ thuộc CDN bên ngoài và có thể chết.
3. **Bỏ analytics PostHog / feedback endpoint** (hoặc trỏ về backend của mình) — tránh gửi dữ liệu đến server lạ.
4. **Schema-driven Inspector** (refactor từ Inspector hiện có) → nền cho mọi thông số mới.
5. **Practice layer**: wait mode + scoring (giá trị cao nhất, phụ thuộc ít).
6. **Notation layer**: MusicXML import + OSMD + cursor.
7. **Sound layer**: multi-instrument + SoundFont.
8. **Learn layer**: hợp âm, scale, fingering DP, độ khó.
9. **Input layer**: remap phím, MIDI output, cảnh báo Bluetooth.
10. **Export mở rộng**: aspect ratio, khoảng render, bitrate, MP3.
11. **PWA + tối ưu hiệu năng + mobile layout**.
12. **P2**: mic, audio→MIDI, camera sync, multiplayer.

## 10.8. Rủi ro kỹ thuật & cách giảm

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Sample Salamander phụ thuộc CDN tác giả | Cao | Tự host trong `public/` hoặc R2 riêng; có fallback synth |
| License PolyForm Shield khi publish | Cao | Xem 10.1, chọn B/D/E trước khi công khai |
| Wait Mode làm lệch đồng hồ audio | Trung bình | Pause/seek engine (đã có), không tự đếm bằng setTimeout |
| Scoring sai do latency | Trung bình | Offset bù latency đo được; cửa sổ ±120ms; calibrate wizard |
| MusicXML ↔ MIDI mapping sai note | Trung bình | Import MusicXML làm nguồn chính (không convert MIDI→XML), giữ id |
| SoundFont nặng (vài trăm MB) | Trung bình | Chỉ load instrument đang dùng, cache, stream |
| Refactor Inspector làm hỏng keyframe | Trung bình | Giữ `isAnimatableKey`, test hồi quy bằng project demo |
| Export 4K chậm / hết RAM | Trung bình | Giới hạn resolution theo GPU, render theo đoạn rồi ghép |
| React 18 + R3F 8 cũ, nâng cấp gây vỡ | Thấp | Không nâng cấp major trong giai đoạn 1 |
| Người dùng không có Web MIDI (Safari) | Trung bình | Fallback PC keyboard + mouse velocity + hướng dẫn dùng Chrome |
