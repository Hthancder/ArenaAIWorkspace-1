# Remote desktop qua trình duyệt — spec + spike

Thiết kế (và phần code đầu tiên) của một công cụ điều khiển máy Windows từ xa
**bằng trình duyệt**: server chạy trên máy Windows của chính tôi, client là một
tab Chrome — không cài gì trên máy điều khiển.

> **Phạm vi: dùng cá nhân, 1–2 người, chi phí $0.** Không phải sản phẩm thương
> mại. Không multi-tenant, không RBAC, không SLA. Xem §0.3.1 trong spec.

## Trong repo có gì

| Đường dẫn | Nội dung |
|---|---|
| [`web/`](web/) | **App mock chạy được trong trình duyệt**: dashboard, phiên demo, window picker, chế độ cửa sổ/toàn màn hình, camera/phòng, âm thanh/micro và tuỳ chỉnh nhanh. Tất cả là mô phỏng cục bộ, chưa kết nối máy thật |
| [`docs/remote-desktop-spec.md`](docs/remote-desktop-spec.md) | **Spec thiết kế, ~6 500 dòng, §1–§56.** Kiến trúc, giao thức, pipeline mã hoá video, UI, bảo mật, edge case |
| [`docs/remote-hidden-window-guide.md`](docs/remote-hidden-window-guide.md) | Cách chạy một cửa sổ trên máy bị điều khiển mà **màn hình thật ở nhà không thấy** |
| [`spike/`](spike/) | Rust, **0 dependency**: sinh chuỗi GStreamer (desktop/camera/mic), guard chính sách 3 mức, 16 test |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI: `clippy -D warnings` → `cargo test` → build `rd.exe` + artifact |

## Máy đích

Dell Inspiron 7467 · i5-7300HQ · HD 630 + GTX 1050 4 GB · 8 GB RAM · Wi-Fi
Intel 8265. Encoder mặc định là **QSV** (iGPU), dGPU để nguội.

## Chạy app mock

```sh
python3 -m http.server 4173 --bind 0.0.0.0 --directory web
```

Mở `http://localhost:4173`. Mock chỉ chạy trong trình duyệt; chưa kết nối máy Windows, chưa capture camera/micro/âm thanh thật.

## Chạy kiểm tra

```sh
./spike/check.sh          # build -D warnings -> 16 test -> smoke-run, ~3 giây
node --check web/app.js   # kiểm cú pháp JavaScript của mock
```

## Ghi chú bảo mật

Repo này **không chứa** credential, khoá, mật khẩu hay cấu hình máy thật —
đã quét toàn bộ lịch sử git. `.gitignore` chặn sẵn `config.json`, `*.pem`,
`*.key`, và các file báo cáo chẩn đoán (chứa hostname/IP/MAC).

Đây là công cụ **điều khiển máy tính từ xa**: chỉ dùng cho máy của chính bạn.
Đừng dán log chẩn đoán, ảnh chụp màn hình, hay `config.json` vào issue công khai.

## Giấy phép

MIT — xem [`LICENSE`](LICENSE).
