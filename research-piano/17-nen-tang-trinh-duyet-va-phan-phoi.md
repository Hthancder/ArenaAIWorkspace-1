# 17 — Nền tảng, trình duyệt và phân phối

> Trả lời: **app chạy được ở đâu, mất gì ở từng nền tảng, đóng gói & host thế nào.**
> Số liệu support kiểm chứng 2026-11-14 (caniuse + tài liệu WebCodecs). Có **đính chính** một số nguồn blog nói sai (xem 17.6).

## 17.1. Web MIDI — bảng thật (nguồn: caniuse.com/midi)

| Trình duyệt | Hỗ trợ | Ghi chú |
|---|---|---|
| Chrome desktop | ✅ 43+ | mặc định bật |
| Edge | ✅ 79+ | |
| Opera / Samsung Internet | ✅ | |
| **Firefox desktop** | ✅ 108+ | nhưng phải **cài Site Permission Add-On** rồi cấp quyền — UX lằng nhằng |
| Firefox Android | ❌ | không có |
| **Safari (macOS/iOS/iPadOS)** | ❌ **không có, mọi phiên bản** | WebKit từ chối vì lý do fingerprinting, không có roadmap |
| Chrome/Edge/Firefox **trên iOS** | ❌ | mọi browser iOS đều phải dùng WebKit |
| Giải pháp thay thế trên Safari | Extension "Web MIDI for Safari" (Safari 18.4+) | là userland, không phải chuẩn → không thể dựa vào |

**Kết luận chiến lược:**
- **Desktop Chrome/Edge là nền tảng chính** cho "chơi đàn thật" (đúng yêu cầu người dùng).
- Safari/Firefox: chơi được bằng **bàn phím máy tính + chuột/touch**, không có MIDI → phải thiết kế fallback tử tế (velocity từ vị trí click, mapping phím rõ ràng).
- Mobile (iOS): **không MIDI** → chỉ chơi on-screen, hoặc mic (P2). Đừng hứa "cắm đàn vào iPhone" trên web.

Cần thêm:
- `navigator.permissions.query({name:'midi'})` để biết đã có quyền chưa (không hiện prompt lại).
- `access.onstatechange` để bắt cắm/rút thiết bị.
- Gửi output: `MIDIOutput.send([0x90, note, vel], timestampMs)` — dùng cho **đèn phím** và "app chơi mẫu trên đàn của bạn".

## 17.2. WebCodecs — bảng thật (dùng cho export video)

| Trình duyệt | WebCodecs | Ghi chú |
|---|---|---|
| Chrome / Edge | ✅ 94+ (desktop), Chrome Android đủ gần đây | đầy đủ video + audio |
| Firefox | ✅ **130+ desktop** | **Firefox Android: không có** |
| Safari | **26+** đầy đủ (video + audio) | Safari 16.4–18.7: **chỉ có video**, `AudioEncoder` undefined |
| Opera / Samsung | ✅ | |

**Encode codec — thực tế không đối xứng:**

| Codec | Encode được ở đâu | Dùng làm gì |
|---|---|---|
| H.264 (AVC) | gần như mọi nơi (Chrome, Safari; Firefox phụ thuộc OpenH264) | **mặc định MP4** — phổ biến nhất để upload |
| AAC | Chrome, Safari — **Firefox không có** (và desktop Linux thường không) | audio cho MP4 |
| Opus | **mọi nơi** (WebCodecs) | audio cho WebM |
| VP9 / AV1 | Chrome/Edge tốt; Safari/Firefox tùy máy | WebM nhẹ, royalty-free |
| **MP3** | **encode gần như không hỗ trợ ở đâu** | đừng hứa export MP3 bằng WebCodecs |
| FLAC | decode phổ biến, encode hạn chế | |

→ NoteFall đã làm đúng: preset **H.264/AAC (MP4)** + **VP9/Opus (WebM)** + **AV1/Opus**, và **probe** `VideoEncoder.isConfigSupported` / `AudioEncoder.isConfigSupported` trước khi render (`export/codec/preflight.ts`). Giữ nguyên logic này, chỉ thêm preset/aspect.

**Nếu muốn MP3**: phải dùng encoder JS (`lamejs`, LGPL-3.0) — nên load động, hoặc bỏ ý định MP3 và dùng WAV/FLAC/Opus.

## 17.3. Ngân sách độ trễ (đo/đối chiếu nhiều nguồn)

| Thành phần | Độ trễ |
|---|---|
| USB MIDI cable | <1 ms |
| Bluetooth MIDI | 15–40 ms (jitter cao) |
| Browser xử lý MIDI event | 1–3 ms |
| `AudioContext` scheduling + baseLatency | 0–20 ms (tùy máy, `latencyHint:'interactive'`) |
| Tai nghe có dây | ~1–5 ms |
| **Tổng (USB + tai nghe dây)** | **~5–25 ms → chơi tốt** |
| **Tổng (Bluetooth MIDI + tai nghe Bluetooth)** | **60–120 ms → không chơi được** |

→ Trong UI: nếu thiết bị MIDI là Bluetooth (tên thường có "BLE"/"Bluetooth"), hiện **badge cảnh báo** + gợi ý dùng cáp. Nếu người dùng chọn output Bluetooth, cảnh báo tương tự.

**Mục tiêu kỹ thuật của app:**
- ≤ 30 ms cảm nhận → tốt (mục tiêu chính).
- 30–50 ms → chấp nhận được, hiện gợi ý calibration.
- > 50 ms → hiện cảnh báo + hướng dẫn.

**Ba việc bắt buộc để đạt mục tiêu:**
1. Preload sample **trước** khi người dùng bấm phím đầu (77 MB tải 1 lần, cache; lần sau từ Cache Storage). Nếu không, phím đầu tiên bị trễ 0.5–2 s.
2. Schedule bằng `AudioContext.currentTime`, **không** `setTimeout`.
3. `resume()` context đúng cách (xem 16.1 — MIDI không tính là gesture).

## 17.4. Đóng gói & phân phối — bảng quyết định

| Cách | Kích thước | Web MIDI? | WebCodecs? | Offline | Ghi chú |
|---|---|---|---|---|---|
| **PWA (web)** | 0 (tải theo) | ✅ trên Chrome/Edge desktop | ✅ | ✅ sau lần đầu (Service Worker + Cache) | **Khuyến nghị chính. Nhanh nhất, cập nhật tức thì, không cần cài** |
| **Electron** | ~150–250 MB | ✅ **mọi nơi** (Chromium đi kèm) | ✅ | ✅ | Nặng nhưng **đồng nhất** — nếu muốn "app desktop thật" có MIDI trên cả macOS |
| **Tauri** | ~5–15 MB | ⚠️ **Windows ✅ (WebView2/Chromium), macOS ❌ (WKWebView), Linux ❌ (WebKitGTK)** | ⚠️ tùy WebView | ✅ | Nhẹ, nhưng **mất MIDI trên macOS/Linux** → không phù hợp mục tiêu chính |
| **Capacitor (iOS)** | ~20–40 MB | ❌ (WKWebView) | ✅ iOS 16.4+ (video), 26+ (audio) | ✅ | iOS: chỉ on-screen + mic |
| **Capacitor (Android)** | ~10–20 MB | ⚠️ tùy WebView (Chrome WebView thường có) | ⚠️ | ✅ | Test thực tế từng máy |
| **Native (Swift/Kotlin)** | — | ✅ | ✅ | ✅ | Ngoài phạm vi; chỉ khi cần chất lượng âm thanh native thật |

**Đề xuất:** **PWA trước** (đúng yêu cầu "chơi trên máy tính"), giữ code sạch để đóng gói Electron sau nếu cần bản offline có MIDI trên macOS. **Đừng chọn Tauri** nếu MIDI là tính năng cốt lõi — vì macOS dùng WKWebView (không có Web MIDI).

## 17.5. Hosting (bao gồm Vercel)

| Hạng mục | Cách làm |
|---|---|
| App (static SPA) | **Vercel** (đang kết nối trong workspace) hoặc Cloudflare Pages/Netlify. `vite build` → `dist/`, rewrite mọi route về `index.html` |
| Sample 480 file (~77 MB) | Đặt trên **CDN/object storage riêng** (Vercel static, Cloudflare R2, Bunny). **Phải bật CORS cho origin của app** — đây chính là lỗi khiến NoteFall phải dùng proxy ở dev |
| Cache | `Cache-Control: public, max-age=31536000, immutable` cho file sample có tên version; app shell `no-cache` |
| Nén | Brotli cho JS/CSS; sample OGG **không** nén lại (đã nén) |
| WASM (nếu audio→MIDI) | Header đúng `application/wasm`; nếu dùng đa luồng cần **COOP/COEP** (cross-origin isolation) → cấu hình header ở Vercel/Cloudflare |
| Analytics | Mặc định **tắt**; nếu bật, dùng loại không cookie (Vercel Analytics/Plausible) và nói rõ trong UI |
| Domain/SSL | Tự động trên Vercel; nhớ HTTPS vì Web MIDI/WebCodecs yêu cầu secure context |
| Giới hạn cần biết | Một số host giới hạn kích thước file tĩnh (Vercel ~100 MB/file mềm) → 480 file OGG nhỏ thì ổn, nhưng đừng gộp thành 1 file lớn |

## 17.6. Đính chính các thông tin sai phổ biến trên blog

| Thông tin gặp trên blog | Thực tế |
|---|---|
| "Safari 18+ hỗ trợ Web MIDI" | ❌ **Sai**. caniuse: Safari không hỗ trợ ở bất kỳ phiên bản nào (kể cả 27.3 TP). Chỉ có extension của bên thứ ba |
| "iPad Safari 17.4+ có Web MIDI" | ❌ Không có trong WebKit chuẩn |
| "Firefox không hỗ trợ Web MIDI" | ⚠️ Đúng một nửa — từ **108+ desktop** có, nhưng cần **Site Permission Add-On**; Android thì không |
| "WebCodecs chỉ Chrome" | ⚠️ Cũ — Firefox 130+ desktop và **Safari 26+** đã có đầy đủ |
| "Export MP3 trong browser dễ" | ❌ Không — `AudioEncoder` không encode MP3 ở đâu; cần lamejs (LGPL) |
| "Bluetooth MIDI không sao, chỉ hơi trễ" | ⚠️ 15–40 ms chỉ riêng MIDI, cộng tai nghe Bluetooth thành 60–120 ms → **không chơi được** |
| "Dùng Tauri nhẹ hơn Electron là xong" | ⚠️ Mất Web MIDI trên macOS/Linux (WKWebView/WebKitGTK) |

## 17.7. Mobile / tablet — thực tế cần chấp nhận

| Vấn đề | Thực tế | Cách xử lý |
|---|---|---|
| Bàn phím 88 phím trên màn hình dọc | Không đủ chỗ | Chế độ 25/49 phím, 2 hàng, cuộn ngang, hoặc xoay ngang |
| Không có MIDI trên iOS | Đúng | On-screen + velocity theo vị trí chạm (không có force touch trên web) |
| Audio latency iOS | Thường 10–40 ms, ổn định | Vẫn chơi được; cảnh báo nếu > 50 |
| WebCodecs iOS | Safari 26+ mới có audio encode | Ẩn export video trên iOS cũ, chỉ export WAV |
| Hiệu năng 3D | GPU mobile yếu | Fallback 2D (Canvas) + giảm particle/bloom, cap `devicePixelRatio` ≤ 2 |
| Pin / nhiệt | 3D + audio liên tục nóng máy | Cho chế độ "tiết kiệm" (giảm FPS, tắt bloom) |
| PWA install | iOS cần "Add to Home Screen" thủ công | Hướng dẫn bằng hình |

## 17.8. Offline & lưu trữ

- **Service Worker**: precache app shell (JS/CSS/font/HTML) + version hoá; cache sample theo yêu cầu (Cache Storage, như NoteFall ~77 MB).
- **Chiến lược sample**: chỉ tải **layer phổ biến** trước (velocity trung bình), lazy các layer khác; hoặc tải theo "tầm quan trọng" (C4 quanh giữa trước).
- **Project**: lưu file người dùng (`.nfz`) — không phụ thuộc IndexedDB. IndexedDB chỉ cho takes + session luyện tập + recent handles.
- **Cập nhật**: version trong `manifest.json` của project; service worker version để không cache JS cũ.
- **Cảnh báo**: nếu đang ghi âm/mở project chưa lưu mà đóng tab → `beforeunload`.

## 17.9. Ngân sách hiệu năng (mục tiêu cụ thể)

| Chỉ số | Mục tiêu | Cách đo |
|---|---|---|
| FPS khi phát bài 2.000 nốt, 1080p | ≥ 55 | Chrome DevTools performance + R3F stats |
| Thời gian load lần đầu (cold, không cache sample) | ≤ 3 s tới "chơi được" (dùng layer mỏng trước) | Lighthouse / PerformanceObserver |
| Load lần sau (có cache) | ≤ 1 s | — |
| Bundle JS chính (gzip) | ≤ 1.2 MB (NoteFall hiện khá nặng vì three + rAC) | `vite build --report` |
| RAM khi phát | ≤ 700 MB (sample đã decode + geometry) | Chrome Task Manager |
| Thời gian export 1080p30 bài 3 phút | ≤ 1× thời lượng bài (máy tầm trung) | đo trực tiếp |
| Độ trễ cảm nhận | ≤ 30 ms | calibration + cảm nhận |
| Thời gian mở MIDI 50k nốt | ≤ 500 ms | đo trực tiếp |

## 17.10. Kiểm thử trên nền tảng (ma trận tối thiểu)

| Nền tảng | Phải test |
|---|---|
| Chrome desktop + USB MIDI | luồng chính: chơi, ghi, wait mode, export |
| Edge desktop | như trên (Chromium) |
| Firefox desktop | không MIDI: PC keyboard, chơi, export WebM |
| Safari macOS | không MIDI: PC keyboard, export MP4 (WebCodecs 26+) |
| Chrome Android | chạm, layout dọc/ngang, hiệu năng, PWA install |
| Safari iOS | chạm, không MIDI, export WAV, PWA |
| Máy yếu (GPU tích hợp cũ) | fallback 2D, giảm hiệu ứng |
| Màn hình 1280×720 | layout không vỡ (NoteFall chặn < 1024 px — cần nới) |
