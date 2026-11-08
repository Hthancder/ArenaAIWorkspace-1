# spike — P0 in code

Mục đích: phần **logic** của spec được viết bằng Rust, compile + test **trên GitHub Actions**
(không cần GPU, không cần Windows), rồi `rd.exe` được upload làm artifact để chạy trên máy thật.

| File | Nội dung | Spec |
|---|---|---|
| `src/machine.rs` | hồ sơ máy (adapter/LUID/VRAM/RAM/pin/nhiệt), trần display, phát hiện cross-adapter | §9.4.1, §51.12, §52.7, §53.9 |
| `src/pipeline.rs` | sinh chuỗi GStreamer: desktop, camera, micro — đúng tham số low-latency | §37, §54.5 |
| `src/policy.rs` | guard 3 mức Block/Warn/Silent, **mặc định Warn** | §54.1 |
| `tests/spec_conformance.rs` | spec thành assertion (14 test) | nhiều chương |

## Chạy

```powershell
cargo test        # 14 test, không cần GPU
cargo run -- --demo
```

## Cái CI **không** làm được

Runner không có GPU, không có desktop, không capture được (§45.7). Nên p95 glass-to-glass,
NVENC/QSV thật, VDD slot, khởi động sau login vẫn phải chạy trên máy bạn (§51.6, §53.12).

## Chạy kiểm tra (thay CI khi Actions tắt — spec §56.8)

```sh
./spike/check.sh
```

Làm đúng 3 bước của job `test`: `cargo build` với `-D warnings` -> `cargo test`
(16 test) -> `cargo run -- --demo`. Khoảng 3 giây.

Không có `cargo` và `static.rust-lang.org` bị chặn (như sandbox đã viết spec)?
Cài Rust từ npm:

```sh
npm install -g @rust-sandbox/rust-1-95-x86_64-linux
export PATH="$HOME/.local/rust/bin:$PATH"
```

## Trạng thái đã kiểm (2026-11-08)

- `cargo build` với `RUSTFLAGS=-D warnings`: sạch.
- `cargo test`: **16/16 pass**.
- `cargo run -- --demo`: exit 0.
- `clippy`: **chưa chạy lần nào** (không có trong toolchain npm; chỉ CI, mà CI
  đang `startup_failure` ở mức repo).
