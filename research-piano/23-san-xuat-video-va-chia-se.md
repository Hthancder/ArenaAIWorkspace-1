# 23 — Sản xuất video & chia sẻ (thông số thật để export đúng)

> Mục tiêu: khi người dùng bấm Export, file ra phải **đăng được luôn** — không bị nền tảng re-encode làm nhoè, không bị chìm tiếng, đúng khung hình cho từng nền tảng.

## 23.1. Thông số nền tảng (2026)

| Nền tảng | Khung hình | Codec khuyến nghị | Bitrate video | Audio | Loudness |
|---|---|---|---|---|---|
| **YouTube** (ngang) | 1920×1080 / 2560×1440 / 3840×2160 | **MP4 + H.264** (HEVC cho 4K nếu muốn nhỏ) | 1080p30 ≈ **8 Mbps**; 1080p60 ≈ **12 Mbps**; 1440p30 ≈ 16 Mbps; **4K30 ≈ 35–45 Mbps**; 4K60 ≈ 53–68 Mbps | **AAC-LC 48 kHz**, stereo, 320–384 kbps | **−14 LUFS** integrated, true peak **−1 dBTP** |
| **YouTube Shorts** | 1080×1920 | H.264 | ~12 Mbps @60 | AAC | −14 LUFS |
| **TikTok** | 1080×1920 | H.264 | 8–12 Mbps | AAC 44.1/48 kHz | −14 … −11 LUFS (nền tảng to hơn) |
| **Instagram Reels** | 1080×1920 | H.264 | 8–10 Mbps | AAC | −14 LUFS |
| **Facebook** | 1080p/4K | H.264 | 8–12 Mbps | AAC | −14 LUFS |
| **Lưu trữ / gửi đi** | bất kỳ | H.264 CRF ~18 hoặc WebM VP9 | chất lượng cao | AAC 320 / Opus 192 | không normalize |

**Nguyên tắc chung:** nền tảng **luôn re-encode**; upload từ nguồn **sạch, bitrate cao hơn mức tối thiểu 20–30%** thì sau khi re-encode mới còn đẹp. `yuv420p` để tương thích tối đa.

## 23.2. Mapping sang code NoteFall

| Yêu cầu | NoteFall đã có | Cần thêm |
|---|---|---|
| MP4 H.264 + AAC | ✅ preset `h264`, `mp4a.40.2`, 44.1 kHz | thêm lựa chọn **48 kHz** cho audio (YouTube khuyến nghị 48k) |
| WebM VP9/AV1 + Opus | ✅ preset `vp9`, `av1`, 48 kHz | — |
| Chọn resolution/fps | ✅ dialog | thêm **24 fps** (điện ảnh) và **custom** |
| Bitrate/quality | ⚠️ chỉ có "quality" | thêm **CRF/bitrate thủ công** + preset theo nền tảng |
| Khung hình dọc 9:16 | ❌ | **thêm** (P1) — cần tính lại camera + `visibleTop` |
| Khoảng render (loop / A–B) | ⚠️ render cả bài | thêm chọn vùng |
| Batch render | ❌ | P2 |
| Lưu preset export | ⚠️ settings chung | thêm preset "YouTube 1080p60", "TikTok 9:16", "Archive 4K" |

Ghi chú kỹ thuật từ code NoteFall: chọn **H.264 level** theo macroblocks/giây (≤1080p30 → 4.0; ≤1080p60 → 4.1; cao hơn → 5.1), VP9/AV1 chọn tier theo luma samples/giây. Đây là cách đúng — giữ nguyên và chỉ thêm preset.

## 23.3. Preset export đề xuất cho app mới

| Tên preset | Container/codec | Kích thước | fps | Bitrate | Audio |
|---|---|---|---|---|---|
| **YouTube 1080p60** | MP4 H.264 High | 1920×1080 | 60 | 12–16 Mbps | AAC 320 kbps 48 kHz |
| **YouTube 4K60** | MP4 H.264 | 3840×2160 | 60 | 55–68 Mbps | AAC 384 kbps 48 kHz |
| **YouTube 4K (nhẹ)** | MP4 HEVC/VP9 | 3840×2160 | 60 | 35–45 Mbps | AAC 320 kbps |
| **TikTok / Shorts 9:16** | MP4 H.264 | 1080×1920 | 60 | 10–12 Mbps | AAC 192 kbps |
| **Instagram 9:16** | MP4 H.264 | 1080×1920 | 30 | 8–10 Mbps | AAC 192 kbps |
| **Archive (chất lượng cao)** | WebM AV1/VP9 | 3840×2160 | 60 | CRF thấp | Opus 192 kbps |
| **Chỉ audio (WAV)** | WAV 24-bit | — | — | — | 48 kHz |
| **Chỉ audio (nén)** | MP4 AAC / WebM Opus | — | — | — | 320 / 192 |

## 23.4. Loudness: cách làm trong app mà không cần thư viện nặng

**Mức đơn giản (khuyến nghị giai đoạn 1):**
1. Render audio offline → có mẫu float.
2. Tính **peak** (max abs) và **RMS** toàn bài.
3. Ước lượng gain để RMS ≈ mục tiêu (−14…−16 LUFS xấp xỉ bằng RMS −14 dBFS cho nhạc piano, sai số ±2 LU).
4. Nhân gain, sau đó **limiter** để peak ≤ −1 dB.
5. Ghi file.

**Mức chính xác (P2):** cài đặt BS.1770 (K-weighting + gating) trong `AudioWorklet`/JS thuần — khoảng 100 dòng, chạy 1 lần khi export.

**Điều cấm:** tự động nén mạnh để "to hơn" — YouTube sẽ hạ xuống, người dùng mất dynamic của piano.

## 23.5. Sản xuất hình: checklist để video "trông chuyên"

| Hạng mục | Gợi ý |
|---|---|
| **Tỉ lệ khung** | 16:9 cho YouTube; 9:16 cho Shorts/TikTok (bàn phím chiếm 1/3 dưới, nốt rơi phía trên) |
| **Hit line** | Đặt ~72–78% chiều cao; không sát đáy (che phím) |
| **Màu nốt** | Tương phản với nền; tránh 2 tay cùng màu; dùng chroma 12 màu nếu muốn "nhìn ra hòa âm" |
| **Độ dài nốt** | Giữ `noteMinLength` để nốt ngắn không thành vạch |
| **Particle/Bloom** | Đẹp nhưng nặng; với 4K nên giảm 30–50% |
| **Camera** | Cố định cho bản "tutorial"; zoom nhẹ cho bản "cinematic" |
| **Tai nghe/loa** | Không áp dụng cho export, nhưng nhắc người dùng nghe lại trước khi đăng |
| **Intro/Outro** | 1–2 s tiêu đề bài + tác giả; outro 2 s credit |
| **Watermark** | **Không** đóng watermark (khác biệt với SeeMusic free) — chỉ credit tuỳ chọn |
| **Thumbnail** | Xuất thêm 1 frame PNG ở thời điểm đẹp (P2: nút "lưu ảnh khung hình") |
| **Phụ đề/metadata** | Cho phép nhập tiêu đề/nghệ sĩ để đặt tên file `Artist - Title [1080p60].mp4` |

## 23.6. Hiệu năng render (thực tế cần biết)

| Yếu tố | Ảnh hưởng | Cách xử lý |
|---|---|---|
| Frame-by-frame render | Tuyến tính theo số frame: 3 phút @60fps = **10.800 frame** | Cảnh báo thời gian ước lượng (NoteFall có ETA) |
| 4K60 | 4× pixel so với 1080p | Đề xuất 1080p60 mặc định; 4K là "advanced" |
| Bloom/particle | Nặng ở 4K | Tự giảm chất lượng hiệu ứng khi >1440p |
| Bộ nhớ | Frame buffer + encoder queue | Giới hạn queue, giải phóng `VideoFrame` ngay sau encode |
| Tab nền | Browser throttle | Render trong Web Worker + giữ tab foreground (hiện thông báo) |
| Hủy giữa chừng | Người dùng đổi ý | Cancel an toàn, không để file dở |

## 23.7. Chia sẻ: những gì nên có trong app

- **Nút "Xuất để đăng YouTube"** → preset sẵn, tên file gợi ý, nhắc loudness.
- **Nút "Xuất dọc cho TikTok/Shorts"** → 9:16, có thể tự crop bàn phím.
- **Copy caption gợi ý**: `"<Bài> — chơi bằng <App>"` + hashtag.
- **Lưu project kèm preset** để lần sau export y hệt.
- **Không upload thay người dùng** (không tích hợp OAuth YouTube ở giai đoạn đầu) — chỉ tạo file.
- **README/credit**: nếu dùng sample CC BY, hiển thị credit trong mô tả gợi ý để người dùng copy.

## 23.8. Kiểm tra trước khi đăng (checklist 10 điểm)

1. Đúng khung hình (16:9 / 9:16), không có viền đen lạ.
2. Âm thanh không clipping (peak ≤ −1 dB).
3. Độ to ~−14 LUFS (nếu cho YouTube).
4. Không có frame trắng/đen ở đầu (hoặc cố ý).
5. Nốt không bị cắt ở hit line (kiểm tra 10 s đầu & cuối).
6. Tên file có tên bài + độ phân giải.
7. Thời lượng khớp nhạc (kể cả tail reverb).
8. Không lộ UI (nếu muốn "sạch") — dùng chế độ ẩn chrome/fullscreen.
9. Watermark: không có (hoặc có logo nhỏ nếu muốn).
10. Đã nghe lại toàn bộ 1 lần trước khi đăng.

## 23.9. Ghi chú về bản quyền khi chia sẻ

- **Video nốt rơi** là tác phẩm phái sinh từ bản nhạc: nếu bài còn bản quyền, YouTube có thể **Content ID** và chặn/kiếm tiền thay.
- App **không chịu trách nhiệm** nhưng nên có cảnh báo nhẹ trong lúc export: "Bạn chịu trách nhiệm về bản quyền bản nhạc."
- Khuyến khích dùng nhạc **public domain** (bản soạn cổ điển) và **MIDI tự làm** — thêm bộ demo public domain.
- Nếu dùng sample CC BY 3.0 (Salamander), **không bắt buộc** ghi trong video, nhưng nên có trong mô tả/credits của app.
