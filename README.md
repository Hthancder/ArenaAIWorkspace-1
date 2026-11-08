# Remote desktop qua trình duyệt — spec + spike

Thiết kế (và phần code đầu tiên) của một công cụ điều khiển máy Windows từ xa
**bằng trình duyệt**: server chạy trên máy Windows của chính tôi, client là một
tab Chrome — không cài gì trên máy điều khiển.

> **Phạm vi: dùng cá nhân, 1–2 người, chi phí $0.** Không phải sản phẩm thương
> mại. Không multi-tenant, không RBAC, không SLA. Xem §0.3.1 trong spec.

## Trong repo có gì

| Đường dẫn | Nội dung |
|---|---|
| [`web/`](web/) | App mock tương tác: dashboard, session controls, window picker, settings T1/T2, responsive mobile |
| [`mock-server/`](mock-server/) | Backend Node.js không dependency: API cho trạng thái, cài đặt, window picker và vòng đời phiên mock |
| [`docs/run-on-windows.md`](docs/run-on-windows.md) | **Chạy thật trên laptop**: cài GStreamer, bấm "Xem máy thật", xem từ điện thoại, lỗi thường gặp |
| [`docs/remote-desktop-spec.md`](docs/remote-desktop-spec.md) | **Spec thiết kế, ~6 985 dòng, §1–§58.** Kiến trúc, giao thức, pipeline mã hoá video, UI, bảo mật, edge case. §57 = tầng bảo mật đã thành code, §58 = xem màn hình thật bằng MJPEG |
| [`docs/remote-hidden-window-guide.md`](docs/remote-hidden-window-guide.md) | Cách chạy một cửa sổ trên máy bị điều khiển mà **màn hình thật ở nhà không thấy** |
| [`spike/`](spike/) | Rust, **0 dependency**: sinh chuỗi GStreamer (desktop/camera/mic), guard chính sách 3 mức, **tầng bảo mật** (`security/`: token, lockout, CSRF, wid, input, cleanup) — **100 test** |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: `clippy -D warnings` → `cargo test` → build `rd.exe` + artifact |

## Máy đích

Dell Inspiron 7467 · i5-7300HQ · HD 630 + GTX 1050 4 GB · 8 GB RAM · Wi-Fi
Intel 8265. Encoder mặc định là **QSV** (iGPU), dGPU để nguội.

## Chạy app mock đầu-cuối

Trên máy phát triển: `npm run mock` → mở `http://127.0.0.1:4173` (Node.js, không cần package install).

Trên laptop Windows không cần cài Node/Rust: GitHub → **Actions** → run thành công mới nhất → **Artifacts → `lantern-mock-windows-x64`** → giải nén và chạy `lantern-mock.exe`. App tự mở browser, bind loopback và lưu mock settings trong `%LOCALAPPDATA%\\LanternMock`.

### Xem màn hình thật trong trình duyệt (bản v3.32)

Exe có nút **◉ Xem máy thật**. Bấm là khung hình chuyển sang **màn hình thật** của laptop (MJPEG ~15 fps). Nút chỉ sáng khi app mở được một phiên DXGI thật; nếu không, nó **nói lý do cụ thể** thay vì hiện khung đen.

**Không phải cài gì.** Bản v3.31 mượn GStreamer ⇒ installer **517 MB** cho 6 element. Bản v3.32 bỏ hẳn: `app/src/jpeg.rs` (~380 dòng, JFIF baseline 4:2:0) và `app/src/capture.rs` (~470 dòng, gọi thẳng DXGI Desktop Duplication qua COM). Exe còn **~2 MB**, 0 phụ thuộc ngoài.

Số đo thật trong sandbox: 1280×720 q70 = **39 KB/frame**, 1080p q70 = **42 ms/frame** (23 fps trên một core). Chi tiết + lý do từng quyết định: spec §58.14–§58.17. Đo trên máy bạn: [`docs/run-on-windows.md`](docs/run-on-windows.md).

Bản này **chỉ có hình**: chưa có tiếng, chưa điều khiển được, chưa phải WebRTC, và chỉ bind loopback (chưa TLS ⇒ không mở ra LAN).

Năm lỗi thật tìm được trong lúc kiểm (kill sai, **FIN ≠ RST**, đọc `stderr` treo, một câu tài liệu hứa chặn LAN mà code không làm, và thiếu bảng lượng tử JPEG) được ghi ở §58.6–§58.16 — mỗi lỗi có test hồi quy. Lỗi JPEG là lỗi đầu tiên **một công cụ ngoài** (ImageMagick) bắt được thay vì một lần chạy thật — giờ nó nằm trong `./spike/check.sh`.

Đây chưa phải remote desktop hoàn chỉnh. Exe có **probe phần cứng thật**: đọc Windows/GPU/RAM/Wi-Fi/monitor, kiểm tra GStreamer plugins và — khi bạn bấm — capture 150 frame DXGI trong 5 giây rồi huỷ vào fakesink. Frame không lưu hay gửi qua mạng. Chưa có session streaming WebRTC, gửi input, camera/micro/audio phiên hay truy cập LAN/Internet. Artifact `rd-windows-x64` khác là CLI pipeline spike.

## Chạy kiểm tra

```sh
./spike/check.sh          # spike (build -D warnings -> 100 test -> smoke-run) + app (32 test) + web, ~10 giây
node --check web/app.js   # kiểm cú pháp JavaScript của mock
npm test                 # integration test API + chặn XSS/innerHTML (T5)
```

`./spike/check.sh` chạy **đúng bộ** mà CI chạy, kể cả `app` — trước v3.30 nó chỉ chạy spike nên có thể "all green" trong khi exe mà bạn tải về không biên dịch được.

Phần nào đó là **[CỨNG]** trong spec thì phải có test ở đây — bảng đối chiếu §41.10 → test nằm ở [spec §57.3](docs/remote-desktop-spec.md).

## Ghi chú bảo mật

Repo này **không chứa** credential, khoá, mật khẩu hay cấu hình máy thật —
đã quét toàn bộ lịch sử git. `.gitignore` chặn sẵn `config.json`, `*.pem`,
`*.key`, và các file báo cáo chẩn đoán (chứa hostname/IP/MAC).

Đây là công cụ **điều khiển máy tính từ xa**: chỉ dùng cho máy của chính bạn.
Đừng dán log chẩn đoán, ảnh chụp màn hình, hay `config.json` vào issue công khai.

## Giấy phép

MIT — xem [`LICENSE`](LICENSE).
