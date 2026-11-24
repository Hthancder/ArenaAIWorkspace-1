# Chain kỹ thuật phối hợp các tính năng có sẵn

Các chain này kết nối những tính năng đã có sẵn trong firmware lại với nhau. Bạn không cần học lệnh mới nhiều — chỉ cần bật chain là nó tự làm các bước.

## 7 chain hiện tại

| Tên trong menu | Làm gì? (nói dễ hiểu) |
|---|---|
| **Do thám → Bắt tin** (`recon-capture`) | Tìm WiFi ẩn/yếu nhất rồi tự thử lấy PMKID. |
| **Chia mạng → Quét mạng** (`napt-lan`) | Vừa chia WiFi (NAPT) xong là tự quét thiết bị + soi web. |
| **Trang giả → Chia mạng → Quét** (`portal-lan`) | Khách vào trang đăng nhập giả xong tự bật theo dõi. |
| **⭐ Deauth + Clone + Verify + Route** (`evil-twin-route`) | Đuổi nạn nhân khỏi WiFi thật → tạo WiFi giả giống y hệt → nạn nhân nhập mật khẩu → kiểm tra đúng/sai → nếu đúng thì tự dùng mật khẩu đó nối vào WiFi thật và chia mạng lại **ngay trên WiFi giả đang chạy** (không ngắt kết nối của nạn nhân). |
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
- Qua USB Serial: `seclab chain start evil-twin-route` (hoặc chỉ rõ mục tiêu: `seclab chain start evil-twin-route <ssid> <kênh>`)

Khi nạn nhân nhập sai thì báo sai, nhập đúng thì tự chuyển sang mạng thật. Log ghi ở `/portal_napt.log` và `/chain.log`.

### Vì sao trước đây nạn nhân bị đá văng (và đã sửa thế nào)

Bản cũ ghép 3 công cụ lại nên các "mối nối" tự đá nạn nhân ra khỏi cả hai mạng. Nay
toàn bộ luật nằm trong `evil_twin_logic.h` (có test riêng ở `tests/chain/evil-twin-test.cpp`):

| Lỗi cũ | Hậu quả | Cách sửa |
|---|---|---|
| Deauth chạy mãi, 250 ms/lần | Điện thoại vào lại mạng thật → bị đá tiếp → coi mạng là "lỗi" và **ngừng tự kết nối** (Android chuyển sang 4G) | Deauth thành **cửa sổ ngắn**: 6 burst, giãn 1.2s → 2.4s → 4.8s → 8s rồi **im hẳn**, không bao giờ đá khi có khách đang ở trên WiFi giả |
| Verify gọi `WiFi.begin()` khi đang phát AP | AP+STA buộc AP nhảy sang kênh của STA ⇒ **mọi khách rớt khỏi WiFi giả** | STA bị **ghim đúng kênh của bản sao**, AP không bao giờ nhảy kênh, không tắt AP |
| Verify chạy ngay trong HTTP handler (chặn 6 giây) | Trang đăng nhập timeout ⇒ Android báo "không có internet" và **bỏ mạng** | Trả lời form **ngay lập tức**, việc thử mật khẩu chạy nền ở task khác |
| Handoff tắt AP rồi dựng lại | Mất beacon 10+ giây, BSSID mới, DHCP mới ⇒ điện thoại bỏ cuộc | Bật NAPT **ngay trên AP đang chạy**: giữ nguyên SSID/BSSID/kênh/lease (`naptEnableOnRunningAp`) |
| Sau khi route vẫn redirect captive | Android giữ trạng thái "connected, no internet" | Ngừng DNS hijack (nhường cổng 53 cho NAPT), probe trả **204/200** |
| Sai mật khẩu là mất luôn WiFi giả | Nạn nhân quay lại mạng thật rồi bị đá tiếp | Sai thì **vẫn giữ bản sao** để nhập lại; chỉ báo "sai mật khẩu" |

Trạng thái thật của chain (`Clone` → `Deauth` → `Verify` → `Route` → `Online`) hiện lên
panel **Active Chains & Tools** của WebUI, kèm lý do deauth dừng (`stop-joined`,
`stop-budget`…), số burst và kết quả verify. WebUI trước đây luôn trống vì firmware chỉ
gửi `chain.chains` chứ không gửi `chain.running`.


## Đường bấm trên máy: `WiFi → WiFi Tools → WiFi Attacks → chọn mục tiêu`

Đây là đường dùng thật (không qua chain). Ba mục `Clone Portal`,
`Deauth+Clone`, `Deauth+Clone+Verify` đều đi vào `EvilPortal`. Bản trước ở đây
có 3 lỗi riêng, đã sửa:

| Trước | Bây giờ |
|---|---|
| `Deauth+Clone+Verify` **không deauth gì cả** (deauth chỉ do chain đặt nhịp) | Tự chạy **cửa sổ kick ngắn**: tối đa 6 burst, giãn 1.2s → 8s rồi im |
| Bản cũ hơn thì deauth **mỗi 250 ms không hạn** ⇒ điện thoại bỏ mạng, nhảy 4G | Có trần burst + giãn dần; khách đã vào WiFi giả là **dừng ngay** |
| `verifyPwd` bị bỏ qua `(void)verifyPwd` ⇒ **không hề kiểm tra mật khẩu** | Form trả lời ngay, mật khẩu được thử **nền**; sai thì vẫn giữ WiFi giả và dùng phần burst còn lại kéo khách về |
| Kiểm tra mật khẩu chạy trong HTTP handler ⇒ trang timeout | Trả lời ngay + thử khóa ở task của portal (`EvilPortal::loop()`) |

## Lỗi "bấm mà như không bấm"

Hai nguyên nhân, đều đã sửa và có test chặn tái phát:

| Lỗi | Hậu quả | Cách sửa |
|---|---|---|
| `loopOptions()` gọi `options[chosen].operation()` trực tiếp, trong khi `options` là **vector dùng chung**. Rất nhiều mục lại ghi đè chính vector đó (EvilPortal::setup, target_atk_menu, chain menu) ⇒ lambda đang chạy **bị huỷ giữa chừng** | Bấm xong "không có gì xảy ra", hoặc văng về menu trước, hoặc reboot | **Copy lambda ra biến cục bộ rồi mới gọi** (`std::function<void()> chosenOp = ...`) |
| Mọi menu con của `Chains` dùng chung `options` + `options.clear()`, menu lồng nhau xoá mất mục của menu đang chạy; `evilTwinRouteMenu()` khi chưa có mục tiêu thì `return;` **im lặng** | `WiFi → Chains` nhảy về menu chain, mục con "bấm không ăn" | Mỗi menu con dùng `std::vector<Option>` **riêng**; chưa có mục tiêu thì **hỏi SSID + kênh tại chỗ**, không bao giờ thoát im lặng |

### Nút bấm trên board dsolution-183-2mic

Menu con **không** dùng chạm để chọn. Điều hướng bằng `Prev` / `Next`, rồi
**nhấn `Sel` (phím giữa) để chọn**. `Sel` giữ 520 ms = Back; `Prev`+`Next` cùng
lúc cũng = Back. Sau khi menu vừa mở có 600 ms chống nhận nhầm.


## WebUI / WebOTA bị đơ (mở trang `/ota` rồi máy không phản hồi)

Triệu chứng: vào WebUI, mở trang cập nhật OTA (hoặc chỉ mở rồi đóng), sau đó bấm
nút trên máy **không có gì xảy ra**, phải tháo pin. Nguyên nhân là **vòng lặp màn
hình OTA chiếm task giao diện**:

| Lỗi | Hậu quả | Cách sửa |
|---|---|---|
| `otaUiCheckpoint()` chạy `while (isOtaInProgress())` — task menu bị **giữ nguyên** suốt quá trình nạp, tối đa **90 giây** | Bấm nút nào cũng bị ăn, Esc cũng không thoát được, nhìn như treo máy | Mỗi lần gọi chỉ vẽ **một lát tối đa 300 ms** rồi trả về, menu/watchdog vẫn chạy |
| Mỗi lát lại **xoá sạch phím** (`NextPress = PrevPress = ... = false`) | Người dùng bấm Esc đúng lúc bị xoá ⇒ **không bao giờ thoát** | Không xoá phím nữa; lát ngắn nên phím cũ tự hết hạn |
| `/ota/begin` thành công nhưng **không có chunk nào** (đóng tab, rớt Wi-Fi) vẫn tính là "đang nạp" **90 s** | Máy ôm màn hình OTA cả phút rưỡi dù chẳng có gì đang ghi | Chưa ghi byte nào thì hết hạn sau **30 s**; đã ghi rồi mới dùng 90 s |
| Màn hình OTA không có đường thoát | Phải tháo pin | **Giữ `Prev`** khi đang nạp ⇒ huỷ phiên nạp và về menu |
| Huỷ được gọi từ task giao diện | Có thể `free()` buffer 32 KB trong khi task mạng đang ghi vào đó ⇒ hỏng heap | Task giao diện chỉ **đặt cờ** `s_otaAbortRequested`; task mạng (`AsyncTCP`) mới gọi `Update.abort()` + giải phóng buffer, và trả `409` cho lần gửi chunk kế tiếp |

## Dùng chung cho các chain khác

1. Trên thiết bị: `WiFi → Chains` rồi chọn 1 chain.
2. Trên máy tính (WebUI): `SecLab+` có nút bật/tắt từng chain.
3. Qua cổng serial: `seclab chain start napt-lan`

Có 3 nút tự động: chia mạng xong tự quét, vào trang giả tự quét, thấy cảnh báo tự điều tra. Bật trong `bruce.conf` là nhớ luôn.

## Lưu ý

- Nếu thiếu bộ nhớ/RAM sẽ báo lỗi ngay, không treo máy.
- Mọi chain chỉ ghi lại những gì quan sát được, không tự kết luận là "bị tấn công".
