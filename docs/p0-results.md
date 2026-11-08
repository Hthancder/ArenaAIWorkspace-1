# P0 — kết quả đo trên Dell Inspiron 7467

Cập nhật từ báo cáo người dùng gửi ngày 2026-11-07. Đây là kết quả đọc được từ probe; ô `Chưa đo` không được suy diễn thành đạt/thất bại. Đối chiếu checklist §51.6 và thứ tự laptop §53.12 trong `remote-desktop-spec.md`.

| P0 | Kết quả hiện có | Trạng thái |
|---|---|---|
| 1. Hồ sơ host/GPU | Windows 10 IoT Enterprise LTSC 10.0.19044; RAM 7.9 GB; Wi-Fi Intel Dual Band Wireless-AC 7265 (Up); NVIDIA GeForce GTX 1050, driver 581.57, 4096 MiB; Intel HD Graphics 630, driver 27.20.100.9664 | Có dữ liệu probe; cần đối chiếu topology/LUID ở bước 4 |
| 2. Cài VDD | Danh sách hiện thấy hai `Generic PnP Monitor`; probe không xác nhận được tên display ảo | Chưa xác nhận VDD hoạt động |
| 3. Đặt resolution display ảo | Chưa có display ảo được xác nhận; chưa đo | Chưa đo |
| 4. Topology/LUID capture ↔ encoder | Chưa có LUID của output/display và adapter encoder | Chưa đo; cần làm trước khi kết luận capture trên hybrid GPU |
| 5. DXGI capture chay | `gst-inspect-1.0` không tìm thấy; không thể chạy pipeline capture | Bị chặn bởi GStreamer runtime chưa được cài |
| 6. Encoder/capture pipeline | Laptop spec ưu tiên QSV; NVIDIA có thể là phương án so sánh/fallback. GStreamer runtime/plugin thiếu | Chưa đo; không suy ra encoder hoạt động chỉ từ việc nhận diện GPU |
| 7. WebRTC trong browser | Chưa chạy pipeline/WebRTC | Chưa đo |
| 8. Glass-to-glass p95 | Chưa có luồng video thật để đo | Chưa đo |
| 9. TWCC/bitrate phản hồi | Chưa có kết nối WebRTC/TWCC | Chưa đo |
| 10. Soak 4 giờ / VRAM | Chưa chạy | Chưa đo |
| 11. Audio driver/capture | Probe báo GStreamer WASAPI plugin không sẵn sàng; trạng thái VB-Audio/Virtual Audio Driver chưa được xác nhận | Chưa đo |
| 12. Cài đặt, reboot, auto-start | Chưa thực hiện trên sản phẩm hoàn chỉnh | Chưa đo; thuộc giai đoạn cài đặt sau P0 |

## Kết luận hiện tại

- Máy có cả Intel HD Graphics 630 và NVIDIA GTX 1050; vì vậy không được mặc định DXGI capture và encoder dùng cùng adapter. Bước topology/LUID là cổng trước khi đánh giá hiệu năng.
- Có nhận diện GTX 1050 và báo cáo 4096 MiB VRAM; đây chưa phải phép đo LUID hay phép thử encode.
- Capture, encode, WebRTC, p95 và TWCC hiện vẫn **chưa được đo**. GStreamer runtime thiếu là blocker đo theo spike đã chốt ở §18; chưa có căn cứ để đổi stack.
- Báo cáo này chỉ ghi lại dữ liệu đã gửi. Chưa yêu cầu người dùng chạy lại probe.
