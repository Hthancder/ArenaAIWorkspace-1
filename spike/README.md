# spike — P0 in code

Mục đích: phần **logic** của spec được viết bằng Rust, compile + test **trên GitHub Actions**
(không cần GPU, không cần Windows), rồi `rd.exe` được upload làm artifact để chạy trên máy thật.

| File | Nội dung | Spec |
|---|---|---|
| `src/machine.rs` | hồ sơ máy (adapter/LUID/VRAM/RAM/pin/nhiệt), trần display, phát hiện cross-adapter | §9.4.1, §51.12, §52.7, §53.9 |
| `src/pipeline.rs` | sinh chuỗi GStreamer: desktop, camera, micro — đúng tham số low-latency | §37, §54.5 |
| `src/policy.rs` | guard 3 mức Block/Warn/Silent, **mặc định Warn** | §54.1 |
| `src/security/` | **7 file**: SHA-256/HMAC tự viết, lockout, JWT+refresh rotate, CSRF/TLS gate, `wid` registry, input sanitizer, cleanup 5 s | §41, §44, §42.13 |
| `tests/spec_conformance.rs` | spec thành assertion (**26** test, gồm 10 kiểm chứng §41.10) | nhiều chương |

## Chạy

```powershell
cargo test        # 100 test, không cần GPU
cargo run -- --demo   # in pipeline + quyết định bảo mật + các "deviation" so với spec
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
- `cargo test`: **74 unit + 26 conformance = 100 pass**.
- `cargo run -- --demo`: exit 0, in cả phần `security` (§57) và các deviation D-1..D-4.
- `clippy`: **không có trong toolchain npm** của sandbox ⇒ chỉ CI chạy; CI đã xanh
  ở §56.10 với `clippy -D warnings`.

## Đọc gì trước

1. `security/mod.rs` — bảng 6 luật [CỨNG] + `DEVIATIONS` (code khác spec ở đâu, vì sao, khi nào quay lại).
2. `security/token.rs` — chỗ dễ sai nhất: rotate, reuse detection, revoke-all.
3. `security/window.rs` — lỗ hổng leo thang quyền thật (§41.4 T1) nếu bỏ qua.
