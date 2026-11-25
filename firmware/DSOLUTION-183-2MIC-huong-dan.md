# Bruce cho board DSolution 1.83" 2-Mic — hướng dẫn nhanh

Port đã được tạo trong `firmware/Bruce` (bản clone `pr3y/Bruce`, HEAD `2b6ba4d`).

## 1. File đã thêm / sửa

| File | Nội dung |
| --- | --- |
| `boards/dsolution-183-2mic/dsolution-183-2mic.ini` | Env build: ESP32-S3 16MB, PSRAM OPI, driver màn hình, audio, LED, nút, pin |
| `boards/dsolution-183-2mic/NV3023_Panel.h` | Class `lgfx::Panel_NV3023` — **init sequence NV3023** + bảng MADCTL (SwapXY/MirrorY/BGR) |
| `boards/dsolution-183-2mic/interface.cpp` | GPIO, I2C/I2S, PA Enable GPIO4, ES8311 (0x18), ES7210 (0x40), nút, pin, nguồn |
| `boards/dsolution-183-2mic/README.md` | Tài liệu kỹ thuật đầy đủ (tiếng Anh, cùng chuẩn với repo) |
| `include/DisplayDrivers_User_Setup.h` | +6 dòng: include panel class khi `DSOLUTION_183_2MIC` được bật |
| `src/modules/others/mic.cpp` | +6 dòng: cấp MCLK cho đường mic I2S (ES7210 bắt buộc cần MCLK) |
| `platformio.ini` | +1 dòng comment thêm env vào danh sách gợi ý |

Toàn bộ thay đổi cũng được đóng gói thành patch: `firmware/dsolution-183-2mic-bruce.patch`
(`git apply` được vào một bản clone Bruce khác).

## 2. Build & nạp

```bash
cd firmware/Bruce
pio run -e dsolution-183-2mic              # build
pio run -e dsolution-183-2mic -t upload    # nạp qua USB-C (USB-CDC)
pio device monitor                         # 115200
```

Lần build đầu cần Internet: PlatformIO tải platform `pioarduino/platform-espressif32@55.03.39`
và **LovyanGFX (nhánh `develop`)** — nhánh này bắt buộc với ESP32-S3 + Arduino core 3.3.x.

## 3. Màn hình NV3023

* Không dùng ST7789: Bruce mặc định Arduino_GFX, mà Arduino_GFX không có driver NV3023 và
  cũng không cho board tự cắm driver riêng → chuyển backend sang **LovyanGFX**
  (`-DUSE_LOVYANGFX=1 -DLOVYAN_PANEL=Panel_NV3023`) và tự viết panel class.
* Init table trong `NV3023_Panel.h` là bảng của bạn, nguyên văn (gồm 2 lần mở khoá `0xFD`,
  gamma `0xE0..0xE8`, `0x11` delay 200ms, `0x29` delay 10ms).
* `Swap XY + Mirror Y + BGR` → `MADCTL = 0xA8`; `Invert = true` → `-DTFT_INVERTION=1`.
* Hình học: kính 240×284, RAM 240×320, cửa sổ nằm ở hàng 36..319. Không đặt
  `TFT_OFFSET_*` (LovyanGFX tự suy ra 36), nếu đặt thêm sẽ lệch 36 px.
* `TFT_ROTATION=3` (mounting offset) + `ROTATION=0` → mặc định landscape 284×240 đúng như
  bảng thông số; xoay trong Config > Rotation vẫn đúng 4 hướng.
* **SPI 40 MHz** (`-DTFT_WRITE_FREQ=40000000`) — đúng tốc độ mà config ESPHome đang chạy
  được cho box này dùng. Bản đầu để 80 MHz, nay đã hạ xuống.
* Toàn bộ bảng init + `MADCTL = 0xA8` + offset 36 đã được đối chiếu **từng dòng** với
  config ESPHome chạy được trên chính máy này (`mipi_spi`, `model: CUSTOM`,
  `color_order: bgr`, `invert_colors: true`, `dimensions 284x240 offset_width 36`,
  `transform: swap_xy + mirror_y`) → khớp. Vậy nếu vẫn đen thì lỗi ở bus/đèn nền, không
  phải ở bảng thanh ghi.

## 4. Audio

Thứ tự khởi tạo theo yêu cầu: **I2C → I2S → ES8311 → ES7210 → PA Enable**.

* I2C: SDA 12 / SCL 11, gán vào `sys_i2c` (mặc định TwoWire 100 kHz).
* I2S: MCLK 5, BCLK 15, WS 16, DIN 7, DOUT 6 (`speaker_bus`, `mic_bus`).
* PA Enable **GPIO4 = HIGH ngay trong `_setup_gpio()`**, và bật lại sau khi cấu hình ES8311.
* ES8311 (0x18): I2S slave, 16-bit, DAC 0 dB, reset → clock → power → xuất âm thanh.
* ES7210 (0x40): chuỗi thanh ghi của Espressif (`esp_codec_dev`) — reset, HPF, analog,
  I2S 16-bit slave, chia clock cho MCLK = 256 × fs, gain MIC1/MIC2 24 dB, MIC3 0 dB (AEC
  reference), power-on.
* MCLK: 256 × fs. Bruce chạy 48 kHz (thu mic cố định 48 kHz, phát nhạc theo file) nên
  MCLK = 12.288 MHz; nếu ép 24 kHz thì đúng 6.144 MHz như tài liệu. Tỉ lệ 256 là yếu tố
  quyết định, không phải con số tuyệt đối.
* `src/modules/others/mic.cpp`: Bruce vốn không xuất MCLK cho đường mic → đã thêm 4 dòng
  để dùng lại MCLK của `speaker_bus` (không có patch này ES7210 sẽ im lặng).

## 5. Nút & LED

* `HAS_3_BUTTONS`: Prev = Volume Down (40), Next = Volume Up (39), Sel = Boot (0),
  Prev+Next = Esc. Tất cả kéo lên nội, tích cực mức thấp.
* LED: WS2812 GPIO48, GRB, 1 bóng (`HAS_RGB_LED`).

## 6. Pin / nguồn

1. **Pin (GPIO17)** — `-DANALOG_BAT_PIN=17`, `-DANALOG_BAT_MULTIPLIER=2.0f`. Đây là chân
   chia áp 1:2 vào **ADC2 kênh 6**, lấy từ bảng chân đọc trực tiếp trong firmware gốc
   (Xiaozhi) của đúng model `ostb-2st-wifi-double-mic`. Bảng thông số ghi "Battery Status
   GPIO38" là sai: ESP32-S3 chỉ có ADC trên GPIO1–20, GPIO38 không có kênh ADC — dùng 38
   thì % pin luôn sai/0 %.
2. **GPIO47 (Detect Charge)**: mức thấp = đang sạc (open-drain). Nếu ngược, đảo so sánh
   trong `isCharging()`.
3. **GPIO21 (Sleep Control)**: **không còn điều khiển nữa**. Không nguồn cộng đồng nào ghi
   nhận chân giữ nguồn trên board này, mà kéo một chân lạ lên HIGH lúc boot rất dễ gây
   reset liên tục (nhìn từ PC chính là "USB chập chờn"). Muốn thử lại: thêm
   `-DDSOLUTION_LATCH_PIN=21` vào `build_flags`.

## 7. Trạng thái build

Đã build **thành công** trên GitHub Actions (workflow `.github/workflows/build-dsolution-183-2mic.yml`
trong repo này: clone Bruce đúng commit `2b6ba4d`, apply patch, chạy `pio run -e dsolution-183-2mic`):

```
Flash: [===       ]  27.4%  (4.601.355 / 16.777.216 bytes)
RAM:   [====      ]  39.8%  (130.260 / 327.680 bytes)
firmware.bin          = 4.601.904 bytes
firmware-factory.bin  = 4.667.440 bytes   (ảnh gộp, nạp ở 0x0)
```

Run CI mới nhất: **44722383672** (commit `abd84f4`) — PASS. Ảnh gộp được ghép bằng Python
thuần trong `merge_bin.py` (đọc/ghi theo offset, đệm 0xFF đủ 16 MB, kiểm tra lại từng byte và
magic `0xE9`), không phụ thuộc phiên bản esptool nữa — bản trước gọi `esptool merge_bin` và
fail vì esptool đổi tên subcommand/option giữa v4 và v5.

Các kiểm tra đi kèm trong CI (đều PASS):
* `interface.cpp.o` được biên dịch và **chuỗi banner của board có trong firmware.bin** →
  code của board thật sự nằm trong ảnh, không bị thay bằng default rỗng.
* `Panel_NV3023::getInitCommands` / `getMadCtl` / `setRotation` xuất hiện trong object của
  backend LovyanGFX → panel class được dùng đúng.
* 0 warning từ `NV3023_Panel.h`, `interface.cpp`, `mic.cpp`.

Tải firmware: tab **Actions** → run "Bruce build (DSolution 1.83 2-Mic)" → **Artifacts** →
`DSolution-183-2mic-factory` (chứa **một file duy nhất** `DSolution-183-2mic-factory.bin`).

### Nạp — chỉ một file, luôn ở địa chỉ 0x0

```bash
esptool.py --chip esp32s3 --baud 921600 write_flash 0x0 DSolution-183-2mic-factory.bin
# nếu máy đang treo lung tung thì xoá trước:
esptool.py --chip esp32s3 erase_flash
```

File này = bootloader (0x0) + partition table (0x8000) + boot_app0 (0xE000) + app (0x10000),
đúng ~4,7 MB (không đệm cho đủ 16 MB — nạp qua web nhanh gấp ba, ít rủi ro rớt kết nối hơn).
Nạp **sau khi Erase chip** là sạch hoàn toàn; muốn bản đệm 16 MB thì build với
`DSOLUTION_PAD_FACTORY=1`.

> ⚠️ **Đừng nạp `firmware.bin` ở 0x0.** `firmware.bin` được link cho 0x10000; ghi nó vào
> 0x0 là xoá bootloader → chip reset vô hạn, màn hình đen, USB chập chờn. Đây chính là
> lỗi của lần nạp đầu tiên (hướng dẫn cũ trong file này ghi sai).

### Nạp bằng web (online, không cần cài gì)

Dùng được, vì file gộp **vốn đã ở địa chỉ 0x0**. Chỉ cần đúng 3 điều:

1. **Giải nén** artifact trước — GitHub trả về `.zip`, nhiều web flasher từ chối file nén.
   Lấy đúng `DSolution-183-2mic-factory.bin` (~4,7 MB, **không** phải `firmware.bin`).
2. **Địa chỉ = 0x0** và **Flash size = 16MB**. Nếu web flasher không có ô địa chỉ (kiểu
   ESP Web Tools / web.esphome.io) thì nó luôn ghi ở 0x0 → đúng luôn. Nếu có ô địa chỉ
   (espressif.github.io/esptool-js, esptool.spacehuhn.com) thì phải tự nhập `0x0` —
   đừng để mặc định `0x10000`.
3. **Xoá chip trước** nếu tool có nút Erase (esptool-js có nút **Erase**). Máy đang mang
   bootloader hỏng từ lần nạp trước nên bước này đáng làm.

Thao tác:

* Trình duyệt **Chrome hoặc Edge trên máy tính** (cần WebSerial; Firefox/Safari không có).
  Đóng Arduino IDE / PlatformIO Monitor / mọi tab khác đang mở cổng COM — "Failed to
  connect" gần như luôn là do cổng bị chiếm.
* Cắm USB **trong khi giữ nút BOOT** (GPIO0) để vào chế độ download — ở chế độ này kết nối
  ổn định nhất, kể cả khi máy đang treo.
* Baud để **921600**; 4,7 MB sẽ mất **khoảng 1–2 phút**. Đừng rút cáp, đừng đóng tab giữa
  chừng. Nếu đường USB hay rớt thì hạ xuống 460800 (chậm hơn nhưng chắc hơn).
* Xong: rút cáp, cắm lại **không giữ BOOT** để máy chạy firmware. Web flasher đôi khi để
  chip nằm lại ở chế độ download nên lần cắm đầu có thể không thấy gì — rút ra cắm lại.

Công cụ: **espressif.github.io/esptool-js** (chính chủ Espressif, có ô Address + nút
Erase + Flash size), **esptool.spacehuhn.com** (giao diện đơn giản, có ô địa chỉ), hoặc bất
kỳ flasher nào ghi ở 0x0.

### Không có log thì xem bằng gì?

Trang tự viết, **đã deploy sẵn**: <https://dsolution-183-flasher.vercel.app/>
(nguồn: `firmware/web-flasher/index.html`, Vercel project `dsolution-183-flasher`).
Mở bằng Chrome/Edge trên máy tính, nó làm cả hai việc:

* **Nạp**: chọn file `.bin` → bấm “Nạp vào 0x0” (địa chỉ cố định, không cần nhập tay),
  có nút **Xoá toàn bộ chip** và thanh tiến trình. Dùng `esptool-js` 0.7.1.
* **Xem log**: bấm “Kết nối &amp; xem log” (115200) → hiện thẳng log ra trang, có nút
  **Reset board**, **Lưu log** (tải về .txt) và **Xoá màn hình**.

Trang này cần **https** (yêu cầu của WebSerial) và phải mở ở **tab riêng**, không nhúng
trong iframe — Chrome chặn cổng serial trong iframe khác origin, nên bản live-preview của
sandbox **không dùng được**, phải dùng URL Vercel ở trên (hoặc tự chạy
`python3 -m http.server 8000` trong `firmware/web-flasher` rồi mở `http://localhost:8000`).

### Trước khi cần đến log: 3 dấu hiệu nhìn bằng mắt

Máy đang đen nên hãy xác định **chip có chạy hay không** trước đã — cái này không cần
công cụ gì:

| Dấu hiệu | Nếu CÓ | Nếu KHÔNG |
| --- | --- | --- |
| Cắm USB, PC có thấy thiết bị/cổng COM mới (Device Manager, `ls /dev/ttyACM*`) | chip sống, USB ổn | cáp chỉ sạc, hoặc chip không khởi động |
| Đèn **WS2812 GPIO48** (LED nhỏ) sáng/đổi màu sau khi cấp nguồn | firmware đã chạy tới phần LED → lỗi ở màn hình | app chưa chạy tới `setup()` (boot/PSRAM) hoặc chết sớm |
| **Đèn nền màn hình** (GPIO13) sáng, dù hình trắng/đen | backlight OK → còn lại là bus SPI/init | backlight chưa bật → app chưa chạy tới `_post_setup_gpio()` |

Đọc bảng này theo hàng: LED sáng mà màn đen = lỗi hiển thị; LED không sáng = lỗi boot
(PSRAM/flash/partition), lúc đó log mới là thứ cần.

### Nếu vẫn đen

1. `erase_flash` rồi nạp lại file factory ở 0x0.
2. Mở serial 115200, reset board: phải thấy ROM banner rồi dòng
   `[board] DSolution 1.83 2-Mic: NV3023 + ES7210/ES8311`.
   * Không thấy banner, ROM banner lặp lại → app chết trước `_setup_gpio()` (PSRAM/partition),
     không phải màn hình.
   * Có banner mà vẫn đen → bus SPI/đèn nền: thử `-DTFT_WRITE_FREQ=20000000`, đo GPIO13.
3. Đèn nền sáng mà hình trắng/xám → bảng init đã chạy, chỉ còn MADCTL/COLMOD.
4. **Cứu máy**: cộng đồng có bản dump **16 MB firmware gốc Xiaozhi** cho đúng box
   `ostb-2st`; nạp lại là về nguyên bản:
   `esptool.py --chip esp32s3 write_flash 0x0 xiaozhi_ostb-2st_full16MB.bin`.

## 7b. Máy này là gì? (kết quả tra cứu)

Retail name **OSTB-2ST-WIFI**; cộng đồng ESPHome/Trung Quốc gọi là **"Xingzhi cube 1.83
2mic"**. Nhờ tên đó mà có bộ thông tin độc lập, đã dùng để sửa port:

| Hạng mục | Nguồn cộng đồng | Trong port |
| --- | --- | --- |
| Panel | **NV3023**, 284×240, x-offset 36 (Espressif có component `esp_lcd_nv3023`) | `NV3023_Panel.h`, offset tự suy ra |
| SPI màn hình | SCLK 9 / MOSI 10 / CS 14 / DC 8 / RST 18 / BL 13, **40 MHz** | khớp, đã hạ 80→40 MHz |
| I2C codec | SDA 12 / SCL 11 (ES8311 0x18, ES7210 0x40) | khớp |
| I2S | MCLK 5 / BCLK 15 / WS 16 / DOUT 6 / DIN 7 | khớp |
| PA loa | GPIO4 = HIGH | khớp |
| Nút | 0 / 39 / 40, kéo lên nội, mức thấp | khớp |
| Sạc | GPIO47 (LOW = đang sạc) | khớp |
| Pin | **GPIO17**, ADC2 ch6, chia 1:2 | đã sửa từ 38 → 17 |
| PSRAM | octal, 80 MHz (ESPHome) | `qio_opi` — khớp |
| USB | ESPHome dùng `USB_SERIAL_JTAG` | `ARDUINO_USB_MODE=1` = HW CDC/JTAG — khớp |

Nguồn: `RealDeco/xiaozhi-esphome` → `devices/Xingzhi/xingzhi-cube-1.83-2mic.yaml`;
`ProD-byte/Maerchenbox` (bảng chân đọc từ firmware gốc + hướng dẫn cứu máy 16 MB);
`espressif/esp_lcd_nv3023`.

**Chưa test được trên phần cứng thật** (máy đang ở trạng thái đen + USB chập chờn sau lần
nạp sai địa chỉ). Thứ tự kiểm tra khi có log serial: (1) banner board, (2) đèn nền GPIO13,
(3) bus SPI, (4) ES8311 nếu tiếng méo/rè, (5) gain ES7210 + MCLK nếu mic im.

## Thử loa và tính năng dễ dùng

- Vào **Config → Audio Config**, bật **Sound**, đặt **Sound Volume** khoảng 30–50%, rồi chọn **Test speaker**. Máy báo "Test sent" nghĩa là firmware đã gửi mẫu âm thanh, **không phải xác nhận tai nghe thấy tiếng**. Chọn **Menu tones OFF** để tắt tiếng điều hướng nhưng vẫn giữ cảnh báo (khi Sound ON). Khi ở menu chính, máy kiểm tra pin định kỳ; cần hai lần đọc thấp liên tiếp trước khi báo và thông số pin chỉ là ước tính.
- Mapping của board này: I²C SDA GPIO12 / SCL GPIO11, ES8311 địa chỉ `0x18`; I²S MCLK GPIO5, BCLK GPIO15, WS GPIO16, DOUT GPIO6; bật ampli GPIO4 HIGH. Firmware khởi động bus I²C và khôi phục chân codec cố định sau khi nạp cấu hình cũ. Nếu vẫn im, kiểm tra log serial `[audio]`, kết nối loa, nguồn ampli và xung I²S; cần đo thực tế để xác định.
- Mở **Quick** ở menu chính để chạy nhanh các mục đã ghim. **Edit favorites** cho ghim/bỏ ghim; **Recent** là mục gần nhất đã chạy *từ Quick*. Cài đặt được lưu trong NVS namespace `dsquick`.
- Trong Dashboard WebUI, **Find device** yêu cầu thiết bị đang có kết nối WebUI. Máy lặp âm đến khi bấm **Stop finding**, trong khi vòng lặp WebUI/menu đang chạy. Một số app và OTA tạm ngừng phục vụ Find; khi trở lại menu máy tiếp tục. Sau mỗi đoạn âm có khoảng nghỉ để giữ UI phản hồi; Stop có thể đợi đoạn WAV hiện tại (tối đa 1 giây). Tính năng tôn trọng cài đặt tắt tiếng, âm lượng và LED blink; nếu đang bận/tắt tiếng, máy vẫn thử nháy LED nếu LED blink được bật, và WebUI báo không thể phát âm thanh thay vì khẳng định loa đã kêu.
- WebUI có công tắc âm thanh, menu tones, âm lượng và độ sáng; bấm **Save sound & display** để lưu. Các thao tác này cần đăng nhập WebUI. Tín hiệu âm thanh và chia sẻ I²S cần được kiểm tra trên máy thật, đặc biệt khi các tác vụ âm thanh/serial khác đang chạy đồng thời.

## Pet và âm UI tùy chỉnh

- Trong **Brucegotchi**, nhấn Select để mở menu: **Pet** chuyển giữa Classic, Cyber Bot, Ghost và Cyber Cat; **Animation** bật/tắt chớp mắt và chấm chuyển động. Cài đặt được nhớ sau khi khởi động lại. Màu lấy từ theme; biểu cảm vẫn dựa trên trạng thái thật của Brucegotchi. Đây chỉ là thay đổi giao diện, không thay đổi tính năng Wi‑Fi của nó. Chỉ dùng các tính năng kiểm thử trên mạng được phép.
- **Config → Audio Config → UI sound events** cho từng sự kiện Select, Back, Success, Warning và Find chuyển giữa **Built-in**, **Off**, **WAV**. **Sound OFF** hoặc âm lượng 0 vẫn tắt tất cả; **Menu tones OFF** tắt riêng Select/Back. Các âm cứng ở những module khác chưa được chuyển hết sang hệ thống này.
- Cách dễ hơn: trên Dashboard WebUI chọn **Upload a custom UI sound**, chọn sự kiện và file WAV. WebUI chuẩn hóa header, hỏi trước khi cắt hoặc ghi đè, rồi tải lên đúng thư mục. Sau đó vẫn cần bật WAV cho sự kiện đó trên máy. File đầu vào vẫn phải là PCM 16-bit 48 kHz, mono/stereo (không tự chuyển MP3/tần số lấy mẫu).
- Hoặc dùng WebUI → Files → LittleFS, tạo thư mục `/ui-sounds` rồi tải các tệp tương ứng: `select.wav`, `back.wav`, `success.wav`, `warning.wav`, `find.wav`. Nếu không có tệp hoặc tệp sai chuẩn, máy dùng tiếng built-in và ghi `[audio]` vào serial. File cần RIFF WAV PCM 16-bit, **48 kHz**, mono/stereo, header chuẩn 44 byte; tối đa **250 ms** cho Select/Back và **1 giây** cho các sự kiện khác. Không phải MP3 và không phải mọi biến thể WAV đều được hỗ trợ.
- Có thể xuất PCM 16-bit 48 kHz từ Audacity rồi chuẩn hóa header/giới hạn bằng Python trên máy tính: `python tools/prepare-ui-sound.py select input.wav select.wav --trim` (thay `select` bằng tên sự kiện). Công cụ chỉ chuẩn hóa/cắt, không chuyển sample rate hay giải mã MP3.
- Các âm ngắn phát trên task menu; sẽ bỏ qua nếu loa/mic đang bận. Chưa có bộ điều phối I²S nguyên tử giữa mọi task, vì vậy vẫn cần thử thật khi phát nhạc/thu mic đồng thời. Màn pet ở hai chiều đã có kiểm thử hình học, nhưng chưa được kiểm tra căn chỉnh, màu sắc hay độ mượt trên màn NV3023 thực.
- Muốn chỉ ngắm và đổi biểu cảm mà **không khởi động radio**, vào **Config → Display & UI → Pet preview**. Nhấn Prev/Next để đổi biểu cảm, Select mở tùy chọn skin/chuyển động, giữ Select để thoát. Brucegotchi thực tế có phát beacon và deauth tới các AP lân cận, không chỉ ngắm pet: bản này hiển thị cảnh báo và yêu cầu xác nhận trước khi chạy; chỉ dùng trong môi trường cô lập được phép.

## WebUI: tự khởi động và bật/tắt ngay

- **Config → System Config → WebUI AutoStart** điều khiển khởi động sau mỗi lần bật máy. Chuyển **OFF** cũng hủy lượt khởi động nền đang chờ và yêu cầu dừng WebUI hiện tại, nhưng giữ kết nối Wi‑Fi. Nếu cấu hình cũ chọn `Startup App = WebUI`, công tắc này tính cả cấu hình đó và xóa lựa chọn trùng khi chuyển OFF. Các Startup App khác không bị thay đổi.
- Để điều khiển ngay mà không đổi AutoStart, vào **WiFi → WebUI control**, **Files → WebUI**, hoặc **Quick → WebUI control**. Các đường này mở cùng menu trạng thái: bắt đầu, xem thông tin, dừng WebUI giữ Wi‑Fi, hoặc dừng cả hai. Bật/tắt thủ công không đổi cấu hình tự khởi động lần sau.
- Khi đang OTA hoặc đang chuyển mạng, lệnh dừng từ menu sẽ báo bận thay vì cố ngắt. Nếu quá trình tự khởi động đang hủy, chờ và thử lại. AutoStart OFF được lưu ngay cả khi WebUI chưa thể dừng vì đang bận; khi xong hãy vào WebUI control để dừng.
- Evil Portal hiển thị **Deauth not configured** khi phiên hiện tại không được cấu hình chức năng đó, thay vì chỉ ghi OFF và gây hiểu nhầm; nhãn **paused** khác với chưa cấu hình.


## Tự thu hồi RAM và xử lý Low RAM

- Khi trở về menu chính, firmware giải phóng vùng nhớ còn giữ của danh sách menu cũ; sau quét BLE, kết quả quét tạm được giải phóng khi đã sao chép thông tin để hiển thị. Việc này không xóa tệp hay cài đặt. Không phải mọi module đều có bộ nhớ đệm đã được thu hồi tự động.
- Với quét BLE và BLE Suite, firmware không áp lại ngưỡng RAM **khởi tạo controller** khi NimBLE đã khởi tạo. Kiểm tra thiếu RAM của board này không tự tắt Wi‑Fi/WebUI hoặc BLE để lấy bộ nhớ; một số tính năng chuyển radio riêng vẫn có hành vi dừng radio như trước.
- Nếu vẫn báo Low RAM, dừng các tác vụ không cần dùng, thử lại; nếu không hồi phục, lưu công việc và khởi động lại. Trong **Device Info**, xem DMA free và DMA max block: tổng RAM còn nhiều vẫn có thể không đủ khối liên tục. Serial `[RAM]` cho biết số đo khi guard từ chối. Không có cách an toàn để tự gom các vùng heap còn đang sử dụng; kiểm thử trên board thật vẫn cần thiết.


## Kiểm tra loa và microphone sau bản sửa audio

- Trên WebUI, bật **System sounds**, chỉnh âm lượng khoảng 50%, bấm **Save sound & display**, rồi chọn **Find device**. Có thể để màn hình WebUI đang mở trên máy hoặc quay về menu; nút báo trạng thái gửi/đang chờ/kết quả. Find bị hoãn khi đang OTA; tính năng vẫn tôn trọng Sound OFF, âm lượng 0 và cấu hình riêng của âm Find. "Playing" chỉ xác nhận dữ liệu đã được gửi, không chứng minh loa phát tiếng.
- Trên thiết bị, thử **Config → Audio Config → Test speaker**; sau đó vào **Others → Microphone → dB Meter/Spectrum** hoặc **Record** và nói gần mic. Không phát loa/nhạc hoặc chạy sonar cùng lúc. Mở file WAV trên máy tính để nghe lại. Công cụ này thu âm trên thiết bị; WebUI không tự thu hay phát mic.
- Firmware sửa clock và nguồn ES7210 theo driver Espressif, kiểm tra I²C và trả lỗi khi codec không phản hồi. Nếu còn im, gửi log serial 115200 có dòng `[audio]`, ảnh màn hình lỗi/trạng thái WebUI và cho biết Test speaker/đồng hồ dB/record có kết quả gì. Cần xác minh chân, clock, codec và âm thanh trên thiết bị thật; ACK I²C hay build thành công không chứng minh microphone/loa hoạt động.


## OTA: tiến trình và an toàn phiên cập nhật

- Trang `/ota` và cửa sổ OTA trong WebUI vẫn là hai giao diện cũ; không cần thiết lập WebUI mới. Sau khi cập nhật, **tải lại trang WebUI** để trình duyệt dùng mã giao diện tương ứng với firmware mới.
- Máy tái sử dụng khung tiến trình OTA hiện có ở màn hình WebUI và các menu; các ứng dụng chạy trên task giao diện có điểm kiểm tra nút cũng tạm chuyển sang khung OTA tại điểm kiểm tra tiếp theo. Một tác vụ đang chặn lâu, tác vụ nền tự vẽ hoặc chế độ ngủ sâu có thể không cập nhật màn hình ngay; theo dõi thêm tiến trình trên trình duyệt. Không rút nguồn trong lúc ghi firmware.
- Bản mới từ chối phiên OTA thứ hai đang hoạt động, gắn mã phiên cho các yêu cầu chia khối/hủy/hoàn tất và không cho hai yêu cầu dùng chung bộ đệm đồng thời. Nếu kết nối bị ngắt, có thể thử lại khối; phiên bỏ dở quá 90 giây được thu hồi khi bắt đầu phiên OTA mới. Khi bấm hủy trong lúc khởi tạo, trình duyệt chờ nhận phiên rồi mới gửi hủy; trong bước hoàn tất không thể hủy an toàn.
- Nếu mất phản hồi khi hoàn tất, chưa thể biết chắc cập nhật đã xong hay chưa: kiểm tra màn hình và kết nối máy trước khi thử lại; không tự rút nguồn. Nếu firmware báo không tạo được tác vụ khởi động lại, hãy khởi động lại thủ công. Kiểm thử máy chủ/màn hình ở đây là mô phỏng; cần xác nhận OTA thực tế, nguồn và màn hình trên thiết bị.

### Vì sao trước đây trang đứng ở "Initializing OTA slot..." (đã sửa)

Hiểu đơn giản: trước kia, khi bấm **Upload**, trình duyệt hỏi máy "chuẩn bị chỗ nhớ mới đi", và máy làm **toàn bộ** việc chuẩn bị đó ngay trong lúc đang trả lời câu hỏi. Việc chuẩn bị gồm nâng xung nhịp CPU, tắt chế độ tiết kiệm Wi-Fi và xoá dần vùng nhớ 6 MB. Chừng nào việc đó chưa xong thì câu trả lời chưa được gửi, nên trang không có số % nào để hiện và cũng **không có giới hạn thời gian** — nhìn như treo vĩnh viễn.

Bây giờ chia làm hai bước:

| Trước | Bây giờ |
| --- | --- |
| Bấm Upload → máy vừa xoá flash vừa giữ kết nối → trang đứng im, không biết bao lâu | Bấm Upload → máy trả lời **ngay** "đã nhận, đang chuẩn bị", trang hiện `Preparing OTA slot... 3s` |
| Không có giới hạn thời gian nếu máy không trả lời | Mọi lệnh đều có hạn 15 giây; quá hạn thì báo lỗi rõ ràng |
| Chuẩn bị thất bại → trang chờ mãi | Trang hỏi lại máy mỗi 0,5 giây; khi máy báo lỗi thì hiện đúng lý do (ví dụ `No OTA partition found`), chậm nhất sau 180 giây |
| Màn hình máy hiện 0% trong khi thực ra đang xoá flash | Màn hình hiện `Preparing OTA slot` / `Erasing 4160 KB`, xong mới chạy % |
| Bấm Cancel lúc đang chuẩn bị thì không có tác dụng | Cancel được ghi nhận và huỷ ngay khi bước chuẩn bị kết thúc |

Cần biết thêm:

- **Bước "Preparing" có thể mất vài chục giây** với slot 6 MB. Đó là xoá flash thật, không phải treo. Trang đếm giây để bạn thấy nó vẫn đang chạy; quá 180 giây mới coi là lỗi và báo khởi động lại máy.
- Trong lúc chuẩn bị, màn hình máy vẫn nhận nút (Esc để thoát khung OTA), nhưng **không nên** rút nguồn.
- Nếu trang báo lỗi kèm `HTTP 404` / `HTTP 401`: đó là lỗi đường dẫn hoặc phiên đăng nhập, không phải lỗi file `.bin`. Tải lại trang WebUI rồi thử lại; `401` nghĩa là phiên đăng nhập đã hết.
- File `.bin` phải là bản `DSolution-183-2mic-ota.bin` (khoảng 4,2 MB). `factory.bin` / bootloader bị chặn ngay khi chọn file.

### Theme và Sonar thử nghiệm

- Sáu bảng màu Cyber Cyan, Matrix Green, Amber Ops, Crimson Red, Ultraviolet và Arctic Ice có trên máy ở **Display & UI → UI Color** và trên WebUI. **Menu Layout** Carousel/Grid cũng chỉnh được trong Personalize; WebUI dùng cùng màu RGB565 và đổi phong cách tương ứng. Làm mới Personalize nếu cài đặt trên máy trong lúc form đang mở; ảnh/icon từ theme JSON chỉ được máy vẽ, không phải bản sao WebUI.
- Sonar Guardian là cảm biến **thay đổi tín hiệu âm thanh thử nghiệm**, không đo được hướng, khoảng cách hay vật đang tiến/lùi; không dùng làm thiết bị an ninh tin cậy. Mặc định Silent. Đặt máy cố định, rời khỏi khu vực trong lúc arm và chờ hiệu chuẩn; nếu báo no signal/clipping thì không thể giám sát. Tín hiệu, độ nhạy và báo giả phụ thuộc loa/mic và môi trường; cần kiểm tra trên thiết bị thật.
- Không nhúng HTML engine vào firmware: bộ nhớ/flash hạn chế. Theme JSON và layout native là lựa chọn nhẹ; WebUI responsive nhưng không phải bản sao pixel của màn máy.
