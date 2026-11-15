# 06 — Virtual piano web & dự án open-source khác

> Nhóm này quan trọng vì: (a) nhiều tính năng "chơi tự do" hay, (b) có source mở để tham khảo code thật, (c) chạy web giống NoteFall.

## 6.1. Virtual piano web (không cài đặt, chơi ngay)

| Site / App | Tính năng nổi bật |
|---|---|
| **virtualpianokeyboard.com** | Web Audio synth zero-latency, 88 phím, multi-touch, USB MIDI, note display, virtual piano sheets, lesson tương tác, 4 sound engine (Grand/Rhodes/Synth/Organ) |
| **tembrica.com/en/online-piano** | 88 phím, 5 voice (grand/electric/pad/organ/harpsichord), MIDI input, PC keyboard mapping (A–L trắng, W–P đen), sustain Space, transpose, octave shift, **chord-name detection realtime**, scale highlighting, record WAV+MIDI, learn mode falling notes 12 bài, drop `.mid` ≤2MB. Synth additive 16-partial Steinway model (không dùng sample) |
| **toolv.com/en/app/online-piano** | 4 instrument, PC keyboard/mouse/touch/MIDI, glissando, sustain Space, octave shift, record MP3 (10 bản local), 5 preset song, demo/learn mode, metronome 40–240 BPM, MIDI velocity |
| **tuneonmusic.com Virtual Piano** | 88 phím sampled grand, 2 velocity layer, sustain toggle, play-along song library, record (audio clock), MIDI velocity, metronome, note labels (letter/solfège/PC key), **game mode echo** (app chơi 1 phrase, người chơi lặp lại, thêm nốt mỗi vòng) |
| **screenpiano.com** | 88 phím, PC keyboard 61 phím, multi-touch, sustain, octave, labels, glide, MIDI từ Settings, letter-note song rack có rhythm |
| **roxypiano.web.id** | **128 General MIDI instrument**, Salamander V3 16 velocity layer, falling notes + MIDI playback + accuracy stats, Wait Mode, metronome time signature, chord detection, transpose/speed, PWA install, 8 ngôn ngữ, Web MIDI velocity + CC64 |
| **synthio.io** | Piano/synth/organ, pitch bend (±2 semitone, wheel + arrow key + MIDI 14-bit), MIDI CC14–17 → cutoff/resonance/detune/low-cut, record audio+video (Pro) |
| **playvirtualinstruments.com** | 17 nhạc cụ ảo, recorder WebM, mark mode (thu nốt rồi replay), chord chart, metronome, tuner |

**Bài học:** virtual piano web chuẩn tối thiểu gồm: 88 phím, 4–5 voice, MIDI input, PC keyboard mapping, sustain, transpose/octave, chord detection, record WAV+MIDI, metronome, learn mode falling notes, drop MIDI. App mới nên có đủ và hơn (NoteFall đã có phần lớn, thiếu chord detection, scale highlight, đa voice).

## 6.2. Midiano (Bewelge/MIDIano) — open-source web

> ⚠️ **Kiểm tra 2026-11-14: repo này KHÔNG có file LICENSE** (GitHub API: license = null). Public nhưng mặc định "all rights reserved" → **không được copy code**, chỉ học ý tưởng. Xem file 14.2.

- JavaScript MIDI player + piano-learning webapp, chạy mọi trình duyệt có WebAudio.
- Mở MIDI → falling bars + **sheet music tự sinh** (VexFlow).
- MIDI keyboard: **Input** (Wait Mode — bài đợi bấm đúng) + **Output** (dùng keyboard làm loa phát MIDI).
- Tùy chỉnh màu track, particle effect, instrument từng track; 3 soundfont từ `gleitz/midi-js-soundfonts`.
- Web MIDI cần Chrome/Edge.
- **Giá trị tham khảo:** kết hợp falling notes + sheet music + MIDI in/out trong một web app nhỏ — đúng combo app mới cần. **Giấy phép: KHÔNG có file LICENSE** (dù GitHub hiển thị "MIT" cho một số fork) → không copy code.

## 6.3. piano-app (IbrahimKhan25) — open-source web, wait mode + fingering

> ⚠️ **Kiểm tra 2026-11-14: không có file LICENSE** → chỉ học ý tưởng, không copy code. Thuật toán đã được mô tả lại (ngôn từ riêng) ở file 16.

- Web app học piano: sheet music (OpenSheetMusicDisplay từ MusicXML) + nghe digital piano qua Web MIDI, **Wait Mode** (cursor chỉ đi khi bấm đúng; chord bấm bất kỳ thứ tự).
- Bàn phím ảo hiển thị **ngón tay gợi ý**; người dùng sửa ngón bằng phím 1–5, lưu per-hand, export/import corrections.
- Thuật toán fingering: **dynamic programming** (tay trái dùng model mirror).
- Hand switch Right/Left/Both giữ nguyên vị trí; loop highlight; skip bằng →; dev keyboard A W S E D… thay piano khi không có MIDI.
- Không backend, chạy 100% browser. **Giá trị tham khảo:** thuật toán fingering DP + OSMD cursor sync — nên bê ý tưởng cho tính năng finger hints.

## 6.4. Các dự án GitHub khác

| Dự án | Mô tả | Tham khảo cho |
|---|---|---|
| `Suma-Udd/notefall` (Python) | MIDI/recording → Synthesia video; app tkinter; **Basic Pitch ONNX + ByteDance piano transcription** (154MB, tải 1 lần); sustain pedal CC64; 5 themes; hands; dark mode; PyInstaller desktop | Audio→MIDI, desktop packaging, transcription |
| `fonghtdev/NoteFall` (Electron) | Falling notes + **composer 2-staff** (VexFlow), **OMR đọc PDF sheet music**, SoundFont `.sf2` (GeneralUser GS), metronome theo meter, export MP4 720/1080, iPad Capacitor | Composer, OMR, SoundFont, iPad |
| `austinrsands/notefall` (web) | Học bài từ MIDI + MIDI keyboard, falling blocks liên tục hoặc dừng chờ phím, chỉnh số phím/transpose/tempo | Wait mode web tối giản |
| `danigb/soundfont-player` | SoundFont loader/player WebAudio, unlimited polyphony, MIDI note number, detune, schedule list, kết nối Web MIDI | Phát `.sf2` trong browser |
| `gleitz/midi-js-soundfonts` | Soundfont dạng MIDI.js (mp3) cho browser | Đa instrument không cần `.sf2` gốc |
| `isc/opensheetmusicdisplay` (OSMD) | Render MusicXML trong browser (VexFlow), đổi màu note, ẩn part, export SVG/PNG, headless Node | Sheet music view + cursor |
| `googlecreativelab/chrome-music-lab` | Chrome Music Lab (Tone.js) — arpeggio, song maker… | UX dạy nhạc cho trẻ |
| `javiert01/MIDI-Scenes` | Đo latency Web MIDI→Web Audio: Chrome ~15–30ms wired, Bluetooth +100–250ms (không chơi được), latencyHint chỉ Chrome tôn trọng | Chuẩn latency mục tiêu (file 08) |

## 6.5. PianoBooster & desktop open-source cũ

- **PianoBooster**: desktop app học piano, scrolling sheet music, BYO music, MIDI feedback. UI dated nhưng chức năng sâu, miễn phí.
- Bài học: desktop app có lợi thế MIDI latency thấp, nhưng web hiện nay đã đủ tốt (15–30ms) và phân phối dễ hơn nhiều.

## 6.5b. Nhóm "piano visualizer / video maker" chuyên nghiệp (đối thủ trực tiếp của NoteFall)

| Sản phẩm | Nền tảng | Tính năng đáng chú ý | Giá / giấy phép |
|---|---|---|---|
| **SeeMusic** (Peter Shannon) | Windows, macOS, iOS, Android | Nốt 3D; record MIDI + audio + **camera video đồng bộ**; **tự align bàn phím trong footage**; isolate hands/keys (keying, color, lighting); crop/rotate/position footage; **pitch detection audio → MIDI**; mở MusicXML + **sheet music đồng bộ**; MIDI editor (add/remove/split/join/move/resize, sửa pitch/velocity/track/tempo); **màu theo 12 pitch class (chroma)**; pitch names, solfège, guides, bar lines; texture/material tự nhập; background image/video; **preset style** lưu/tái dùng; export HD/4K, widescreen + vertical | Free có watermark; Pro ~$8.99/tháng hoặc $79.99/năm |
| **Embers** | Windows (và browser) | Render cinematic từ MIDI, chất lượng hình ảnh cao, particle/light đẹp | Free chơi; render qua tier Patreon |
| **PianoViz** | Web | **AI transcription piano từ audio** (MP3/WAV/FLAC/M4A/OGG ≤50 MB) → MIDI; WebGL2 realtime; export MP4 Full HD 30/60fps **ngay trên máy**; hand separation (beta); project lưu trong Transcriptions | Web, freemium |
| **LumaKeys** | macOS (+Windows) | Học + record + export video (4K/60, vertical/widescreen) trong một app | Free tải, Pro $79 một lần |
| **Neothesia** (PolyMeilex) | Windows, macOS, Linux | Rust + wgpu, GPL-3.0; **open-source**; falling notes, MIDI input, chọn track, SoundFont playback, **free-play recording** (release 9/2026), **ffmpeg-encoder** xuất video, có `neothesia-ai`, `neothesia-cli`, `piano-layout`, `neothesia-image` trong workspace | **GPL-3.0** (copyleft — nếu phân phối bản sửa phải mở source) |
| **Piano From Above** | Windows | Free, falling-note player cổ điển, nhẹ | Free |
| **Pianotify** | Web | Không cần cài, falling notes + sheet music | Freemium |
| **Anything Piano** | iPhone | Từ **link YouTube** → bài luyện (audio→MIDI) | Freemium |
| **Falling Note** | iPhone | Falling notes + sheet music từ bất kỳ bài nào | Freemium |
| **worldwiderad/pianoroll** | Web (GitHub, **không có LICENSE**) | TS + Three.js + Vite; nốt rơi theo track + keyboard sáng/nhấn; **press beams, hit-line ripples, impact bursts, particles, bloom**; **background media**; audio riêng giữ sync theo MIDI clock **hoặc** SoundFont sampler (piano, strings, brass, woodwinds, synth pad/lead, drums); **theme preset + import/export JSON**; **timeline keyframes**; export MP4 bằng WebCodecs (frame-by-frame); project library IndexedDB | ❌ Không LICENSE — học ý tưởng |
| **pirozhki/piano-visualizer-classic** | Web (GitHub Pages, **không có LICENSE**) | Canvas 2D thuần, 88 phím, màu + glow theo track, hit effect (Smoke Glow / Spark / Hybrid), effect quality (Smooth/Cinema/Ultra), background image + dimming, play/seek/fullscreen, export WebM (VP9/VP8) offline, 1080p/720p/30–60fps, **không cần CDN** | ❌ Không LICENSE file |
| **RenCheng0525/WebGL-Piano** | Web (single HTML) | README **nói** MIT nhưng repo **không có file LICENSE** (rủi ro — cần xác nhận tác giả); Three.js + Tone.js + @tonejs/midi + **abcjs** (sheet music tự sinh); 30 sample Salamander (mỗi minor third); pedal CC64 + re-strike cắt note trước; schedule bằng Tone.Transport (không rAF) → chạy nền vẫn đúng nhịp; **bỏ track drum channel 10**; decode tên track Big5/GBK/Shift_JIS; 1 InstancedMesh cho waterfall; phím lún theo velocity + sáng màu track; play live chuột/touch/PC keyboard/MIDI; resize divider score ↔ piano, nhớ kích thước | ⚠️ Không có LICENSE file — đọc để học, không copy |

**Rút ra:**
- NoteFall mạnh nhất về **chất lượng hình ảnh 3D + độ sâu thông số**, nhưng **SeeMusic vượt** ở: footage sync, audio→MIDI, MusicXML, chroma color, preset, mobile.
- **Về giấy phép**: chỉ **Neothesia (GPL-3.0)** là rõ ràng trong nhóm visualizer; WebGL-Piano/pianoroll/MIDIano/piano-app **không có file LICENSE** → không dùng được code, chỉ học ý tưởng. Xem bảng đầy đủ ở file 14.2.
- **Chroma color theo 12 pitch class** (SeeMusic) là tính năng hay, dễ thêm vào NoteFall (noteColorMode mới: theo pitch class, 12 màu tùy chỉnh).
- **Theme preset import/export JSON** (pianoroll, SeeMusic) — NoteFall chưa có: nên thêm (export/import settings JSON).
- **Vertical 9:16 export** (SeeMusic, PianoViz, LumaKeys) — NoteFall hiện 16:9; thêm aspect ratio là việc nhỏ, giá trị lớn cho TikTok/Shorts.
- **Background video** + **camera footage sync** là khoảng trống lớn của NoteFall (P2).

## 6.6. Tổng hợp "tính năng chơi tự do" nên có (từ nhóm này)

- Đa voice/instrument (≥5, tốt nhất 128 GM hoặc SoundFont tùy chọn).
- Chord-name detection realtime + scale highlighting.
- PC keyboard mapping tùy chỉnh được (không cố định A–L).
- Pitch bend wheel (ảo + MIDI 14-bit) — cho synth/organ.
- Mark mode, game mode echo, oscilloscope waveform.
- PWA installable, offline-ready.
- MIDI output (gửi ra keyboard/DAW ngoài) — Midiano có, NoteFall chưa.
