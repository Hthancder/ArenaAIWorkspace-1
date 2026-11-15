# AI-START-HERE — đọc file này trước (≈2 phút)

Bạn là AI coding agent. Nhiệm vụ: **clone ra một web app piano 3D hoàn chỉnh, đẹp, đủ tính năng, tiếng Việt** từ bộ tài liệu trong thư mục này.
Đây là **đặc tả**, không phải repo code. Bạn viết code từ đầu (trừ khi người dùng chọn fork NoteFall).

## 1. Sản phẩm

Web app chạy 100% trên trình duyệt: mở file MIDI → nốt rơi 3D → chơi thật bằng bàn phím máy tính hoặc đàn MIDI USB (độ trễ thấp) → chỉnh gần như mọi tham số → sửa nốt trên piano roll → luyện tập có chấm điểm → lưu project `.nfz` → xuất WAV/video.
**Không backend, không tài khoản, không upload, không telemetry.** Tiếng Việt mặc định.

**Stack chốt:** Vite + React 19 + TypeScript strict + three.js (@react-three/fiber, drei) + zustand + Tailwind (layout) + CSS var (token) + Vitest + Playwright.

## 2. Đọc gì, theo thứ tự

| Bước | File | Vì sao |
|---|---|---|
| 1 | `41-cach-ai-doc-bo-tai-lieu-nay.md` | 12 luật, thứ quyền, định nghĩa "xong" |
| 2 | `45-build-brief-thi-hanh.md` | Milestone M0–M6 + tiêu chí nghiệm thu |
| 3 | `spec/design-tokens.json` · `spec/app-spec.json` | Dữ liệu máy đọc |
| 4 | `44-hop-dong-du-lieu-va-kien-truc-module.md` | Types + cây thư mục + bất biến |
| 5 | `43` (thiết kế) → `42` (màn hình) | Làm UI |
| 6 | File chủ đề của milestone | `41.2` có bảng |

## 3. Mười luật không được vi phạm

1. Không bịa số liệu — thiếu thì `TODO(spec)`.
2. Không đổi tên type trong `44`.
3. Mọi màu/khoảng cách lấy từ token, không hex rời.
4. Nốt nhạc = MIDI tick + tempo map; view chỉ đọc.
5. Một nguồn thời gian duy nhất (`audio/clock`).
6. Không CDN `samples.notefall.app`.
7. Không copy code repo không LICENSE; không dùng code NoteFall nếu thương mại (PolyForm).
8. Không thêm backend/analytics/UI kit ngoài.
9. Chuỗi UI tiếng Việt chép nguyên văn từ `42`/`25`.
10. Chạy đủ cổng chất lượng trước khi bàn giao (`45.11`).

## 4. Thứ tự build

`M0` khung → `M1` chơi được → `M2` tuỳ biến & lưu → `M3` nhập MIDI + timeline → `M4` sửa & xuất → `M5` luyện tập → `M6` đánh bóng & phát hành.

Không mở rộng phạm vi ngoài milestone đang làm. Ý tưởng mới → `docs/ideas.md`.

## 5. Định nghĩa "xong" (tóm tắt)

- Bấm phím → có tiếng < 30 ms (máy thật); mở app lạnh → tiếng đầu < 15 s.
- 12 file MIDI test mở được, không treo > 1 s; tempo đổi không làm nốt nhảy sai.
- 2.000 nốt @1080p ≥ 55 fps; 10.000 nốt vẫn dùng được.
- 25+ thông số chỉnh được ngay và lưu vào `.nfz`; round-trip MIDI đúng.
- Wait mode + chấm điểm đúng công thức `16.3`.
- UI tiếng Việt đúng dấu, chạy 768 px; Lighthouse A11y ≥ 95.
- Không request mạng ngoài CDN sample.

## 6. Nếu bí

| Vấn đề | File |
|---|---|
| Cách parse MIDI, ca biên | `19` |
| Công thức chấm điểm, calibration | `16` |
| Âm thanh, pedal, reverb, LUFS | `22` |
| Hiệu năng, bộ nhớ sample | `34` |
| Lưu trữ, định dạng `.nfz` | `33` |
| Safari/iOS | `36` |
| Thiết kế, token, component | `43` |
| Màn hình, chuỗi UI | `42` |
| Mâu thuẫn tài liệu | `46` |
| Tổng quan & lý do chọn | `30` |
