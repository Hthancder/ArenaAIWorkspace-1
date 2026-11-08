# Chạy trên máy thật — từ 0 tới "thấy màn hình trong trình duyệt"

> Mục tiêu của file này: **5 phút**, kết thúc bằng một tab trình duyệt (trên laptop hoặc trên điện thoại cùng Wi-Fi) hiện **màn hình thật** của laptop Windows.
>
> Đây **chưa phải** bản remote desktop hoàn chỉnh. Nó **chỉ có hình**. Không có tiếng, không điều khiển được chuột/bàn phím, và không phải WebRTC. Nói rõ để bạn không chờ đợi sai: xem §"Nó chưa làm được gì" ở cuối.

---

## 0. Bạn cần gì

| Thứ | Vì sao | Thời gian |
|---|---|---|
| Laptop Dell 7467 đang chạy | máy ghi hình | — |
| ~~GStreamer~~ **không cần** | capture DXGI + JPEG nằm trong exe | **0 phút** |
| Artifact `lantern-mock-windows-x64` từ GitHub Actions | app + UI, không cần cài Rust | 10 giây |
| Chrome/Edge trên máy xem | hiển thị MJPEG | — |

---

## 1. Không cần cài **bất cứ thứ gì**

> Bản v3.32 bỏ hẳn GStreamer. Trước đó để xem màn hình bạn phải cài **517 MB**
> (installer GStreamer) — với một người dùng cá nhân, đó là cái giá sai cho một
> việc chỉ cần hai thứ: một frame ảnh, và một hàm nén JPEG.
>
> Giờ cả hai nằm **trong `lantern-mock.exe`** (747 KB): app tự gọi DXGI Desktop
> Duplication qua COM và tự nén JPEG. Không DLL, không PATH, không installer,
> không bước cài nào. Xem `docs/remote-desktop-spec.md` §58.15.

Nếu nút **Xem máy thật** bị xám, lý do là **môi trường**, không phải thiếu phần
mềm. Ba nguyên nhân thật, mỗi cái có cách xử lý riêng:

| App báo | Nghĩa là | Làm gì |
|---|---|---|
| "Capture màn hình chỉ chạy trên Windows" | bạn đang chạy bản build cho Linux/macOS | tải artifact `lantern-mock-windows-x64` |
| "Không thấy màn hình nào gắn vào desktop" | phiên RDP đã ngắt, hoặc driver display lỗi | mở phiên local (hoặc kết nối lại RDP rồi thử) |
| "monitor-index N không tồn tại" | máy chỉ có ít màn hình hơn N+1 | chọn monitor 0 trong thanh dưới khung hình |

---



## 2. Lấy app (10 giây)

GitHub → **Actions** → run mới nhất trên nhánh này → **Artifacts** → `lantern-mock-windows-x64` → giải nén → chạy **`lantern-mock.exe`**.

App sẽ:
- bind **chỉ `127.0.0.1`** (không mở ra LAN — §41.5 D4/§54.5 #1),
- tự mở trình duyệt,
- in ra console 2 địa chỉ: trang chính và `/live`.

---

## 3. Bấm nút "◉ Xem máy thật"

Nút này **chỉ sáng** khi app mở được một phiên DXGI Desktop Duplication thật rồi đóng lại ngay. Nếu không, nó vẫn hiện nhưng bị mờ và **nói lý do cụ thể** — không có khung đen im lặng.

Khi bật:
- khung "Màn hình từ xa" chuyển từ bản mô phỏng sang **ảnh thật**, ~15 fps, 1280×720;
- thanh dưới có: chọn **màn hình 0/1/2/3**, chọn **FPS 5/10/15/30**, nút toàn màn hình, nút **↗ mở tab riêng**.

---

## 4. Xem từ điện thoại (tuỳ chọn, 2 phút)

Đường này **không** mở cổng ra LAN. Muốn xem từ điện thoại trong nhà, có hai cách — chọn **một**:

### Cách A (khuyên): Tailscale — không mở cổng, có TLS

```powershell
# Trên laptop và trên điện thoại: cài Tailscale, đăng nhập cùng tài khoản
tailscale cert inspiron-7467.<tailnet>.ts.net     # lấy cert hợp lệ
```

Rồi chạy app với cổng LAN + cert (bước này **cần** TLS, xem §54.5 #1):

```powershell
$env:HOST="0.0.0.0"; $env:PORT="8443"
.\lantern-mock.exe
```

Mở trên điện thoại: `https://inspiron-7467.<tailnet>.ts.net:8443/live`

> Chưa nối cert vào binary? Xem §6 "Giới hạn đã biết" — hiện app **chỉ bind loopback**, nên cách A cần thêm bước (chưa làm).

### Cách B (tạm, chỉ trong nhà): SSH port-forward

```powershell
# Trên điện thoại dùng Termius/JuiceSSH, forward 8080 -> 127.0.0.1:PORT của laptop
# rồi mở http://127.0.0.1:8080/live trong trình duyệt điện thoại
```

Không mở cổng nào ra ngoài, không cần cert, nhưng cần bật OpenSSH Server trên Windows.

> ⚠️ **Đừng** đặt `HOST=0.0.0.0` không có TLS và mở cổng router. Đó là đưa màn hình của bạn cho cả quán cà phê.
>
> App **thật sự** chặn việc này: mọi `HOST` không phải loopback đều bị hạ về `127.0.0.1` kèm cảnh báo trong console (§58.11 — trước v3.30 tài liệu nói câu này mà code không kiểm tra gì). Nếu bạn tự chịu rủi ro và hiểu mình đang làm gì: `LANTERN_ALLOW_LAN=1` + `HOST=0.0.0.0`. Không khuyến khích.

---

## 5. Đọc số đo của đường này (đừng nhầm với p95 của spec)

MJPEG **không phải** đường đo p95 glass-to-glass (§6.2.3). Nó dùng để *nhìn*, không phải để *kết luận*. Cách đọc đúng:

| Bạn thấy | Nghĩa là | Không có nghĩa là |
|---|---|---|
| Hình hiện, ~10–15 fps | `d3d11screencapturesrc` **chạy được** trên adapter đang dùng | p95 đạt |
| Hình hiện nhưng chữ mờ | JPEG q70 + downscale 720p | encoder QSV có vấn đề |
| Hình hiện, mở Task Manager thấy CPU ~10–25% | JPEG encode là CPU (`jpegenc`), không phải GPU | QSV tốn CPU |
| Trễ ~150–300 ms | MJPEG qua HTTP: buffer + JPEG decode | WebRTC sẽ trễ thế này |
| **Không** hiện, báo lỗi rõ trong toast | pipeline chết và app nói lý do | — |
| Bấm nút, chờ ~4 s rồi mới báo lỗi | app chờ frame đầu tối đa 4 s rồi trả `504` kèm số monitor đã thử | — |
| Hình đứng ở frame đầu | app **không** tự mở lại phiên khi desktop đổi (UAC/khoá máy) — bấm Dừng rồi Xem lại | — |

Muốn số p95 thật (mục đích của P0): dùng `gst-launch-1.0` với pipeline trong §37, cộng camera chụp đồng hồ — đúng §6.2.3. Đường MJPEG này **không** thay thế bước đó.

---

### Vì sao "đóng tab" là chuyện kỹ thuật, không phải chuyện lịch sự

Khi bạn đóng tab, app phải **dừng capture ngay**. Bản v3.31 phải kill một tiến
trình `gst-launch-1.0` bên ngoài — và làm sai ba lần (xem §58.7–§58.9). Bản v3.32
không có tiến trình con nào: vòng lặp capture kiểm socket mỗi 200 ms và `return`,
`Capture` drop ⇒ device DXGI + duplication được giải phóng. Không có gì để mồ côi.

Nếu bạn thấy quạt vẫn chạy sau khi đóng tab, đó là bug thật — không phải "chuyện
bình thường".

## 6. Giới hạn đã biết của bản này (đọc trước khi báo lỗi)

| Hạn chế | Vì sao | Cách xử lý tạm |
|---|---|---|
| **Chỉ bind `127.0.0.1`** | chưa có TLS trong binary; §54.5 #1 cấm bind LAN không TLS | SSH tunnel / Tailscale + bước thêm (chưa làm) |
| Không có tiếng | MJPEG không mang audio; WASAPI loopback là §40, chưa nối | — |
| Không điều khiển được | `SendInput` + DataChannel là §44, chưa nối | — |
| Không có xác thực | app chưa có `/api/login`; chỉ loopback nên chưa cần | **không** đổi `HOST` |
| Hình đứng thì phải tắt/bật lại | pipeline không tự restart (chưa có watchdog) | bấm Dừng rồi Xem lại |
| Đổi monitor khi đang xem | phiên capture được mở lại từ đầu — mất < 1 s | bình thường |
| Trình duyệt cũ không hỗ trợ MJPEG | `multipart/x-mixed-replace` cần Chrome/Edge/Firefox/Safari bản còn được cập nhật | dùng Chrome hoặc Edge |
| `monitor-index` **không** khớp số trong Settings Windows | app đếm theo DXGI (thứ tự output của adapter), Windows đếm theo display | thử 0, 1, 2 cho tới khi đúng hình |

---

## 7. Lỗi thường gặp → việc cần làm

| Thông báo / hiện tượng | Nguyên nhân | Làm gì |
|---|---|---|
| Nút "Xem máy thật" mờ, tooltip "Capture màn hình chỉ chạy trên Windows" | bạn đang chạy bản build Linux/macOS | tải artifact `lantern-mock-windows-x64` |
| "Không thấy màn hình nào gắn vào desktop" | phiên RDP đã ngắt, hoặc display driver lỗi | mở phiên local; cập nhật driver Intel HD 630 |
| "monitor-index N không tồn tại: máy chỉ có M màn hình" | N ≥ M | chọn monitor trong thanh dưới khung hình (0-based) |
| `503` kèm "DuplicateOutput → 0x…" | một app khác đang giữ Desktop Duplication, hoặc DXGI từ chối | đóng app ghi hình khác rồi Xem lại |
| `504` sau 4 s | màn hình đứng hoàn toàn (screensaver đen, DPMS tắt) | bấm phím rồi Xem lại |
| Hình hiện rồi đứng | chưa có watchdog restart | Dừng → Xem lại |
| Toàn đen, nhưng Task Manager thấy GPU | app đang capture một display không tồn tại (VDD chưa cài) | thử monitor khác; VDD là §51.6 |
| Trình duyệt tải mãi không dừng | proxy/extension chặn `multipart/x-mixed-replace` | thử cửa sổ ẩn danh, tắt extension |
| Laptop nóng quá | JPEG ở 15 fps là CPU thật | hạ FPS xuống 5–10, hạ monitor, đóng tab khi không xem |

---

## 8. Nó **chưa** làm được gì

Đọc để không kỳ vọng sai:

- ❌ **Không có tiếng** (chưa nối `wasapi2src`/Opus — §40, §55)
- ❌ **Không điều khiển được** (chưa có `SendInput`, chưa có DataChannel — §44)
- ❌ **Không phải WebRTC** (chưa có `webrtcbin`, SDP, ICE, DTLS — §37, §10.2)
- ❌ **Không có đăng nhập** (chưa có `/api/login`; §57 có code nhưng chưa nối)
- ❌ **Không click được cửa sổ** (chỉ xem cả màn hình; window picker vẫn là mock — §41.4 T1 có registry, chưa nối `EnumWindows`)
- ❌ **Không chạy ngoài LAN** mà không có tunnel

Đây là **bước 1**: chứng minh **đường capture → trình duyệt chạy trên máy bạn**. Mỗi ❌ ở trên là một chương spec đã có thiết kế, chưa có code — theo đúng thứ tự §57.8: `config.rs` → `signaling.rs` → client shell.
