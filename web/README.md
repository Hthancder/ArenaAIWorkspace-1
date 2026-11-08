# Lantern web mock

Frontend tĩnh, không dependency, mô phỏng luồng chính của remote desktop theo spec. Không kết nối đến máy Windows và không capture/stream màn hình, camera, micro hay âm thanh.

## Chạy

Từ thư mục gốc repo:

```sh
python3 -m http.server 4173 --bind 0.0.0.0 --directory web
```

Mở `http://localhost:4173`. Hoặc mở `index.html` trực tiếp trong trình duyệt.

## Luồng đã mô phỏng

- Bắt đầu/kết thúc phiên và trạng thái/metrics minh hoạ.
- Window picker, lựa chọn cửa sổ, hai mode xem.
- Bật/tắt khung camera phòng, âm thanh và micro (chỉ trạng thái UI).
- Panel cài đặt searchable với 12 mục T1, nhóm, phạm vi thiết bị/máy chủ, nhãn hiệu lực, lưu cục bộ và khôi phục mặc định.
- Phóng to màn hình, responsive desktop/mobile và thông báo thao tác.

Mọi thông tin màn hình đều được gắn `MOCK`; không có request backend hay quyền thiết bị.
