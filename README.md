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
| [`docs/remote-desktop-spec.md`](docs/remote-desktop-spec.md) | **Spec thiết kế, ~6 500 dòng, §1–§56.** Kiến trúc, giao thức, pipeline mã hoá video, UI, bảo mật, edge case |
| [`docs/remote-hidden-window-guide.md`](docs/remote-hidden-window-guide.md) | Cách chạy một cửa sổ trên máy bị điều khiển mà **màn hình thật ở nhà không thấy** |
| [`spike/`](spike/) | Rust, **0 dependency**: sinh chuỗi GStreamer (desktop/camera/mic), guard chính sách 3 mức, **tầng bảo mật** (`security/`: token, lockout, CSRF, wid, input, cleanup) — **100 test** |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: `clippy -D warnings` → `cargo test` → build `rd.exe` + artifact |

## Máy đích

Dell Inspiron 7467 · i5-7300HQ · HD 630 + GTX 1050 4 GB · 8 GB RAM · Wi-Fi
Intel 8265. Encoder mặc định là **QSV** (iGPU), dGPU để nguội.

## Chạy app mock đầu-cuối

Trên máy phát triển: `npm run mock` → mở `http://127.0.0.1:4173` (Node.js, không cần package install).

Trên laptop Windows không cần cài Node/Rust: GitHub → **Actions** → run thành công mới nhất → **Artifacts → `lantern-mock-windows-x64`** → giải nén và chạy `lantern-mock.exe`. App tự mở browser, bind loopback và lưu mock settings trong `%LOCALAPPDATA%\\LanternMock`.

Đây chưa phải remote desktop hoàn chỉnh. Exe có **probe phần cứng thật**: đọc Windows/GPU/RAM/Wi-Fi/monitor, kiểm tra GStreamer plugins và — khi bạn bấm — capture 150 frame DXGI trong 5 giây rồi huỷ vào fakesink. Frame không lưu hay gửi qua mạng. Chưa có session streaming WebRTC, gửi input, camera/micro/audio phiên hay truy cập LAN/Internet. Artifact `rd-windows-x64` khác là CLI pipeline spike.

## Chạy kiểm tra

```sh
./spike/check.sh          # build -D warnings -> 100 test -> smoke-run, ~2 giây
node --check web/app.js   # kiểm cú pháp JavaScript của mock
npm test                 # integration test API + chặn XSS/innerHTML (T5)
```

Phần nào đó là **[CỨNG]** trong spec thì phải có test ở đây — bảng đối chiếu §41.10 → test nằm ở [spec §57.3](docs/remote-desktop-spec.md).

## Ghi chú bảo mật

Repo này **không chứa** credential, khoá, mật khẩu hay cấu hình máy thật —
đã quét toàn bộ lịch sử git. `.gitignore` chặn sẵn `config.json`, `*.pem`,
`*.key`, và các file báo cáo chẩn đoán (chứa hostname/IP/MAC).

Đây là công cụ **điều khiển máy tính từ xa**: chỉ dùng cho máy của chính bạn.
Đừng dán log chẩn đoán, ảnh chụp màn hình, hay `config.json` vào issue công khai.

## Giấy phép

MIT — xem [`LICENSE`](LICENSE).
