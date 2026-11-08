# Chạy trên máy thật — từ 0 tới "thấy màn hình trong trình duyệt"

> Mục tiêu của file này: **15 phút**, kết thúc bằng một tab trình duyệt (trên laptop hoặc trên điện thoại cùng Wi-Fi) hiện **màn hình thật** của laptop Windows.
>
> Đây **chưa phải** bản remote desktop hoàn chỉnh. Nó **chỉ có hình**. Không có tiếng, không điều khiển được chuột/bàn phím, và không phải WebRTC. Nói rõ để bạn không chờ đợi sai: xem §"Nó chưa làm được gì" ở cuối.

---

## 0. Bạn cần gì

| Thứ | Vì sao | Thời gian |
|---|---|---|
| Laptop Dell 7467 đang chạy | máy ghi hình | — |
| **GStreamer MSVC 64-bit** (bản **Complete**) | capture DXGI + JPEG + multipart | ~5 phút tải/cài |
| Artifact `lantern-mock-windows-x64` từ GitHub Actions | app + UI, không cần cài Rust | 10 giây |
| Chrome/Edge trên máy xem | hiển thị MJPEG | — |

---

## 1. Cài GStreamer (5 phút, 1 lần)

1. Mở <https://gstreamer.freedesktop.org/download/#windows>
2. Tải **runtime installer** và **development installer**, loại **MSVC 64-bit**.
   ⚠️ **Bắt buộc chọn bản "Complete"**, không phải "Typical": `d3d11` nằm trong
   `gst-plugins-bad`, mà bản Typical bỏ qua nhóm này.
3. Cài **cả hai** vào cùng một thư mục, ví dụ `C:\gstreamer`.
4. Thêm vào `PATH` (System properties → Environment Variables):

```powershell
# PowerShell, chạy 1 lần, không cần admin nếu dùng PATH của user
$gst = "C:\gstreamer\1.0\msvc_x86_64\bin"
[Environment]::SetEnvironmentVariable(
  "PATH",
  [Environment]::GetEnvironmentVariable("PATH", "User") + ";$gst",
  "User")
```

5. **Mở cửa sổ PowerShell mới** (cửa sổ cũ không thấy `PATH` mới) và kiểm:

```powershell
gst-launch-1.0 --version
gst-inspect-1.0 d3d11screencapturesrc    # phải in ra thông tin element, không phải "No such element"
gst-inspect-1.0 jpegenc
```

> Nếu `gst-inspect-1.0` báo **No such element or plugin 'd3d11screencapturesrc'** ⇒ bạn đã cài bản Typical. Cài lại bản Complete.

---

## 2. Lấy app (10 giây)

GitHub → **Actions** → run mới nhất trên nhánh này → **Artifacts** → `lantern-mock-windows-x64` → giải nén → chạy **`lantern-mock.exe`**.

App sẽ:
- bind **chỉ `127.0.0.1`** (không mở ra LAN — §41.5 D4/§54.5 #1),
- tự mở trình duyệt,
- in ra console 2 địa chỉ: trang chính và `/live`.

---

## 3. Bấm nút "◉ Xem máy thật"

Nút này **chỉ hiện** khi app kiểm tra thấy đủ GStreamer + plugin `d3d11`. Nếu không đủ, nó vẫn hiện nhưng bị mờ và **nói lý do** (thiếu GStreamer / thiếu plugin / chỉ chạy trên Windows) — không có khung đen im lặng.

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
| Bấm nút, chờ ~8 s rồi mới báo lỗi | app chờ frame đầu tối đa 8 s rồi trả `504` + lỗi GStreamer | — |
| Hình đứng ở frame đầu | app **không** tự restart pipeline — xem §6 | — |

Muốn số p95 thật (mục đích của P0): dùng `gst-launch-1.0` với pipeline trong §37, cộng camera chụp đồng hồ — đúng §6.2.3. Đường MJPEG này **không** thay thế bước đó.

---

### Vì sao "đóng tab" là chuyện kỹ thuật, không phải chuyện lịch sự

Khi bạn đóng tab, app **phải** kill `gst-launch-1.0`. Bản v3.30 làm việc đó trong ≤ ¼ s, kể cả khi pipeline im lặng (màn hình tĩnh) và kể cả khi trình duyệt cắt kết nối bằng RST thay vì FIN. Nếu một ngày bạn thấy `gst-launch-1.0.exe` còn trong Task Manager sau khi đóng tab, đó là bug — mở lại `docs/remote-desktop-spec.md` §58.7–§58.9 để biết ba cách nó từng xảy ra.

## 6. Giới hạn đã biết của bản này (đọc trước khi báo lỗi)

| Hạn chế | Vì sao | Cách xử lý tạm |
|---|---|---|
| **Chỉ bind `127.0.0.1`** | chưa có TLS trong binary; §54.5 #1 cấm bind LAN không TLS | SSH tunnel / Tailscale + bước thêm (chưa làm) |
| Không có tiếng | MJPEG không mang audio; WASAPI loopback là §40, chưa nối | — |
| Không điều khiển được | `SendInput` + DataChannel là §44, chưa nối | — |
| Không có xác thực | app chưa có `/api/login`; chỉ loopback nên chưa cần | **không** đổi `HOST` |
| Hình đứng thì phải tắt/bật lại | pipeline không tự restart (chưa có watchdog) | bấm Dừng rồi Xem lại |
| Đổi monitor khi đang xem | pipeline được tạo lại từ đầu — có thể mất 1–2 s | bình thường |
| GStreamer bản Typical | thiếu `d3d11` | cài lại bản Complete |
| `monitor-index` trong GStreamer **không** khớp số trong Settings Windows | GStreamer đếm theo DXGI, Windows đếm theo display | thử 0,1,2 cho tới khi đúng hình |

---

## 7. Lỗi thường gặp → việc cần làm

| Thông báo / hiện tượng | Nguyên nhân | Làm gì |
|---|---|---|
| Nút "Xem máy thật" mờ, tooltip "Chưa có GStreamer trong PATH" | PATH của **tiến trình** chưa có `bin` | mở PowerShell mới rồi chạy lại exe; kiểm `gst-launch-1.0 --version` |
| "Thiếu plugin d3d11" | bản Typical | cài lại GStreamer bản Complete |
| `503` + stderr của GStreamer | pipeline sai monitor index / không có output nào | xem đúng stderr hiện trong toast; thử monitor 0 |
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
