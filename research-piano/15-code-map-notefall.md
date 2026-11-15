# 15 — Code map NoteFall (bản đồ source để fork và mở rộng)

> Đọc trực tiếp từ bản clone `ekkx/notefall` (2026-11-14). Số liệu: **~39.600 dòng TS/TSX** trong `src/` (201 file), 7.6 MB (gồm 2 demo `.nfz`, ảnh, wasm hands).
> Mục đích: khi bắt đầu build, biết **file nào làm gì, sửa ở đâu, thêm gì vào đâu** — không phải đọc lại 40k dòng.

## 15.1. File lớn nhất (ưu tiên hiểu trước)

| File | Dòng | Vai trò |
|---|---|---|
| `src/ui/Timeline.tsx` | 2.650 | Timeline editor: lane MIDI/speed/audio, kéo trim, pins keyframe — file phức tạp nhất |
| `src/store.ts` | 2.026 | Toàn bộ state + `Settings` (~300 key) + undo/redo + dirty hash |
| `src/notes/FallingNotes.tsx` | 1.816 | Render nốt rơi (InstancedMesh + shader), animate theo clock |
| `src/ui/Inspector.tsx` | 1.603 | Panel Customize 5 tab + search |
| `src/ui/controls.tsx` | 1.429 | Component điều khiển dùng lại (slider, color, bound row) |
| `src/audio/engine.ts` | 1.376 | AudioEngine: scheduler, pedal, live input, transport |
| `src/keyboard/geometry.ts` | 974 | Hình học 3D phím (bo góc, chamfer) |
| `src/keyboard/Keyboard.tsx` | 918 | Bàn phím 3D + hit test chuột/touch |
| `src/notes/noteShader.ts` | 849 | Fragment shader vật liệu nốt (bevel, pattern, frost…) |
| `src/hands/meshHand.ts` | 761 | Tay ảo (mesh + motion) |
| `src/notes/HitParticles.tsx` | 675 | Particle system |
| `src/midi/settingsKeyframes.ts` | 568 | Keyframe settings + nội suy |
| `src/scene/Scene.tsx` | 632 | Dựng scene R3F, đồng bộ camera |

## 15.2. Bản đồ module (theo thư mục)

### `src/midi/` — dữ liệu nhạc
| File | Export chính | Ghi chú |
|---|---|---|
| `parse.ts` | `parseMidi(file: ArrayBuffer, name): Promise<ParsedSong>` | Dùng `@tonejs/midi`; 56 dòng → phần nặng nằm trong `@tonejs/midi` + helper resolve overlap |
| `serialize.ts` | `serializeMidi(song, opts): ArrayBuffer` | Ghi lại SMF (tempo, pedal, control) |
| `edit.ts` | `nextNoteId`, `computeDuration`, `resolveOverlaps`, `deleteNotes`, `moveNotes`, `setNotesHand`, `setNotesFinger`, `setNotesVelocity`, `addNote`, `splitNote` | Mọi thao tác sửa nốt là **hàm thuần** trả `ParsedSong` mới → dễ test |
| `types.ts` | `NoteEvent`, `PedalEvent`, `ControlEvent`, `TrackInfo`, `ParsedSong`, `KEPT_CONTROLS=[66,67]` | Model chuẩn; `hand`/`finger` optional (không có trong SMF) |
| `noteHands.ts` | sidecar hand/finger ↔ manifest | Map lại theo pitch + thời gian ≤10 ms |
| `speedMap.ts` | `SpeedPoint`, map thời gian | Tích phân nghịch đảo cho speed automation |
| `settingsKeyframes.ts` | `SettingsKeyframe`, `pickAnimatable`, `resolveSettingsAt`, `isAnimatableKey` | Nền cho mọi thông số "đổi theo thời gian" |
| `noteName.ts` | `PitchLabelFormat`, `Accidental`, format tên nốt | letter / solfège / scale degree |

### `src/audio/` — âm thanh
| File | Vai trò |
|---|---|
`engine.ts` | `AudioEngine` singleton. Public: `init`, `play`, `pause`, `stop`, `seek(tlAudio)`, `isPlaying`, `currentSongTime/currentMidiTime/currentDisplayTime`, `loadSong/updateSong/unloadSong`, `triggerKey(midi,vel)`, `triggerPreview`, `addKeyListener`, `addLiveListener`, `setLoop`, `setRate`, `setPedalEnabled`, `setLivePedal`, `setLiveControl`, `setMidiOffset/Trim`, `setUserAudio(+Offset/Trim/Volume)`, `setSpeedAutomation`, `setReverb*`, `setEqBand`, `setVelocityCurve`, `setTranspose`, `tick()`, `beginExportPlayback/endExportPlayback`
`clock.ts` | `Clock` interface + `now()` + `setActiveClock` + `clockEpoch()` — đổi wall-clock ↔ virtual clock khi export
`sampler.ts` | `createPiano` (smplr + Salamander), `PianoInstrument` interface (`start/stopAll/setVolume/…`)
`salamanderDescriptor.ts` | Map note→file URL, 30 key × 16 layer, velocity compensation
`sampleCache.ts` | Cache Storage (~77 MB tải 1 lần)
`pedalDepth.ts` | CC64 0..1 → damper lift (≤0.15 = không nhấc, ≥0.85 = nhấc hoàn toàn)
`smoothRelease.ts` | Patch `AudioParam.linearRampToValueAtTime` → release dạng exponential (tránh click)
`velocityCurve.ts` | `VelocityCurve`, `DEFAULT_VELOCITY_CURVE`
`recorder.ts` | `RecorderManager` (singleton) + `Recording`; hydrate từ IndexedDB
`recordControl.ts` | `toggleRecord()` dùng chung toolbar + Shift+R; snapshot trước khi ghi
`click.ts` | Metronome count-in (sine, 100 BPM, 4 nhịp)
`midiInput.ts` / `useMidiInput.ts` | Web MIDI: `parseMidiMessage`, `connectMidi`, thiết bị, pedal
`useRecorder.ts`, `userAudio.ts`, `preview.ts`, `recordingStore.ts`, `useCurrentTime.ts` | hook/tiện ích

### `src/keyboard/` — bàn phím
| File | Vai trò |
|---|---|
`layout.ts` | Hằng số chuẩn: `MIDI_MIN=21`, `MIDI_MAX=108`, `KEY_COUNT=88`, `WHITE_KEY_WIDTH=0.235`, `WHITE_KEY_LENGTH=1.475`, `BLACK_KEY_WIDTH=0.137`, `BLACK_KEY_LENGTH=0.95`, `KEYBOARD_Y=-2.0`, `keyForMidi`, `adjacentBlackKeys`
`geometry.ts` | Tạo geometry 3D phím trắng bo góc + phím đen chamfer có lõi đặc
`Keyboard.tsx` | Hit test raycast → `triggerKey`; glow phím; render
`pcInput.ts` | Mapping phím máy tính → midi (**cố định** — cần sửa để remap)
`whiteKeyShader.ts` | Shader phím trắng
`flashLights.ts`, `retriggerDip.ts` | Hiệu ứng đèn/chìm phím

### `src/notes/` — nốt rơi
| File | Vai trò |
|---|---|
`FallingNotes.tsx` | InstancedMesh + shader; đọc `currentSongTime`, tính vị trí theo `fallDurationSec`
`positions.ts` | `NOTE_PLANE_Z=0.1`, `frustumTop/Bottom`, `fallDistance`, `clickYToTime`, `clickXToMidi`, `timeToHeadY`, `midiToX`, `noteVisualBounds`
`noteShader.ts` | Fragment shader: bevel, rim, pattern, cloud, frost, outline, merge…
`noteColor.ts` | `NoteColorMode`, `NOTE_COLOR_DEFAULTS`, `HIT_LINE_COLOR_DEFAULTS`, random palette
`looks/` | Preset vật liệu: `realistic.ts`, `caustics.ts`, `crystalLight/Normal`, `gemFacets`, `hammeredNormal`, `lightsPattern`, `merge`, `noteLook`, `noteLookResources`
`HitLine.tsx`, `HitParticles.tsx`, `LandingFlashes.tsx`, `noteDeathFx.ts`, `particleSim.ts` | Hiệu ứng
`pitchLabels.ts`, `customTexture.ts`, `curlNoise/curlLattice` | Nhãn + texture

### `src/scene/`, `src/projects/`, `src/export/`, `src/ui/`
| Nhóm | File chính | Vai trò |
|---|---|---|
Scene | `Scene.tsx`, `CameraControls.tsx`, `EditTools.tsx`, `automatedSettings.ts`, `exportBridge.ts`, `cameraLimits.ts`, `visibleTop.ts` (`applyViewShift`), `stageBackground.ts` | Dựng scene, camera, chỉnh sửa khi pause, cầu nối cho export offline |
Projects | `io.ts` (`pack`, `unpack`, `showOpen`, `showSaveAs`, `hasFileSystemAccess`), `actions.ts`, `recent.ts`, `types.ts` | `.nfz` zip + FSA + recent 8 file |
Export | `timeline.ts` (`computeExportTimeline`, `TAIL_SECONDS=5`), `renderAudio.ts`, `renderVideo.ts`, `exportAudio/Video.ts`, `codec/{codecs,video,audio,muxer,preflight}.ts`, `synth/{piano,schedule}.ts`, `sceneExportMode.ts` | Render offline frame-by-frame + encode/mux |
UI | `Layout.tsx`, `Toolbar.tsx`, `Inspector.tsx`, `controls.tsx`, `Timeline.tsx`, `TimelineEditor.tsx`, `SelectionCard.tsx`, `ExportSettingsDialog.tsx`, `VelocityCurveEditor.tsx`, `SettingsPinLane.tsx`, `kit/`, `shell/` | Toàn bộ chrome |

## 15.3. Luồng dữ liệu (data flow)

```
[File .mid] ──parseMidi()──► ParsedSong ──► store.song
                                              │
        ┌─────────────────────────────────────┼──────────────────────────────┐
        ▼                                     ▼                              ▼
  audioEngine.loadSong(song)          FallingNotes (mỗi frame)        Timeline (lanes)
  scheduler theo clock.now()          đọc currentSongTime()            trim/pins/speed
        │                                     │
        ▼                                     ▼
  smplr (Salamander)                  keyboard glow / particles
        │
        ▼
  master gain → reverb → destination

[Settings] ──(Layout useEffect)──► từng setter của audioEngine + uniforms của shader
[Live input: MIDI/PC/chuột] ──► engine.triggerKey() ──► addLiveListener ──► recorder
                                                        └► addKeyListener ──► visuals
[Export] ──► setActiveClock(VirtualClock) ──► renderVideo: từng frame → encoder → muxer
```

**Ba "bus" sự kiện quan trọng nhất khi thêm tính năng:**
1. `addKeyListener` — mọi note **phát ra** (bài + preview) kèm `songTime`, `track`, `id`.
2. `addLiveListener` — mọi note **người dùng bấm** kèm `time` (bao gồm pedal + control).
3. `currentSongTime()` — vị trí hiện tại trong bài (giây).

→ Wait mode, chấm điểm, chord detection, MIDI-out (đèn phím) đều gắn vào 3 điểm này.

## 15.4. Muốn thêm X thì sửa ở đâu

| Tính năng | File cần sửa/thêm |
|---|---|
| Thêm 1 **setting** | `store.ts`: thêm vào `Settings` + `defaultSettings` (+ `RESET_PRESERVED_KEYS` nếu ngoài Inspector) → `Inspector.tsx` thêm row → (nếu animate được) `settingsKeyframes.ts` |
| Thêm **thông số shader** | `noteShader.ts` (uniform) + `FallingNotes.tsx` (truyền uniform) + `noteLook.ts` (preset mặc định) |
| **Remap phím máy tính** | `keyboard/pcInput.ts` (đọc mapping từ settings thay vì hằng số) + `store.ts` (`pcKeymap`) |
| **Loop A–B** | `store.ts` (`loopStartSec/loopEndSec`) + `audio/engine.ts` (`setLoop` đang loop cả bài → đổi thành vùng) + `ui/Timeline.tsx` (2 handle) + `export/timeline.ts` (render đúng vùng) |
| **Wait mode** | module mới `practice/waitMode.ts`; nối `addKeyListener` + `addLiveListener` + `engine.pause()/seek()`; UI ở `TransportPill` |
| **Chấm điểm** | `practice/scoring.ts`; UI overlay mới; lưu IndexedDB |
| **Sheet music** | module `notation/osmd.ts`; layout mới trong `Layout.tsx`; cursor theo `currentSongTime()` |
| **SoundFont / đa instrument** | `audio/sampler.ts` (thêm implementation `PianoInstrument` khác) + `audio/engine.ts` (chọn instrument) + per-track program change |
| **Metronome đầy đủ** | `audio/click.ts` → scheduler riêng theo BPM/time signature |
| **MIDI output / đèn phím** | module mới `audio/midiOutput.ts` (`access.outputs`) + gọi từ `practice/waitMode.ts` |
| **Aspect 9:16** | `export/codec/video.ts` (width/height) + `scene/visibleTop.ts` + `cameraLimits.ts` + dialog |
| **Preset JSON** | `projects/types.ts` + module `library/presets.ts` (serialize subset Settings) |
| **i18n tiếng Việt** | `i18n/index.ts` + `i18n/locales/vi/*.json` (copy 7 file từ `en`) |

## 15.5. Hằng số & toạ độ phải nhớ (đừng "sửa" mù)

- Camera `[0,0,12]`, FOV 32°. `KEYBOARD_Y = -2.0`. 88 phím trắng × 0.235 = 12.22 wu = đúng chiều ngang 16:9.
- Hit line `NOTE_HIT_Y = KEYBOARD_Y + WHITE_KEY_LENGTH`.
- Nốt ở `z = 0.1`, clip bằng **SDF per-fragment** (`vWorldY < uHitY`) — **không** đổi z để "cắt" nốt (sẽ lệch parallax với phím).
- `keyboardScreenY` là **lens shift** (`camera.view.offsetY`), không phải di chuyển bàn phím.
- `stopId` phải unique khi gọi `piano.start(...)` — nếu không, note cùng pitch sẽ triệt tiêu nhau.
- `Lookahead 0.015 s`, `stop buffer 0.02 s` trong engine — đừng giảm, sẽ click.

## 15.6. Những chỗ **phải** sửa ngay khi fork (checklist kỹ thuật)

- [ ] `src/audio/sampler.ts`: `SAMPLES_BASE_URL` → CDN của mình (hoặc `/samples/...` self-host). Bản dev đang trỏ `/samples-cdn/*` (proxy tới R2 của tác giả, **CORS chỉ cho notefall.app**).
- [ ] `vite.config.ts`: bỏ proxy `/samples-cdn` nếu self-host.
- [ ] `src/usage/*` + `posthog-js`: bỏ hoặc thay bằng analytics của mình (mặc định nên **tắt**).
- [ ] `functions/api/report.ts` + `VITE_TURNSTILE_SITE_KEY`: bỏ endpoint feedback của tác giả.
- [ ] `index.html`, `public/`, icon, tên app, `i18n` → branding mới.
- [ ] `LICENSE.md` + `Required Notice` → **giữ lại**, thêm ghi công trong README.
- [ ] `scripts/fetch-salamander.sh` yêu cầu **Docker** + `ffmpeg` (cho `prepare-salamander.mjs`); nếu không có Docker → tải tar.bz2 trực tiếp và đổi tên `#`→`s` thủ công (480 file).
- [ ] Kiểm tra `package.json` engines / Node version; `npm ci` với lockfile hiện có.

## 15.7. Rủi ro khi fork (đã kiểm chứng bằng code)

| Rủi ro | Chi tiết | Cách xử lý |
|---|---|---|
| Sample CDN khoá CORS | `samples.notefall.app` chỉ cho origin `notefall.app` | Self-host; bật CORS `*` hoặc domain của mình |
| `tone` nặng 5.3 MB | chỉ dùng để giữ AudioContext | Thay bằng `new AudioContext({latencyHint:'interactive'})` |
| React 18 + R3F 8 | nâng lên R3F 9 cần React 19 | Giữ nguyên giai đoạn 1 |
| `three` 0.169 vs 0.187 | shader tự viết dễ vỡ khi nâng | Pin version |
| `mediabunny` MPL-2.0 | 11.6 MB | Dùng nguyên; hoặc thay `mp4-muxer`/`webm-muxer` (MIT) |
| 2 file demo `.nfz` | chứa nhạc có thể có bản quyền | Kiểm tra trước khi phát hành, thay bằng demo tự làm |
| Hands wasm + data | fetch từ CDN khi bật | Cần self-host nếu muốn offline |
| Test coverage | gần như không có test | Viết test cho `midi/edit.ts`, `speedMap`, `settingsKeyframes` trước khi sửa sâu |

## 15.8. Lệnh build/dev (từ repo)

```bash
npm install
npm run dev        # Vite :5173
npm run typecheck  # tsc -b --noEmit + functions/tsconfig.json
npm run build      # tsc -b && vite build → dist/
npm run fetch-salamander   # Docker: tải ~78 MB OGG → public/samples/salamander-v3-close
npm run prepare-salamander # ffmpeg: WAV → OGG 96k, 30 key × 16 layer
```
