# 07 — Ma trận tính năng tổng hợp

> ✅ = có, ⚠️ = có một phần / hạn chế, ❌ = không có, — = không áp dụng.
> "App mới (mục tiêu)" là cột đích cần đạt — chi tiết checklist ở file 09.

## 7.1. Chơi tự do (Free Play)

| Tính năng | NoteFall ekkx | Perfect Piano | Synthesia | Virtual piano web | App mới (mục tiêu) |
|---|---|---|---|---|---|
| Bàn phím 88 phím ảo | ✅ 3D | ✅ | ✅ | ✅ | ✅ P0 |
| Chuột / touch / multitouch | ✅ | ✅ | ✅ | ✅ | ✅ P0 |
| Phím máy tính (PC keyboard) | ✅ | ⚠️ (mobile) | ✅ | ✅ | ✅ P0 |
| Web MIDI / USB MIDI input | ✅ | ✅ USB Android | ✅ | ✅ | ✅ P0 |
| Bluetooth MIDI | ✅ (qua Web MIDI) | ⚠️ | ✅ | ⚠️ | ✅ P0 |
| Velocity (lực phím) | ✅ + curve | ✅ force touch | ✅ MIDI | ✅ MIDI | ✅ P0 |
| Sustain pedal CC64 (half) | ✅ 0..1 | ✅ | ✅ | ✅ | ✅ P0 |
| Sostenuto/soft CC66/67 | ⚠️ ghi, không phát | — | — | — | P1 phát |
| Đa timbre / instrument | ❌ 1 grand | ✅ 9+ plugin | ⚠️ ít | ✅ 5–128 | ✅ P1 SoundFont |
| SoundFont `.sf2` tùy chọn | ❌ | ❌ (plugin riêng) | ❌ | ❌ | ✅ P1 |
| Pitch bend | ❌ | ❌ | ⚠️ keybind | ✅ | P2 |
| Chord detection | ❌ | ⚠️ chords mode | ✅ Free Play | ✅ | P1 |
| Scale highlighting | ❌ | ❌ | ⚠️ labels | ✅ | P1 |
| Metronome | ⚠️ count-in | ✅ | ✅ | ✅ | ✅ P0 |
| Ghi WAV + MIDI | ✅ | ✅ MIDI+AAC | ⚠️ multi-track | ✅ | ✅ P0 |
| MIDI output ra ngoài | ❌ | ❌ | ✅ | ⚠️ Midiano | P1 |

## 7.2. MIDI & Playback

| Tính năng | NoteFall | Perfect Piano | Synthesia | App mới |
|---|---|---|---|---|
| Mở `.mid` tùy ý | ✅ | ⚠️ thư viện | ✅ | ✅ P0 |
| Import MusicXML | ❌ | ✅ | ✅ | ✅ P1 |
| Import audio (MP3/WAV) đệm | ✅ accompaniment | ❌ | ❌ | ✅ P1 |
| Audio→MIDI transcription | ❌ | ❌ | ❌ | P2 |
| Play / pause / seek / stop | ✅ | ✅ | ✅ | ✅ P0 |
| Đổi tốc độ (speed) | ✅ speedMap | ✅ | ✅ | ✅ P0 |
| Loop A-B / đoạn | ⚠️ timeline | ✅ | ✅ | ✅ P0 |
| Bookmark / marker | ⚠️ pins keyframe | ❌ | ✅ | ✅ P1 |
| Transpose / đổi key | ❌ | ❌ | ⚠️ octave | ✅ P1 |
| Tách tay L/R (auto) | ⚠️ gán tay tay | ✅ | ✅ | ✅ P1 |
| Đổi màu theo track | ✅ | ❌ | ✅ | ✅ P0 |
| Sửa MIDI trên canvas | ✅ | ❌ | ❌ | ✅ P0 (giữ) |
| Undo/redo | ✅ 50 | ❌ | ❌ | ✅ P0 (giữ) |
| Lưu project file | ✅ `.nfz` | ❌ | ❌ | ✅ P0 (giữ) |
| Export MIDI | ✅ | ✅ | ⚠️ record | ✅ P0 |
| Export video | ✅ 4K | ❌ | ❌ | ✅ P0 (giữ) |
| Export audio WAV | ✅ | ❌ | ❌ | ✅ P0 (giữ) |

## 7.3. Học / Luyện tập

| Tính năng | NoteFall | Perfect Piano | Synthesia | Simply/Flowkey… | App mới |
|---|---|---|---|---|---|
| Falling notes | ✅ 3D | ✅ | ✅ | ✅ | ✅ P0 |
| Waterfall | ❌ | ✅ | ❌ | ⚠️ | P1 |
| Sheet music (stave) | ❌ | ✅ | ✅ | ✅ | ✅ P1 |
| Wait Mode (Note pause) | ❌ | ✅ | ✅ | ✅ | ✅ P1 |
| Auto / Semi-auto play | ⚠️ | ✅ | ✅ | ✅ | ✅ P1 |
| Chấm điểm note/timing/length | ❌ | ⚠️ | ✅ 100 | ✅ | ✅ P1 |
| Luyện từng tay | ⚠️ | ✅ | ✅ | ✅ | ✅ P1 |
| Gợi ý ngón tay | ⚠️ thủ công | ❌ | ✅ | ⚠️ | ✅ P1 |
| Tên nốt / solfège / scale degree | ⚠️ pitch label | ⚠️ | ✅ | ✅ | ✅ P1 |
| Độ khó (dễ/khó cùng bài) | ❌ | ✅ | ⚠️ | ✅ | P2 |
| Curriculum / lộ trình | ❌ | ⚠️ | ❌ | ✅ | P2 |
| Thư viện bài hát | ❌ 2 demo | ✅ hàng nghìn | ✅ 150+ | ✅ 1,500+ | P2 (BYO trước) |
| Mic detection (đàn cơ) | ❌ | ❌ | ❌ | ✅ | P2 |
| Sight-reading test (SASR) | ❌ | ❌ | ❌ | ✅ Piano Marvel | P2 |
| Gamification (streak, rank) | ❌ | ✅ | ⚠️ điểm | ✅ | P2 |
| Multiplayer | ❌ | ✅ | ❌ | ❌ | P2 |

## 7.4. Tùy chỉnh & Hiển thị

| Tính năng | NoteFall | Perfect Piano | Synthesia | App mới |
|---|---|---|---|---|
| Màu nốt / gradient / random | ✅ rất sâu | ⚠️ | ⚠️ | ✅ P0 (giữ) |
| Vật liệu nốt (metal/ice/glass…) | ✅ | ❌ | ❌ | ✅ P0 (giữ) |
| Keyframe visual theo thời gian | ✅ | ❌ | ❌ | ✅ P0 (giữ) |
| Camera (FOV, vị trí, lookAt) | ✅ | ❌ | ⚠️ zoom | ✅ P0 (giữ) |
| Độ rộng phím | ⚠️ width scale nốt | ✅ | ✅ zoom custom | ✅ P1 |
| Single/Double/Dual row | ❌ | ✅ | ❌ | P1 |
| Keyboard Y / lens shift | ✅ | ❌ | ❌ | ✅ P0 (giữ) |
| Bloom / particles / background | ✅ | ❌ | ❌ | ✅ P0 (giữ) |
| Velocity curve | ✅ | ❌ | ❌ | ✅ P0 (giữ) |
| Phím tắt tùy chỉnh | ⚠️ cố định | ⚠️ | ✅ keybind | ✅ P1 |
| Ngôn ngữ | ✅ en/ja | ✅ đa | ✅ đa | ✅ P1 (vi/en) |
| Dark/light mode | ⚠️ | ✅ | ✅ | P1 |

## 7.5. Nhóm piano visualizer / video maker (đối thủ trực tiếp)

| Tính năng | NoteFall | SeeMusic | PianoViz | Neothesia | pianoroll (web) | WebGL-Piano | App mới |
|---|---|---|---|---|---|---|---|
| Nốt rơi 3D | ✅ đẹp nhất | ✅ | ⚠️ WebGL2 2.5D | ⚠️ 2D blocks | ✅ | ✅ 3D | ✅ P0 |
| Nốt rơi 2D/waterfall | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | P1 |
| Màu theo 12 pitch class | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | P1 |
| Màu theo track/tay | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ P0 |
| Particles / bloom / hit line | ✅ | ✅ + Saber | ✅ | ⚠️ | ✅ | ⚠️ | ✅ P0 |
| Texture/material tự nhập | ✅ custom texture + material | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ P0 |
| Background image / video | ✅ image | ✅ image + video | ❌ | ❌ | ✅ media | ❌ | P1 video |
| Preset style lưu/tái dùng | ⚠️ project `.nfz` | ✅ presets | ❌ | ⚠️ | ✅ theme JSON | ❌ | ✅ P1 |
| Timeline keyframe | ✅ | ⚠️ | ❌ | ❌ | ✅ | ❌ | ✅ P0 |
| MIDI editor | ✅ trên canvas | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ P0 |
| Record MIDI + audio | ✅ MIDI, audio export | ✅ + camera | ❌ | ✅ free play | ❌ | ❌ | P1 camera |
| Audio → MIDI | ❌ | ✅ | ✅ (AI) | ✅ neothesia-ai | ❌ | ❌ | P2 |
| MusicXML + sheet đồng bộ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ abcjs | P1 |
| Export MP4 4K | ✅ | ✅ | ⚠️ Full HD | ✅ ffmpeg | ✅ WebCodecs | ⚠️ WebM | ✅ P0 |
| Export vertical 9:16 | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | P1 |
| Chạy trên mobile | ❌ | ✅ | ✅ web | ❌ | ✅ | ✅ | P2 |
| Giấy phép dùng lại code | ⚠️ PolyForm Noncompete | Đóng | Đóng | GPL-3.0 | xem repo | **MIT** | — |

## 7.6. Đọc kết quả

- **NoteFall thắng** ở: MIDI tự do, editor, export video, tùy chỉnh visual, chơi live web.
- **Perfect Piano thắng** ở: mobile, multiplayer, đa timbre, đa chế độ bàn phím.
- **Synthesia thắng** ở: Wait Mode + chấm điểm + giá một lần + MIDI/MusicXML tự do.
- **Simply/Flowkey/Piano Marvel thắng** ở: curriculum, mic detection, thư viện biên soạn, sight-reading.
- **App mới cần**: giữ điểm mạnh NoteFall (P0) + bổ sung Wait Mode/chấm điểm/sheet music/SoundFont (P1) + mic/curriculum/multiplayer (P2).
