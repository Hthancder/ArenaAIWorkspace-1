# 27 — Bảo mật & quyền riêng tư

> App xử lý **file của người dùng** (MIDI, ảnh, video, project zip) và chạy hàng chục nghìn dòng JS bên thứ ba. Bảo mật ở đây chủ yếu là **không để file người dùng làm hại máy họ**, và **giữ đúng lời hứa "không upload"**.

## 27.1. Mô hình mối đe doạ (thực tế, không hoang tưởng)

| Mối đe doạ | Khả năng | Hậu quả | Xử lý |
|---|---|---|---|
| **File `.nfz` độc hại (zip bomb)** | Trung bình | Treo tab / hết RAM | Giới hạn kích thước + số entry khi giải nén |
| **MIDI dị dạng** (hàng triệu event, độ dài vô lý) | Trung bình | Treo, crash | Giới hạn số event, độ dài, thời gian parse; parse trong Worker |
| **Tên track/nốt chứa HTML** | Thấp nhưng dễ mắc | XSS nếu render bằng `innerHTML` | Luôn render bằng text node / React (đã escape) |
| **Ảnh/video background độc hại** | Thấp | Lỗi decode, tốn RAM | Giới hạn dung lượng, dimension, thời lượng |
| **Service worker bị chiếm** (nếu có lỗ hổng) | Rất thấp | Chèn mã độc lâu dài | CSP chặt, không `eval`, kiểm soát build |
| **Supply chain (npm)** | **Cao** (phổ biến nhất) | Mã độc trong dependency | Lockfile, `npm audit`, Dependabot, pin version, tránh package lạ |
| **CDN sample bị thay nội dung** | Thấp | Hại âm thanh, không phải mã | HTTPS + immutable + hash kiểm tra (tuỳ chọn) |
| **Rò rỉ file người dùng qua analytics** | Nếu làm sai | Vi phạm lời hứa | Mặc định không gửi gì; analytics không có nội dung |
| **Lừa đảo "upload để lưu"** | — | Mất niềm tin | Nói rõ: file xử lý tại máy, lưu local |

**Ngoài phạm vi:** tấn công có chủ đích vào người dùng cụ thể, malware cài sẵn trên máy — app web không phòng được.

## 27.2. Hardening cụ thể (theo thứ tự ưu tiên)

### (1) Giải nén `.nfz` an toàn
```ts
const LIMITS = {
  maxZipBytes: 200 * 1024 * 1024,   // 200 MB file zip
  maxEntries: 64,                    // dự kiến 3–5
  maxEntryBytes: 100 * 1024 * 1024,  // 1 asset tối đa 100 MB
  maxTotalUncompressed: 400 * 1024 * 1024,
}
```
- Kiểm tra **kích thước khai báo** trước khi giải nén; đếm entry; cộng dồn uncompressed size; **dừng ngay** khi vượt.
- Chỉ chấp nhận đường dẫn trong `assets/` và `manifest.json`; **chặn `../`, đường dẫn tuyệt đối, ký tự NUL** (path traversal).
- Validate `manifest.json` bằng schema (appVersion, name, settings object) — không tin dữ liệu.
- Giải nén trong **Web Worker** để không treo UI.

### (2) Parse MIDI an toàn
- Giới hạn: file ≤ 100 MB, số track ≤ 256, số event ≤ **2 triệu**, độ dài ≤ 6 giờ.
- Nếu vượt: từ chối kèm thông báo rõ (xem file 19.8).
- Parse trong Worker; timeout 10 s → huỷ.
- Không `eval`, không dựng hàm từ dữ liệu.

### (3) Render dữ liệu người dùng
- Tên track, tên bài, text feedback: **chỉ text node** (React tự escape). Không `dangerouslySetInnerHTML`.
- Nếu cần hiển thị "rich" (ví dụ hợp âm), whitelist ký tự.
- URL ảnh background: chỉ chấp nhận `blob:` tạo từ file người dùng, không nhận URL ngoài (tránh SSRF/tracking).

### (4) CSP & header
```
Content-Security-Policy:
  default-src 'self';
  script-src 'self';
  style-src 'self' 'unsafe-inline';        /* Tailwind + style động */
  img-src 'self' blob: data:;
  media-src 'self' blob:;
  connect-src 'self' https://samples.example.com;
  worker-src 'self' blob:;
  frame-ancestors 'self';                   /* cho phép preview cùng origin */
  object-src 'none';
  base-uri 'self';
```
- **Không** dùng `'unsafe-eval'` (trừ khi WASM cần — `wasm-unsafe-eval` cho phép WASM).
- Nếu dùng PostHog/analytics: phải thêm domain vào `connect-src` — hoặc tốt hơn, **bỏ**.
- Bật `Trusted Types` nếu không vướng thư viện (tùy chọn nâng cao).

### (5) Supply chain
- `package-lock.json` commit; CI dùng `npm ci`.
- `npm audit --omit=dev` trong CI; Dependabot/Renovate bật.
- Hạn chế dependency mới: ưu tiên package có license rõ, nhiều maintainer, ít dependency con (xem file 14).
- Với thư viện nặng (three, rAC): pin version, không auto-merge major.
- Nếu dùng CDN ngoài cho script: **SRI** (`integrity="sha384-..."`) — tốt nhất là **không** dùng CDN script.

### (6) File System Access & quyền
- Chỉ xin quyền khi người dùng bấm (open/save), không tự động.
- Lưu handle trong IndexedDB → có thể **hết hạn**; luôn re-check và fallback.
- Không giữ quyền ghi sau khi lưu xong nếu không cần.

## 27.3. Quyền riêng tư: bản đồ dữ liệu

| Dữ liệu | Rời khỏi máy? | Lưu ở đâu | Ghi chú |
|---|---|---|---|
| File MIDI | **Không** | RAM + `.nfz` trên đĩa người dùng | |
| Bản ghi (takes) | **Không** | IndexedDB | có thể mất khi clear site data → nhắc export |
| Project `.nfz` | **Không** | Filesystem người dùng | đây là lý do chọn file-based |
| Ảnh/video background | **Không** | trong `.nfz` | |
| Settings | **Không** | localStorage + `.nfz` | |
| Phiên luyện tập | **Không** | IndexedDB | có thể export JSON |
| Telemetry | **Mặc định không** | — | nếu bật: không cookie, không nội dung |
| Lỗi/crash report | **Chỉ khi người dùng bấm gửi** | server của mình hoặc GitHub issue | phải hiện nội dung trước khi gửi |
| Yêu cầu sample | Có (chỉ tên file) | CDN | lộ việc "đang chơi đàn" + IP |

**Những gì phải nói rõ trong UI/README (trung thực, không marketing quá):**
1. "File MIDI, bản ghi và project **không được tải lên** — xử lý tại máy bạn."
2. "Chúng tôi tải sample piano từ CDN (tên file + IP được ghi nhận như mọi trang web)."
3. "Không có tài khoản, không có cloud, không bán dữ liệu."
4. Nếu bật analytics: "Thống kê ẩn danh, có thể tắt trong menu."

## 27.4. License compliance như một phần của bảo mật pháp lý

- **Salamander CC BY 3.0** → màn hình Credits + link license + tên tác giả (Alexander Holm).
- **NoteFall (nếu fork)** → giữ `LICENSE.md` + `Required Notice` (PolyForm Shield).
- **Thư viện**: MIT/BSD/Apache/MPL/Zlib → giữ copyright notice; nếu phân phối bản build, có thể tạo trang "Third-party licenses" tự sinh từ `license-checker`.
- **Không** đóng gói sample có license cấm thương mại (kiểm tra GeneralUser GS, FluidR3).
- Nếu publish: thêm `LICENSE` cho **code của mình** (ví dụ MIT) trừ phần phải giữ PolyForm.

## 27.5. Vận hành & phản ứng sự cố

| Tình huống | Việc cần làm |
|---|---|
| Phát hiện lỗi XSS/zip bomb | Vá + phát hành bản mới; thông báo trong app; bump cache version |
| Dependency bị compromise | `npm audit`, pin bản an toàn, rebuild, kiểm tra bundle diff |
| CDN sample bị lỗi | Fallback sang synth tạm; hiện thông báo; đổi domain nếu cần |
| Người dùng báo mất dữ liệu | Hướng dẫn tìm `.nfz`, IndexedDB, export; cải thiện cảnh báo |
| Bị report bản quyền nội dung | Không host nội dung → chuyển tiếp hướng dẫn; không cần gỡ app |

**Kênh báo lỗi bảo mật:** file `/.well-known/security.txt` + email; chính sách "không truy cứu người báo lỗi thiện chí" (nếu muốn).

## 27.6. Những điều **không** nên làm

- Không thêm backend "để lưu project" khi chưa cần — mở ra trách nhiệm bảo mật, GDPR, chi phí.
- Không dùng `eval`, `new Function`, `innerHTML` với dữ liệu người dùng.
- Không nhận URL ảnh/âm thanh từ xa (chỉ file local).
- Không bật analytics mặc định; không gửi nội dung file.
- Không tự động tải và chạy script từ CDN bên thứ ba.
- Không lưu MIDI của người dùng ở server "để cải thiện AI" mà không có sự đồng ý rõ ràng.

## 27.7. Checklist bảo mật trước khi publish

- [ ] Giới hạn zip/midi/ảnh đã code + có test (file zip bomb giả, MIDI 3 triệu event).
- [ ] Không có `dangerouslySetInnerHTML` với dữ liệu người dùng (grep).
- [ ] CSP + `Permissions-Policy` + `nosniff` đã bật trên domain thật.
- [ ] `npm audit` sạch (hoặc có lý do cho từng cảnh báo).
- [ ] Không còn analytics/feedback endpoint của NoteFall.
- [ ] Trang Credits/Licenses đủ (Salamander, font OFL, libs).
- [ ] README nêu đúng 4 điểm ở 27.3.
- [ ] `security.txt` + email (tuỳ chọn nhưng nên có).
- [ ] Kiểm tra: mở app không có request lạ (DevTools Network, chỉ thấy CDN sample).
