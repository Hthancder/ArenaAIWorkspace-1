# 02 — NoteFall (ekkx) — Deep dive: nền tảng của app mới

> Repo: https://github.com/ekkx/notefall — "Make piano videos from MIDI in the browser: 3D notes with realistic reflections, MIDI recording and editing, 4K export. Free, no watermark."
> Đây là dự án người dùng chỉ định: "notefall là mã nguồn mở rất đẹp rất hay, bê y nguyên source code về".
> File này ghi lại toàn bộ những gì đã kiểm chứng trực tiếp từ repo (clone shallow ngày 2026-11-14).

## 2.1. ⚠️ Cảnh báo giấy phép — ĐỌC TRƯỚC KHI BÊ SOURCE

- Giấy phép: **PolyForm Shield License 1.0.0** (`LICENSE.md` trong repo, `Required Notice: Copyright (c) 2026 ekkx`).
- PolyForm Shield **không phải open-source theo định nghĩa OSI**. Nó là giấy phép *source-available* với điều khoản **Noncompete**: "Any purpose is a permitted purpose, **except for providing to others any product that competes with the software**."
- Hệ quả thực tế:
  - ✅ Dùng cá nhân, học tập, nghiên cứu, nội bộ, không phân phối sản phẩm cạnh tranh: được phép.
  - ✅ Sửa code, tạo tác phẩm phái sinh cho mục đích được phép: được phép, phải giữ nguyên LICENSE + Required Notice khi phân phối bản sao.
  - ❌ Phát hành app công khai **cạnh tranh trực tiếp** với NoteFall (piano visualizer / MIDI editor / video export): **không được phép** nếu không có giấy phép riêng từ tác giả.
  - ❌ Không được sublicense / chuyển nhượng giấy phép cho người khác.
- **Hành động đề xuất trước khi build:**
  1. Nếu chỉ dùng cá nhân: bê nguyên source về, giữ LICENSE, ghi nguồn — đúng như yêu cầu hiện tại.
  2. Nếu muốn công bố: liên hệ tác giả xin phép, hoặc chỉ **tham khảo kiến trúc/tính năng** và viết lại code của mình (không copy code), hoặc chọn nền tảng open-source thật (ví dụ Midiano — xem file 06).
  3. Không xóa LICENSE, không đổi tên tác giả, không claim là code của mình.
- Các sample âm thanh: **Salamander Grand Piano V3** của Alexander Holm, **CC BY 3.0** (phải ghi công). Hand models: CC0. Hai nguồn này có giấy phép riêng, độc lập với code.
- **Lưu ý về các fork**: nhiều bản fork (kể cả vài bản cùng tên "notefall") **không giữ LICENSE.md** → không được dùng code từ các fork đó như một nguồn "thoáng" hơn. Luôn quay về repo gốc `ekkx/notefall` để xem điều khoản.
- Không có LICENSE ở một số repo tương tự (MIDIano, piano-app, pianoroll, WebGL-Piano) — xem bảng ở file 14.2.

## 2.2. Tổng quan sản phẩm

NoteFall là **piano visualizer chạy hoàn toàn trong trình duyệt**: nạp file MIDI, nốt nhạc rơi 3D xuống bàn phím 88 phím, phát bằng sample grand piano, người dùng có thể chơi live, ghi lại, sửa MIDI ngay trên canvas, đặt keyframe thay đổi cảnh theo thời gian, và export video tới 4K/60fps. Không tài khoản, không watermark, không upload dữ liệu (chỉ có analytics ẩn danh tắt được + form báo lỗi khi người dùng tự gửi).

## 2.3. Tech stack (từ `package.json` + `CLAUDE.md` của repo)

| Lớp | Công nghệ |
|---|---|
| Build | Vite 5 + TypeScript 5.6 |
| UI | React 18, react-aria-components, Tailwind CSS 3 |
| State | zustand |
| 3D | three, @react-three/fiber, @react-three/drei, @react-three/postprocessing (Bloom) |
| Âm thanh | smplr (sample playback), tone (chỉ quản lý AudioContext lifecycle) |
| MIDI | @tonejs/midi (parse/serialize SMF) |
| Export video | mediabunny + WebCodecs (VideoEncoder/AudioEncoder), render offline frame-by-frame |
| Project file | fflate (zip `.nfz`), File System Access API + fallback download |
| Ghi âm | IndexedDB (takes), Web MIDI API |
| i18n | i18next (en, ja) |
| Analytics | posthog-js (opt-out) |
| Deploy | Cloudflare Pages + Pages Function (`functions/api/report.ts`) |

## 2.4. Kiến trúc thư mục (`src/`, 201 file, ~7.6 MB)

```
src/
├ App.tsx            Layout, fallback khi không có WebGL / màn hình < 1024px
├ store.ts           zustand: settings, song, transport, editor, project (~2000 dòng)
├ midi/              parse / serialize / edit / speedMap / settingsKeyframes / noteHands
├ projects/          .nfz zip + File System Access + recent files
├ audio/             engine, sampler, recorder, click metronome, MIDI input, clock,
│                    velocityCurve, pedalDepth, smoothRelease, sampleCache…
├ keyboard/          layout 88 phím + Keyboard.tsx (hình học 3D, glow, input)
├ notes/             FallingNotes (SDF shader), HitLine, HitParticles,
│                    LandingFlashes, noteShader, looks/ (vật liệu nốt), noteColor…
├ scene/             Canvas + EditTools / PlayToggleArea + exportBridge
├ export/            renderAudio (OfflineAudioContext → WAV), renderVideo
│                    (frame-stepped → encoder → muxer), synth/ (offline piano),
│                    codec/ (MP4/WebM presets, probe, muxer)
├ hands/             Virtual hands (alpha): motion từ WebAssembly runtime
├ ui/                Layout, Toolbar, Inspector (Customize), Timeline, dialogs…
└ i18n/              en / ja
```

Điểm kiến trúc đáng học:
- **AudioEngine singleton, tách khỏi React**, tự chạy clock riêng (`audio/clock.ts` — có thể hoán đổi wall-clock ↔ virtual clock để export offline).
- **Hai tick driver**: `useFrame` cho hình ảnh + Web Worker `setInterval(25ms)` để tab nền không bị đứng nhạc.
- **Mỗi note có `stopId` duy nhất** — tránh lỗi hai note cùng pitch triệt tiêu lẫn nhau (lỗi kinh điển của smplr).
- **Lookahead 0.015s + stop buffer 0.02s** chống click khi attack/release.
- **Pedal sustain half-pedal aware**: CC64 giữ dạng 0..1, map thành damper lift, voice được fade theo hàm mũ, re-target khi pedal di chuyển.
- **Project lưu thành file `.nfz`** (zip: `manifest.json` + `assets/song.mid` + texture) trên đĩa người dùng — không phụ thuộc IndexedDB (tránh mất dữ liệu khi clear site data / private mode / Safari ITP).
- **Undo/redo giới hạn 50 bước** (snapshot toàn bộ notes/pedals).

## 2.5. Tính năng chi tiết (đã kiểm chứng)

### 2.5.1. Hiển thị / Visualizer
- Nốt 3D với phản chiếu thực, texture: metal, water, ice, glass, marble, jewel, crystal…
- Hạt (particles) + haze bốc lên như khói từ hit line; key sáng lên khi nốt chạm.
- Màu nốt theo: track, tay (hand), gradient ngang bàn phím, palette ngẫu nhiên (seed).
- Keyframe trên timeline: đổi màu, camera, bloom, background… theo thời gian trong bài.
- Virtual hands (alpha) chơi theo bài — motion load từ WebAssembly, data fetch từ CDN khi bật hands, cache trong Cache Storage.
- Pitch labels trên nốt, hit line, landing flashes, note death FX.
- Camera: FOV, vị trí, lookAt, giới hạn camera, keyboard screen Y (lens shift — bàn phím không di chuyển trong world).
- Tọa độ chuẩn: camera `[0,0,12]`, FOV 32°, `KEYBOARD_Y = -2.0`, phím trắng 0.235×1.475 wu, 88 phím = 12.22 wu = full chiều ngang 16:9. Hit line tại `NOTE_HIT_Y = KEYBOARD_Y + WHITE_KEY_LENGTH`. Clip nốt bằng SDF per-fragment, không dùng z-occlusion.

### 2.5.2. Chơi live (Live Play)
- Input: touch, chuột, **phím máy tính (PC keyboard)**, **Web MIDI** (USB/Bluetooth).
- Ghi velocity + sustain pedal (CC64, half-pedal 0..1). Sostenuto CC66 / soft CC67 được ghi và giữ qua round-trip (playback bỏ qua).
- Velocity curve tùy chỉnh (editor riêng `VelocityCurveEditor`).
- Pedal depth mapping tùy chỉnh.
- Preview note khi sửa settings.

### 2.5.3. Ghi lại (Record)
- Ghi từ MIDI keyboard / PC keyboard / chuột / touch.
- Count-in 4 nhịp metronome (100 BPM, sine click) — tùy bật/tắt.
- Snapshot bài đang mở trước khi ghi; take rỗng thì khôi phục + toast.
- Tự load take vào editor khi dừng ghi. Badge "unread" cho takes mới.
- Lưu takes vào IndexedDB; xuất MIDI hoặc WAV.

### 2.5.4. Sửa MIDI ngay trên canvas (Editor)
- Thêm, di chuyển, resize, split, xóa, vẽ (draw), marquee-select nốt ngay trên visualizer.
- Sửa velocity, hand (L/R), finger (1–5) trong selection card.
- Undo/redo đầy đủ.
- Hand/finger không có chỗ trong SMF → lưu trong `manifest.noteHands` của `.nfz` dạng `[midi, timeMs, hand, finger]`, map lại theo pitch + thời gian gần nhất (≤10ms).

### 2.5.5. Timeline & Playback
- MIDI offset, trim, speed automation (speedMap — đổi tốc độ theo thời gian), audio track đệm (accompaniment) phát cùng.
- Settings keyframes (pins) trên timeline — scene morph giữa các pin.
- Transport: play/pause, seek, loop (qua timeline editor), fullscreen.
- Metronome click riêng.

### 2.5.6. Âm thanh
- Sampled grand piano: Salamander Grand Piano V3 (Yamaha C5, 16 velocity layers, fetch từ R2 CDN, cache).
- Offline synth piano riêng cho export (`export/synth/`) — schedule note + pedal theo cùng model với live engine.
- Smooth release, pedal held voices, stop buffer… (xem 2.4).

### 2.5.7. Export
- Video tới **4K 60fps**: MP4 (H.264 + AAC) hoặc WebM (VP9/AV1 + Opus), có/không audio; WAV cho audio-only.
- Render offline frame-by-frame (không quay realtime) → mượt trên máy yếu. Progress + ETA theo wall-clock, cancel được.
- `computeExportTimeline` là nguồn duy nhất cho cửa sổ render (offset, trim, speed, tail 5s) — audio và video luôn cùng độ dài.

### 2.5.8. Project & File
- `.nfz` zip: `manifest.json` {appVersion, name, createdAt, updatedAt, settings, songRef, customTexture} + `assets/song.mid` + texture.
- File System Access API (Chrome/Edge): giữ handle để Save ghi đè tại chỗ; recent files (tối đa 8 handle trong IndexedDB).
- Safari/Firefox: `<input type=file>` + Blob download; Save As.
- Explicit save only, không autosave. `Cmd+S` ghi đè, `Cmd+Shift+S` luôn mở picker. `beforeunload` cảnh báo khi dirty. History không persist.
- Drag & drop toàn cửa sổ: `.nfz` → mở project, `.mid` → nạp bài, audio → thêm làm accompaniment.
- Demo songs kèm theo (2 file `.nfz`: Schubert Impromptu, Scizzie Aquatic Ambience).

### 2.5.9. UI / UX
- Inspector = Customize panel, 5 tab (Notes / Effects / Keyboard / Scene / Sound), mỗi tab là stack Section có switch on/off, search xuyên tab, Detail disclosure.
- Design system riêng (`docs/design-system.md` + `ui/kit/tokens.css`), không dùng `window.confirm/alert`.
- i18n en/ja, language switcher.
- Feedback form trong app → Cloudflare Function → tạo GitHub issue công khai (có Turnstile chống spam, defuse @mention). Fallback về form GitHub khi endpoint chưa cấu hình.
- Analytics PostHog ẩn danh, opt-out trong menu. Không upload MIDI/recording/project/audio.
- Fallback màn hình khi không có WebGL hoặc viewport < 1024px. Shortcuts toàn cục (Cmd+O/S, Space…) bắt ở capture phase.

### 2.5.10. Số lượng thông số tùy chỉnh
`Settings` trong `store.ts` có **hàng trăm key** (notes: màu, gradient 5 stops, random palette, emissive, opacity, corner radius, width scale, min length, material, shape, bevel ×7, light ×5, reflectivity, sheen, transparency, saturation, surface/albedo/specular/emission, pattern ×12, bump ×6, cloud ×4, highlight ×3, frost ×4, outline ×4, rim band ×5, merge ×4…; camera, keyboard, sound, effects, bloom, background…). Đây chính là điểm mạnh nhất để đáp ứng yêu cầu "tùy chỉnh được hầu hết thông số".

## 2.6. Những gì NoteFall CHƯA có (so với các app khác)

| Tính năng | Trạng thái | App khác có |
|---|---|---|
| Wait Mode (đợi bấm đúng nốt) | ❌ Không có | Synthesia, Flowkey |
| Chấm điểm / accuracy / timing | ❌ Không có | Synthesia, Simply Piano, Yousician |
| Sheet music (MusicXML, stave) | ❌ Không có | Synthesia, Flowkey, Piano Marvel |
| Curriculum / bài học / thư viện bài hát | ❌ Không có (chỉ 2 demo) | Simply Piano, Piano Marvel |
| Mic detection (đàn piano thật) | ❌ Không có | Simply Piano, Flowkey, Skoove |
| SoundFont `.sf2` tùy chọn / nhiều instrument | ❌ Chỉ 1 grand piano sample | Perfect Piano (9+ timbre + plugin), RoxyPiano (128 GM) |
| Multiplayer / social | ❌ Không có | Perfect Piano |
| Mobile app | ❌ Web desktop ≥1024px | Perfect Piano, Simply Piano… |
| Luyện từng tay tự động (auto-split) | ⚠️ Có gán hand thủ công, không auto-split | Synthesia (easy hand split) |
| Transpose / đổi key | ⚠️ Chưa thấy trong settings chính | Nhiều app có |
| Metronome đầy đủ (BPM, time signature) | ⚠️ Chỉ count-in 100 BPM | Perfect Piano, Synthesia |
| Gợi ý ngón tay tự động | ⚠️ Gán thủ công, không gợi ý | Synthesia (finger hints), piano-app (DP) |

→ Đây là danh sách "tính năng còn thiếu" để build thêm. Chi tiết checklist ở file 09.

## 2.7. Cách bê nguyên source về (khi bắt đầu build — CHƯA LÀM trong đợt nghiên cứu này)

```bash
git clone https://github.com/ekkx/notefall.git notefall-base
cd notefall-base
# Giữ nguyên LICENSE.md + Required Notice. Ghi nguồn trong README của app mới.
npm install
npm run dev        # Vite dev server :5173
npm run build      # tsc -b && vite build → dist/
npm run typecheck
# Sample Salamander: npm run fetch-salamander / prepare-salamander (xem scripts/)
```

- Không xóa `LICENSE.md`. Không đổi tên tác giả. Ghi rõ "Dựa trên NoteFall của ekkx, PolyForm Shield 1.0.0".
- Nếu mục đích là phát hành cạnh tranh: **dừng lại, xin phép tác giả trước** (mục 2.1).
- Source NoteFall **không** được copy vào repo nghiên cứu này (đợt này chỉ nghiên cứu).

## 2.8. Các repo NoteFall khác (không nhầm lẫn)

| Repo | Mô tả | Liên quan? |
|---|---|---|
| `ekkx/notefall` | Web visualizer 3D (repo chính, file này) | ✅ Nền tảng |
| `Suma-Udd/notefall` | Python desktop: MIDI/recording → Synthesia-style video, có app tkinter, Basic Pitch / ByteDance piano transcription ONNX, sustain pedal, 5 themes, PyInstaller build | Tham khảo: audio→MIDI, desktop packaging |
| `fonghtdev/NoteFall` | Electron + composer 2-staff (VexFlow), OMR đọc PDF sheet music, SoundFont, export MP4, iPad Capacitor | Tham khảo: composer, OMR, SoundFont |
| `austinrsands/notefall` | Web app học bài từ MIDI với MIDI keyboard, wait mode, transpose, tempo | Tham khảo: wait mode web đơn giản |
| `notefall.jrglee.dev` (NoteFall iOS) | iOS practice room, USB-MIDI, import MIDI/MusicXML qua web importer | Tham khảo: mobile + importer |
| `micooz/notefall`, `Wesley-AlvesRolim/notefall`… | Fork của ekkx | Không cần |

## 2.9. Tài liệu liên quan trong bộ này

| Chủ đề | File |
|---|---|
| Bản đồ source chi tiết (file nào làm gì, sửa ở đâu, hook nào để gắn tính năng) | **15-code-map-notefall.md** |
| Giấy phép của mọi dependency + sample + repo tham khảo | **14-thu-vien-va-giay-phep.md** |
| Cách tự host lại 480 sample Salamander (bắt buộc khi fork) | 14.4 + 15.6 |
| Thiết kế wait mode / chấm điểm / fingering dựa trên hook của engine | **16-practice-engine-chi-tiet.md** |

## 2.10. Đánh giá nhanh

| Tiêu chí | Điểm |
|---|---|
| Chơi đàn trên máy tính (live play) | ★★★★★ — Web MIDI + PC keyboard + touch, pedal half, velocity curve |
| MIDI tùy chỉnh | ★★★★★ — parse/serialize, edit trên canvas, speedMap, trim/offset, keyframe |
| Tùy chỉnh thông số | ★★★★★ — hàng trăm settings, keyframe theo thời gian |
| Âm thanh | ★★★★☆ — 1 grand piano sample chất lượng cao; thiếu đa timbre/SoundFont |
| Học/luyện tập | ★☆☆☆☆ — không có wait mode, điểm, sheet music, curriculum |
| Export video | ★★★★★ — 4K offline render, không watermark |
| Mobile | ★☆☆☆☆ — desktop-first ≥1024px |
| Giấy phép cho mục đích thương mại cạnh tranh | ★☆☆☆☆ — PolyForm Shield Noncompete |
