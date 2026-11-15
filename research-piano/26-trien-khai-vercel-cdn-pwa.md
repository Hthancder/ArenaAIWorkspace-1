# 26 — Triển khai: hosting, CDN sample, PWA

> Mục tiêu: app + 480 file sample chạy nhanh, rẻ, không bị CORS, cài được như app, hoạt động offline.
> Số liệu hosting kiểm tra 14/11/2026.

## 26.1. Bài toán băng thông (con số quyết định kiến trúc)

Mỗi người dùng mới tải **~77 MB** sample (480 OGG) + ~1–2 MB JS/CSS.

| Lưu lượng | Băng thông sample | Ghi chú |
|---|---|---|
| 100 người mới/tháng | ~7.7 GB | thoải mái |
| 1.000 người mới/tháng | ~77 GB | **sát trần Vercel Hobby (100 GB)** |
| 10.000 người mới/tháng | ~770 GB | **vượt xa** mọi gói free |
| Người dùng quay lại | ~0 | nhờ Cache Storage / service worker |

→ **Kết luận: KHÔNG đặt 77 MB sample lên Vercel Hobby.** Chỉ cần ~1.300 lượt khách mới là hết 100 GB.

## 26.2. So sánh hosting (2026)

| Nền tảng | Băng thông free | Giới hạn file | Thương mại | Ghi chú |
|---|---|---|---|---|
| **Vercel Hobby** | **100 GB/tháng** | — | ❌ **chỉ phi thương mại** | Vượt hạn mức → deployment bị tạm dừng; Pro $20/người/tháng, 1 TB, quá thì $0.15/GB |
| **Cloudflare Pages** | **Static: không giới hạn** | **20.000 file/site**, **25 MiB/file** | ✅ | 500 build/tháng; Functions 100k request/ngày |
| **Cloudflare R2** | **Egress $0** | — | ✅ | Free 10 GB storage; $0.015/GB-tháng |
| Netlify | 100 GB | — | ✅ (gói free hạn chế) | tương tự Vercel |
| GitHub Pages | ~100 GB mềm | 1 GB repo, 100 MB/file | ✅ | không có header tuỳ chỉnh → khó CORS/COOP |
| Bunny / Backblaze B2 | rẻ | — | ✅ | CDN sample tốt |

**Kiến trúc khuyến nghị:**

```
┌──────────────────────────────┐        ┌─────────────────────────────┐
│ App (JS/CSS/HTML)            │        │ Samples (480 OGG)           │
│ Vercel  ✅ preview/CI tốt     │        │ Cloudflare R2 + custom domain│
│ hoặc Cloudflare Pages        │        │ CORS: https://app.example    │
└──────────────────────────────┘        │ Cache-Control: immutable     │
                                        └─────────────────────────────┘
```

- **Vercel** cho app: đúng thế mạnh (preview mỗi PR, build nhanh, domain). Nhớ điều khoản: Hobby **không thương mại**.
- **R2** cho sample: egress 0 đồng, không lo băng thông, CORS do mình kiểm soát.
- Nếu muốn tất cả ở một chỗ: **Cloudflare Pages** (static không giới hạn băng thông, 25 MiB/file — mỗi OGG ~160 KB nên thoải mái; 480 file < 20.000).

## 26.3. Cấu hình Vercel (`vercel.json`)

```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "/index.html",
      "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
    },
    {
      "source": "/(.*)",
      "headers": [
        { "key": "Permissions-Policy", "value": "midi=(self), microphone=(self)" },
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" }
      ]
    }
  ]
}
```

**Vì sao các header này:**
- `rewrites` → SPA chạy đúng khi mở link trực tiếp (không 404).
- `immutable` cho `assets/` (Vite đã hash tên file) → trình duyệt không tải lại.
- `no-cache` cho `index.html` → người dùng nhận bản mới ngay sau deploy.
- **`Permissions-Policy: midi=(self)`** → bắt buộc nếu app nằm trong iframe (preview, nhúng) — nếu thiếu, MIDI bị chặn dù Chrome hỗ trợ.
- `microphone=(self)` chỉ cần khi làm mic detection (P2).

**Biến môi trường:** `VITE_SAMPLES_BASE_URL=https://samples.example.com/salamander-v3-close` (NoteFall đã dùng biến này).

## 26.4. Cấu hình R2 / CDN sample

| Header | Giá trị | Lý do |
|---|---|---|
| `Access-Control-Allow-Origin` | `https://app.example` (hoặc `*` nếu chấp nhận) | NoteFall bị chặn vì khoá đúng 1 domain — đừng lặp lại |
| `Access-Control-Allow-Methods` | `GET, HEAD` | chỉ đọc |
| `Cache-Control` | `public, max-age=31536000, immutable` | file không đổi tên thì không đổi nội dung; nếu đổi bộ sample → **đổi tiền tố thư mục** (`/salamander-v4-close/`) |
| `Content-Type` | `audio/ogg` | đúng MIME để decode |
| `Accept-Ranges` | `bytes` | cho phép seek/tải từng phần (hữu ích khi resume) |
| Nén | **không** nén OGG | đã nén sẵn; nén lại chỉ tốn CPU |
| ETag/version | bật | cache revalidation nhẹ |

**Kiểm tra nhanh sau khi cấu hình:**
```bash
curl -I https://samples.example.com/salamander-v3-close/C4v8.ogg
# phải thấy 200/304, content-type audio/ogg, cache-control immutable, access-control-allow-origin
```

## 26.5. Chiến lược tải sample (để "chơi được trong 3 giây")

| Bước | Việc | Lý do |
|---|---|---|
| 1 | Tải **app shell** (JS/CSS/HTML) | mở được UI ngay |
| 2 | Tải **layer velocity trung bình** (v8/v9) cho ~30 phím | đủ để chơi thử; nhẹ hơn nhiều so với 480 file |
| 3 | Tải nền các layer còn lại | crossfade mượt khi người dùng chơi mạnh/nhẹ |
| 4 | Cache Storage | lần sau 0 băng thông |
| 5 | Ưu tiên tải quanh C4 trước | người mới chơi ở giữa bàn phím |

- Nếu mạng chậm: cho chơi bằng **synth tạm** (oscillator + envelope) cho tới khi sample sẵn sàng — tránh im lặng.
- Hiện tiến độ theo từng nhóm (30/480, 120/480…) chứ không phải 1 thanh % chung.

## 26.6. PWA: manifest + service worker

**`manifest.webmanifest`:**
```json
{
  "name": "Piano Studio",
  "short_name": "Piano",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#05060a",
  "theme_color": "#05060a",
  "orientation": "landscape",
  "icons": [
    { "src": "/icons/192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "file_handlers": [{ "action": "/open", "accept": { "audio/midi": [".mid", ".midi"] } }]
}
```
- `file_handlers` (Chromium) cho phép mở file `.mid` trực tiếp bằng app đã cài — rất hợp app desktop.
- `display: standalone` + `orientation: landscape` (bàn phím 88 phím cần ngang).

**Service worker (chiến lược):**

| Tài nguyên | Chiến lược | Ghi chú |
|---|---|---|
| `index.html` | network-first, fallback cache | luôn nhận bản mới; offline vẫn mở được |
| `assets/*.js,css` (có hash) | cache-first, immutable | không bao giờ đổi |
| Sample OGG | cache-first, **runtime cache có giới hạn** | dùng `CacheStorage` riêng (`samples-v1`), giới hạn ~120 MB, xoá LRU |
| Font | cache-first | |
| API (nếu có) | network-only | app local-first nên gần như không có |

**Cập nhật app:** service worker `skipWaiting()` + thông báo "Đã có bản mới — tải lại" (không tự reload khi đang chơi/ghi).

**Cảnh báo:** đổi build mà không đổi version cache → người dùng kẹt bản cũ. Dùng hậu tố version trong tên cache, xoá cache cũ trong `activate`.

## 26.7. Cross-origin isolation (COOP/COEP) — chỉ khi cần

- **Cần** nếu dùng `SharedArrayBuffer` / WASM đa luồng (ví dụ `onnxruntime-web` multithread cho audio→MIDI).
- **Hệ quả:** chặn nhúng iframe không có COEP, chặn một số tài nguyên cross-origin (phải có `crossorigin` + CORP header), và **phá preview iframe**.
- **Khuyến nghị:** không bật toàn app. Nếu cần, tách **trang riêng** `/transcribe` bật COOP/COEP; phần chơi nhạc không bật.

## 26.8. Chi phí ước tính

| Quy mô | App hosting | Sample (R2) | Tổng/tháng |
|---|---|---|---|
| 100 người mới/tháng | Vercel Hobby $0 | 7.7 GB egress × $0 + 0.08 GB lưu ≈ $0 | **$0** |
| 1.000/tháng | Vercel Hobby $0 (nếu phi thương mại) | egress $0, storage ~$0 | **$0** |
| 10.000/tháng | Vercel Pro $20 (hoặc CF Pages $0) | egress $0, storage ~$0.1 | **$0–20** |
| 100.000/tháng | CF Pages / Vercel Pro + băng thông | vẫn $0 egress | **$20–40** |

→ **R2 là quyết định quan trọng nhất về chi phí**: egress 0 đồng khiến 77 MB/người dùng không còn là vấn đề.

## 26.9. Checklist go-live

- [ ] `npm run build` không lỗi; `dist/` mở được bằng `npx serve dist`.
- [ ] SPA rewrite hoạt động (mở `/practice` trực tiếp không 404).
- [ ] Sample tải được từ domain thật, **CORS đúng**, không có lỗi trong console.
- [ ] `Cache-Control` đúng cho `assets/` và `index.html`.
- [ ] PWA cài được trên Chrome desktop + Android; mở offline được sau lần đầu.
- [ ] MIDI hoạt động trên domain HTTPS thật (không chỉ localhost).
- [ ] Nếu nhúng iframe: `Permissions-Policy` có `midi=(self)`.
- [ ] Lighthouse: Performance ≥ 80, Accessibility ≥ 95, PWA pass.
- [ ] Không còn endpoint analytics/feedback của tác giả NoteFall.
- [ ] Trang **Credits/Licenses** có Salamander CC BY 3.0 + license thư viện.
- [ ] `robots.txt` + `sitemap.xml` + og:image (nếu muốn SEO).
- [ ] Kiểm tra trên mạng chậm (DevTools throttle "Slow 4G") — vẫn chơi được trong 3–5 s nhờ synth tạm.

## 26.10. Lỗi triển khai thường gặp

| Triệu chứng | Nguyên nhân | Sửa |
|---|---|---|
| "Failed to fetch" khi tải sample | thiếu CORS header | thêm `Access-Control-Allow-Origin` |
| Sample 404 | sai tiền tố đường dẫn / phân biệt hoa-thường | kiểm tra `C4v8.ogg` đúng tên, `#`→`s` |
| MIDI không chạy trên bản deploy, chạy ở localhost | iframe/permissions policy hoặc không phải HTTPS | HTTPS + `Permissions-Policy: midi=(self)` |
| Người dùng thấy bản cũ | `index.html` bị cache | `no-cache` + SW versioning |
| Tải lại 77 MB mỗi lần | thiếu Cache Storage / cache bị xoá | dùng cache-first có version |
| Vercel báo vượt băng thông | để sample trên Vercel | chuyển sang R2/Cloudflare |
| PWA không cài được trên iOS | thiếu icon/maskable hoặc mở trong iframe | thêm icon, mở tab riêng, hướng dẫn "Add to Home Screen" |
| Trang trắng sau deploy | base path sai | `base: '/'` trong `vite.config.ts` |
