# 11 — Lộ trình thực hiện (sau khi nghiên cứu)

> Mục tiêu giai đoạn 1: **một app web chơi piano thật trên máy tính**, tùy chỉnh MIDI và thông số tự do, ổn định để dùng hàng ngày. Sau đó mới mở rộng.
> Ước lượng thời gian theo "ngày công của 1 người có kinh nghiệm React/TS", dùng AI hỗ trợ.

## Giai đoạn 0 — Chuẩn bị (0.5–1 ngày)

- [ ] Quyết định chiến lược giấy phép (file 10, mục 10.1) — ghi vào README.
- [ ] Clone NoteFall vào repo riêng (`notefall-base`), giữ LICENSE + Required Notice.
  - Nếu chọn **tự dựng** thay vì fork (D5, file 30.3): theo kiến trúc file 10 + bản đồ code file 15, và dựng test/CI ngay từ đầu theo **file 28.7**.
- [ ] `npm install`, chạy `npm run dev`, chạy thử: mở MIDI, chơi live, export 1 video.
- [ ] Tự host sample Salamander (`fetch-salamander` + `prepare-salamander`), bỏ phụ thuộc R2 của tác giả.
  - Cách làm + chi phí + header CORS/cache: **file 26.2–26.4** (R2 egress $0, 77 MB/bộ sample, prefix có version).
- [ ] Tắt/bỏ PostHog analytics + feedback endpoint hoặc trỏ về backend riêng.
  - Đồng thời áp checklist bảo mật **file 27.7** (giới hạn zip/MIDI, CSP, `Permissions-Policy: midi=(self)`).
- [ ] Đổi branding, thêm `vi` vào i18n.
- **Xong khi:** app chạy local, chơi được bằng phím máy tính + USB MIDI, mở/ghi/export được.

## Giai đoạn 1 — "Chơi thật trên máy tính" (P0) (4–6 tuần)

### 1.1. Input & cảm giác chơi (1 tuần)
- [ ] Rà soát và hoàn thiện: mapping phím máy tính (cho phép remap), velocity từ vị trí click, glide/glissando.
- [ ] Trang **Settings → Input**: chọn thiết bị MIDI, test, hiển thị latency ước lượng, cảnh báo Bluetooth.
- [ ] **Calibrate latency** wizard (đo bằng cách bấm theo metronome rồi bù).
- [ ] Trạng thái "sẵn sàng chơi" rõ ràng (sample đã load, context đã resume).

### 1.2. Bàn phím & hiển thị (1 tuần)
- [ ] Số phím hiển thị (25/49/61/76/88), độ rộng phím, chế độ chỉ-nốt-đang-bấm.
- [ ] Preset camera (top/nghiêng/cận cảnh/toàn cảnh) + aspect 16:9/9:16/1:1.
- [ ] Fallback 2D nhẹ khi máy yếu / màn hình nhỏ (bước đầu của mobile).
- [ ] Tùy chọn ẩn bàn phím 3D → chỉ nốt + hit line (chế độ "video sạch").

### 1.3. MIDI playback tùy chỉnh (1.5 tuần)
- [ ] Loop A–B có UI rõ (2 handle + phím L), loop count, pre-roll.
- [ ] Marker/bookmark có tên, nhảy nhanh, lưu vào project.
- [ ] Tách tay tự động + luyện từng tay (tay kia tự phát).
- [ ] Transpose theo key có tên; hiển thị key hiện tại.
- [ ] Metronome đầy đủ (BPM, time signature, subdivision, accent, count-in tùy chỉnh).
- [ ] Chọn/bật-tắt từng track, volume/pan per track.

### 1.4. Tùy chỉnh thông số (1.5 tuần)
- [ ] Refactor Inspector → **schema-driven** (file 10.5), migrate toàn bộ key hiện có.
- [ ] Thêm ~60–80 key mới (file 09, Phần B: những dòng "Cần thêm" ở P0).
- [ ] **Preset JSON**: lưu/import/export bộ style; preset mặc định (Cinematic / Minimal / Classic / Neon).
- [ ] Advanced mode: hiện key kỹ thuật + copy/paste giá trị.

### 1.5. Ghi & export (1 tuần)
- [ ] Export MP3 + FLAC (ngoài WAV).
- [ ] Export video theo aspect + khoảng render (loop) + bitrate thủ công.
- [ ] Export MIDI chuẩn (tempo, pedal, tên track).
- [ ] Quản lý takes: đổi tên, xoá, nghe lại, merge.

### 1.6. Ổn định (0.5 tuần)
- [ ] Test: MIDI 50k note, tab nền, rút/cắm MIDI giữa lúc chơi, mở project cũ.
- [ ] Kiểm tra Safari/Firefox fallback (không MIDI), Chrome/Edge full.
- [ ] Đo FPS trên máy yếu; giảm particle nếu cần.
- **Xong khi:** đạt "Definition of Done P0" ở file 09 Phần C.

## Giai đoạn 2 — "Luyện tập thật sự" (P1) (6–8 tuần)

### 2.1. Practice engine (2 tuần)
- [ ] `practice/` module: state machine Wait/Rhythm/Recital/Free.
- [ ] Wait Mode chính xác với chord, note lặp, pedal.
- [ ] Scoring: note/timing/length, cửa sổ thời gian cấu hình, per-bar report.
- [ ] Feedback trực quan: phím xanh/đỏ, hit line pulse, đếm streak.
- [ ] Session history + biểu đồ tiến bộ (local).

### 2.2. Sheet music (2 tuần)
- [ ] Import MusicXML, render OSMD, cursor đồng bộ, chuyển trang.
- [ ] Chế độ hiển thị: chỉ nốt rơi / chỉ sheet / cả hai.
- [ ] Màu nốt xanh-đỏ khi luyện (OSMD note coloring).
- [ ] Sinh sheet đơn giản từ MIDI (VexFlow) — mức cơ bản, có cảnh báo độ chính xác.

### 2.3. Âm thanh đa dạng (1.5 tuần)
- [ ] 8 timbre có sẵn (Grand/Bright/Rhodes/Organ/Music Box/Synth Pad/Harpsichord/Strings).
- [ ] SoundFont `.sf2` loader + chọn instrument theo track (program change).
- [ ] Pitch bend + modulation; MIDI output cho lighted keyboard.

### 2.4. Học & gợi ý (1.5 tuần)
- [ ] Gợi ý ngón tay DP + sửa tay + lưu.
- [ ] Chord detection realtime + hiển thị; scale highlighting.
- [ ] Nhãn nâng cao: số ngón, tên nốt, solfège, scale degree.
- [ ] Bản dễ/khó tự sinh (bỏ nốt ngoài, giữ giai điệu + bass).

### 2.5. Sư phạm & tiếng Việt (1.5 tuần)
- [ ] **Chunk có tên** + tự phát hiện ranh giới câu/đoạn (file 24.2).
- [ ] **Tempo ladder** tự động (+5 BPM sau 3 lần đạt) + thang tempo trực quan (file 24.4).
- [ ] **Template phiên luyện** + chọn chunk theo điểm yếu (file 24.9).
- [ ] **Hệ tên nốt** chữ cái / Đô Rê Mi / movable do + nhãn phím theo hệ (file 25.2).
- [ ] Rà toàn bộ UI tiếng Việt: chuỗi dài, dấu, `Intl.*`, search không dấu (file 25.3–25.5).
- [ ] **Accessibility**: bàn phím toàn app, `aria-live`, reduced-motion, high contrast (file 20.8).

### 2.6. PWA & thư viện (1 tuần)
- [ ] PWA installable + offline (cache app + sample).
  - Chiến lược cache (shell / sample / update flow / tránh cache sai): **file 26.6**.
- [ ] Thư viện bài của tôi: list, gắn cờ, tìm kiếm, sắp xếp, mở nhanh.
- [ ] Layout tablet (768–1024 px).
- **Xong khi:** đạt "Definition of Done P1".

## Giai đoạn 3 — Mở rộng (P2, chọn theo nhu cầu)

| Hạng mục | Công | Ghi chú |
|---|---|---|
| Audio → MIDI (Basic Pitch ONNX) | 1–2 tuần | Cần WASM/WebGPU, hậu xử lý pedal |
| Mic detection cho đàn cơ | 3–6 tuần | Khó, độ chính xác phụ thuộc phòng; nên làm "melody only" trước |
| Camera footage sync | 2–3 tuần | Auto-align bàn phím trong video (computer vision) |
| Curriculum + bài học | 4–8 tuần | Cần nội dung (bản quyền), không chỉ code |
| Multiplayer / social | 4+ tuần | Cần backend, auth, moderation |
| Mobile app (Capacitor) | 2–4 tuần | Force touch, layout dọc |
| OMR (PDF → MusicXML) | 3–6 tuần | Audiveris/ONNX, chất lượng đầu vào quan trọng |
| Composer 2 staff | 3–4 tuần | VexFlow editor + in PDF |

## Giai đoạn 4 — Hoàn thiện sản phẩm

- [ ] Onboarding tương tác (chọn input → mở MIDI → chơi → luyện).
- [ ] Tài liệu người dùng tiếng Việt + video ngắn.
- [ ] Trang landing, hướng dẫn cài (PWA/desktop wrapper).
- [ ] Đóng gói desktop bằng **Tauri** (~10 MB, nhẹ hơn Electron, dùng WebView2/WebKit) nếu cần bản offline thật.
- [ ] Đánh giá giấy phép lần cuối trước khi publish.

## Nguyên tắc quản lý dự án

1. **Mỗi giai đoạn phải chơi được** — không có "big bang refactor". Sau mỗi tuần app vẫn chạy.
2. **Test bằng 3 file MIDI thật**: 1 bài cổ điển nhiều track, 1 bài pop 2 tay + pedal, 1 file "xấu" (note chồng, tempo đổi liên tục).
3. **Không thêm tính năng khi P0 chưa ổn định** — cám dỗ lớn nhất là nhảy sang sheet music/AI quá sớm.
4. **Đo trước khi tối ưu**: FPS, latency, thời gian load sample, thời gian render video.
5. **Ghi lại quyết định** (ADR ngắn trong `docs/decisions/`) để sau này không cãi lại chính mình.

## Ghi chú liên kết

- **Backlog cắt nhỏ theo sprint + ước lượng từng task**: file **29** (Sprint 0–5, ~30 ngày công, Definition of Done, checklist dễ bỏ sót).
- **Thứ tự ưu tiên khi thiếu thời gian** và **5 câu hỏi cần chốt trước khi code**: file **29.8 / 29.11** và **30.6**.
- **Test/CI phải dựng ngay Sprint 0**, không để sau: file **28**.
- **Bảo mật & quyền riêng tư** không phải việc "làm sau": file **27**.
- **Hiệu năng & bộ nhớ**: ngân sách + chiến lược giải mã sample: file **34**.
- **Lưu trữ & định dạng project**: đặc tả `.nfz`, autosave, migration: file **33**.
- **Nội dung & bản quyền**: chính sách "không host nhạc", nguồn MIDI hợp pháp: file **35**.
- **iOS/Safari**: nếu mở rộng mobile, đọc **36** trước khi hứa tính năng.
- **Tính năng nâng cao**: transcription (**31**) và sheet/MusicXML (**32**) đều đã có ước lượng công sức.
