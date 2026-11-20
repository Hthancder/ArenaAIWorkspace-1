# Xác định chân & "từng ngóc ngách" của một board ESP32 — quy trình 2026

Mục tiêu: từ một chiếc máy lạ (như OSTB-2ST-WIFI / DSolution 1.83" 2-Mic) đi tới một file
mô tả board **đầy đủ, kiểm chứng được**, để lần sau port firmware nào (Bruce, ESPHome,
firmware tự viết) cũng chỉ là đọc file đó ra dùng — không phải đoán lại.

Nguyên tắc: **luôn đi từ rẻ → đắt, từ chắc chắn → phỏng đoán**, và mỗi kết luận phải có
*nguồn* + *cách kiểm chứng*. Ba nguồn tốt nhất, theo thứ tự:

1. **Firmware gốc trong máy** (chân do lập trình viên hãng viết ra — chính xác 100%).
2. **Đo đạc trên board** (đồng hồ, logic analyzer — chính xác 100%, tốn thời gian).
3. **Cộng đồng / tài liệu hãng** (nhanh nhất, độ tin ~70–90%, phải kiểm lại).

---

## Bước 0 — Khoanh vùng trong 15 phút (làm trước khi cắm đồng hồ)

| Việc | Cách làm | Ghi chú |
| --- | --- | --- |
| Tên thật của máy | Nhãn dưới đáy, vỏ hộp, app điện thoại đi kèm | `OSTB-2ST-WIFI` là tên in trên máy; tên này mới tra ra được mọi thứ |
| Chip gì | `esptool.py --chip auto chip_id` / `esptool.py flash_id` (esptool v5 gộp thành `esptool.py info`) | Ra chip, revision, flash JEDEC → suy ra dung lượng + vendor flash |
| Flash/PSRAM | `esptool.py flash_id`, `espefuse.py summary`, và log boot của IDF (`SPI Flash Size`, `Found 8MB PSRAM`) | PSRAM quad/octal quyết định `memory_type` khi build |
| USB gì | Xem tên thiết bị trong Device Manager / `lsusb`: `303a:1001` = USB-Serial-JTAG (native), `1a86:7523` = CH340, `10c4:ea60` = CP210x | Native USB ⇒ có thể không cần BOOT để nạp |
| Tra cộng đồng | GitHub code search `"ostb-2st"`, `"xingzhi cube 1.83"`, ESPHome devices DB, Reddit/Discord | Với máy này ra ngay `RealDeco/xiaozhi-esphome` + `ProD-byte/Maerchenbox` |
| Ảnh board của hãng | FCC ID (Mỹ), SRRC (Trung Quốc), CE — hồ sơ thường có **ảnh nội bộ độ phân giải cao**, đôi khi cả sơ đồ | Tìm theo tên model, không theo tên thương mại |

> Bài học từ chính máy này: 3 thông tin trong "bảng thông số" của người bán (NV3030B,
> battery GPIO38, sleep GPIO21) **sai**; bảng chân đọc từ firmware gốc của cộng đồng
> **đúng**. Đừng tin bảng của người bán.

---

## Bước 1 — Đọc firmware gốc (nguồn chính xác nhất)

### 1.1 Dump toàn bộ flash — làm ngay khi máy còn zin

```bash
esptool.py --chip esp32s3 -p COM7 -b 921600 read_flash 0 0x1000000 stock-16MB.bin
# giữ file này như bảo hiểm: nạp lại là về nguyên bản
esptool.py --chip esp32s3 -p COM7 write_flash 0x0 stock-16MB.bin
```

Với board 16 MB: luôn dump **0x1000000**, kể cả khi chỉ quan tâm app — NVS, calibration
RF, và partition của hãng nằm rải rác.

### 1.2 Bóc ảnh ra từng phần

```bash
# Cách 1: bộ công cụ của Tenable — xem partition, dump NVS, tạo ELF cho Ghidra/IDA
git clone https://github.com/tenable/esp32_image_parser
python esp32_image_parser.py show_partitions stock-16MB.bin
python esp32_image_parser.py create_elf stock-16MB.bin -partition app0 -output app.elf
python esp32_image_parser.py dump_nvs stock-16MB.bin

# Cách 2: một lệnh làm hết (dump từ máy hoặc từ file, tự tách partition + tạo ELF + báo cáo)
#   https://github.com/kimasplund/esp32_universal_extractor

# Cách 3: esp32knife (tương tự, có GUI NVS)
strings -n 6 stock-16MB.bin | less          # log message, tên board, URL, tên biến
binwalk stock-16MB.bin                       # tìm filesystem (LittleFS/SPIFFS/FAT)
```

### 1.3 Đọc NVS — nơi giấu cấu hình đã lưu

NVS thường chứa: hiệu chỉnh ADC/RF, wifi đã lưu, **và đôi khi cả chân GPIO do người dùng
cấu hình**. `esp32_image_parser dump_nvs` in ra từng namespace/key/value đọc được.

### 1.4 Ghidra + AI agent (cách 2026)

Đây là bước biến "một đống assembly" thành danh sách chân. Quy trình:

1. Mở `app.elf` trong **Ghidra** (Xtensa, 32-bit, little-endian).
2. Cắm **GhidraMCP** (LaurieWired, ~12k sao, v2.0/10-2026) hoặc **ReVa** (cyberkaida,
   có headless) để agent (Claude/GPT/local) tự gọi: decompile, xref, rename, search string.
3. Hỏi agent những câu rất cụ thể — đây là phần hiệu quả nhất:
   - "Tìm mọi lời gọi `gpio_config`/`gpio_set_direction`/`gpio_set_level`, in ra số chân
     hằng số và hàm gọi chúng." (Xtensa: các hàm này đi qua `rom_gpio_*` hoặc
     `esp_rom_gpio_pad_select_gpio(i)` với `i` là hằng số.)
   - "Tìm struct `i2s_std_config_t`/`i2s_pin_config_t` và in các trường
     `mclk_io_num/bclk_io_num/ws_io_num/dout_io_num/din_io_num`."
   - "Tìm `i2c_config_t` → `sda_io_num/scl_io_num`."
   - "Tìm `spi_bus_config_t`/`esp_lcd_panel_io_spi_config_t` → `sclk/mosi/cs/dc/rst`."
   - "Liệt kê các chuỗi log có chứa `gpio`, `pin`, `IO`."
4. Mọi kết quả **ghi ngay vào manifest** (xem Bước 5) kèm địa chỉ hàm làm bằng chứng.

Với firmware Xiaozhi/ESP-IDF, phần lớn chân nằm trong `boards/<tên>/config.h` dạng
`#define BSP_xxx_GPIO` — trong nhị phân chúng thành hằng số ngay trước các lời gọi init,
nên agent tìm rất nhanh.

> Giới hạn: AI vẫn đoán. Mọi chân lấy từ Ghidra phải đối chiếu Bước 2 hoặc Bước 3.

---

## Bước 2 — Đo đạc trên board (không thể tranh cãi)

### 2.1 Đồng hồ vạn năng — continuity (board đã rút điện)

Mục tiêu: biết chân nào nối tới đâu. Đặt một que ở **pad/chân IC**, quét que kia qua các
linh kiện tới khi "bíp".

- Từ chân ESP32 → **điện trở 0Ω/cuộn ferrite** → đầu nối, nút bấm, đèn LED, chân loa.
- Từ chân codec (ES8311/ES7210) → MCLK/BCLK/LRCK/DIN/DOUT: đo 5 chân này ra 5 chân ESP32
  là biết ngay toàn bộ I2S.
- Từ chân panel (hoặc test point cạnh flex) → SCLK/MOSI/CS/DC/RST/BL.
- Đo điện trở giữa chân và GND/3V3: ~0Ω = chân nguồn; vài chục kΩ + tụ = chân
  reset/strap; mạch chia áp 1:1 hoặc 1:2 = **chân đo pin**.

Mẹo: chụp ảnh mặt trên + mặt dưới thật nét, dùng **PCB Tracer** (miễn phí, chạy trong
trình duyệt) để chồng 2 ảnh, vẽ đường mạch, xuất KiCad/BOM — thay cho vẽ tay.

### 2.2 Logic analyzer — "nghe lén" lúc máy chạy firmware gốc

Đây là cách **chắc chắn nhất cho màn hình và codec**, và rẻ (8 kênh ~10–20 USD, dùng
**sigrok/PulseView** hoặc bản 2026 có decoder sẵn):

1. Nạp lại firmware gốc, cấp nguồn.
2. Kẹp LA vào các chân nghi ngờ (SCLK, MOSI, CS, DC).
3. Bắt từ lúc bật nguồn 2 giây → decode **SPI**: bạn sẽ thấy **đúng bảng init** của panel,
   đúng tốc độ clock, đúng thứ tự lệnh. (Với máy này: chính là bảng `0xFD 0x06 0x08…`
   mà `NV3023_Panel.h` đang dùng, và clock ~40 MHz.)
4. Kẹp vào I2C (SDA/SCL) → decode ra **toàn bộ chuỗi thanh ghi ES8311/ES7210** mà hãng
   ghi, khỏi phải mò datasheet.
5. Kẹp vào I2S → xác nhận MCLK/BCLK/LRCK và tần số lấy mẫu (16 kHz mic, 48 kHz loa).

### 2.3 Quét GPIO bằng firmware tự viết

Khi không rõ chân nào đi đâu, hãy để con chip tự khai:

```cpp
// probe.ino — nạp bằng Arduino/PlatformIO, chạy trên board cần dò
void setup() {
  Serial.begin(115200);
  delay(500);
  for (int g = 0; g <= 48; g++) {           // S3: 0..48 (bỏ 22..25 không tồn tại, 26..32 = flash)
    if (g == 19 || g == 20) continue;        // USB
    pinMode(g, INPUT_PULLUP);
    int v = digitalRead(g);
    Serial.printf("GPIO%-2d pullup=%d\n", g, v);   // =0  -> có gì đó kéo xuống (nút, LED, tải)
  }
  // Lần 2: kéo từng chân lên HIGH rồi đo bằng đồng hồ/đèn LED để tìm đèn nền, PA enable
}
void loop() {}
```

Kết hợp: chân nào `pullup=0` ⇒ có tải kéo xuống; chân nào HIGH mãi ⇒ đang bị kéo lên.
Sau đó kéo từng chân HIGH 1 giây, quan sát: đèn nền sáng? loa "pop"? màn hình nháy? ⇒
biết chắc chân đó là gì.

### 2.4 I2C scanner — nhận diện codec/PMIC/cảm ứng trong 20 giây

```cpp
Wire.begin(12 /*SDA*/, 11 /*SCL*/);
for (uint8_t a = 1; a < 127; a++) { Wire.beginTransmission(a); if (!Wire.endTransmission()) Serial.printf("0x%02X\n", a); }
```

Địa chỉ là "dấu vân tay": `0x18` ES8311, `0x40` ES7210, `0x34` AXP192, `0x38` AHT20,
`0x5D` GT911… Có danh sách này là biết board có những gì mà chưa cần datasheet.

### 2.5 Máy ảnh nhiệt / đo dòng

- **Thermal**: chụp lúc board chạy → chip nào nóng = chip đang làm việc (biết ngay đâu là
  codec, đâu là flash, đâu là amp).
- **Dòng tiêu thụ**: nguồn bench có đo mA. Nhảy 60 mA rồi tụt = **reset loop**; giữ ổn định
  ~20 mA = chạy nhưng chưa bật ngoại vi; vọt 200 mA = loa/amp bật.

### 2.6 Khi mọi thứ bí: X-ray/CT

Board 2–4 lớp thì chụp ảnh + soi kính hiển vi + continuity là đủ. 6+ lớp (BGA, via ẩn) thì
thuê chụp **X-ray 2D (~150–400 USD/giờ)** hoặc **CT 3D** — không cần mua máy 30–80k.
Cách rẻ hơn: **delayering** hoá học (bào lớp) trên một board hỏng — phá huỷ nhưng đọc được
từng lớp đồng.

---

## Bước 3 — Đối chiếu & loại trừ

Mỗi chân phải có **2 nguồn độc lập** trước khi tin:

| Chân | Nguồn A | Nguồn B | Kết luận |
| --- | --- | --- | --- |
| SCLK màn hình | community (9) | LA decode trên board (9) | tin |
| Battery ADC | community (17) | đo chia áp 1:2 tại chân 17 | tin |
| "Sleep control" | bảng người bán (21) | firmware gốc không dùng | **bỏ** |

Nếu hai nguồn lệch nhau: thử trên phần cứng, đừng tranh luận trên giấy.

---

## Bước 4 — Biến mọi thứ thành manifest (để lần sau build là xong)

Đây là phần "để sau này build firmware nào cũng dễ" bạn cần: **một file JSON là nguồn sự
thật duy nhất**, dùng để sinh `build_flags` của Bruce, YAML của ESPHome, hay `config.h` của
firmware tự viết.

Mẫu đầy đủ: `firmware/board-manifest.example.json` (kèm trong repo này). Những trường
**bắt buộc** phải có, vì thiếu cái nào là tốn một buổi debug:

- `mcu`: chip, revision, flash size/mode, PSRAM (loại + tốc độ), USB (native/JTAG/bridge).
- `panel`: controller, kích thước thật, RAM của controller, offset, MADCTL, invert, BGR,
  **clock SPI**, bảng init (hoặc đường dẫn file).
- `bus`: I2C, I2S (mclk/bclk/ws/din/dout), SPI.
- `codecs`: địa chỉ + chip + sample rate.
- `power`: chân PA enable, đèn nền (+ PWM/kênh), chân giữ nguồn (nếu có), charge detect,
  battery ADC (kênh + hệ số chia).
- `buttons`: chân, pull, mức tích cực, chức năng.
- `led`, `ir`, `rf`, `sd`, `audio out`.
- `quirks`: mọi thứ kỳ quái đã gặp — ví dụ "mic.cpp gọi `gpio_reset_pin(0)` làm mất nút
  Sel", "phải kéo GPIO21 HIGH ngay lệnh đầu tiên", "nạp phải dùng USB-Serial-JTAG".
- `evidence`: mỗi mục ghi nguồn (`community:xingzhi-yaml`, `la-decode:2026-11-20`,
  `ghidra:0x400d1a3c`) — để 6 tháng sau không phải làm lại.

Quy ước: **không có `evidence` thì không được coi là đã xác định.**

---

## Bước 5 — Checklist riêng cho board này (DSolution 1.83" / OSTB-2ST-WIFI)

Đã chắc (2 nguồn):

| Hạng mục | Giá trị | Nguồn |
| --- | --- | --- |
| Panel | NV3023, 284×240, offset X 36, MADCTL `0xA8`, invert, BGR, SPI 40 MHz | ESPHome yaml + bảng init khớp |
| SPI màn hình | SCLK 9 / MOSI 10 / CS 14 / DC 8 / RST 18 / BL 13 | ESPHome yaml + Maerchenbox |
| I2C | SDA 12 / SCL 11 (ES8311 `0x18`, ES7210 `0x40`) | ESPHome + Maerchenbox |
| I2S | MCLK 5 / BCLK 15 / WS 16 / DIN 7 / DOUT 6 | ESPHome + Maerchenbox |
| PA loa | GPIO4 HIGH | ESPHome ("Speaker Enable") |
| Nút | 0 / 39 / 40, pull-up, mức thấp | ESPHome + Maerchenbox |
| Sạc | GPIO47, LOW = đang sạc | Maerchenbox |
| Pin | GPIO17, ADC2 ch6, chia 1:2 | Maerchenbox |
| WS2812 | GPIO48 | ESPHome |

Còn **phải kiểm bằng tay** (chưa ai xác nhận):

| Câu hỏi | Cách kiểm trong 5 phút |
| --- | --- |
| GPIO21 có phải chân **giữ nguồn**? | Nạp firmware có/không kéo GPIO21 HIGH, xem board có trụ nguồn qua 10 giây; hoặc đo: khi chạy, chân 21 có mức cao ổn định và nối tới chân EN của LDO/MOSFET? |
| GPIO38 là gì? | Đo continuity tới đâu; thử input pull-up/pull-down xem mức đổi (nếu là "battery low" thì đổi theo pin yếu) |
| Đèn nền có PWM được không? | Kéo HIGH/LOW, rồi PWM 0/50/100% — nếu độ sáng đổi thì ok (LEDC) |
| Mic nào là MIC1/2? | Ghi âm, che từng lỗ mic, xem kênh nào tắt |
| Có cảm ứng không? | I2C scan xem có `0x5D`/`0x14`/`0x38` không |

---

## Bộ công cụ tối thiểu (2026)

| Việc | Dụng cụ | Giá |
| --- | --- | --- |
| Nạp/dump | esptool v5 (`esptool.py info`, `flash-id`, `read-flash`) | free |
| Bóc firmware | `esp32_image_parser`, `esp32_universal_extractor`, `esp32knife`, binwalk | free |
| Dịch ngược | Ghidra 12.x + **GhidraMCP** / **ReVa** (agent AI gọi trực tiếp) | free |
| Đo | đồng hồ vạn năng có continuity + nguồn bench đo mA | 30–80 USD |
| Bắt tín hiệu | logic analyzer 8 kênh + PulseView (decoder I2C/SPI/I2S) | 10–30 USD |
| Ảnh mạch | điện thoại 12MP + macro, **PCB Tracer** (chồng 2 mặt, xuất KiCad) | free |
| Nhiệt | camera nhiệt cắm điện thoại | 80–200 USD |
| Lớp trong (nếu bí) | thuê X-ray/CT theo giờ | 150–400 USD/giờ |

Tổng dưới 150 USD là đã đủ xác định **mọi chân** của một board như thế này. Phần đắt
(X-ray/CT) gần như không bao giờ cần cho board 2–4 lớp.

---

## Quy trình chuẩn hoá cho lần sau (mỗi board mới ~2 giờ)

1. 15 phút: Bước 0 — tên máy, chip, USB, tra cộng đồng.
2. 20 phút: dump 16 MB + `show_partitions` + `strings` (giữ file dump làm bảo hiểm).
3. 30 phút: I2C scan + logic analyzer trên SPI/I2S khi chạy firmware gốc.
4. 20 phút: continuity cho nút/đèn/amp/pin.
5. 15 phút: Ghidra + agent đối chiếu danh sách chân (nếu còn nghi).
6. 20 phút: viết `board-manifest.json` + `evidence`, rồi sinh `build_flags`/YAML từ nó.

Xong bước 6 là board đó **không bao giờ phải đoán lại** — build firmware nào cũng chỉ là
một lệnh.
