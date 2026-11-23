# WiFi menu: kiến trúc thông tin và nhật ký audit

Tài liệu này mô tả lần rà soát menu WiFi của bản DSolution 1.83" 2-Mic. Mục tiêu là
**một tính năng chỉ có một chỗ vào**, nhãn phản ánh đúng chức năng, và mọi menu con
thoát được bằng `Back` hoặc nút Esc.

## Trước / sau

Trước đây menu WiFi có 20 mục cấp 1, nhiều mục trùng chức năng nhưng nằm ở nhóm khác
nhau. Sau khi sắp xếp còn 6–8 mục, phần còn lại nằm trong nhóm:

| Cấp 1 | Nội dung |
| --- | --- |
| `WiFi: off / connected / AP mode` | Kết nối, bật AP, tắt WiFi, AP info, Change MAC |
| `WebUI control [ON]` | Bật/tắt WebUI |
| `WiFi Tools` | Wifi Atks, Evil Portal, NetCut, WiFite (S3), Crack Handshake, Brucegotchi, SDR (S3) |
| `Scan & Analyze` | Probe Radar, 2.4 GHz Analyzer, 5 GHz Analyzer (C5), Packet Sniffer, FTM, CSI Radar, Hidden networks |
| `Defense` | WIDS / Deauth Guard, Jamming Detector, LAN Blue-Team Guard |
| `LAN & HTTP` | ARP Scan Hosts, LAN IoT Auditor, Responder, Responder+, NAPT Router, NAPT HTTP Inspector |
| `Remote Access` | Listen TCP, Client TCP, SOCKS4, TelNET, SSH, Wireguard, SSH/Telnet log |

## Các mục trùng đã gộp

| Chức năng | Trước đây xuất hiện ở | Nay |
| --- | --- | --- |
| Evil Portal | menu WiFi, `WiFi Config`, `Wifi Atks → Clone Portal` | `WiFi Tools → Evil Portal` |
| Portal -> NAPT | menu WiFi, mục riêng cấp 1 | `WiFi Tools → Evil Portal` |
| Add/Remove Evil Wifi, gateway, password mode, endpoint | `WiFi Config` | `Evil Portal → Network Settings` / `Captive Endpoints` |
| NAPT Router | menu WiFi, trong `SecLab+ LAN / HTTP` | `LAN & HTTP` |
| Responder / Responder+ | menu WiFi và `SecLab+` | `LAN & HTTP`, cạnh nhau |
| Scan Hosts | menu WiFi | `LAN & HTTP → ARP Scan Hosts` |
| Probe Radar / Sniffer / Analyzer | rải rác ở cấp 1 | `Scan & Analyze` |
| WIDS, Jam Detect, LAN Guard | cấp 1 và `SecLab+` | `Defense` |
| Hidden networks | `WiFi Config` | `Scan & Analyze` (bản LITE: `WiFi Tools`) |
| SSH/Telnet log | `WiFi Config` | `Remote Access` |
| Change MAC | `WiFi Config` | menu kết nối |

Menu `WiFi Config` và `SecLab+ LAN / HTTP` được bỏ vì chỉ còn là lớp trung gian sau khi
các mục đã về đúng nhóm.

## Hành vi được sửa

- `Back` trước đây gọi lại `optionsMenu()`/`configMenu()` từ bên trong một `loopOptions()`
  đang chạy, tạo thêm một tầng menu mỗi lần bấm. Nay `Back` là no-op: `loopOptions()`
  vốn đã trả về sau khi chọn, nên chỉ đóng đúng một tầng.
- `Turn Off WiFi` trước đây chỉ dừng WebUI; nay dừng WebUI **và** ngắt WiFi, và nếu WebUI
  đang bận OTA/đổi WiFi thì hiện cảnh báo thay vì im lặng.
- `Start WiFi AP` trước đây luôn hiện mật khẩu kể cả khi người dùng huỷ; nay chỉ hiện khi
  AP thực sự đã bật, ngược lại báo lỗi.
- `Scan Hosts` trước đây bỏ qua im lặng khi không lấy được netif; nay báo lỗi rõ.
- Nút bật/tắt Hidden networks và SSH/Telnet log giờ vẽ lại đúng nhãn ON/OFF ngay sau khi
  đổi, thay vì đệ quy mở lại cả menu.
- `Wifi Atks` trước đây bật AP tấn công cả khi người dùng bấm `Back`/Esc; nay chỉ bật khi
  thực sự mở danh sách mục tiêu. Menu này cũng dùng tiêu đề `Wifi Atks` nhất quán với các
  menu con khác.
- Chặn xung đột: không mở `Portal -> NAPT` khi NAPT Router đang chạy và ngược lại; trước
  đây chỉ một chiều được kiểm tra.
- Nhãn được tính lại mỗi lần mở menu, nên trạng thái `[ON]`, WiFi connected/AP mode và
  WebUI starting không còn bị cũ.

## Kiểm thử

`tests/wifi-menu/audit-test.py` đọc mã nguồn và kiểm tra:

- mỗi chức năng chỉ xuất hiện trong đúng một menu;
- không còn mẫu `Back` đệ quy;
- mỗi menu con có đúng một `loopOptions` và có `Back`;
- cấp 1 vẫn còn đủ các nhóm và thứ tự nhóm ngắn gọn.

Đây là kiểm tra tĩnh trên mã nguồn, không thay thế việc bấm thử trên thiết bị.

## Chưa thay đổi

- Các biến thể tấn công (`Deauth Flood`, `Enhanced Deauth`, `Karma Attack`, `Clone/Deauth+Clone`)
  vẫn giữ nguyên hành vi; tài liệu này chỉ sắp xếp lại chỗ vào.
- Các board khác dùng chung `WifiMenu`; cần build lại cho từng board để chắc chắn các nhánh
  `CONFIG_IDF_TARGET_*` và `LITE_VERSION` vẫn biên dịch.
