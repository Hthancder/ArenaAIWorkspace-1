# Bruce cho board DSolution 1.83" 2-Mic — hướng dẫn nhanh

Port đã được tạo trong `firmware/Bruce` (bản clone `pr3y/Bruce`, HEAD `2b6ba4d`).

## 1. File đã thêm / sửa

| File | Nội dung |
| --- | --- |
| `boards/dsolution-183-2mic/dsolution-183-2mic.ini` | Env build: ESP32-S3 16MB, PSRAM OPI, driver màn hình, audio, LED, nút, pin |
| `boards/dsolution-183-2mic/NV3030B_Panel.h` | Class `lgfx::Panel_NV3030B` — **init sequence NV3030B** + bảng MADCTL (SwapXY/MirrorY/BGR) |
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

## 3. Màn hình NV3030B

* Không dùng ST7789: Bruce mặc định Arduino_GFX, mà Arduino_GFX không có driver NV3030B và
  cũng không cho board tự cắm driver riêng → chuyển backend sang **LovyanGFX**
  (`-DUSE_LOVYANGFX=1 -DLOVYAN_PANEL=Panel_NV3030B`) và tự viết panel class.
* Init table trong `NV3030B_Panel.h` là bảng của bạn, nguyên văn (gồm 2 lần mở khoá `0xFD`,
  gamma `0xE0..0xE8`, `0x11` delay 200ms, `0x29` delay 10ms).
* `Swap XY + Mirror Y + BGR` → `MADCTL = 0xA8`; `Invert = true` → `-DTFT_INVERTION=1`.
* Hình học: kính 240×284, RAM 240×320, cửa sổ nằm ở hàng 36..319. Không đặt
  `TFT_OFFSET_*` (LovyanGFX tự suy ra 36), nếu đặt thêm sẽ lệch 36 px.
* `TFT_ROTATION=3` (mounting offset) + `ROTATION=0` → mặc định landscape 284×240 đúng như
  bảng thông số; xoay trong Config > Rotation vẫn đúng 4 hướng.
* SPI 80 MHz (giảm còn `-DTFT_WRITE_FREQ=40000000` nếu hình bị nhiễu).

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

## 6. Pin / nguồn — 3 điểm cần kiểm chứng trên board thật

1. **GPIO38 (Battery Status)**: trên ESP32-S3 ADC chỉ có GPIO1–GPIO10 (ADC1) và
   GPIO11–GPIO20 (ADC2). **GPIO38 không có kênh ADC**, nên `analogRead(38)` không thể ra
   điện áp pin. Vẫn khai báo đúng như tài liệu (`-DANALOG_BAT_PIN=38`) nhưng nếu % pin sai,
   cần đo lại schematic (rất có thể 38 là chân "battery low" dạng số, hoặc chia áp nằm ở
   chân khác).
2. **GPIO47 (Detect Charge)**: đọc mức thấp = đang sạc (kiểu open-drain của IC sạc). Nếu
   ngược, đảo so sánh trong `isCharging()`.
3. **GPIO21 (Sleep Control)**: giữ HIGH khi chạy, kéo LOW trong `powerOff()` trước khi vào
   deep sleep (coi như chân giữ nguồn). Nếu là chân input thì vẫn deep sleep bình thường.

## 7. Trạng thái

* `.ini` đã được kiểm tra bằng `pio project config` (parse OK, flag đúng).
* **Chưa build/nạp được trong môi trường này**: sandbox chỉ mở `github.com`, `pypi.org`…
  nên PlatformIO không tải được platform zip (redirect sang `objects.githubusercontent.com`
  bị chặn) và toolchain xtensa. Trên máy bạn có Internet bình thường thì `pio run -e
  dsolution-183-2mic` sẽ chạy.
* Chưa test trên phần cứng thật — thứ tự tinh chỉnh khi có board: (1) đèn nền + hướng/màu
  (`TFT_INVERTION`, `getMadCtl()`), (2) tốc độ SPI, (3) thanh ghi ES8311 nếu tiếng méo,
  (4) gain ES7210 / MCLK nếu mic im.
