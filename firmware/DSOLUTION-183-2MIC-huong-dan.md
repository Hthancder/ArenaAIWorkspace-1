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
firmware-factory.bin  = 4.732.528 bytes   (ảnh gộp, nạp ở 0x0)
```

Run CI mới nhất: **44718198693** (commit `cf7f03b`) — PASS. Ảnh gộp được ghép bằng Python
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
