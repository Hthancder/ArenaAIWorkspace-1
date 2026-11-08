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
