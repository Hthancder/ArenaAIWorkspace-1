# 30 — Tổng kết: bản đồ tính năng, quyết định và việc còn lại

> File chốt của bộ nghiên cứu. Đọc file này trước, rồi đi vào file chi tiết khi cần. Mọi khẳng định ở đây đều có nguồn trong file tương ứng (cột "Xem").

## 30.1. Toàn cảnh: các sản phẩm đã khảo sát

| Sản phẩm | Nền tảng | Mô hình | Điểm mạnh nhất | Điểm yếu chí mạng | Xem |
|---|---|---|---|---|---|
| **NoteFall** | Web (3D) | Miễn phí, mã nguồn mở PolyForm | Hình ảnh đẹp, cảm giác chơi, inspector sâu | Không phải app học, không mobile, không i18n | 02, 15 |
| **Perfect Piano** | iOS/Android | Free + ads/IAP | Phổ biến nhất, nhiều chế độ chơi | Mobile-only, không MIDI editor thật | 03 |
| **Synthesia** | Win/mac/iPad | $29 một lần | Chuẩn mực học bằng nốt rơi, fingering | Đóng, UI cũ, không tuỳ biến sâu | 04 |
| **Flowkey** | Web/mobile | $120–170/năm | Bài giảng + nghe bạn chơi | Khoá nội dung, cần mic, không phải player | 05, 21 |
| **Piano Marvel** | Web | Thuê bao | Chấm điểm theo sheet | Không phải synth 3D | 05 |
| **SeeMusic** | Win/mac | ~$80/năm | Video piano đẹp, watermark nếu free | Đắt, đóng | 21, 23 |
| **PianoViz / Embers** | Web | Free | 3D đẹp, nhẹ | Ít tính năng học | 06 |
| **Pianoteq** | Desktop | €/$ trả một lần | Modelling: resonance, half-pedal | Không phải app chơi | 22 |
| **Neothesia** | Desktop (Rust) | GPL-3.0 | Nhẹ, nốt rơi, MIDI | UI thô, không web | 04, 07 |
| **MIDIano / piano-visualizer** | Web | Không license | Tham khảo kỹ thuật | **Không được dùng lại code** | 06, 14 |
| **Đàn piano web VN** | Web | Free | Tiếng Việt | Rất sơ khai | 21 |

**Kết luận cạnh tranh:** không sản phẩm nào kết hợp **miễn phí + local-first + MIDI của bạn + wait mode + 3D đẹp + tuỳ biến sâu + tiếng Việt**. Đó là khoảng trống (file 21).

## 30.2. Ma trận tính năng hợp nhất (nguồn để "dùng lại tất cả")

| Nhóm | Tính năng | Có ở đâu | Đưa vào v1? |
|---|---|---|---|
| **Phát** | Play/pause/stop, seek, tốc độ 0.25–2×, tempo ramp | tất cả | ✅ |
| | Loop A–B, loop theo ô nhịp | Synthesia, NoteFall | ✅ |
| | Đếm vào (count-in), đếm nhịp | Synthesia, Perfect Piano | ✅ |
| | Wait mode (dừng chờ đúng nốt) | Synthesia, Flowkey | ✅ (v1.1) |
| | Chuyển tay trái/phải, mute từng track | Synthesia | ✅ |
| | Metronome + accent | nhiều | ✅ |
| **Chơi** | Bàn phím máy tính (2 hàng), octave shift | NoteFall, web pianos | ✅ |
| | Web MIDI in/out, CC64/CC1/pitch bend | NoteFall | ✅ |
| | Đàn on-screen bấm được (chuột/cảm ứng) | Perfect Piano | ✅ |
| | Velocity từ độ dài phím / vị trí bấm | NoteFall | ✅ |
| | Ghi âm take, chồng lớp | NoteFall | ✅ (v1.1) |
| **Hình** | Nốt rơi 3D, camera, FOV | NoteFall | ✅ |
| | Nốt 2D / piano roll | Synthesia, Neothesia | v2 |
| | Màu nốt: theo tay/màu/random/cao độ | NoteFall | ✅ |
| | Nhãn tên nốt (Anh/số/Đô) | Synthesia | ✅ |
| | Phím đàn, vệt phím, particle | NoteFall | ✅ |
| | Background ảnh/video | NoteFall | ✅ |
| | Thanh nhịp/phách, lưới | Synthesia | ✅ |
| **Sửa** | Chọn/dịch/đổi độ dài/xoá/thêm nốt | NoteFall | ✅ |
| | Undo/redo, snap | NoteFall | ✅ |
| | Transpose, quantize | nhiều | ✅ |
| | Fingering (gợi ý ngón) | Synthesia | v2 |
| **Học** | Chấm điểm, report nốt yếu | Synthesia, Marvel | v2 |
| | Tempo ladder, practice log | file 24 | v1.1 |
| | Thư viện bài có sẵn | Flowkey | ❌ (tránh bản quyền) |
| **Xuất** | WAV/MP3, MIDI sau khi sửa, project `.nfz` | NoteFall (một phần) | ✅ |
| | Video MP4, preset 9:16 | SeeMusic | v2 (file 23) |
| **Khác** | i18n Việt/Anh | — | ✅ |
| | PWA offline | nhiều | ✅ |
| | Sheet music hiển thị | OSMD | v3 |

Chi tiết từng ô + bằng chứng: file 07 (ma trận gốc) và 20–24 (mở rộng). File 22 nói rõ phần **âm thanh** nào cần làm thêm (release, resonance, half-pedal) và phần nào NoteFall đã có (half-pedal fade).

## 30.3. Mười quyết định kiến trúc (ADR rút gọn)

| # | Quyết định | Lý do ngắn | Trạng thái |
|---|---|---|---|
| D1 | **Web app (Vite + React + three)**, không Electron trước | Chạy mọi nơi, không cài, preview được | đề xuất |
| D2 | **Sample Salamander** làm engine mặc định | Chất lượng cao, license CC BY | đề xuất |
| D3 | **Engine âm thanh pluggable** | Cho phép thay bằng modelling sau | đề xuất |
| D4 | **Project = file `.nfz`**, app không có backend | Local-first, không chi phí, không rủi ro dữ liệu | đề xuất |
| D5 | **Fork NoteFall hay tự dựng** = câu hỏi mở (PolyForm) | License quyết định | **chưa quyết** |
| D6 | **Sample tự host trên R2**, không dùng CDN NoteFall | CORS + độc lập | đề xuất |
| D7 | **WAV cho export audio v1**, Opus/MP4 v2 | Tránh vấn đề codec (file 23) | đề xuất |
| D8 | **Tách route `/transcribe`** nếu làm basic-pitch (COOP/COEP) | Không phá app chính | đề xuất |
| D9 | **Tiếng Việt là ngôn ngữ mặc định**, i18n từ đầu | Chi phí thấp nếu làm sớm | đề xuất |
| D10 | **Không telemetry mặc định** | Đúng lời hứa local-first | đề xuất |

Mọi ADR trong file 18 vẫn ở trạng thái "chưa xác nhận" — cần người dùng chốt.

## 30.4. Những con số phải nhớ

| Số | Ý nghĩa | Xem |
|---|---|---|
| **77 MB** | Bộ sample Salamander 30 phím × 16 tầng @96 kbps | 22 |
| **~30 ms** | Mục tiêu độ trễ bấm → nghe | 08 |
| **60–120 ms** | Độ trễ Bluetooth (phải cảnh báo) | 08 |
| **100 GB / tháng** | Giới hạn băng thông Vercel Hobby | 26 |
| **$0** | Egress Cloudflare R2 | 26 |
| **−14 LUFS / −1 dBTP** | Chuẩn loudness video | 23 |
| **≥ 90% / ≥ 70%** | Ngưỡng "đạt" khi chấm điểm (Keystair) | 16 |
| **12 lần bấm** | Calibration latency @80 BPM | 16 |
| **201 file / 2.650 dòng** | Quy mô NoteFall, `Timeline.tsx` lớn nhất | 15 |
| **2.000 nốt** | Mức tải để test FPS ≥ 55 | 28 |

## 30.5. Rủi ro xếp hạng

| # | Rủi ro | Xác suất | Tác động | Giảm thiểu |
|---|---|---|---|---|
| R1 | **License NoteFall chặn dùng thương mại** | Cao | Cao | Tự dựng theo file 10/15; hoặc giữ phi thương mại |
| R2 | Sample 77 MB tải chậm trên mạng yếu | Cao | Trung bình | Tải theo tầng, synth tạm, cache |
| R3 | Safari/iOS không Web MIDI | Chắc chắn | Trung bình | Fallback phím/mic (file 08) |
| R4 | Độ trễ không đạt 30 ms trên máy yếu | Trung bình | Cao | Đo + hiển thị + hướng dẫn |
| R5 | Phạm vi phình ra (video, AI, sheet) | Cao | Cao | v1 chỉ 4 việc (file 29.1) |
| R6 | NoteFall code phức tạp, fork khó bảo trì | Trung bình | Trung bình | Đọc file 15 trước; ưu tiên thay module |
| R7 | Bản quyền nội dung (bài hát) | Trung bình | Cao | Không host nhạc; người dùng tự mang file |

## 30.6. Việc còn lại (đúng thứ tự)

**Cần người dùng quyết (chặn code):**
1. D5 — fork NoteFall hay tự dựng? (quyết định lớn nhất)
2. Có cần thương mại hoá không? (ảnh hưởng license + hosting)
3. v1 có mobile / video export không? (khuyến nghị: không)

**Nghiên cứu có thể làm thêm (không chặn):**
4. Đọc sâu `ui/Timeline.tsx` + `store.ts` để đánh giá công sức fork (2–3 giờ đọc).
5. Thử `npm ci && npm run dev` trên NoteFall trong `/tmp` để xem có build được không.
6. Nghe thử 16 tầng velocity của Salamander để chọn số tầng (8 vs 16) → giảm 38 MB.
7. So sánh trực tiếp chất lượng: NoteFall sample vs `smplr` + sample khác.
8. Khảo sát 5–10 người chơi piano nghiệp dư VN về tính năng họ muốn (nếu muốn làm sản phẩm thật).

**Khi được phép code:**
9. Sprint 0 (file 29.2) — 4–5 ngày.

## 30.7. Bảng thuật ngữ nhanh (Anh → Việt)

| Anh | Việt | Ghi chú |
|---|---|---|
| falling notes | nốt rơi | |
| piano roll | cuộn nốt / piano roll | giữ nguyên tiếng Anh nếu quen |
| velocity | lực bấm (velocity) | |
| tempo / BPM | nhịp độ / số nhịp mỗi phút | |
| time signature | số chỉ nhịp | ví dụ 4/4 |
| bar / measure | ô nhịp | |
| beat | phách | |
| loop | lặp / vòng lặp | |
| sustain pedal | bàn đạp ngân / pedal | |
| half-pedal | pedal nửa | |
| wait mode | chế độ chờ | |
| count-in | đếm vào | |
| metronome | máy đếm nhịp | |
| transpose | dịch giọng / chuyển giọng | |
| quantize | chỉnh đều nốt / lượng tử | |
| fingering | ngón tay (cách bấm) | |
| take | bản ghi | |
| stem | bè tách | |
| soundfont | soundfont | giữ nguyên |
| latency | độ trễ | |
| sample rate | tần số lấy mẫu | |

Thuật ngữ đầy đủ + quy tắc hiển thị: file 25.

## 30.8. Một câu tóm tắt

> Xây một **web app piano 3D, local-first, tiếng Việt**, mở mọi file MIDI, chơi bằng bàn phím máy tính hoặc MIDI USB với độ trễ thấp, tuỳ biến gần như mọi tham số và lưu vào một file project — dùng lại hình ảnh/kiến trúc của NoteFall nếu license cho phép, tự dựng phần lõi nếu không.

## 30.9. Bản đồ đọc bộ tài liệu

```
Bắt đầu:  00-README → 01 (phạm vi) → 30 (file này)
Hiểu đối thủ: 02 NoteFall · 03 Perfect Piano · 04 Synthesia · 05 học · 06 web · 21 thị trường
Hiểu tính năng: 07 ma trận · 09 P0/P1/P2 · 20 UI · 22 âm thanh · 23 video · 24 sư phạm
Hiểu kỹ thuật: 08 nền tảng · 10 kiến trúc · 13 lý thuyết · 14 thư viện · 15 code NoteFall · 16 chấm điểm · 18 ADR · 19 MIDI · 26 deploy · 27 bảo mật · 28 test
Làm việc: 11 roadmap · 29 backlog
Tra cứu: 12 nguồn · 17 phân phối · 25 thuật ngữ
```
