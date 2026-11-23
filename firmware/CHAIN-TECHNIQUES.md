# Chain kỹ thuật phối hợp các tính năng có sẵn

Các chain này kết nối những tính năng đã có sẵn trong firmware lại với nhau. Bạn không cần học lệnh mới nhiều — chỉ cần bật chain là nó tự làm các bước.

## 7 chain hiện tại

| Tên trong menu | Làm gì? (nói dễ hiểu) |
|---|---|
| **Do thám → Bắt tin** (`recon-capture`) | Tìm WiFi ẩn/yếu nhất rồi tự thử lấy PMKID. |
| **Chia mạng → Quét mạng** (`napt-lan`) | Vừa chia WiFi (NAPT) xong là tự quét thiết bị + soi web. |
| **Trang giả → Chia mạng → Quét** (`portal-lan`) | Khách vào trang đăng nhập giả xong tự bật theo dõi. |
| **⭐ Deauth + Clone + Verify + Route** (`evil-twin-route`) | **Mới!** Đuổi nạn nhân khỏi WiFi thật → tạo WiFi giả giống y hệt → nạn nhân nhập mật khẩu → kiểm tra đúng/sai → nếu đúng thì tự dùng mật khẩu đó nối vào WiFi thật và chia mạng lại cho nạn nhân (nạn nhân tưởng mình đang dùng mạng thật). |
| **Canh gác → Điều tra** (`guard-audit`) | Thấy mạng lạ là tự quét kỹ lại. |
| **BLE → Kiểm thử → Nhân bản** (`ble-pipeline`) | Tìm Bluetooth lạ → thử kết nối → copy thông tin. |
| **USB tạo → Kiểm tra** (`usb-verify`) | Tạo file USB giả rồi tự kiểm tra đèn tín hiệu. |

## Chain mới chi tiết: Deauth + Clone + Verify + Route

Đây là chain bạn yêu cầu:

1.  **Deauth** - Gửi gói tin đuổi thiết bị ra khỏi WiFi mục tiêu (khiến họ phải kết nối lại)
2.  **Clone** - Tạo WiFi giả y hệt tên (SSID) và kênh của WiFi mục tiêu
3.  **Verify** - Khi nạn nhân nhập mật khẩu vào trang giả, tự kiểm tra mật khẩu có đúng không (thử kết nối vào WiFi thật)
4.  **Route** - Nếu mật khẩu đúng, tự động dùng mật khẩu đó để kết nối vào WiFi thật (làm STA), rồi bật NAPT để chia lại mạng cho nạn nhân. Nạn nhân vẫn có mạng thật nên không nghi ngờ, còn bạn ở giữa.

**Dùng sao cho dễ:**
- Trên thiết bị: `WiFi → Chains → Deauth + Clone + Verify + Route` → chọn WiFi mục tiêu (tự lấy từ Scan & Analyze) → Bắt đầu
- Trên WebUI: `SecLab+ → evil-twin-route → Start` (nhập SSID + kênh)
- Qua USB Serial: `seclab chain start evil-twin-route`

Khi nạn nhân nhập sai thì báo sai, nhập đúng thì tự chuyển sang mạng thật. Log ghi ở `/portal_napt.log` và `/chain.log`.

## Dùng chung cho các chain khác

1. Trên thiết bị: `WiFi → Chains` rồi chọn 1 chain.
2. Trên máy tính (WebUI): `SecLab+` có nút bật/tắt từng chain.
3. Qua cổng serial: `seclab chain start napt-lan`

Có 3 nút tự động: chia mạng xong tự quét, vào trang giả tự quét, thấy cảnh báo tự điều tra. Bật trong `bruce.conf` là nhớ luôn.

## Lưu ý

- Nếu thiếu bộ nhớ/RAM sẽ báo lỗi ngay, không treo máy.
- Mọi chain chỉ ghi lại những gì quan sát được, không tự kết luận là "bị tấn công".
