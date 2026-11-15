# 34 — Hiệu năng & tối ưu render

> App piano là app **thời gian thực**: 60 fps, âm thanh không được giật, tải sample không được chặn UI. File này là ngân sách hiệu năng + cách đạt.

## 34.1. Ngân sách khung hình (60 fps = 16.6 ms/frame)

| Việc | Ngân sách | Ghi chú |
|---|---|---|
| Cập nhật logic (nốt, camera, HUD) | ≤ 2 ms | tránh cấp phát trong loop |
| Cập nhật hình học nốt (visible set) | ≤ 3 ms | chỉ nốt trong cửa sổ thời gian |
| Render (three.js draw calls) | ≤ 7 ms | 1–5 draw call nhờ instancing |
| Trình duyệt/compositor | ≤ 3 ms | |
| Còn lại | ~1.5 ms | dự phòng cho GC/đột biến |

**Quy tắc:** nếu vượt, **giảm số nốt hiển thị** trước khi giảm chất lượng hình.

## 34.2. Kỹ thuật render nốt

| Kỹ thuật | Lợi | Cách |
|---|---|---|
| **InstancedMesh** | 1 draw call cho 5.000 nốt | ma trận + màu trong instance attribute; cập nhật buffer mỗi frame |
| **Chỉ cập nhật nốt thay đổi** | Tránh upload cả buffer | Theo dõi `dirtyRange`, `needsUpdate` |
| **Loại nốt ngoài màn hình** | Giảm instance count | Cửa sổ `[now - 2s, now + fallDuration]` |
| **Không tạo object mới trong loop** | Tránh GC | Dùng pool `Float32Array`, `Matrix4` tái sử dụng |
| **Texture atlas cho glyph/nhãn** | Ít draw call | Nhãn tên nốt vẽ vào canvas 1 lần |
| **LOD** | Nốt xa → hình đơn giản | Chỉ khi cần |
| **`powerPreference: 'high-performance'`** | Dùng GPU rời | tùy chọn |
| **Giới hạn DPR** | Tiết kiệm fill rate | `min(devicePixelRatio, 2)`; cho phép 1.0 ở chế độ "tiết kiệm pin" |

**Con số tham chiếu:** NoteFall dùng InstancedMesh cho phím và nốt; `FallingNotes.tsx` 1.816 dòng xử lý toàn bộ phần này → đọc kỹ trước khi viết lại (file 15).

## 34.3. Âm thanh: chi phí thật (không chỉ CPU)

**Bộ nhớ giải mã sample — con số quan trọng:**
- 1 giây audio mono float32 @48 kHz = **192 KB**; stereo = **384 KB**.
- 1 phút stereo = **~23 MB** (đúng như tài liệu về iPad: "23 MB mỗi phút stereo").
- Salamander NoteFall: 30 phím × 16 tầng, mỗi sample ~2–4 s → 480 × ~3 s × 384 KB ≈ **~550 MB** nếu giải mã hết!

→ **Không bao giờ giải mã tất cả.** Chiến lược:
1. Giữ **AudioBufferSourceNode** trỏ tới buffer đã giải mã, nhưng chỉ giải mã **tầng đang dùng ± 2 tầng** (velocity band). Người chơi bình thường chỉ dùng 4–6 tầng.
2. Hoặc dùng **`decodeAudioData` theo lô** (8–16 sample/lô) và giải phóng tầng xa khi bộ nhớ cao.
3. Hoặc dùng **AudioWorklet + streaming** (phức tạp, chỉ khi cần).
4. **Giới hạn voice**: 64–96 nốt đồng thời; cắt nốt cũ nhất (voice stealing, file 22.8).

**Đo trên thực tế:** 1 tab bị WebKit kill ở **>1.5 GB** (báo cáo của kỹ sư WebKit). → Ngân sách bộ nhớ app: **≤ 400 MB** trên desktop, **≤ 200 MB** trên iPad.

## 34.4. Tải sample: thứ tự và chiến lược

```
1. App shell (JS/CSS)         ~1.2 MB gz   → hiện UI ngay
2. Sample v8 + v9 (mid velocity), 30 phím  ~8 MB → chơi được trong ~1–2 s
3. Các tầng còn lại (background)           ~69 MB → hoàn tất sau 10–30 s
4. Sample release/pedal (nếu bật)          +5–10 MB
```
- Dùng **`<link rel=preload>`** cho 2 file quan trọng nhất? Không — quá nhiều file; thay bằng `fetch` song song có giới hạn (6–10 concurrent) và `decodeAudioData` ngay khi về.
- **Cache Storage** lưu response đã tải; lần sau chỉ đọc từ cache (nhanh hơn 10–50×).
- Hiển thị "đang tải đàn… 43%" và **cho phép chơi bằng synth tạm** trong lúc chờ (nếu muốn cầu toàn).

## 34.5. Những nút thắt thường bị bỏ qua

| Nút thắt | Triệu chứng | Cách xử lý |
|---|---|---|
| Cấp phát trong `requestAnimationFrame` | Giật mỗi vài giây (GC) | Pool, không `new` trong loop |
| React re-render mỗi frame | CPU cao, pin nóng | Zustand selector hẹp; giá trị thời gian không đưa vào React state |
| Cập nhật DOM mỗi frame (HUD) | Layout thrashing | Vẽ HUD vào canvas hoặc cập nhật 10 Hz |
| `getBoundingClientRect()` trong loop | Forced reflow | Cache kích thước, cập nhật khi resize |
| Chia text lớn thành nhiều `<span>` | Hàng nghìn node | Canvas/atlas |
| `JSON.parse` file MIDI lớn trên main thread | Treo 1–3 s | Worker (file 19) |
| Sample decode trên main thread | Treo | `decodeAudioData` là async nhưng vẫn tốn CPU; chia lô |
| Shader biên dịch lần đầu | Khựng 200–800 ms | Warm-up: render 1 frame ẩn trước khi phát |

## 34.6. Đo lường (không đoán)

- **`performance.mark/measure`** quanh: parse, build scene, mỗi frame (chỉ khi bật debug).
- **FPS meter** trong app (phím tắt `F`): FPS, frame time, số instance, số voice, RAM ước lượng.
- **Chrome DevTools Performance**: flame chart khi phát 2.000 nốt; tìm "Recalculate Style", "GC", "Upload".
- **`renderer.info`** (three.js): draw calls, triangles, textures — hiển thị ở debug HUD.
- **Bộ benchmark tự động** (Playwright + CDP): đo frame time trung bình trong 5 s phát với file test; lưu vào `docs/perf.md` mỗi release để phát hiện hồi quy.

## 34.7. Máy yếu & tiết kiệm pin

| Cấp | Điều chỉnh |
|---|---|
| **Cao** (desktop rời) | 88 phím, DPR 2, particle, bloom, 60 fps |
| **Trung bình** (laptop tích hợp) | DPR 1.5, tắt bloom, 60 fps |
| **Thấp** (mobile/CPU yếu) | DPR 1, 61 phím, tắt particle, giới hạn 30 fps khi không tương tác |
| **Tiết kiệm pin** | 30 fps, tắt hiệu ứng, giảm số voice |

- Tự phát hiện: đo 60 frame đầu → chọn cấp; cho người dùng ghi đè.
- Tôn trọng `prefers-reduced-motion` (giảm particle, không rung camera).

## 34.8. Checklist hiệu năng trước release

- [ ] 2.000 nốt @1080p, DPR 1.5 → ≥ 55 fps trên laptop tích hợp.
- [ ] 10.000 nốt (black MIDI) → ≥ 30 fps, không crash.
- [ ] Thời gian mở file MIDI 5.000 nốt < 500 ms (parse trong worker).
- [ ] Thời gian từ bấm "phát" đến tiếng đầu < 100 ms (sample đã cache).
- [ ] RAM sau 10 phút phát không tăng liên tục (rò rỉ).
- [ ] 5 lần mở/đóng project → RAM quay về mức ban đầu (dispose đúng).
- [ ] Chuyển tab đi rồi về → không nhảy thời gian, không mất tiếng.
- [ ] Đo trên 1 máy 4 GB RAM (hoặc Chromium với 4× CPU throttle).
