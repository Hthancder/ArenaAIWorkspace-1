# Rà soát lỗi UI / UX / logic — bản giao ngày 2026-11-25

Tài liệu này liệt kê **từng lỗi thật đã tìm được**, chỉ rõ nó nằm ở dòng nào trong
mã, vì sao nó xảy ra, đã sửa thế nào, và **cách bạn tự kiểm chứng trên máy thật**.
Chỉ ghi những gì truy được tới đúng chỗ trong code — không có mục nào là phỏng đoán.

Tất cả nằm trong `firmware/dsolution-183-2mic-bruce.patch` (áp lên Bruce `2b6ba4d`),
commit `aa1dfc1`.

---

## Bảng tổng hợp

| # | Người dùng thấy gì | Nằm ở đâu | Nguyên nhân thật |
|---|---|---|---|
| 1 | Một ô vuông/rỗng trong tên mục menu BLE | `ble_spam.cpp:701` | Nhãn có emoji `🎉`, mà màn hình chỉ vẽ được chữ ASCII |
| 2 | Gợi ý phím ghi "Click=Select ESC=Back", "SEL run ESC back", "[ESC] Stop" | ~20 chỗ, xem mục 3 | Chép từ bản chạy trên máy tính, board này chỉ có 3 nút |
| 3 | Mục menu dài (múi giờ…) tràn chữ ra ngoài khung | `display.cpp:1466-1515` | Hàng trên/dưới mục đang chọn **không bị cắt chữ** |
| 4 | Bấm nút "Play again" ở game Pet bị nhảy ra ngoài luôn | `tururururu.cpp:317` | Dùng `while(check(SelPress))` — hàm `check()` chỉ báo "vừa bấm", nên vòng chờ thoát ngay |
| 5 | Bấm vào dòng "--- Actions ---" trong NetCut không có gì xảy ra | `netcut.cpp:855` | Đó là dòng phân cách nhưng vẫn bấm được, mà bấm thì không làm gì |
| 6 | OTA báo "Network error" thay vì "phiên đăng nhập hết hạn" | `webInterface.cpp:2007` | Route `/ota/chunk` trả lỗi dạng chữ thường, trang lại đọc dạng JSON |
| 7 | WebUI nửa tiếng Việt nửa tiếng Anh | `index.js` (23 chuỗi) | Phần BadUSB/portal mới viết bằng tiếng Việt, phần còn lại tiếng Anh |
| 8 | OTA đứng mãi ở "Verifying & committing…" | `index.js:1443` | Bước commit là `fetch()` **duy nhất không có timeout** |

---

## 1. Ô vuông trong tên mục menu BLE

**Thấy gì:** trong menu BLE Spam, dòng "Party Mode (All Devices)" hiện một ô vuông lạ.

**Vì sao:** nhãn gốc là `"🎉 Party Mode (All Devices)"`. Màn hình của board vẽ chữ bằng
font bitmap ASCII của LovyanGFX. Mình đã kiểm tra thư viện hiển thị
(`bmorcelli/DisplayDrivers`): không có chỗ nào gọi `setFont()`, nghĩa là **không có font
Unicode**. Ký tự emoji bị cắt thành byte rác nên ra ô vuông.

Đây là lỗi có sẵn từ trước, không phải do đợt sửa này, nhưng cùng bản chất với các
chuỗi khác nên sửa luôn.

**Sửa:** bỏ emoji, giữ nguyên chữ.

**Tự kiểm trên máy:** vào `BLE → BLE Spam Lab`, nhìn dòng "Party Mode (All Devices)" —
không còn ô vuông.

---

## 2 + 3. Gợi ý phím sai board và lệch nhau

**Thấy gì:** dưới đáy màn hình có những dòng như
`Click=Select  ESC=Back`, `SEL run  ESC back`, `[ESC] Stop`, `Press SEL to abort`.

**Vì sao:** board `dsolution-183-2mic` **không có phím "Click"**, cũng không có phím
ESC để bấm. Nó có 3 nút vật lý: Vol−, Vol+, Boot. ESC là **tổ hợp** giữ nút Boot 520 ms.
Nhưng các dòng gợi ý này được gõ tay ở từng chỗ, chép từ bản Bruce chạy trên máy tính,
nên chúng ghi những phím không tồn tại. Vì gõ tay từng nơi nên mỗi nơi lại ghi một kiểu.

**Sửa:** đưa toàn bộ về **một chỗ duy nhất** trong `include/precompiler_flags.h`:

```
UI_HINT_SELECT   -> "Sel"
UI_HINT_BACK     -> "Esc"
UI_HINT_LIST     -> "Sel=Select  Esc=Back"
UI_HINT_STOP     -> "Sel=Edit  Esc=Stop"
UI_HINT_YES_NO   -> "Sel=Yes  Esc=No"
UI_HINT_CONFIRM  -> "Sel=Confirm  Esc=Cancel"
UI_HINT_OPEN / PICK / RUN / TOGGLE ...
```

Tên nút lấy từ `BTN_ALIAS`, nên board nào đặt tên nút khác chỉ cần sửa **một dòng**.
Đã thay ở: `ble_spam.cpp`, `BLE_Suite.cpp`, `ble_sniffer.cpp`, `ble_tracker_guard.cpp`,
`pwnagotchi/ui.cpp`, `nrf_mousejack.cpp`, `rf_jammer.cpp`, `ducky_typer.cpp`,
`timer.cpp`, `ir_read.cpp`, `wifi_recover.cpp`, `tururururu.cpp`.

**Tự kiểm trên máy:** mở vài màn hình bất kỳ (BLE Suite, RF Jammer, NetCut…), dòng gợi ý
dưới đáy phải luôn ghi `Sel` / `Esc`, không còn chữ `Click`, `SEL …` kiểu cũ, hay `[ESC]`.

---

## 3. Chữ tràn khung trong menu

**Thấy gì:** khi một mục menu dài (ví dụ tên múi giờ, 39–41 ký tự), chữ của **mục bên
trên/bên dưới mục đang chọn** chạy thẳng ra ngoài khung viền.

**Vì sao:** trong `displayMenu()`, chỉ **mục đang chọn** được cắt chữ cho vừa. Hai mục
hàng xóm vẽ nguyên văn nhãn gốc (`display.cpp:1470`, `1505`). Nhãn dài hơn bề rộng màn
hình thì tràn.

**Sửa:** thêm hàm `fitMenuLabel()` (khai báo ở `display.h`) cắt theo số ký tự vừa bề rộng
và thêm `~` ở cuối để biết là đã cắt. Cả ba chỗ (mục đang chọn + 2 hàng xóm) dùng chung
hàm này, nên quy tắc cắt giống hệt nhau ở mọi dòng.

**Tự kiểm trên máy:** `Config → Time zone`, bấm xuống qua các mục — không dòng nào tràn
qua viền; dòng nào bị cắt sẽ có `~` ở cuối.

---

## 4. Game Pet: "Play again" bị nhảy ra ngoài

**Thấy gì:** ở màn hình GAME OVER bấm nút chọn để chơi lại thì game thoát luôn ra menu.

**Vì sao:** mã cũ viết `while (check(SelPress)) {...}`. Hàm `check()` nghĩa là *"vừa bấm
trong lần đọc này"* — nó tự xoá trạng thái sau khi đọc. Vì vậy vòng chờ thoát ra ngay
lập tức, trước khi người dùng kịp nhấc tay; cú bấm đó lại bị lần đọc kế tiếp hiểu là
"bấm để thoát".

**Sửa:** chờ đúng mức tín hiệu `while (SelPress)` (giữ nút thì còn chờ), và đặt lại
`levelStart = millis()` khi bắt đầu ván mới để đồng hồ không cộng dồn thời gian ở màn
hình chờ.

**Tự kiểm trên máy:** `Studio → Pet (offline)` → chơi cho thua → bấm chọn → phải vào ván
mới, không nhảy ra menu.

---

## 5. NetCut: dòng "--- Actions ---" bấm không có gì

**Thấy gì:** trong danh sách thiết bị NetCut, dòng chữ `--- Actions ---` bấm vào không
phản hồi gì — giống như nút bị liệt.

**Vì sao:** đó là **dòng phân cách** cho đẹp, nhưng được tạo như một mục menu bình
thường (`netcut.cpp:855`), mà chức năng của nó là hàm rỗng `[]() {}`. Người dùng bấm
được nhưng không có gì xảy ra.

**Sửa:** tạo nó ở trạng thái **bị khoá** nên con trỏ tự bỏ qua, không chọn được nữa.

**Tự kiểm trên máy:** `WiFi → NetCut`, bấm xuống: con trỏ phải nhảy qua dòng
`--- Actions ---`, dừng ở "Cut All".

---

## 6. OTA báo "Network error" khi phiên đăng nhập hết hạn

**Thấy gì:** đang nạp OTA mà phiên đăng nhập WebUI hết hạn thì trang báo "Network
error" — không nói được là phải đăng nhập lại.

**Vì sao:** mọi nhánh trả lời của route `/ota/chunk` đều là JSON, **trừ** nhánh kiểm tra
đăng nhập: nó trả `text/plain` (`webInterface.cpp:2007`). Trang thì luôn đọc nội dung
bằng `.json()`, nên gặp chữ thường là lỗi parse → hiện "Network error".

**Sửa:** nhánh đó cũng trả JSON, kèm câu nói rõ: *"WebUI session expired. Reload the
page and log in again."*

**Tự kiểm trên máy:** hơi khó tái hiện thủ công (phải để phiên hết hạn giữa lúc nạp).
Cách nhanh: đăng xuất ở tab khác rồi bấm Upload — trang phải nói "session expired",
không phải "Network error".

---

## 7. WebUI nửa Việt nửa Anh

**Thấy gì:** các nút "Dùng làm payload", thông báo "Đã lưu: …", "Chưa có mẫu nào…",
nút "Dùng / Sửa / Nhân bản / Xoá" nằm giữa một trang toàn tiếng Anh.

**Vì sao:** phần BadUSB + portal templates được viết sau, bằng tiếng Việt, trong khi
toàn bộ WebUI còn lại là tiếng Anh. Không phải lỗi chức năng, nhưng là thiếu nhất quán
rõ rệt.

**Sửa:** dịch 23 chuỗi sang tiếng Anh. **Giữ nguyên tiếng Việt** ở trang captive portal
(`index.js:1966`) — trang đó để nạn nhân đọc, tiếng Việt mới đúng.

**Tự kiểm trên máy:** mở WebUI, vào tab Studio/BadUSB và tab Portal templates — chữ phải
là tiếng Anh, thống nhất với phần còn lại.

---

## 8. OTA đứng mãi ở "Verifying & committing…"

**Thấy gì:** nạp xong 100%, trang hiện "Verifying & committing OTA slot...", rồi **đứng
im mãi**; nút Cancel đã bị ẩn nên không còn cách nào ngoài tải lại trang.

**Vì sao:** trong cả luồng OTA, mỗi bước đều có giới hạn thời gian: `/ota/begin` 180 s,
mỗi `/ota/chunk` 12 s, chờ khởi động lại 20 lần. Riêng `/ota/commit` là `fetch()` **duy
nhất không có timeout** (`index.js:1443`). Nếu thiết bị khởi động lại trước khi kịp trả
lời, hoặc gói tin cuối bị rơi, trang chờ vô hạn.

**Sửa:** thêm timeout 30 s cho commit. Hết 30 s thì rơi vào nhánh xử lý đã có sẵn, hiện
đúng câu: *"Commit reply lost or failed. Check the device and do not power it off; the
update may have completed."* — tức là vẫn cảnh báo không được tắt máy giữa chừng.

**Tự kiểm trên máy:** nạp OTA bình thường — vẫn phải chạy xong và tự khởi động lại. Điều
khác biệt chỉ thấy khi mạng rớt đúng lúc commit: trang sẽ báo sau ≤30 s thay vì đứng im.

---

## Test khoá hồi quy

`tests/device-ux/consistency-test.py` chạy trong CI mỗi lần build, kiểm tra:

- Không nhãn menu nào trong 3 file UI chính chứa ký tự ngoài ASCII
- Mọi macro `UI_HINT_*` đều tồn tại và lấy tên nút từ `BTN_ALIAS`
- Không file nào còn gõ tay `Click=`, `ESC=`, `SEL `, `[ESC]` (miễn trừ đúng 2 file
  lệnh serial — đó là console gõ trên máy tính, ESC ở đó là thật)
- Không còn dòng phân cách `--- … ---` nào bấm được mà rỗng
- `fitMenuLabel` phải được dùng ở cả 3 chỗ vẽ menu và có khai báo trong `display.h`
- `/ota/chunk` trả JSON ở nhánh 401
- `index.js` không còn chuỗi tiếng Việt nào ngoài trang captive portal
- Mọi `fetch()` của `/ota/begin|chunk|commit` phải có `signal` (timeout)

Chạy tay:

```bash
python3 tests/device-ux/consistency-test.py /tmp/Bruce
bash tests/device-ux/run.sh /tmp/Bruce        # toàn bộ 14 nhóm test
```

---

## Những chỗ đã kiểm nhưng **không** phải lỗi

Ghi lại để khỏi rà lại lần nữa:

- **45 route WebUI** đều kiểm tra đăng nhập, trừ `/login` — đúng thiết kế.
- **Cấp phát bộ nhớ** ở `sonar_guard.cpp`, `pmkid_capture.cpp`, `probe_radar.cpp`,
  `virtual_msc.cpp`: đều kiểm tra NULL sau khi cấp phát.
- **Cờ trạng thái** `s_running` / `s_stopReq` ở `lan_auditor.cpp`, `lan_guard.cpp`,
  `napt_router.cpp`: reset đúng trên mọi nhánh thoát, kể cả khi tạo task thất bại.
- **Rò rỉ bộ nhớ:** không có `malloc`/`new` nào trong code mới thiếu `free`/`delete`
  tương ứng.
- **Tên chủ máy** (`ownerName`) đã bị cắt 24 ký tự khi lưu và 12 ký tự khi vẽ.
- **`showSubMenu("DoS Attacks", …)` xuất hiện 2 lần** nhưng ở 2 ngữ cảnh khác nhau
  (một cho BLE, một cho WiFi) — không phải mục trùng.
- **`ensureMouse()` trong `smart_badusb.cpp`** chờ tối đa 5 s khi cắm USB, nhưng hàm
  `smartBadUsbMouseJiggler()` hiện **không được nơi nào gọi** — code chết, không ảnh
  hưởng.
