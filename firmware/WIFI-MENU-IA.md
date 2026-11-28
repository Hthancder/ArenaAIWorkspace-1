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
- Menu WiFi giữ nguyên cấp đang mở sau khi thoát một nhóm; trước đây chọn một mục là rơi
  thẳng về Main Menu. Esc ở cấp WiFi đóng menu, Esc trong nhóm con quay về cấp WiFi.
- `Network info` dùng chung cho STA và AP-only; trước đây chế độ chỉ có AP không xem được
  SSID/IP của AP.
- Nhãn mới được cập nhật trong Feature Guide (`Packet Sniffer`, `2.4 GHz Analyzer`,
  `WIDS / Deauth Guard`, `ARP Scan Hosts`) để giữ nguyên nội dung hướng dẫn.

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

## Beacon SPAM: số lượng chọn được + deauth song song

Trước đây `Beacon SPAM` chỉ có một kiểu chạy: phát mãi cho tới khi bấm nút, và
phát một mình. Nay hai thứ đó đều chọn được ngay trước khi chạy.

### Đường đi trong menu (không thêm màn mới)

```
WiFi → WiFi Atks → Beacon SPAM
        ↓ chọn nguồn SSID (Funny / Ricky / Random / Single / Custom file)
        ↓ Beacon Count      ← mới: Unlimited, 50, 100, 500, Custom…
        ↓ Deauth in parallel ← mới: No / Yes same channel / Yes sweep all channels
        ↓ màn chạy: đếm beacon + đếm deauth + kênh hiện tại
```

### Hai menu mới

| Menu | Lựa chọn | Ý nghĩa |
|---|---|---|
| `Beacon Count` | `Unlimited (until stop)` | như hành vi cũ, chỉ dừng khi bấm BACK |
| | `50 / 100 / 500 beacons` | dừng đúng số, hiện màn "done" rồi về menu |
| | `Custom…` | bàn phím số, `0` = không giới hạn, tối đa 100000 |
| `Deauth in parallel?` | `No` | chỉ phát beacon |
| | `Yes - same channel` | beacon + deauth trên đúng kênh đang phát |
| | `Yes - sweep all channels` | beacon + deauth, deauth tự nhảy kênh 1…11 |

### Vì sao phải gộp vào một vòng lặp

Card WiFi chỉ nằm được ở **một kênh tại một thời điểm**. Nếu chạy deauth ở một
task riêng song song thì hai bên giành nhau `esp_wifi_set_channel()`: beacon sẽ
phát lẫn sang kênh của deauth và ngược lại. Vì vậy "song song" ở đây được làm
đúng cách: **một vòng lặp, mỗi lượt phát 1 beacon rồi phát 3 frame deauth**, kênh
do một biến duy nhất quyết định.

Số liệu thực tế của vòng lặp (đã test trên máy tính, xem dưới):

- 1 beacon ↔ 3 frame deauth mỗi lượt;
- chế độ sweep nhảy kênh sau mỗi lượt, chế độ same-channel đứng yên;
- chế độ không kèm deauth thì cứ hết danh sách SSID lại nhảy kênh như bản cũ
  (`nextChannel()` sau mỗi lượt vòng qua danh sách) — **giữ nguyên hành vi cũ**;
- dừng đúng số beacon đã chọn, không phát thừa.

### Nút bấm khi đang chạy

| Nút | Tác dụng |
|---|---|
| `Sel` (Boot) | tạm dừng / chạy tiếp |
| `Esc` (giữ Boot) | dừng và về menu |

Trước đây không có tạm dừng.

### Kiểm thử

`tests/beacon-spam/run.sh` **trích thẳng** đoạn mã trong
`src/modules/wifi/wifi_atks.cpp` (hàm sinh SSID + vòng lặp truyền) rồi biên dịch
và chạy trên máy tính, nên test không thể lệch khỏi code thật. Các trường hợp
đang được khoá:

1. dừng đúng 1 / 5 / 100 beacon;
2. 10 beacon + deauth = đúng 30 frame deauth, và 0 frame khi tắt deauth;
3. chế độ sweep thật sự đổi kênh;
4. danh sách SSID **không có newline ở cuối** vẫn phát được mục cuối
   (đây là lỗi bắt được ngay khi viết test);
5. `nextChannel()` vẫn chạy khi hết một lượt danh sách — chống tái phát lỗi
   "beacon đứng một kênh" của bản viết lại đầu tiên;
6. SSID single ghép số đếm không vượt 32 byte; SSID random dài 7–28 ký tự.

`tests/beacon-spam/run.sh /tmp/Bruce` là cách chạy riêng; CI chạy cùng 14 suite khác.
