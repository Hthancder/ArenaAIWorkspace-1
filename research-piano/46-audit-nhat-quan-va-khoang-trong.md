# 46 — Audit tính nhất quán & khoảng trống

> Rà soát toàn bộ 45 file trước đó **dưới góc nhìn máy đọc**: chỗ nào mâu thuẫn, chỗ nào thiếu, chỗ nào người đọc hiểu nhưng máy sẽ hiểu sai. Mọi xung đột ở đây **đã được xử lý**; AI làm theo cột "Quyết định".

## 46.1. Mâu thuẫn đã phát hiện & xử lý

| # | Mâu thuẫn | Nguồn | Quyết định (AI làm theo) |
|---|---|---|---|
| C1 | `maxVoices`: 64–96 vs 64–128 | `34.3` vs `44.3` | **Mặc định 96, cho phép 64–128**; dưới 64 không cho chọn |
| C2 | Ngưỡng màn hình tối thiểu: chặn < 1024 vs hỗ trợ 768 | `20.2` (NoteFall) vs `43.8` | **768 px là tối thiểu**, không chặn cứng; < 768 hiện banner gợi ý xoay ngang |
| C3 | License Salamander: CC BY 3.0 vs CC BY-SA 3.0 | `22`, `40` vs trang chuyển đổi Kronos | **Coi là CC BY 3.0** (nguồn gốc Alexander Holm) nhưng **để asset ở repo/prefix riêng**, không nhúng vào bundle code; kiểm `LICENSE` trong bản tải trước khi phát hành |
| C4 | Số tầng velocity: 16 (NoteFall) vs 8 (đề xuất tối ưu) | `22.3`, `40.1` | **16 tầng cho bộ "đầy đủ", 8 tầng cho bộ "nhẹ"**; `sampleSet: 'full' | 'lite'` |
| C5 | Export video: "P0" ở `23` vs "không làm v1" ở `29` | `23.3` vs `29.1` | **v1 không có video**; `pri: P2`, milestone M6 tùy chọn |
| C6 | Camera mặc định: `[0,0,12]` FOV 32 vs token "distance 12" | `15.3`, `42 S1` vs `44.3` | Giữ **distance = 12, fov = 32, keyboardScreenY = -2.0**; mọi giá trị khác là suy ra |
| C7 | "Không dùng Next.js" vs các tài liệu nói "web app" | `26` (Vercel) vs `45.1` | **Vite SPA tĩnh**; Vercel chỉ host static, không cần SSR |
| C8 | Sheet nhạc: "v2" vs "P2" | `32.7` vs `09` | **P2, ngoài M0–M6**; chỉ làm sau khi 10 mục `41.7` đạt |
| C9 | `positionSec` cập nhật mỗi frame vs "30 Hz" | `34.1` vs `44.8` | **Store 30 Hz; HUD/render đọc trực tiếp clock mỗi frame** (không qua store) |
| C10 | Màu nốt mặc định: trắng vs "theo tay" | `43.2` vs `09` | **Mặc định `mode: 'hands'`** (trái `#6aa9ff`, phải `#ffb26a`) khi bài có ≥ 2 track; nếu 1 track → `single: #f3f2ee` |
| C11 | Tempo ramp: "speedMap" vs "keyframe" | `16.2` vs `44.6` | **Keyframe là nguồn**, `speedAt()` dẫn xuất; `speed` slider ghi 1 keyframe tại vị trí hiện tại hoặc 2 đầu |
| C12 | Zoom camera giới hạn 0.6–2.0 vs fov thay đổi | `42 S1` vs `44.3` | Chỉ đổi **distance** (0.6–2.0 × 12), **không đổi fov** khi người dùng zoom; fov chỉ trong Customize |
| C13 | "Không có telemetry" vs "đo 4 chỉ số" | `41.1` vs `38.5` | Đo **local**, hiển thị trong app, **không gửi đi**; không có network call |
| C14 | Ghi âm: "P1" vs có trong `42 S1` | `09` vs `42` | Nút Record **hiện** nhưng có thể disabled ở M1–M3 với tooltip "có ở M4"; bật thật ở M4 |
| C15 | `NoteEvent.startTick` vs NoteFall có thể lưu giây | `44.2` vs `15` | **Chốt tick**; khi đọc code NoteFall để tham chiếu, **không copy** cách lưu giây |

## 46.2. Chỗ tài liệu **cố ý** không quyết (AI không được tự chốt)

| # | Câu hỏi | Ảnh hưởng | Mặc định an toàn khi chờ |
|---|---|---|---|
| D1 | Fork NoteFall hay tự dựng? | Toàn bộ cách làm | **Tự dựng theo `44`**; NoteFall chỉ để tham chiếu hành vi |
| D2 | Có thương mại hoá? | License, hosting | Giả định **có thể** → không dùng code PolyForm, sample để riêng |
| D3 | Tên app / domain | Branding, metadata | Dùng `piano-app`, hiển thị `Piano` |
| D4 | Mobile trong v1? | Layout, input | **Không**; nhưng layout phải chạy 768 px |
| D5 | Bộ sample cuối cùng? | Dung lượng, chất lượng | **Full 16 tầng OGG 96k** + bộ lite |
| D6 | Có làm transcription? | Bundle, phức tạp | **Không** ở M0–M6; route tách sau |
| D7 | Ngôn ngữ thứ hai? | i18n | Có `en` nhưng **vi là mặc định** |

## 46.3. Khoảng trống tài liệu (AI phải TODO, không bịa)

| # | Thiếu gì | Cách xử lý tạm |
|---|---|---|
| G1 | License chính xác của `basic-pitch-rs` | Không dùng; nếu dùng thì kiểm repo trước, ghi `TODO(license)` |
| G2 | Số đo latency thật trên máy người dùng | Hiển thị ước lượng + nút calibrate; ghi `TODO(measure)` |
| G3 | Nội dung 3 bài demo | Tự tạo MIDI đơn giản (scale, Twinkle, canon đơn giản PD) + ghi nguồn |
| G4 | Kích thước bundle thật của three + R3F + drei | Đo ở M0, ghi `docs/baseline.md` |
| G5 | Chất lượng Opus 64 kbps trên Safari | Test thật; nếu lỗi → chỉ OGG 96 |
| G6 | Thời gian render WAV thật (OfflineAudioContext) | Đo ở M4, ghi lại |
| G7 | Danh sách icon UI cuối cùng | Dùng Lucide, chốt khi làm S1–S2 |
| G8 | Nội dung trang Credits đầy đủ | Sinh từ `docs/licenses/ASSETS.md` |
| G9 | Quy tắc tách tay L/R chính xác | Ngưỡng pitch (C4) + track name; cho người dùng sửa |
| G10 | Fingering algorithm | Dùng `16.6` (DP), hoặc bỏ ở v1 |

## 46.4. Những chỗ dễ khiến AI hiểu sai (đã thêm chỉ dẫn)

| Chỗ | Hiểu sai thường gặp | Đã chặn bằng |
|---|---|---|
| "bê nguyên source NoteFall" | Copy code vào repo mới | `41.1` luật 8, `45.12` |
| "tùy chỉnh hầu hết thông số" | Tạo 400 control rời rạc | `43` + `42 S2` (tab + search + disclosure) |
| "nốt rơi" | Tự viết shader phức tạp | `34.2` (instancing) + `15.3` |
| "âm thanh thật" | Giải mã hết 480 sample | `34.3`, `44.5` (`readyLayers`) |
| "lưu project" | Viết backend | `41.1` luật 10, `33` |
| "phím tắt" | Dùng `Ctrl+S` cho lưu file | `20.5` (S = split trong editor) |
| "tiếng Việt" | Dịch máy tự động | `25` + `41.5` (chép nguyên văn) |
| "đẹp" | Thêm gradient màu mè | `43.1` (không accent), `43.12` |

## 46.5. Kiểm tra cấu trúc tài liệu

| Kiểm tra | Kết quả |
|---|---|
| Số file | 46 file `.md` + `spec/` 2 file JSON |
| Tham chiếu `file NN` trỏ tới file không tồn tại | **0** (đã quét toàn bộ) |
| Ký tự CJK lẫn trong tài liệu tiếng Việt | **0** (đã quét sau mỗi vòng) |
| File trùng chủ đề | `20` vs `43`/`42` (20 = khảo sát, 42/43 = chốt) — đã ghi rõ thứ quyền ở `41.3` |
| File có mục lục | Có, ở `00-README` |
| Mọi file có mục "dùng khi nào" | Có trong `00-README` |

## 46.6. Nhật ký audit (cập nhật mỗi vòng)

| Ngày | Việc | Kết quả |
|---|---|---|
| 2026-11-14 | Quét tham chiếu chéo 41 file | 0 tham chiếu hỏng |
| 2026-11-14 | Quét CJK | 0 |
| 2026-11-14 | Rà 15 mâu thuẫn (C1–C15) | Đã có quyết định |
| 2026-11-14 | Thêm lớp "máy đọc": `41`–`45`, `spec/*` | Xong |
| 2026-11-14 | Xác định 7 câu hỏi chưa chốt (D1–D7) + 10 khoảng trống (G1–G10) | Ghi lại |

## 46.7. CONFLICT phát hiện khi build (2026-11-15)

| Dòng | Mâu thuẫn → Quyết định |
|---|---|
| CONFLICT: `20.5` đề xuất `Z`/`X` = octave shift, `M` = metronome, `L` = loop — nhưng `20.4` map Z/X/M/L là phím đàn, và nguyên tắc "chọn phím" của chính `20.5` cấm shortcut không-modifier trên phím đàn → **Quyết:** octave shift = `PgUp`/`PgDn`, metronome = `Ctrl/Cmd+M`, bỏ `L` (loop A–B chưa có). Căn cứ: `41.3` (mâu thuẫn trong cùng file → theo nguyên tắc tổng quát hơn). |
| CONFLICT: `20.5` nguyên tắc mô tả phím đàn là "A–L, Q–P, số" (kiểu tembrica/Perfect Piano) nhưng map thực tế của nền tảng NoteFall là 2 hàng Z–X–C… / Q–W–E… → **Quyết:** giữ map NoteFall làm mặc định (người dùng chỉ định "lấy all của NoteFall"); remap/preset AZERTY/Dvorak để dành (ideas.md). |
| TODO(spec): velocity theo vị trí nhấn chuột — tài liệu `09` nói "vị trí click (Y trên phím)" nhưng không nêu min/max → dùng tạm 0.35–1.0 (trước = nhẹ, sau = mạnh). |
| TODO(spec): metronome 40–240 BPM theo `06`, nhưng chưa rõ có đồng bộ tempo map bài không → hiện là metronome độc lập, mặc định 100 BPM / 4 nhịp (số liệu count-in của NoteFall). |
