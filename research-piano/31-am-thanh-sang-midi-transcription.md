# 31 — Âm thanh → MIDI (transcription) trong trình duyệt

> Tính năng "đưa file nhạc/ghi âm vào → ra nốt" là thứ nhiều người dùng mong nhất ở app piano (Synthesia không có, SeeMusic có, fonghtdev NoteFall có). File này xác định **có làm được 100% trên máy người dùng không**, với chi phí bao nhiêu.

## 31.1. Các mô hình khả dụng (2026)

| Mô hình | Nguồn | Giấy phép | Kích thước | Vào/ra | Ghi chú |
|---|---|---|---|---|---|
| **Basic Pitch (Spotify)** | `spotify/basic-pitch` | Apache-2.0 | model `nmp.onnx` **230 KB** | 2 s audio @22.05 kHz → onset/frame/contour | Nhẹ nhất, chạy WASM được, có pitch bend |
| **basic-pitch-rs** | `AThevon/basic-pitch-rs` | (kiểm tra repo) | module WASM **2.3 MB gzip** (kèm model) | như trên, Rust→WASM | **Đo thật**: 1 cửa sổ 2 s = **31 ms** (tract, 1 core) / **9.8 ms** (ort); 60 s audio → **0.19–1.15 s**; "nhanh gấp ~22 lần thời gian thực" trong Chromium |
| **Transkun 2.0** | Yujia Yan & Zhiyao Duan | (nghiên cứu, kiểm tra) | ONNX FP32 | piano, có pedal/velocity tốt hơn | Bản ONNX cho browser tồn tại (`ericfithian/piano-duet-recording-transcription-onnx`): 3 phút nhạc thật khớp **960/960 onset trong 30 ms** trên WASM |
| **Piano transcription inference (ByteDance)** | `qiuqiangkong/piano_transcription_inference` | MIT | ~40 MB (CNN) | piano solo, chất lượng cao | Nặng, cần ONNX/WebGPU; hợp chạy offline 1 lần |
| **Onsets and Frames (Magenta)** | `magenta/onsets-frames` | Apache-2.0 | lớn (TF) | piano | Khó chạy browser, chỉ tham khảo |
| **MT3** | Google | Apache-2.0 | rất lớn | đa nhạc cụ | Không hợp browser |
| **CREPE / pYIN (đơn âm)** | nhiều | MIT/BSD | nhỏ | 1 nốt | Chỉ dùng cho mic/giọng, không cho piano |

**Kết luận kỹ thuật:** với **piano solo**, `basic-pitch-rs` là lựa chọn thực dụng nhất cho browser (nhẹ, nhanh, Apache-2.0 ở bản gốc). Với chất lượng cao hơn (pedal, velocity), Transkun ONNX đáng thử nhưng nặng hơn nhiều.

## 31.2. Những cái bẫy đã được xác nhận

1. **`session.run` chạy trên thread gọi nó** → chạy trong trang sẽ **đóng băng UI** mỗi cửa sổ 2 s. Một PR thật ghi: "35 ms đóng băng trước, **2–3 ms sau** khi chuyển sang Worker" (dự án `FabienCouprie/attic`). → **Bắt buộc dùng Web Worker.**
2. **Worker + `onnxruntime-web`**: phải nạp WASM đúng cách; trong Vitest/jsdom không chạy được → test bằng Playwright thật (file 28.3).
3. **Model đọc cửa sổ 2 giây** → không thể "live" (trễ ~2 s). Muốn live phải tự cắt cửa sổ trượt và chấp nhận nhiễu.
4. **Tiền xử lý phải khớp lúc train**: log-mel 22.05 kHz, `top_db=80`, Slaney mel — lệch một chút là sai hoàn toàn (đã có dự án ghi lại: mel filterbank lệch → "phân phối chuẩn hoá khác hẳn").
5. **`torch.onnx.export` mặc định tách weight ra file `.data`** → WASM không đọc được; phải `save_as_external_data=False`.
6. **Giới hạn bộ nhớ**: giải mã 1 bài 10 phút stereo 48 kHz = **~230 MB float32** (xem 36.4) → transcribe theo từng đoạn, giải phóng buffer.
7. **Không dùng GPU**: các bản WASM hiện tại chạy CPU cho kết quả tất định; WebGPU có thể nhanh hơn nhưng chưa ổn định cho `onnxruntime-web` trong mọi trình duyệt.

## 31.3. Kiến trúc đề xuất (route riêng)

```
/transcribe  (route tách, lazy-load toàn bộ)
   │
   ├─ UI: kéo file (wav/mp3/m4a/ogg/flac) hoặc ghi từ mic
   ├─ decodeAudioData → AudioBuffer (mono 22.05 kHz)
   ├─ worker: transcribe.worker.ts
   │     ├─ import onnxruntime-web (wasm)
   │     ├─ cắt cửa sổ 2 s, overlap 0.5 s
   │     ├─ hậu xử lý: onset → note, gộp contour, velocity từ amplitude
   │     └─ postMessage tiến độ {done, total} mỗi cửa sổ
   ├─ hiển thị piano roll kết quả + nghe thử
   ├─ người dùng SỬA (xoá nốt sai, đổi velocity) — bước quan trọng nhất
   └─ "Đưa vào trình phát" → ParsedSong (cùng kiểu dữ liệu với MIDI)
```

**Vì sao route riêng:** cần `COOP/COEP` (`crossOriginIsolated`) cho `SharedArrayBuffer`/threads nếu muốn đa luồng; bật toàn app sẽ chặn nhúng iframe và một số CDN → chỉ bật ở `/transcribe` (đã ghi ở file 26).

**Không cần COOP/COEP** nếu dùng 1 worker đơn luồng (chậm hơn nhưng đơn giản hơn). Khuyến nghị: bắt đầu đơn luồng.

## 31.4. Ước lượng thời gian & chất lượng

| Máy | 3 phút nhạc | 10 phút |
|---|---|---|
| Laptop 2020 (4 core, WASM đơn luồng) | ~40–90 s | ~2.5–5 phút |
| Laptop 2024 | ~15–40 s | ~1–2.5 phút |
| Điện thoại | 2–5× chậm hơn laptop | không khuyến khích |

**Chất lượng thực tế (kỳ vọng đúng):**
- Piano solo, thu tốt: **70–90% nốt đúng**, sai chủ yếu ở hợp âm dày, nốt lặp nhanh, pedal giữ.
- Có trống/giọng/đàn khác: giảm mạnh — phải nói rõ "dành cho piano solo".
- **Không có pedal** trong Basic Pitch (chỉ cao độ + thời lượng) → người dùng phải thêm pedal bằng tay.

**Thông điệp UI phải trung thực:** "Kết quả là bản nháp — hãy sửa lại. Với piano thu tốt, thường đúng 70–90% nốt." (Đừng hứa "chuyển bài hát thành MIDI hoàn hảo".)

## 31.5. Luồng sửa kết quả (make-or-break)

Transcription **không có giá trị** nếu không sửa được. Tối thiểu:
- Piano roll 2D có zoom, kéo nốt, xoá bằng chuột phải, nghe từng đoạn.
- **Chế độ A/B**: nghe audio gốc và MIDI phát song song, cùng vị trí.
- Tô đỏ nốt có độ tin cậy thấp (Basic Pitch trả `confidence`) → người dùng rà nhanh.
- Nút "chỉnh đều nốt" (quantize) + "gộp nốt trùng".
- Lưu thành project, không chỉ file MIDI rời.

## 31.6. Phương án thay thế (nếu không muốn tự làm)

| Cách | Ưu | Nhược |
|---|---|---|
| Chỉ nhận MIDI, không transcribe | Đơn giản, đúng phạm vi v1 | Mất một tính năng "wow" |
| Hướng dẫn người dùng dùng công cụ ngoài (Basic Pitch CLI, Ableton, Melodyne) | Không tốn công | Trải nghiệm gãy |
| Server riêng chạy Transkun | Chất lượng cao nhất | Vi phạm "local-first", tốn tiền, rủi ro dữ liệu |
| WebGPU + model lớn | Nhanh, tốt hơn | Chưa ổn định, khó test |

## 31.7. Quyết định đề xuất

| Hạng mục | Quyết định |
|---|---|
| v1 | **Không** có transcription (giữ 4 việc cốt lõi — file 29.1) |
| v2 | `/transcribe` với **basic-pitch-rs** hoặc `onnxruntime-web` + Basic Pitch, **worker**, **UI sửa**, nhãn "bản nháp" |
| Không làm | Server transcription, model đa nhạc cụ, live transcription |
| Điều kiện bật tính năng | Bundle route ≤ 5 MB gzip; chạy được trên 4 GB RAM; có test Playwright so số nốt với file chuẩn (±10%) |

## 31.8. Checklist khi triển khai

- [ ] Worker riêng, không chặn UI; đo "đóng băng" < 50 ms.
- [ ] Tiền xử lý mel **khớp** tham chiếu Python (so trên 1 file vàng).
- [ ] Model nằm trong bundle route (không CDN ngoài) hoặc CDN của mình.
- [ ] Giới hạn: file ≤ 20 phút, ≤ 100 MB; báo lỗi rõ.
- [ ] Hiện tiến độ theo cửa sổ + ước lượng thời gian còn lại.
- [ ] Huỷ được giữa chừng (terminate worker).
- [ ] Kết quả vào `ParsedSong` giống MIDI → mọi tính năng khác dùng được ngay.
- [ ] Ghi rõ license của model trong Credits.
- [ ] Không upload audio; nói rõ trong UI.
