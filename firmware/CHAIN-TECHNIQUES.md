# Chain kỹ thuật phối hợp các tính năng có sẵn

Các chain này kết nối những tính năng đã có sẵn trong firmware lại với nhau. Bạn không cần học lệnh mới nhiều — chỉ cần bật chain là nó tự làm các bước.

## 6 chain hiện tại

| Tên trong menu | Làm gì? |
|---|---|
| **Do thám → Bắt tin** (`recon-capture`) | Tìm WiFi ẩn/yếu nhất rồi tự thử lấy PMKID. |
| **Chia mạng → Quét mạng** (`napt-lan`) | Vừa chia WiFi (NAPT) xong là tự quét thiết bị + soi web. |
| **Trang giả → Chia mạng → Quét** (`portal-lan`) | Khách vào trang đăng nhập giả xong tự bật theo dõi. |
| **Canh gác → Điều tra** (`guard-audit`) | Thấy mạng lạ là tự quét kỹ lại. |
| **BLE → Kiểm thử → Nhân bản** (`ble-pipeline`) | Tìm Bluetooth lạ → thử kết nối → copy thông tin. |
| **USB tạo → Kiểm tra** (`usb-verify`) | Tạo file USB giả rồi tự kiểm tra đèn tín hiệu. |

> Đã bỏ 2 chain ít dùng: Sonar và Gom bằng chứng.

Mỗi chain chỉ là danh sách bước ngắn, ví dụ `NAPT → LAN Auditor → HTTP Inspector → Responder+`. Trạng thái ghi ở `/chain.log`.

## Dùng thế nào?

1. Trên thiết bị: `WiFi → Chains` rồi chọn 1 chain.
2. Trên máy tính (WebUI): `SecLab+` có nút bật/tắt từng chain.
3. Qua cổng serial: `seclab chain start napt-lan`

Có 3 nút tự động: chia mạng xong tự quét, vào trang giả tự quét, thấy cảnh báo tự điều tra. Bật trong `bruce.conf` là nhớ luôn.

## Lưu ý

- Nếu thiếu bộ nhớ/RAM sẽ báo lỗi ngay, không treo máy.
- Mọi chain chỉ ghi lại những gì quan sát được, không tự kết luận là "bị tấn công".
