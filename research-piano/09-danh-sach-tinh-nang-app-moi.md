# 09 — Danh sách tính năng + thông số tùy chỉnh cho app mới

> Đây là file "spec" chính để build. Mỗi mục ghi: tính năng, mức ưu tiên, app nào đã có (để tham khảo), ghi chú kỹ thuật.
> P0 = bản đầu tiên (chơi đàn thật trên máy tính). P1 = ngay sau P0. P2 = mở rộng.

---

# PHẦN A — CHECKLIST TÍNH NĂNG

## A1. P0 — Bắt buộc cho bản đầu tiên (chơi thật trên máy tính)

### A1.1. Bàn phím & nhập liệu
- [ ] Bàn phím 88 phím (A0–C8) hiển thị đầy đủ, đúng vị trí phím đen/trắng. *(NoteFall)*
- [ ] Chơi bằng **chuột** (click/giữ), **touch** (multitouch), **phím máy tính** (mapping mặc định A W S E D F T G Y H U J K + O L P ; , Z/X đổi octave). *(NoteFall, WebGL-Piano)*
- [ ] **Web MIDI input**: chọn thiết bị, hiển thị trạng thái kết nối, tự reconnect. *(NoteFall)*
- [ ] Velocity: từ MIDI thật; từ chuột/phím máy tính lấy theo vị trí click (Y trên phím) hoặc slider velocity khi không có MIDI. *(NoteFall)*
- [ ] **Velocity curve** tùy chỉnh bằng đồ thị kéo điểm. *(NoteFall)*
- [ ] **Sustain pedal CC64** đúng: half-pedal 0..1, note giữ sau khi nhả phím, nhả pedal tắt dần. *(NoteFall — đã làm rất chuẩn)*
- [ ] Glissando khi kéo chuột qua phím. *(WebGL-Piano, toolv)*
- [ ] Hiển thị nhãn phím (C, C#, …) bật/tắt được; chế độ chỉ hiện C. *(NoteFall)*
- [ ] Đổi octave / transpose ± nửa cung, ± octave. *(NoteFall settings.transpose có sẵn)*

### A1.2. Âm thanh
- [ ] Sample grand piano chất lượng cao, nhiều velocity layer (Salamander V3, 16 layer) — preload + lazy decode. *(NoteFall)*
- [ ] Độ trễ thấp: `latencyHint: 'interactive'`, schedule theo `AudioContext.currentTime`, lookahead ~15 ms. *(NoteFall)*
- [ ] Volume master, mute, **reverb** (size/decay/damping/pre-delay/HiCut/LowCut/wet-dry), **EQ 6 bands**. *(NoteFall)*
- [ ] Release time, detune (cents), velocity compensation. *(NoteFall)*
- [ ] Cảnh báo khi input là Bluetooth MIDI (độ trễ cao). *(mới)*
- [ ] Không bị "nuốt note" khi 2 note cùng pitch (stopId duy nhất). *(NoteFall)*

### A1.3. MIDI file & playback
- [ ] Mở `.mid`/`.midi` (drag & drop + file picker). Format 0/1, tempo map, track name, drum track tách riêng. *(NoteFall, WebGL-Piano)*
- [ ] Phát / tạm dừng / dừng / seek (timeline) / đếm nhịp trước khi vào. *(NoteFall)*
- [ ] **Tốc độ phát** (0.25× – 2× hoặc tự do) + **speed automation** theo thời gian. *(NoteFall)*
- [ ] **Loop A–B** rõ ràng (kéo 2 handle trên timeline, bật/tắt). *(Synthesia; NoteFall mới có trim)*
- [ ] **Offset / trim** đầu-cuối bài. *(NoteFall)*
- [ ] Chọn track: bật/tắt từng track, đổi màu, đổi instrument (nếu có SoundFont). *(NoteFall màu; Midiano đổi instrument)*
- [ ] **Tách tay trái/phải**: chọn track hoặc **auto-split theo pitch/time**; luyện từng tay (tay kia tự phát). *(Synthesia, Perfect Piano)*
- [ ] Metronome: BPM, time signature, âm lượng, accent nhịp 1, count-in bật/tắt. *(Perfect Piano, Synthesia)*
- [ ] Nhạc đệm: thêm 1 file audio (mp3/wav) đồng bộ với MIDI, chỉnh offset/volume/trim. *(NoteFall accompaniment — giữ)*
- [ ] Hiển thị tên bài, tổng thời lượng, số note, số track.

### A1.4. Visualizer
- [ ] Nốt rơi xuống bàn phím, tốc độ rơi tùy chỉnh (fall duration). *(NoteFall)*
- [ ] Nốt hướng xuống hoặc **hướng lên** (fallDirection). *(NoteFall)*
- [ ] Màu nốt: solid / gradient / random / theo track / **theo tay**. *(NoteFall)*
- [ ] Hiệu ứng: glow phím, hit line, particles, landing flash, bloom — bật/tắt từng cái + cường độ. *(NoteFall)*
- [ ] Camera: FOV, vị trí, lookAt; preset camera; khóa camera. *(NoteFall)*
- [ ] Background: màu, ảnh (fit/scale/offset/rotation/opacity). *(NoteFall)*
- [ ] Nhãn nốt: pitch (letter/solfège/scale degree), vị trí, cỡ, màu, outline. *(NoteFall + Synthesia)*
- [ ] **Keyframe** đổi thông số theo thời gian trên timeline (pin). *(NoteFall)*
- [ ] Fullscreen, ẩn UI khi chơi (idle fade). *(NoteFall)*
- [ ] FPS thấp / máy yếu: **fallback chế độ 2D nhẹ**. *(mới, cho mobile/máy cũ)*

### A1.5. Ghi & sửa
- [ ] Ghi phần chơi live (MIDI), count-in 4 nhịp, tự load lại vào editor khi dừng. *(NoteFall)*
- [ ] Lưu nhiều "take", nghe lại, xóa, đổi tên. *(NoteFall)*
- [ ] Sửa nốt trên canvas: thêm / xóa / di chuyển / đổi độ dài / split / velocity / hand / finger. *(NoteFall)*
- [ ] Undo/redo (≥50 bước). *(NoteFall)*
- [ ] Export MIDI (đúng tempo, pedal, track). *(NoteFall)*
- [ ] Export WAV (audio offline, không rớt mẫu). *(NoteFall)*
- [ ] Export video MP4/WebM (1080p mặc định, 4K tùy chọn) + **vertical 9:16** *(NoteFall 16:9; SeeMusic vertical)*

### A1.6. Quản lý file
- [ ] Project file (zip) lưu settings + MIDI + ảnh; mở lại đúng trạng thái. *(NoteFall `.nfz`)*
- [ ] Save / Save As / Open / Open Recent (File System Access + fallback). *(NoteFall)*
- [ ] Cảnh báo "chưa lưu" khi đóng tab / mở project khác. *(NoteFall)*
- [ ] **Preset**: lưu/lưu lại bộ style (visual + sound) dưới dạng JSON, import/export. *(pianoroll theme JSON, SeeMusic presets — NoteFall thiếu)*
- [ ] Kéo-thả file vào cửa sổ: `.mid`, project, ảnh, audio. *(NoteFall)*

### A1.7. UI/UX nền tảng
- [ ] Mở app là **chơi được ngay**: bàn phím + sound load sẵn, không đăng nhập, không modal chặn.
- [ ] Layout desktop ≥1024 px; có layout hẹp (tablet) tối thiểu. *(NoteFall chặn <1024 — cần nới)*
- [ ] Phím tắt: Space play/pause, ←/→ seek, R record, L loop, Esc thoát, ? trợ giúp.
- [ ] **Bảng phím tắt tùy chỉnh được** (remap). *(Synthesia keybind; NoteFall cố định)*
- [ ] Panel "Customize" có search, chia tab, mỗi mục có nút bật/tắt. *(NoteFall Inspector)*
- [ ] i18n: **vi** + en (NoteFall có en/ja → thêm vi). *(mới)*
- [ ] Dark theme mặc định + light theme. *(mới)*
- [ ] Toast/thông báo lỗi rõ ràng, không dùng `alert()`.
- [ ] Onboarding 3 bước: chọn input → mở MIDI → chơi.

## A2. P1 — Bổ sung ngay sau P0 (học/luyện + MIDI nâng cao)

- [ ] **Wait Mode** (Melody Practice): bài dừng chờ bấm đúng nốt; chord bấm bất kỳ thứ tự; tùy chọn "chờ hay tự đi sau X giây". *(Synthesia, Perfect Piano note pause)*
- [ ] **Rhythm Mode**: chạy theo nhịp, chấm timing.
- [ ] **Recital Mode**: chạy full, chấm note + timing + length.
- [ ] **Chấm điểm**: % note đúng, % timing, streak, hiển thị theo bar "đoạn yếu". *(Synthesia, Yousician, Piano Marvel)*
- [ ] **Sheet music**: import MusicXML (OSMD) hiển thị song song hoặc thay falling notes; cursor chạy theo nhạc; tùy chọn sinh sheet từ MIDI (VexFlow). *(Synthesia, SeeMusic, piano-app)*
- [ ] **Waterfall mode** (nốt rơi dạng thác, bám sát phím). *(Perfect Piano)*
- [ ] **Auto / Semi-auto play**: app tự chơi, hoặc chơi hộ tay đang không luyện. *(Perfect Piano, Synthesia)*
- [ ] **Gợi ý ngón tay** tự động (dynamic programming) + sửa tay + lưu vào project. *(piano-app, Synthesia)*
- [ ] **Nhãn nốt nâng cao**: số ngón, tên nốt, solfège (fixed/movable do), scale degree. *(Synthesia)*
- [ ] **Chord detection** realtime khi chơi tự do + hiển thị tên hợp âm. *(tembrica, Synthesia Free Play)*
- [ ] **Scale highlighting**: chọn key/scale, phím ngoài scale mờ đi. *(tembrica, RoxyPiano)*
- [ ] **SoundFont `.sf2`**: load file người dùng chọn, chọn instrument theo track (program change), fallback sample grand. *(RoxyPiano 128 GM, fonghtdev SoundFont)*
- [ ] **Đa timbre có sẵn**: Grand, Bright, Electric (Rhodes), Organ, Music Box, Synth pad, Harpsichord, Strings. *(Perfect Piano)*
- [ ] **Pitch bend** + modulation (wheel ảo + MIDI). *(synthio)*
- [ ] **MIDI output**: gửi note ra thiết bị/DAW; **lighted keyboard** (đèn phím sáng nốt sắp tới). *(Synthesia, Midiano)*
- [ ] **Bookmark / marker** trong bài + danh sách đoạn luyện. *(Synthesia)*
- [ ] **Transpose** đổi key toàn bài (không chỉ +/- 1). *(nhiều app)*
- [ ] **Độ khó**: tạo bản dễ từ MIDI (bỏ nốt thừa, giữ giai điệu/bass). *(Perfect Piano)*
- [ ] **Bàn phím 2 hàng / dual player / chord mode** cho màn hình hẹp. *(Perfect Piano)*
- [ ] **Độ rộng phím** điều chỉnh (key width), số phím hiển thị (25/49/61/76/88). *(Perfect Piano, austinrsands)*
- [ ] **Thư viện bài của tôi**: list project/bài đã mở, gắn cờ, sắp xếp, tìm kiếm. *(Synthesia song flags)*
- [ ] **PWA**: cài như app, chạy offline sau lần đầu. *(RoxyPiano)*
- [ ] **Export MIDI từ take ghi âm** với tên track, và **merge nhiều take**. *(mở rộng NoteFall)*
- [ ] **Metronome nâng cao**: tap tempo, subdivision (8th/16th), tiếng click khác nhau.
- [ ] **Chế độ luyện tập có mục tiêu**: đặt mục tiêu % đúng để qua đoạn. *(Melodics)*

## A3. P2 — Mở rộng

- [ ] **Mic detection** (nghe đàn piano thật qua microphone) — chấm nốt giai điệu, không cần MIDI. *(Simply Piano, Flowkey)*
- [ ] **Audio → MIDI** (upload mp3 → transcription → luyện). Basic Pitch / ByteDance ONNX. *(PianoViz, SeeMusic, Suma-Udd)*
- [ ] **Camera footage sync**: import video quay tay, tự align bàn phím, ghép nốt 3D lên trên. *(SeeMusic)*
- [ ] **Background video** + chroma key.
- [ ] **Curriculum**: lộ trình level 1→9, bài tập 5 ngón, scale, arpeggio, lý thuyết ngắn. *(Simply Piano, Piano Marvel)*
- [ ] **Sight-reading test (SASR-style)**: nhìn 20 giây rồi chơi, chấm %.
- [ ] **Gamification**: streak, XP, huy hiệu, weekly challenge. *(Yousician, Perfect Piano)*
- [ ] **Multiplayer / social**: phòng chơi chung, chat, leaderboard. *(Perfect Piano)*
- [ ] **Mobile app** (Capacitor/React Native wrapper hoặc PWA tối ưu) + force touch. *(Perfect Piano, SeeMusic)*
- [ ] **OMR**: đọc PDF/ảnh sheet nhạc → MusicXML. *(fonghtdev NoteFall, Piano Nova)*
- [ ] **Composer**: 2 staff editor, kéo nốt, in PDF. *(fonghtdev NoteFall)*
- [ ] **Cloud sync** (tùy chọn) — nhưng phải giữ nguyên tắc "không upload mặc định".
- [ ] **AI gợi ý luyện tập** dựa trên lịch sử lỗi.
- [ ] **Export video hàng loạt** (batch render nhiều bài).
- [ ] **Plugin/extension API** cho hiệu ứng nốt tùy biến.

## A4. Bổ sung từ nghiên cứu sâu (đợt 3 — files 20–24)

### P0 (làm cùng bản đầu)
- [ ] **Tiếng Việt mặc định** + setting chọn hệ tên nốt (chữ cái / Đô Rê Mi / movable do) — file 25.
- [ ] **Accessibility nền**: điều hướng bằng bàn phím toàn app, focus ring, `aria-live` cho vị trí/kết quả, tôn trọng `prefers-reduced-motion`, chế độ tương phản cao — file 20.8.
- [ ] **Release sample + pedal noise** rất nhỏ (bộ Salamander có sẵn) — file 22.3.
- [ ] **Limiter + headroom −6 dB** chống vỡ tiếng khi hợp âm dày — file 22.3.
- [ ] **Preset export theo nền tảng** (YouTube 1080p60 / TikTok 9:16 / Archive) + loudness −14 LUFS — file 23.3.
- [ ] **Đồng hồ + calibration** trước khi làm bất kỳ chấm điểm nào — file 16.1–16.2.

### P1
- [ ] **Chunk có tên** (tự phát hiện ranh giới câu/đoạn + lưu) — file 24.2.
- [ ] **Tempo ladder tự động** (+5 BPM sau 3 lần đạt; −5 khi <80%) — file 24.4.
- [ ] **Template phiên luyện** (khởi động / kỹ thuật / tiết mục / củng cố / ghi chú) + thuật toán chọn chunk — file 24.9.
- [ ] **Chấm điểm theo ô nhịp** + nút "luyện lại bar yếu" — file 16.4.4.
- [ ] **Chế độ nghe/hình dung** (phát mẫu, không bắt bấm) — file 24.6.
- [ ] **Ghi âm & so sánh A/B** với bản gốc — file 24.7.
- [ ] **Grid/snap + 24 fps + custom bitrate** trong export — file 23.2.
- [ ] **Khung 9:16** cho Shorts/TikTok — file 23.3.
- [ ] **One-hand mode** (app tự chơi tay còn lại) — file 20.8.
- [ ] **Search không dấu** + `Intl.Collator('vi')` + `Intl.NumberFormat` — file 25.3.

### P2
- [ ] **Chroma 12 màu theo pitch class** — file 07.5 (SeeMusic).
- [ ] **Preset style JSON** import/export — file 15.4.
- [ ] **Background video / camera footage sync** — file 21.3.
- [ ] **Đo LUFS chuẩn BS.1770** trong app — file 23.4.
- [ ] **"Mờ dần nốt rơi"** chống phụ thuộc falling notes — file 24.11.
- [ ] **Curriculum 9 level** với tiêu chí đo được — file 24.10.

## A5. Bổ sung từ nghiên cứu đợt 4 (files 26–30)

### P0 (phải có trước khi công bố)
- [ ] **Sample tự host** trên R2/Cloudflare Pages với prefix có version + header `immutable`, `audio/ogg`, CORS — file 26.2.
- [ ] **Giới hạn an toàn** khi nhập: zip `.nfz` ≤ 200 MB / 64 entry / 400 MB giải nén; MIDI ≤ 2 triệu event, chặn `../` — file 27.2.
- [ ] **CSP + `Permissions-Policy: midi=(self)`** + `nosniff` trên domain thật — file 26.5, 27.2.
- [ ] **Test + CI ngay từ Sprint 0**: Vitest + Playwright + size-limit; quality gates (coverage ≥60% cho `midi/`, `practice/`, `audio/`) — file 28.
- [ ] **Trang Credits/Licenses** (Salamander CC BY, font OFL, thư viện) + README nêu rõ "file không rời khỏi máy" — file 27.3–27.4.
- [ ] **Không telemetry mặc định**; báo lỗi do người dùng bấm gửi và xem trước nội dung — file 27.3, 28.10.

### P1
- [ ] **Audio snapshot test** bằng `OfflineAudioContext` (peak/RMS/duration) — file 28.3.
- [ ] **Visual regression** 5 trạng thái canvas (sau khi clock dừng, DPR=1) — file 28.6.
- [ ] **Báo lỗi dạng "mở GitHub Issue điền sẵn"** thay cho endpoint riêng — file 28.10.
- [ ] **Chế độ pedal đầy đủ CC64 0–127** + cảnh báo pedal không tương thích (FC3A/DP-10) — file 22.4, 26.

### P2
- [ ] **`security.txt` + chính sách báo lỗi** — file 27.5.
- [ ] **Kiểm tra hash sample** (SRI-like) khi tải từ CDN — file 27.1.
- [ ] **Trusted Types** nếu không vướng thư viện — file 27.2.

## A6. Bổ sung từ nghiên cứu đợt 5 (files 31–36)

### P0 (bắt buộc — đã thành "không thể bỏ")
- [ ] **Giải mã sample theo tầng** (không giải mã 480 file ≈ 550 MB) + giới hạn voice 64–96 — file 34.3.
- [ ] **Autosave 3 lớp** (localStorage settings / IDB phiên / nhắc xuất `.nfz`) + cảnh báo **Safari xoá sau 7 ngày** — file 33.5.
- [ ] **Đặc tả `.nfz` v1** với `formatVersion` + migration + MIDI là nguồn sự thật — file 33.2, 33.4.
- [ ] **Không truyền `sampleRate`** khi tạo AudioContext; xử lý `visibilitychange` (suspend/resume + kiểm tra `currentTime`) — file 36.2.
- [ ] **Chính sách nội dung**: không host nhạc; bộ bài khởi đầu chỉ gồm bản tự soạn + PD có provenance — file 35.3.
- [ ] **Ngân sách hiệu năng** (16.6 ms/frame; HUD cập nhật 10 Hz; không cấp phát trong loop) — file 34.1, 34.5.

### P1
- [ ] **Chế độ sheet nhẹ**: hiển thị PDF/ảnh + lật trang + mốc đồng bộ thời gian — file 32.5.
- [ ] **Nhập MusicXML/MXL** (nếu làm) → chuyển MIDI nội bộ ngay, sheet chỉ là lớp hiển thị — file 32.3.
- [ ] **Cấp đồ hoạ tự động** (cao/trung bình/thấp/tiết kiệm pin) — file 34.7.
- [ ] **FPS/debug HUD** + benchmark tự động trong CI — file 34.6.
- [ ] **Thông báo thiếu Web MIDI** thay vì im lặng — file 36.6.
- [ ] **Bộ sample nhẹ thay thế** (Upright Piano KW CC0 27 MB / Splendid Grand PD 77 MB) cho máy yếu — file 22 + 35.2.

### P2
- [ ] **`/transcribe` với Basic Pitch trong Worker** + UI sửa kết quả + nhãn "bản nháp" — file 31.
- [ ] **Ghi âm mic → MIDI** (đơn âm) — file 31, 16.
- [ ] **Editor MusicXML** — file 32.7 (rất đắt).
- [ ] **Đồng bộ qua thư mục cloud của người dùng** (không server) — file 33.6.
- [ ] **PWA iOS + kiểm thử silent switch / lock screen** — file 36.7.

---

# PHẦN B — CATALOGUE THÔNG SỐ TÙY CHỈNH

> Đây là danh mục đầy đủ. Cột "Có ở NoteFall" = key đã tồn tại trong `defaultSettings` (giữ nguyên, chỉ đổi UI). Cột "Cần thêm" = phải code mới.
> Tổng: NoteFall có **~300 key**; app mới nên có **~380–420** sau khi thêm.

## B1. Bàn phím (Keyboard)

| Thông số | Có ở NoteFall | Cần thêm |
|---|---|---|
| Vị trí bàn phím trên màn hình (Y, lens shift) | ✅ `keyboardScreenY` | — |
| Màu phím trắng / đen | ✅ `whiteKeyColor`, `blackKeyColor` | — |
| Màu gỗ (thân đàn) | ✅ `woodColor` | — |
| Độ sáng bàn phím | ✅ `keyboardBrightness` | — |
| Glow phím (bật, theo màu nốt, màu, cường độ, decay) | ✅ `keyGlow*` (5 key) | — |
| Nhãn phím (bật, chế độ C/all, format letter/letterOctave/solfège, accidental sharp/flat, size, opacity, offset, màu trắng/đen) | ✅ `keyLabels*` (9 key) | — |
| Số phím hiển thị (25/49/61/76/88) | ❌ | ✅ |
| Độ rộng phím (key width) | ❌ | ✅ |
| Single / Double row / Dual player / Chord mode | ❌ | ✅ (P1) |
| Độ lún phím theo velocity | ⚠️ shader nội bộ | ✅ exposed |
| Hiệu ứng nhấn phím (dip/retrigger) | ✅ `retriggerDip.ts` nội bộ | ✅ exposed |
| Hiển thị octave lines | ✅ `octaveLinesEnabled` | — |
| Bàn phím trong suốt / ẩn hẳn (chỉ nốt) | ❌ | ✅ |
| Vị trí đặt bàn phím (dưới/giữa/trên) | ⚠️ Y | ✅ preset |
| Màu viền phím / bo góc phím | ❌ | ✅ |

## B2. Nốt rơi (Notes)

**Hình học & chuyển động**
| Thông số | NoteFall | Cần thêm |
|---|---|---|
| Bật/tắt nốt | ✅ `notesEnabled` | — |
| Hướng rơi (xuống/lên) | ✅ `fallDirection` | — |
| Thời gian rơi (fall duration) | ✅ `fallDurationSec` | — |
| Độ rộng nốt | ✅ `noteWidthScale` | — |
| Độ dài tối thiểu | ✅ `noteMinLength` | — |
| Bo góc | ✅ `noteCornerRadius` | — |
| Hình dạng (gem/angled/round…) | ✅ `noteShape` | — |
| Khoảng cách giữa các nốt cùng phím (gap) | ⚠️ merge | ✅ |
| Nốt mờ dần khi tới hit line | ⚠️ | ✅ |
| Trailing effect (đuôi sáng) | ❌ | ✅ |

**Màu**
| Thông số | NoteFall | Cần thêm |
|---|---|---|
| Màu gốc | ✅ `noteColor` | — |
| Màu theo track | ✅ `trackColors{}` | — |
| Chế độ màu (solid/gradient/random/hand) | ✅ `noteColorMode` | ✅ thêm `pitchClass` (12 màu chroma), `scale` |
| Gradient: số stop, góc, độ mềm, 5 màu, 5 vị trí | ✅ (13 key) | — |
| Random: theo gì, seed, số màu, 5 màu | ✅ (8 key) | — |
| Màu tay trái/phải | ✅ `noteHandColorL/R` | — |
| Màu 12 pitch class (chroma) | ❌ | ✅ P1 |
| Độ bão hòa | ✅ `noteSaturation` | — |
| Opacity, emissive | ✅ | — |
| Preset màu (theme) | ⚠️ project | ✅ P1 |

**Vật liệu & ánh sáng (rất sâu — giữ nguyên)**
- `noteMaterial`, `noteSurface`, `noteBump`, `noteBumpScale/Depth/Softness/Melt/Scatter`
- bevel: `noteBevelWidth/Depth/Profile/Softness/Reflect`, `noteRimShade/Fade`, `noteRimBand*`, `noteRimGap*`
- light: `noteLightIntensity/Azimuth/Elevation`, `noteFillIntensity`, `noteAmbient`
- reflection: `noteReflectivity`, `noteSheen`, `noteTransparency`
- realistic: `noteAlbedoGain`, `noteSpecular`, `noteEmission`, `noteSurfaceContrast/Cells/Irregularity`
- pattern: `notePattern`, `notePatternScale/Density/Sharpness/Contrast/Brightness/Speed/Lock/Distortion/Amount/Drift/Knee/KneeSoftness/Ribbon`
- silk: `noteSilk/Scale/Speed`
- cloud: `noteCloud/Scale/Softness/Clear`
- highlight: `noteHighlight/Threshold/Softness`
- frost: `noteFrost/Grain/Scale/Veil`
- outline: `noteOutlineWidth/Brightness/Color/Blend/Reflect`
- merge: `noteMergeRadius/ColorSpread/…`
- texture: `noteTexture`, `noteTextureScale/Blur/Variation/Contrast/OffsetX/Y`, `noteAnimSpeedX/Y`

**Nhãn trên nốt**
- ✅ `noteLabelsEnabled`, `noteLabelContent`, `noteLabelFormat`, `noteLabelAccidental`, `noteLabelSize/Color/Opacity/OutlineWidth/OutlineColor/Position/Offset`
- ✅ thêm (P1): số ngón tay hiển thị trên nốt, ký hiệu tay L/R.

## B3. Hiệu ứng (Effects)

| Nhóm | Thông số NoteFall | Cần thêm |
|---|---|---|
| Hit line | `hitLineEnabled`, `hitLineColor`, `hitLineIntensity`, `hitLineThickness`, wave (enabled/intensity/amplitude/scale/scrollSpeed/morphSpeed/thickness/grain), `hitLineBarY`, `hitLineWaveY`, `hitLineBarHalo`, `hitLineWaveHalo` + `HIT_LINE_COLOR_DEFAULTS` | Kiểu hit line (bar/wave/none) chọn nhanh |
| Landing flash | `flashEnabled`, `flashFollowNote`, `flashBrightness/Intensity/Size/Width/HaloWidth/Color` | — |
| Particles | `particlesEnabled`, `particleBlending`, `particleDotCount/Size/Opacity/Brightness`, `particleLife`, `particleRise`, `particleSpread`, `particleEmitterWidth`, flow (strength/X/Y/Z/octaves/octaveScale/octaveGain/frequency/evolution/follow), `particleLaunchSpeed/RandomDirection/RandomSpeed/AirFriction/GravityCurl/Twirl/TwirlVariance/MotionTrail`, `particleRaysEnabled/Length/Opacity/Angle/Spread`, `particleFogEnabled/Count/Opacity`, `particleColorFollowNote/Color` | Preset hạt (smoke/spark/hybrid) *(piano-visualizer-classic)* |
| Bloom | `bloomEnabled/Intensity/Threshold/Radius/Smoothing` | — |
| Note death FX | nội bộ `noteDeathFx.ts` | ✅ exposed (kiểu biến mất) |
| Saber / beam | ❌ | ✅ P2 *(SeeMusic)* |
| Background media | `backgroundColor`, `backgroundImageFit/Opacity/Scale/OffsetX/Y/Rotation` | ✅ video background P1 |
| Khác | — | Grain / vignette / chromatic aberration / motion blur toàn cảnh |

## B4. Camera & Scene

| Thông số | NoteFall | Cần thêm |
|---|---|---|
| FOV | ✅ `cameraFov` | — |
| Vị trí camera | ✅ `cameraPos` | — |
| Look at | ✅ `cameraLookAt` | — |
| Giới hạn camera | ✅ `cameraLimits.ts` | ✅ UI chỉnh |
| Preset góc nhìn | ❌ | ✅ (top / nghiêng / cận cảnh phím / toàn cảnh) |
| Camera animation theo thời gian | ✅ keyframe | ✅ preset chuyển động (zoom in/out, pan) |
| Hands ảo | ✅ `handsEnabled`, `handsBrightness`, `handsFlashLight`, `handsMotionBlur`, `handsBlurSamples` | ✅ chọn kiểu tay, skin tone, tay trái/phải riêng |
| Aspect ratio khung hình | ⚠️ 16:9 cố định | ✅ 16:9 / 9:16 / 1:1 / 4:5 |
| FPS mục tiêu (30/60/120) | ⚠️ `previewHighFps` | ✅ |

## B5. Âm thanh (Sound)

| Thông số | NoteFall | Cần thêm |
|---|---|---|
| Volume master | ✅ `volume` | — |
| Volume MIDI (bài) | ✅ `midiVolume` | — |
| Volume từng track | ❌ | ✅ |
| Bật/tắt MIDI input | ✅ `midiEnabled` | — |
| Playback rate | ✅ `playbackRate` | — |
| Pedal bật/tắt | ✅ `pedalEnabled` | — |
| Reverb: bật, dry, wet, size, decayTime, decay, preDelay, damping, HiCut, LowCut | ✅ (10 key) | ✅ chọn impulse (room/hall/plate/church) |
| Release time | ✅ `releaseTime` | — |
| Detune | ✅ `samplerDetune` | — |
| EQ 6 bands | ✅ `eqBands` | ✅ thêm band / EQ curve UI |
| Velocity curve | ✅ `velocityCurve` | ✅ preset (linear/soft/hard/fixed) |
| Velocity compensation | ✅ `velocityCompensation` | — |
| Transpose | ✅ `transpose` | ✅ transpose theo track |
| Instrument / timbre | ❌ | ✅ 8 timbre + SoundFont P1 |
| Chọn sample set | ⚠️ 1 bộ | ✅ Salamander / GeneralUser / khác |
| Stereo width / pan | ❌ | ✅ |
| Compressor / limiter | ⚠️ export có limiter | ✅ exposed |
| Chorus / delay | ❌ | ✅ P2 |
| Sympathetic resonance / string resonance | ❌ | ✅ P2 (khó, cần model) |
| Half-pedal curve | ⚠️ `pedalDepth.ts` | ✅ UI chỉnh |
| Tiếng metronome (âm, volume, accent) | ⚠️ click cố định | ✅ |
| Latency compensation (ms) | ❌ | ✅ quan trọng cho người chơi khó tính |
| Audio output device chọn | ❌ | ✅ (setSinkId) |

## B6. Timeline & Playback

| Thông số | NoteFall | Cần thêm |
|---|---|---|
| MIDI offset | ✅ `midiOffsetSec` | — |
| Trim start / end (MIDI) | ✅ `midiTrimStartSec/EndSec` | — |
| Trim audio | ✅ `userAudioTrimStartSec/EndSec` | — |
| Audio offset / volume | ✅ `userAudioOffsetSec/Volume` | ✅ audio EQ, loop |
| Speed automation | ✅ `midiSpeedAutomation` + Y range/center | ✅ preset (ritardando, accelerando) |
| Loop A-B | ⚠️ trim | ✅ loop riêng, loop count, "pre-roll" |
| Bookmark | ⚠️ keyframe pins | ✅ marker riêng có tên |
| Timeline editor mở/đóng, lane scale/ratios | ✅ (6 key) | — |
| Theo playhead | ✅ `followPlayhead` | — |
| Snap / grid | ❌ | ✅ (theo beat/bar/0.1s) |
| Zoom timeline | ⚠️ lane scale | ✅ zoom ngang |
| Count-in | ⚠️ cố định 100BPM 4 nhịp | ✅ BPM/nhịp tùy chỉnh |

## B7. Chấm điểm & luyện tập (P1)

| Thông số | Cần thêm |
|---|---|
| Chế độ: Wait / Rhythm / Recital / Free | ✅ |
| Ngưỡng "đúng" (timing window ms) | ✅ (dễ/chuẩn/khắt khe) |
| Chấm velocity? (có/không) | ✅ |
| Chấm note length (staccato/legato) | ✅ |
| Điểm tối đa / thang điểm | ✅ |
| Cho phép bỏ qua nốt (skip) | ✅ |
| Tự động chậm khi sai nhiều | ✅ |
| Số lần thử / reset | ✅ |
| Hiển thị lỗi theo màu (xanh/đỏ/vàng) | ✅ |
| Báo cáo sau khi chơi (bar yếu, % từng tay) | ✅ |
| Lưu lịch sử luyện tập | ✅ (local) |

## B8. Ghi âm & Export

| Thông số | NoteFall | Cần thêm |
|---|---|---|
| Định dạng audio: WAV / MP3 / FLAC | WAV | ✅ MP3 (lamejs/wasm), FLAC |
| Sample rate / bit depth | ⚠️ theo context | ✅ 44.1/48k, 16/24-bit |
| Video container: MP4 / WebM / MOV | MP4, WebM | ✅ MOV (nếu encoder hỗ trợ) |
| Codec video: H.264 / HEVC / VP9 / AV1 | H.264, VP9, AV1 | ✅ HEVC (hardware) |
| Codec audio: AAC / Opus / PCM | AAC, Opus | ✅ |
| Resolution: 720p/1080p/1440p/4K + custom | ✅ | ✅ |
| FPS: 24/30/60/120 | ✅ | ✅ 24 |
| Bitrate / quality (CRF) | ✅ quality option | ✅ bitrate thủ công |
| Aspect: 16:9 / 9:16 / 1:1 | 16:9 | ✅ |
| Khoảng render (toàn bài / loop / A-B) | ⚠️ toàn bài | ✅ |
| Watermark | ❌ (không có) | giữ không watermark |
| Batch export | ❌ | ✅ P2 |
| Background render (không chặn UI) | ⚠️ modal | ✅ |

## B9. Ứng dụng / Hệ thống

| Thông số | NoteFall | Cần thêm |
|---|---|---|
| Ngôn ngữ (vi/en/ja/zh…) | en, ja | ✅ vi |
| Theme UI (dark/light/auto) | dark | ✅ light |
| Cỡ chữ UI / mật độ | ❌ | ✅ |
| Phím tắt tùy chỉnh | ❌ cố định | ✅ remap |
| Bàn phím mapping (phím nào = nốt nào) | ⚠️ cố định `pcInput.ts` | ✅ remap + preset (AZERTY, QWERTY, Dvorak) |
| Layout: bàn phím máy tính ↔ nốt | ⚠️ | ✅ octave offset, số octave |
| Autosave | ❌ (explicit) | ✅ tùy chọn (off mặc định) |
| Telemetry | ✅ opt-out | ✅ off mặc định (tốt hơn) |
| Thông báo / toast | ✅ | — |
| Cache sample (xoá / preload toàn bộ) | ⚠️ | ✅ UI quản lý cache |
| Giới hạn undo | 50 | ✅ tùy chỉnh |
| Export/Import toàn bộ settings | ❌ | ✅ JSON (preset) |
| Reset settings (giữ key ngoài Inspector) | ✅ | ✅ |

## B10. Ưu tiên "tùy chỉnh được hầu hết thông số" — cách làm

Yêu cầu của người dùng: **"tùy chỉnh được hầu hết thông số tùy ý"**. Cách hiện thực:

1. **Mọi setting là 1 key trong store**, có type rõ ràng, có default, được serialize vào project + preset.
2. **Inspector tự sinh UI** từ schema (number slider, color picker, select, toggle) → thêm setting mới chỉ cần khai báo 1 dòng, không viết UI tay.
3. **Search xuyên tab** (NoteFall đã có) + hiển thị key kỹ thuật (advanced mode).
4. **Preset/JSON import-export** để chia sẻ cấu hình.
5. **Keyframe** cho mọi key "animatable" (NoteFall đã phân loại `isAnimatableKey`).
6. **URL hash** chia sẻ cấu hình nhanh (P2).
7. **Console/dev panel** (NoteFall có `lil-gui` trong dev) expose toàn bộ settings khi dev.

---

# PHẦN C — TIÊU CHÍ HOÀN THÀNH (Definition of Done)

## P0 xong khi:
- [ ] Mở app → bấm phím máy tính nghe tiếng đàn trong < 2 giây, độ trễ cảm nhận ≤ 30 ms.
- [ ] Cắm USB MIDI keyboard → chơi có velocity + pedal, không nuốt note, không click/pop.
- [ ] Kéo 1 file `.mid` bất kỳ → phát đúng, đúng tempo, đúng track, có pedal.
- [ ] Loop A-B + đổi tốc độ + tách tay hoạt động, không lệch hình/tiếng.
- [ ] Ghi 1 take → sửa vài nốt → export MIDI + WAV + MP4 1080p, mở lại project đúng trạng thái.
- [ ] Tùy chỉnh ≥ 250 thông số qua UI, search được, lưu vào preset.
- [ ] Không crash khi tab nền, khi đổi thiết bị MIDI, khi mở MIDI lớn (≥ 50k note).
- [ ] Chạy được trên Chrome + Edge (Web MIDI), Firefox + Safari (fallback không MIDI).

## P1 xong khi:
- [ ] Wait Mode + chấm điểm hoạt động với MIDI, hiển thị % đúng/sai theo bar.
- [ ] MusicXML mở được, cursor chạy khớp nhạc + nốt rơi.
- [ ] SoundFont `.sf2` load được, đổi instrument theo track.
- [ ] Gợi ý ngón tay tự động + sửa được + lưu vào project.
- [ ] PWA cài được, chạy offline.
