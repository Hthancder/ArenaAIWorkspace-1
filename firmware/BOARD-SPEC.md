# Đặc tả phần cứng — OSTB-2ST-WIFI / DSolution 1.83" 2-Mic

> Tài liệu chuẩn chung cho **mọi firmware** (ESP-IDF, Arduino/PlatformIO, ESPHome, MicroPython, Xiaozhi, Bruce...).
> Tên thương mại: **OSTB-2ST-WIFI** · Tên cộng đồng: **Xingzhi cube 1.83 2mic** · Trạng thái: **Đã kiểm chứng chạy thực tế trên phần cứng**.

---

## 1. Kiến trúc hệ thống

| Thành phần | Thông số |
| --- | --- |
| **SoC** | ESP32-S3, dual-core Xtensa LX7 @ 240 MHz, Wi-Fi 802.11 b/g/n (2.4 GHz) + BLE 5 |
| **Flash** | 16 MB QIO @ 80 MHz |
| **PSRAM** | 8 MB Octal (OPI) @ 80 MHz (`memory_type = qio_opi`) |
| **USB** | Native USB trên **GPIO19 (D-) / GPIO20 (D+)** — hỗ trợ USB-Serial-JTAG (`303a:1001`) và USB-OTG; **không** có chip cầu UART ngoài |
| **Anten** | PCB onboard |

---

## 2. Bảng chân đầy đủ (Pinout)

### Màn hình (SPI write-only)
| Chức năng | GPIO | Ghi chú |
| --- | :---: | --- |
| LCD SCLK | `9` | SPI2 (FSPI), Mode 0 |
| LCD MOSI | `10` | Chỉ ghi (không nối MISO) |
| LCD CS | `14` | Active LOW |
| LCD DC | `8` | Data / Command |
| LCD RST | `18` | Reset phần cứng |
| LCD Backlight | `13` | Active HIGH, hỗ trợ PWM (LEDC) |

### Audio (I2C + I2S chung bus)
| Chức năng | GPIO | Ghi chú |
| --- | :---: | --- |
| I2C SDA | `12` | Bus điều khiển codec (100 kHz) |
| I2C SCL | `11` | Dùng chung cho ES8311 (`0x18`) + ES7210 (`0x40`) |
| I2S MCLK | `5` | `256 × fs` (ESP32-S3 xuất ra) |
| I2S BCLK | `15` | Bit clock |
| I2S WS / LRCK | `16` | Word select / Left-Right clock |
| I2S DOUT | `6` | ESP32-S3 → ES8311 (loa) |
| I2S DIN | `7` | ES7210 → ESP32-S3 (mic) |
| Speaker PA Enable | `4` | Mạch khuếch đại NS4150, `HIGH` = bật loa |

### Nút nhấn, LED & Nguồn
| Chức năng | GPIO | Ghi chú |
| --- | :---: | --- |
| Nút Boot / Sel | `0` | Nối GND, `INPUT_PULLUP`, active `LOW` (kiêm strapping pin & wake deep-sleep `ext0`) |
| Nút Vol+ | `39` | Nối GND, `INPUT_PULLUP`, active `LOW` |
| Nút Vol- | `40` | Nối GND, `INPUT_PULLUP`, active `LOW` |
| RGB LED | `48` | 1× WS2812B (thứ tự màu `GRB`, RMT) |
| Đo điện áp pin | `17` | `ADC2_CH6`, cầu chia áp `1:2` (`Vbat = Vadc × 2`, dải `3.0–4.2V`) |
| Phát hiện sạc | `47` | Open-drain, `INPUT_PULLUP`, `LOW` = đang sạc |
| Sleep / Power Latch | `21` | Kéo `HIGH` sớm lúc boot, nhả `LOW` trước khi deep-sleep / tắt nguồn |
| USB D- / D+ | `19` / `20` | Native USB — không dùng làm GPIO thường |

> **Lưu ý chân GPIO38:** Một số bảng chân từ người bán ghi "Battery Status = GPIO38", nhưng ESP32-S3 **không có kênh ADC** trên GPIO38; chân đo pin thực tế là **GPIO17**.

---

## 3. Màn hình — NV3023 (284×240 IPS)

| Thông số | Giá trị |
| --- | --- |
| **Controller** | **NewVision NV3023** *(khác hoàn toàn ST7789 và NV3030B)* |
| **Độ phân giải kính** | `284 × 240` (ngang / landscape) |
| **RAM controller** | `240 × 320` (chỉ hiển thị 284 dòng cuối của trục 320 → offset `36`) |
| **Giao tiếp** | SPI 4 dây, Mode 0, **tối đa 40 MHz** *(80 MHz gây đen màn)* |
| **Định dạng màu** | RGB565 (`0x3A = 0x55`), thứ tự `BGR` (bit `0x08` trong `MADCTL`) |
| **Đảo màu** | Bắt buộc bật (`INVON` = `0x21`) |
| **Xoay màn hình (`MADCTL 0x36`)** | `0xA8` = Landscape mặc định (`MV \| MY \| BGR`) · Portrait `0x08` · Portrait đảo `0xC8` · Landscape đảo `0x68` |
| **Offset cửa sổ** | Ngang (MV=1): `colstart = 36, rowstart = 0` · Dọc (MV=0): `colstart = 0, rowstart = 36` |

### Chuỗi khởi tạo NV3023 chuẩn (bắt buộc)
> `0xFD 0x06 0x08` và `0xFD 0xFA 0xFC` là 2 lệnh mở khóa trang thanh ghi hãng — thiếu chúng màn hình sẽ đen hoàn toàn.

```text
0xFD, 2, 0x06, 0x08
0x61, 2, 0x07, 0x04
0x62, 3, 0x00, 0x44, 0x45
0x63, 4, 0x41, 0x07, 0x12, 0x12
0x64, 1, 0x37
0x65, 3, 0x09, 0x10, 0x21
0x66, 3, 0x09, 0x10, 0x21
0x67, 2, 0x20, 0x40
0x68, 4, 0x90, 0x4C, 0x7C, 0x66
0xB1, 3, 0x0F, 0x02, 0x01
0xB4, 1, 0x01
0xB5, 4, 0x02, 0x02, 0x0A, 0x14
0xB6, 5, 0x04, 0x01, 0x9F, 0x00, 0x02
0xDF, 1, 0x11
0xE2, 6, 0x13, 0x00, 0x00, 0x30, 0x33, 0x3F
0xE5, 6, 0x3F, 0x33, 0x30, 0x00, 0x00, 0x13
0xE1, 2, 0x00, 0x57
0xE4, 2, 0x58, 0x00
0xE0, 8, 0x01, 0x03, 0x0D, 0x0E, 0x0E, 0x0C, 0x15, 0x19
0xE3, 8, 0x1A, 0x16, 0x0C, 0x0F, 0x0E, 0x0D, 0x02, 0x01
0xE6, 2, 0x00, 0xFF
0xE7, 6, 0x01, 0x04, 0x03, 0x03, 0x00, 0x12
0xE8, 3, 0x00, 0x70, 0x00
0xEC, 1, 0x52
0xF1, 3, 0x01, 0x01, 0x02
0xF6, 4, 0x09, 0x10, 0x00, 0x00
0xFD, 2, 0xFA, 0xFC
0x35, 1, 0x00
0x11, DELAY 200ms
0x29, DELAY 10ms
```
*(Sau chuỗi trên gửi thêm `0x3A=0x55`, `0x36=0xA8`, `0x21` và bật đèn nền GPIO13.)*

---

## 4. Hệ thống Audio (ES8311 + ES7210 + NS4150)

- **Kiến trúc I2S:** ESP32-S3 làm **Master**, cả 2 codec làm **Slave** dùng chung BCLK (`15`), WS (`16`), MCLK (`5`).
- **Tần số MCLK:** luôn bằng **`256 × fs`** (ví dụ `4.096 MHz` @ 16 kHz, `6.144 MHz` @ 24 kHz, `12.288 MHz` @ 48 kHz).
- **Kênh mic ES7210:** `MIC1` + `MIC2` là 2 mic thu âm; `MIC3` nối vòng từ đầu ra `ES8311` làm tín hiệu tham chiếu khử tiếng vọng (AEC).
- **Trình tự bật loa:** Cấu hình `ES8311` qua I2C trước → đợi ~10 ms → kéo `GPIO4` (`NS4150 PA`) lên `HIGH`. Khi tắt tiếng/ngủ thì kéo `GPIO4` xuống `LOW` trước khi tắt codec.

### Thanh ghi init tối thiểu cho firmware tự viết (I2S 16-bit Philips, 48 kHz, MCLK 12.288 MHz)

**ES8311 (`0x18` — DAC loa, hỗ trợ 256×fs ở mọi `fs` tiêu chuẩn):**
```text
0x00=0x1F → delay 20ms → 0x00=0x00 → 0x00=0x80   // reset & power on
0x01=0x3F  0x02=0x00  0x03=0x10  0x04=0x10        // MCLK pin, 256×fs, OSR
0x05=0x00  0x06=0x03  0x07=0x00  0x08=0xFF        // dividers
0x09=0x0C  0x0A=0x0C                              // I2S 16-bit in/out
0x0D=0x01  0x0E=0x02  0x12=0x00  0x13=0x10        // analog & DAC & HP drive on
0x1C=0x6A  0x37=0x08  0x32=0xBF                   // EQ bypass, volume 0 dB
```

**ES7210 (`0x40` — ADC 2-Mic, ví dụ `fs = 48 kHz`, `MCLK = 12.288 MHz`):**
```text
0x00=0xFF  0x00=0x32  0x01=0x3F  0x09=0x30  0x0A=0x30
0x23=0x2A  0x22=0x0A  0x20=0x0A  0x21=0x2A        // HPF
0x08=0x00                                         // I2S slave
0x40=0xC3  0x41=0x70  0x42=0x70                   // analog & mic bias
0x11=0x60  0x12=0x00                              // 16-bit I2S, MIC1/2 trên SDOUT1
0x02=0xC1  0x07=0x20  0x04=0x01  0x05=0x00        // clock @ 48 kHz (đổi theo bảng ESP-IDF nếu chạy 16 kHz)
0x47=0x08  0x48=0x08  0x49=0x08  0x4A=0x08  0x06=0x04
0x4B=0x0F  0x4C=0x0F  0x00=0x71  0x00=0x41        // bật ADC1..4
0x43=0x18  0x44=0x18  0x45=0x10  0x46=0x10        // gain: MIC1/2 = +24 dB, MIC3 (AEC) = 0 dB
```

---

## 5. Nạp firmware & USB-Serial-JTAG

- **Chế độ USB:** Nối thẳng USB-C vào USB-Serial-JTAG (`303a:1001`).
  - `DTR` nối vào `EN` (Reset) · `RTS` nối vào `GPIO0` (Boot).
  - Nạp bình thường không cần bấm giữ `BOOT` (`esptool` tự điều khiển DTR/RTS).
  - Nếu làm web flasher / script reset: chỉ nháy `DTR` để reset, **giữ `RTS` cao** (nhả `GPIO0`), tránh kéo `RTS` xuống thấp khiến chip kẹt vào chế độ download.
- **Địa chỉ flash chuẩn (ảnh gộp từ offset `0x0`):**
  - `0x0000` Bootloader · `0x8000` Partition table · `0xE000` `boot_app0` · `0x10000` App.

---

## 6. Mẫu cấu hình nhanh cho từng nền tảng

### PlatformIO / Arduino-ESP32
```ini
board = esp32s3
board_build.arduino.memory_type = qio_opi
board_upload.flash_size = 16MB
build_flags =
  -DBOARD_HAS_PSRAM=1
  -DARDUINO_USB_MODE=1
  -DARDUINO_USB_CDC_ON_BOOT=1
```

### ESP-IDF
- Component sẵn có: `espressif/esp_lcd_nv3023` (màn hình), `espressif/esp_codec_dev` (ES8311 + ES7210), `driver/i2s_std`.
- `sdkconfig`: `CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y`, `CONFIG_ESPTOOLPY_FLASHMODE_QIO=y`, `CONFIG_SPIRAM=y`, `CONFIG_SPIRAM_MODE_OCT=y`, `CONFIG_SPIRAM_SPEED_80M=y`, `CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y`.

### ESPHome (YAML)
```yaml
esp32:
  board: esp32-s3-devkitc-1
  flash_size: 16MB
  framework: { type: esp-idf }
psram: { mode: octal, speed: 80MHz }
logger: { hardware_uart: USB_SERIAL_JTAG }
i2c: { sda: 12, scl: 11 }
i2s_audio: { i2s_lrclk_pin: 16, i2s_bclk_pin: 15, i2s_mclk_pin: 5 }
audio_adc: { platform: es7210, bits_per_sample: 16bit, sample_rate: 16000Hz }
audio_dac: { platform: es8311, bits_per_sample: 16bit, sample_rate: 48000Hz }
spi: { clk_pin: 9, mosi_pin: 10 }
display:
  platform: mipi_spi
  model: CUSTOM
  cs_pin: 14
  dc_pin: 8
  reset_pin: 18
  data_rate: 40MHz
  spi_mode: MODE0
  color_order: bgr
  invert_colors: true
  dimensions: { width: 284, height: 240, offset_width: 36, offset_height: 0 }
  transform: { swap_xy: true, mirror_x: false, mirror_y: true }
output:
  - { platform: ledc, id: bl_pwm, pin: GPIO13 }
switch:
  - { platform: gpio, pin: GPIO4,  name: "Speaker PA", restore_mode: RESTORE_DEFAULT_ON }
  - { platform: gpio, pin: GPIO21, name: "Power Latch", restore_mode: RESTORE_DEFAULT_ON }
light:
  - { platform: esp32_rmt_led_strip, pin: GPIO48, chipset: ws2812, num_leds: 1, rgb_order: GRB }
binary_sensor:
  - { platform: gpio, pin: { number: 0,  inverted: true, mode: INPUT_PULLUP }, name: "Boot" }
  - { platform: gpio, pin: { number: 39, inverted: true, mode: INPUT_PULLUP }, name: "Vol+" }
  - { platform: gpio, pin: { number: 40, inverted: true, mode: INPUT_PULLUP }, name: "Vol-" }
```

---

## 7. Những điểm dễ vấp khi port firmware mới

1. **Đừng dùng driver ST7789/NV3030B:** Panel là **NV3023**, phải gửi đủ chuỗi init mở khóa `0xFD`, giữ SPI ≤ **40 MHz**, bật `invert`, set `BGR`, và trừ offset **36 px** trên trục 320.
2. **Không gọi `gpio_reset_pin(GPIO_NUM_0)`:** GPIO0 vừa là chân Boot/Wake vừa là nút chọn chính — reset pin sẽ làm mất `INPUT_PULLUP`.
3. **Kéo GPIO21 `HIGH` đầu hàm boot** và kéo `LOW` trong `powerOff()` trước khi gọi `esp_deep_sleep_start()`.
4. **USB-OTG vs USB-Serial-JTAG:** Nếu firmware bật USB-HID / MSC (OTG), cổng CDC nạp/log có thể chuyển đổi mode — nhớ chuẩn bị cơ chế về DFU/Boot nếu người dùng cần nạp lại qua web flasher.
