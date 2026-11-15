# 40 — Chế tạo bộ sample riêng (công thức cụ thể)

> File 22 nói **cần gì** về âm thanh. File này nói **làm thế nào** để có một bộ sample của riêng mình: lấy gì, cắt gì, nén gì, kích thước bao nhiêu, kiểm tra thế nào. Mục tiêu: **thay thế CDN của NoteFall và tối ưu dung lượng**.

## 40.1. Ba phương án (chọn theo mục tiêu)

| Phương án | Dung lượng | Công sức | Chất lượng | Khi nào chọn |
|---|---|---|---|---|
| **A. Tái tạo như NoteFall** (Salamander, 30 phím × 16 tầng, OGG 96 kbps) | ~77 MB | Thấp (có script sẵn) | Cao | Mặc định |
| **B. Tối ưu cho web** (Salamander, 30 phím × **8 tầng**, Opus 64 kbps) | **~20–25 MB** | Trung bình | Rất tốt | Nếu ưu tiên tải nhanh / mobile |
| **C. Siêu nhẹ** (Upright Piano KW CC0, hoặc Splendid Grand PD) | **~10–27 MB cả bộ** | Thấp | Khá | Máy yếu, mạng chậm, chế độ "lite" |

**Đề xuất:** làm **A làm mặc định**, thêm **C làm bộ "nhẹ"** cho người dùng chọn; đo chất lượng trước khi chốt (40.7).

## 40.2. Nguồn nguyên liệu & license

| Bộ | License | Kích thước gốc | Ghi chú |
|---|---|---|---|
| **Salamander Grand Piano** (Alexander Holm, Yamaha C5) | **CC BY 3.0** (một số bản chuyển đổi ghi BY-SA — **kiểm tra LICENSE trong bản tải**) | 394 MB SFZ / 1.27 GB SF2, 48 kHz 24-bit, 16 tầng, mỗi 3 phím | Nguồn tốt nhất, đã có người dùng thực tế |
| **Upright Piano KW** | **CC0** | 27 MB | Nhỏ, không cần ghi công |
| **Splendid Grand Piano (AKAI)** | Public domain | 77 MB | SF2 cổ điển, chất lượng ổn |
| **VCSL Keys** | **CC0** | 680 MB | Nhiều nhạc cụ phím, để mở rộng sau |
| **Piano in 162** (Ivy Audio) | Miễn phí nhưng **cấm đóng gói lại** | 4.9 GB | ❌ không dùng cho sản phẩm phân phối |
| **Accurate-Salamander** | CC BY | 1.6 GB | Chỉnh âm chuẩn hơn, nặng |

**Quy tắc:** lưu `LICENSE` gốc + ghi ngày tải + URL vào `docs/licenses/samples.md`. Nếu license là BY-SA, **không** trộn với code MIT trong cùng bundle.

## 40.3. Công thức cắt (giống cách làm của NoteFall)

1. **Lấy mỗi 3 phím** (C, D#, F#, A…) → 30 phím cho 88 phím; các phím còn lại **pitch-shift** khi phát (±1 semitone chấp nhận được, ±2 tệ hơn).
2. **16 tầng velocity** có sẵn → giữ hoặc giảm còn 8 (mỗi tầng cách ~6 dB).
3. **Cắt đuôi**: giữ ~2–3 s sau khi tắt phím, có fade-out 150–300 ms (tránh click).
4. **Chuẩn hoá**: peak mỗi sample về −3 dBFS (hoặc −6 dB để có headroom, file 22.3), **không** dùng limiter khi cắt.
5. **Resample**: 48 kHz giữ nguyên (khớp phần lớn thiết bị); nếu muốn nhẹ: 44.1 kHz không giúp nhiều.
6. **Đặt tên**: `<note>v<layer>.ogg`, `#` → `s` (giống NoteFall để tương thích code cũ): `C4v8.ogg`, `Cs4v8.ogg`.
7. **Thêm** (tùy chọn): release samples (`rel*`), pedal noise, harmonic layers — NoteFall **bỏ** các nhóm này, đây là cải tiến rẻ nhất (file 22.3).

## 40.4. Định dạng nén: số liệu thật

| Định dạng | Bitrate | 480 file × ~3 s | Ưu | Nhược |
|---|---|---|---|---|
| **OGG Vorbis** | 96 kbps | **~77 MB** | Hỗ trợ rộng, decode nhanh | Không tốt bằng Opus ở bitrate thấp |
| **Opus** | 64 kbps | **~20–25 MB** | Tốt nhất ở bitrate thấp, decode nhanh | Safari cần `.ogg`/Opus support (có từ Safari 17?) — **kiểm tra** |
| **MP3** | 128 kbps | ~100 MB | Vạn năng | Decode chậm hơn, chất lượng kém hơn ở cùng dung lượng |
| **FLAC** | ~50% gốc | >300 MB | Không mất dữ liệu | Quá nặng cho web |
| **WAV** | 1.4 MB/s | ~2 GB | Nhanh nhất (không decode) | Không dùng được cho web |

**Khuyến nghị:** OGG 96 kbps (an toàn nhất), thử Opus 64 kbps như bộ "tiết kiệm" nếu Safari/Chrome/Firefox đều decode đúng (test thật, có `canPlayType`).

**Lưu ý:** `decodeAudioData` giải mã **toàn bộ** file vào RAM; dung lượng file nhỏ **không** làm RAM nhỏ (file 34.3). Nén chỉ giúp **tải**, không giúp bộ nhớ.

## 40.5. Quy trình sản xuất (script)

```
scripts/
  fetch-source.sh      # tải Salamander (SFZ) + kiểm tra sha256
  convert.py           # đọc SFZ → chọn 30 phím × N tầng → cắt đuôi → chuẩn hoá
  encode.sh            # ffmpeg -c:a libvorbis -b:a 96k / libopus -b:a 64k
  verify.py            # kiểm tra: đủ 480 file, đúng tên, duration, peak, không clip
  manifest.json        # { note: [layers], bytes, sha256 từng file }
```

- **`ffmpeg`** là công cụ chính: `-af "afade=t=out:st=2.5:d=0.3"`, `-ar 48000`.
- **`sha256`** từng file → dùng để kiểm tra cache và phát hiện CDN bị sửa.
- Chạy **một lần**, kết quả đẩy lên R2 với prefix `samples/v1/`.
- Nếu cắt từ SFZ: `sfz` là text, đọc được trực tiếp (region sample=... lovel/hivel=...).

## 40.6. Phân phối & cache

- **Prefix có version**: `/samples/v1/...` → đổi bộ sample = đổi prefix, không lo cache cũ.
- Header: `Content-Type: audio/ogg`, `Cache-Control: public, max-age=31536000, immutable`, CORS cho origin của app (file 26).
- **Nén ở tầng CDN**: OGG/Opus đã nén, **không** bật gzip/brotli cho audio (vô ích, tốn CPU).
- **Manifest nhỏ** (`manifest.json`, ~30 KB) tải trước để biết cần file nào.

## 40.7. Đánh giá chất lượng trước khi chốt (đừng chỉ nghe cảm tính)

| Kiểm tra | Cách | Ngưỡng |
|---|---|---|
| **Null test** | So waveform bản gốc vs bản nén, tính sai số | Chênh lệch < −40 dB ở dải 100 Hz–5 kHz |
| **Nghe mù** | 5 người, 10 cặp A/B (96 vs 64 kbps) | ≥ 4/5 không phân biệt được → chấp nhận 64 |
| **Cảm giác velocity** | Chơi 8 tầng liên tiếp, nghe "bậc thang" | Không nghe rõ bước nhảy |
| **Pitch-shift** | So C4 gốc vs D4 shift từ C4 | Không "nhựa" ở ±1; ghi nhận ±2 xấu |
| **Đuôi/release** | Nhấn nhả nhanh | Không click, đuôi tự nhiên |
| **Tải thực tế** | 4G, cold cache | Bộ mid (8 MB) < 3 s |

## 40.8. Bộ sample "nhẹ" (phương án C) — chi tiết

- Nguồn: **Upright Piano KW** (CC0, 27 MB) hoặc **Splendid Grand** (PD, 77 MB).
- Giữ 1–2 tầng velocity, 30 phím, OGG 96 → **~8–12 MB**.
- Dùng khi: mạng chậm, thiết bị yếu, người dùng chọn "chế độ nhẹ", hoặc làm fallback khi CDN chính lỗi.
- Ghi rõ trong Settings: "Bộ đàn nhẹ (12 MB) / Bộ đàn đầy đủ (77 MB)".

## 40.9. Mở rộng sau này

| Ý tưởng | Chi phí | Giá trị |
|---|---|---|
| **Release samples** (`rel*`) | +5 MB | Cao (file 22.3) |
| **Pedal noise** | +1 MB | Trung bình |
| **Sympathetic resonance** (xấp xỉ bằng convolution) | CPU | Cao |
| **Đàn thứ hai** (upright, felt piano) | +20–80 MB | Cao cho người làm video |
| **SoundFont `.sf2` tùy chọn** (người dùng tự nạp) | 0 | Cao cho người dùng nâng cao |
| **Physical modelling** (Pianoteq-style) | Rất lớn | Rất cao nhưng ngoài phạm vi |

## 40.10. Checklist bộ sample

- [ ] License gốc lưu trong repo + ghi công trong app.
- [ ] Đủ số file, tên đúng quy ước, không thiếu tầng.
- [ ] Không clip (peak ≤ −1 dBFS), có fade-out.
- [ ] Có `manifest.json` + sha256.
- [ ] Prefix version + header cache/CORS đúng.
- [ ] Có bộ nhẹ dự phòng.
- [ ] Test null + nghe mù đã ghi kết quả vào `docs/audio-quality.md`.
- [ ] Kích thước tổng ghi vào README (minh bạch với người dùng).
