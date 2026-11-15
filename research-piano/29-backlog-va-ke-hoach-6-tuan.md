# 29 — Backlog chi tiết & kế hoạch 6 tuần

> File 11 cho roadmap theo giai đoạn. File này **cắt nhỏ thành task** có ước lượng, để bắt đầu code được ngay khi được phép. Mọi ước lượng tính theo **ngày công 1 người**, đã bao gồm test cơ bản.

## 29.1. Nguyên tắc cắt phạm vi cho v1

**v1 phải làm được 4 việc, không hơn:**
1. Mở file MIDI bất kỳ → phát đúng, mượt.
2. Chơi bằng bàn phím máy tính / MIDI USB → nghe thật, độ trễ thấp.
3. Chỉnh được tempo, âm lượng từng tay, loop, tốc độ, màu, camera — **lưu vào project**.
4. Xuất WAV (và MIDI sau khi sửa).

**v1 KHÔNG làm:** video export, chấm điểm, thư viện bài, mobile, i18n, sheet music, AI.

## 29.2. Sprint 0 — Nền móng (4–5 ngày)

| # | Task | Ước lượng | Định nghĩa hoàn thành |
|---|---|---|---|
| S0.1 | Fork NoteFall (hoặc `create-vite` nếu tự làm), chạy `npm ci`, `npm run dev` | 0.5 | App chạy local, không lỗi console |
| S0.2 | Dọn dẹp: xoá analytics/feedback, đổi tên app, xoá route không dùng | 1 | grep không còn endpoint ngoài |
| S0.3 | Dựng Vitest + Playwright + ESLint + `tsc -b` | 1 | CI xanh với 1 test mẫu |
| S0.4 | Tách `samples` khỏi `samples.notefall.app` → `/public/samples` (v9 trước) | 1 | Chạy offline được |
| S0.5 | `OfflineAudioContext` test đầu tiên (render 2 giây) | 0.5 | Hash ổn định giữa 2 lần chạy |
| S0.6 | Đo baseline: FPS, bundle size, thời gian mở 1 file MIDI | 0.5 | Số liệu ghi vào `docs/baseline.md` |

**Rủi ro:** NoteFall có thể phụ thuộc asset/API nội bộ → kiểm tra ngay S0.2; nếu vướng nhiều, cân nhắc tự dựng (file 10).

## 29.3. Sprint 1 — MIDI chắc (5 ngày)

| # | Task | Ước lượng |
|---|---|---|
| S1.1 | Viết `midi/parse` của mình (hoặc bọc thư viện) + giới hạn an toàn (file 27) | 1.5 |
| S1.2 | Bộ 12 fixture MIDI + 20 unit test (tempo map, vel 0, overlap, drum, note treo) | 1.5 |
| S1.3 | Import drag&drop + báo lỗi rõ ràng (file 19.8) | 0.5 |
| S1.4 | Hiển thị thông tin bài: track, số nốt, độ dài, tempo range | 0.5 |
| S1.5 | Sửa lỗi hình học khi tempo đổi (nốt không nhảy sai) | 1 |

**Kiểm chứng:** mở được 12 file, không file nào treo > 1 s; round-trip parse→export giữ nguyên số nốt.

## 29.4. Sprint 2 — Chơi thật, độ trễ thấp (5 ngày)

| # | Task | Ước lượng |
|---|---|---|
| S2.1 | Keyboard mapping chuẩn + octave shift + velocity từ độ dài phím | 1 |
| S2.2 | Web MIDI input (hot-plug, CC64, CC1, velocity, pitch bend) + fallback | 1 |
| S2.3 | Đo & hiển thị latency (`outputLatency + baseLatency`), nút calibrate | 0.5 |
| S2.4 | Preload sample theo tầng ưu tiên (shell → v8 → phần còn lại) | 1 |
| S2.5 | Chống "note treo": panic, mất focus, đổi tab | 0.5 |
| S2.6 | Test: fake MIDI → engine nhận đúng, panic xoá hết | 1 |

**Kiểm chứng:** trên máy thật, bấm phím → nghe < 30 ms; rút MIDI không treo nốt.

## 29.5. Sprint 3 — Điều khiển & cấu hình (6 ngày)

| # | Task | Ước lượng |
|---|---|---|
| S3.1 | Đồng hồ + seek + play/pause/stop + loop A–B | 1.5 |
| S3.2 | `speedMap` (tempo ramp tuyến tính) + `speed` slider | 1 |
| S3.3 | Volume/pan/mute/solo theo track + "tay trái/phải" | 1 |
| S3.4 | Inspector: màu nốt, phím, nhãn tên nốt, hướng rơi, hiển thị phím đàn | 1 |
| S3.5 | Settings: lưu localStorage + presets + reset | 0.5 |
| S3.6 | Test: `timeToSong(songToTime(t)) ≈ t`, loop không lệch | 1 |

## 29.6. Sprint 4 — Project & export (5 ngày)

| # | Task | Ước lượng |
|---|---|---|
| S4.1 | `project.json` schema + validate + `appVersion` | 1 |
| S4.2 | Export/Import `.nfz` (zip, giới hạn an toàn) | 1.5 |
| S4.3 | Autosave IndexedDB + phục hồi sau crash | 0.5 |
| S4.4 | Export WAV bằng `OfflineAudioContext` + progress (file 22.10) | 1.5 |
| S4.5 | Export MIDI sau khi sửa (round-trip) | 0.5 |

## 29.7. Sprint 5 — Đánh bóng & phát hành (5 ngày)

| # | Task | Ước lượng |
|---|---|---|
| S5.1 | Polish UI theo tokens (file 20): trạng thái rỗng, loading, tooltip, focus | 1.5 |
| S5.2 | Phím tắt đầy đủ + dialog "?" + không xung đột phím đàn | 1 |
| S5.3 | A11y: focus visible, `aria-live` cho phát/dừng, contrast | 1 |
| S5.4 | Trang Credits/license + README trung thực (file 27.4) | 0.5 |
| S5.5 | Deploy (file 26) + smoke test production + 3 máy thật | 1 |

**Tổng: ~30 ngày công ≈ 6 tuần** cho 1 người làm bán thời gian (hoặc 3 tuần toàn thời gian).

## 29.8. Thứ tự ưu tiên nếu thiếu thời gian

Nếu chỉ có **2 tuần**, làm: S0.1–S0.4, S1.1–S1.3, S2.1–S2.4, S3.1, S3.4, S3.5, S4.1. Đó là "mở MIDI, phát, chỉnh màu, chơi được" — đủ để dùng thật.

Bỏ được mà không chết: export MIDI, presets, autosave, trang Credits (không nên bỏ license nhưng có thể để dạng text trong README).

## 29.9. Định nghĩa "xong" (Definition of Done) cho mọi task

1. Có code + type đúng, `tsc` sạch.
2. Có test (unit hoặc e2e) hoặc lý do rõ ràng tại sao không.
3. Không thêm dependency mới mà không ghi vào `docs/deps.md` + license.
4. Không làm tăng bundle quá 20 KB gzip mà không bàn.
5. Có mô tả ngắn trong PR (tiếng Việt) + ảnh/GIF nếu là UI.
6. Nếu đổi hành vi người dùng → cập nhật tài liệu tương ứng trong `research-piano/` hoặc `docs/`.

## 29.10. Những việc dễ bị bỏ sót (đừng quên)

- **Bàn phím đàn trên màn hình phải bấm được bằng chuột/cảm ứng** và có phản hồi thị giác ngay.
- **Nốt đang phát phải sáng** trên phím đàn (kể cả nốt do MIDI file phát).
- **Nốt do người dùng chơi** phải hiện khác nốt của bài (màu/viền).
- **Dừng phát phải tắt hết nốt** và trả pedal về 0.
- **Đổi tempo khi đang phát** không làm hình nhảy.
- **Chuyển tab trình duyệt** rồi quay lại: đồng hồ không nhảy vọt.
- **File MIDI có 1 nốt duy nhất dài 10 phút**: vẫn hiển thị đúng.
- **Màn hình nhỏ 1280×720**: inspector không che bàn phím.
- **Tiếng Việt có dấu** trong tên file và tên bài: không lỗi.
- **Người dùng xoá sample trong cache**: app tự tải lại.

## 29.11. Câu hỏi cần người dùng quyết trước khi code

1. **Fork NoteFall hay tự dựng?** (PolyForm Shield: chỉ dùng cá nhân/phi thương mại; nếu muốn thương mại → tự dựng theo file 10/15).
2. **Có cần mobile trong v1?** (khuyến nghị: không).
3. **Có cần tiếng Việt ngay từ đầu?** (khuyến nghị: có, vì chi phí thấp nếu làm từ đầu — file 25).
4. **Có cần video export trong v1?** (khuyến nghị: không, để v2).
5. **Sample: tự host 77 MB?** (khuyến nghị: có, R2 miễn phí egress — file 26).
