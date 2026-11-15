# 18 — Các quyết định cần chốt trước khi code (ADR log)

> Mỗi mục: bối cảnh → lựa chọn → khuyến nghị → trạng thái. Khi bắt đầu build, chốt từng mục và ghi ngày.
> Trạng thái hiện tại: **tất cả đang "chưa chốt"** (đợt này chỉ nghiên cứu).

---

## D1. Giấy phép & cách dùng NoteFall

**Bối cảnh:** NoteFall là PolyForm Shield 1.0.0 — có Noncompete. Yêu cầu ban đầu: "bê y nguyên source".

| Lựa chọn | Hệ quả |
|---|---|
| A. Dùng cá nhân, không publish | ✅ Hợp pháp, nhanh nhất. ❌ Không chia sẻ được |
| B. Xin phép tác giả | ✅ Có thể publish. ❌ Phụ thuộc phản hồi |
| C. Clean-room (chỉ học ý tưởng) | ✅ Toàn quyền. ❌ Mất phần "đẹp sẵn", tốn nhiều tháng |
| D. Base khác có license rõ (Neothesia GPL-3.0) | ✅ Hợp pháp. ❌ GPL copyleft + kém đẹp |
| E. Hybrid: NoteFall cho prototype cá nhân → thay dần module | ✅ Cân bằng. ❌ Hai nhánh |

**Khuyến nghị:** A cho giai đoạn 1; trước khi publish chuyển B (ưu tiên) hoặc C.
**Cần làm ngay:** ghi rõ trong README "Dựa trên NoteFall của ekkx — PolyForm Shield 1.0.0"; giữ LICENSE + Required Notice.
**Trạng thái:** ☐ chưa chốt

---

## D2. Ai là người dùng? (quyết định mọi thứ khác)

| Lựa chọn | Ảnh hưởng |
|---|---|
| A. Chỉ mình dùng (công cụ cá nhân) | Không cần onboarding, không cần i18n đa, không cần tài khoản, không cần mobile |
| B. Chia sẻ miễn phí cho cộng đồng | Cần onboarding, hướng dẫn, xử lý lỗi tốt, i18n vi/en |
| C. Sản phẩm thương mại | Cần license rõ (D1), thanh toán, hỗ trợ, phân tích, chính sách dữ liệu |

**Khuyến nghị:** thiết kế cho **B** (cá nhân + chia sẻ miễn phí), vì nó bao trùm A và không chặn C.
**Trạng thái:** ☐ chưa chốt

---

## D3. Giữ NoteFall bao nhiêu, viết mới bao nhiêu

| Lựa chọn | Công | Rủi ro |
|---|---|---|
| A. Fork nguyên, chỉ thêm module | Thấp | Kéo theo nợ kỹ thuật (React 18/R3F 8, tone 5MB, PostHog, code 40k dòng chưa test) |
| B. Fork + dọn dần (bỏ tone, bỏ analytics, thêm test) | Trung bình | Cần thời gian nhưng sạch |
| C. Viết mới, mượn ý tưởng | Cao | Chậm |

**Khuyến nghị:** **B** — fork, rồi làm 1 "tuần dọn dẹp" trước khi thêm tính năng: bỏ `tone`/`posthog`, self-host sample, thêm `vitest` cho `midi/` + `practice/`.
**Trạng thái:** ☐ chưa chốt

---

## D4. Nâng React 19 + R3F 9 hay giữ React 18 + R3F 8

| | Giữ (18/8) | Nâng (19/9) |
|---|---|---|
| Công | 0 | 1–3 ngày + sửa vỡ |
| Rủi ro | Không có cập nhật bảo mật lâu dài | Vỡ shader/geometry tùy chỉnh |
| Lợi | Ổn định ngay | Tương lai |

**Khuyến nghị:** giữ React 18 + R3F 8 cho Giai đoạn 1; lên kế hoạch nâng ở Giai đoạn 3 khi đã có test.
**Trạng thái:** ☐ chưa chốt

---

## D5. Sample piano: self-host hay dùng CDN của NoteFall

| Lựa chọn | Vấn đề |
|---|---|
| Dùng CDN `samples.notefall.app` | ❌ CORS chỉ cho notefall.app → **không chạy được**; lại phụ thuộc tác giả |
| Self-host 480 OGG (~77 MB) trên storage của mình | ✅ Chủ động; cần cấu hình CORS + cache |
| Chuyển sang sample nhẹ hơn (30 sample, 1 layer) | Nhẹ hơn nhiều nhưng kém biểu cảm |

**Khuyến nghị:** self-host bộ đầy đủ (480 OGG), cấu hình `Access-Control-Allow-Origin` cho domain app; ghi công CC BY 3.0.
**Trạng thái:** ☐ chưa chốt

---

## D6. Âm thanh: giữ `tone` hay bỏ

**Bối cảnh:** `tone` 5.3 MB chỉ dùng để giữ AudioContext; engine đã tự quản lý schedule.

**Khuyến nghị:** **bỏ** — thay bằng `new AudioContext({ latencyHint: 'interactive' })`, giảm bundle đáng kể. Kiểm tra kỹ chỗ nào còn import `tone`.
**Trạng thái:** ☐ chưa chốt

---

## D7. Export video: giữ `mediabunny` (MPL-2.0) hay thay bằng muxer MIT

| | mediabunny | mp4-muxer / webm-muxer |
|---|---|---|
| License | MPL-2.0 (copyleft theo file) | MIT |
| Tính năng | Nhiều container/codec, đã tích hợp | Đủ dùng |
| Công thay | 0 | 1–2 ngày |

**Khuyến nghị:** giữ mediabunny (dùng nguyên, không sửa file của họ) — MPL không lan sang code của mình. Chỉ thay nếu muốn toàn bộ dependency là MIT/BSD.
**Trạng thái:** ☐ chưa chốt

---

## D8. MP3 export

**Bối cảnh:** WebCodecs không encode MP3; lamejs là LGPL-3.0.

**Khuyến nghị:** **không** làm MP3 ở Giai đoạn 1 — xuất WAV + FLAC (lossless) và MP4/WebM (có AAC/Opus). Nếu người dùng cần MP3, load động lamejs sau (và ghi chú license).
**Trạng thái:** ☐ chưa chốt

---

## D9. Nền tảng ưu tiên

**Khuyến nghị:** **PWA desktop Chrome/Edge** (đúng yêu cầu "chơi trên máy tính"); Electron chỉ khi cần bản cài offline có MIDI trên macOS. **Không** Tauri (mất Web MIDI trên macOS/Linux).
**Trạng thái:** ☐ chưa chốt

---

## D10. Hosting

**Bối cảnh:** Vercel đang được kết nối trong workspace.

**Khuyến nghị:** Vercel cho app (static) + object storage có CORS cho sample (Vercel static hoặc Cloudflare R2). Cấu hình cache immutable cho sample, `no-cache` cho `index.html`.
**Trạng thái:** ☐ chưa chốt

---

## D11. Analytics / feedback

**Khuyến nghị:** **tắt mặc định**, không gửi MIDI/project/recording đi đâu (giữ nguyên tắc của NoteFall). Nếu cần số liệu: dùng analytics không cookie + opt-in rõ ràng. Bỏ endpoint feedback của tác giả, thay bằng link GitHub Issues của mình.
**Trạng thái:** ☐ chưa chốt

---

## D12. Ngôn ngữ

**Khuyến nghị:** mặc định **tiếng Việt**, thêm en; giữ ja nếu muốn (đã có sẵn file). Tên thông số kỹ thuật giữ tiếng Anh trong ngoặc để dễ tra cứu.
**Trạng thái:** ☐ chưa chốt

---

## D13. Thứ tự tính năng P0 (để không bị phân tán)

**Khuyến nghị (theo giá trị/công):**
1. Self-host sample + bỏ analytics (nền)
2. Loop A–B + marker + metronome đầy đủ (chơi thật)
3. Remap phím + calibration latency (chơi thật)
4. Schema-driven Inspector + preset JSON (tùy chỉnh)
5. Export mở rộng (aspect/khoảng render) (chia sẻ)
6. **Wait Mode + scoring** (giá trị khác biệt lớn nhất)
7. Sheet music (OSMD)
8. SoundFont / đa instrument
9. Fingering DP
10. PWA + layout hẹp

**Trạng thái:** ☐ chưa chốt

---

## D14. Có làm "thư viện bài hát" không

**Bối cảnh:** mọi app thương mại đều có thư viện, nhưng bản quyền bản phối MIDI là vấn đề.

**Khuyến nghị:** **không** xây thư viện có bản quyền. Thay vào đó:
- 5–10 bài demo **public domain** do mình tự làm MIDI (hoặc CC0).
- "BYO MIDI" là tính năng chính (như Synthesia/NoteFall).
- Nếu sau này muốn thư viện: chỉ dùng nguồn CC0/CC BY (Mutopia, OpenScore) + ghi công.
**Trạng thái:** ☐ chưa chốt

---

## D15. Mic detection / audio→MIDI có làm không

| | Mic detection (nghe đàn cơ) | Audio→MIDI (upload file) |
|---|---|---|
| Độ khó | Rất cao (đa âm, pedal, ồn) | Cao nhưng có model sẵn (Basic Pitch Apache-2.0) |
| Giá trị | Lớn cho người có đàn cơ | Lớn cho người có bản thu |
| Rủi ro | Chấm sai → mất niềm tin | Cần tải model, xử lý lâu |

**Khuyến nghị:** Giai đoạn 3, **audio→MIDI trước** (kết quả rõ ràng, có thể kiểm tra bằng mắt), mic detection sau và chỉ ở mức "melody/đúng nốt", không hứa polyphonic.
**Trạng thái:** ☐ chưa chốt

---

## Mẫu ghi khi chốt

```
D<n>. <tên quyết định>
Ngày: YYYY-MM-DD
Chọn: <phương án>
Lý do: <2–3 dòng>
Ảnh hưởng: <file/module nào sẽ đổi>
Người quyết: <ai>
```
