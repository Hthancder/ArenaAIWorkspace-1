# Hướng dẫn: Chạy cửa sổ ứng dụng trên máy Windows bị điều khiển — máy điều khiển thấy (kể cả âm thanh), máy bị điều khiển thì KHÔNG thấy

## 1. Vấn đề và nguyên lý

Bạn cần một cách để:

- **Máy bị điều khiển** (Windows) chạy một cửa sổ ứng dụng.
- **Máy điều khiển** (từ xa) nhìn thấy cửa sổ đó và nghe được âm thanh của nó.
- **Máy bị điều khiển ở cục bộ** (monitor/chân máy thật) **không nhìn thấy** cửa sổ ứng dụng đó.

Nguyên lý chung: cửa sổ ứng dụng phải được vẽ lên **một nơi khác** thay vì màn hình vật lý của máy bị điều khiển. Có 3 nơi phổ biến:

| Cách | Cửa sổ được vẽ ở đâu | Ai thấy |
|---|---|---|
| **A. RDP ngắt kết nối** | Desktop của một session RDP đang bị ngắt kết nối | Chỉ máy điều khiển (khi kết nối lại) |
| **B. Màn hình ảo (VDD) + Sunshine/Moonlight** | Một "màn hình giả" do driver tạo ra | Chỉ máy điều khiển |
| **C. Dummy plug (EDID) + Parsec/AnyDesk** | Màn hình giả do thiết bị dummy plug tạo | Chỉ máy điều khiển |

---

## 2. Phương án A — RDP built-in (dễ nhất, không cần cài thêm phần mềm, âm thanh đi kèm)

### Nguyên lý
Khi bạn kết nối qua RDP, ứng dụng chạy trong một **session RDP riêng**. Nếu bạn **ngắt kết nối (disconnect) mà không đăng xuất (log off)**, session vẫn sống, cửa sổ vẫn chạy, nhưng desktop của session RDP **không được vẽ lên màn hình vật lý** của máy bị điều khiển. Máy cục bộ vẫn thấy desktop của session console bình thường. Khi bạn kết nối lại, cửa sổ hiện ra như chưa từng ngắt.

### Bước 1: Bật Remote Desktop trên máy bị điều khiển
**Settings → System → Remote Desktop → Enable Remote Desktop**
Hoặc PowerShell (admin):

```powershell
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
```

### Bước 2: Kết nối và chạy ứng dụng
- Máy điều khiển: mở **Remote Desktop Connection (mstsc)** → nhập IP máy bị điều khiển → Connect.
- Trong session, mở ứng dụng bạn muốn (cửa sổ hiện ra chỉ ở đây).

### Bước 3: Ngắt kết nối (chính xác hành động làm cửa sổ "biến mất" ở máy cục bộ)
- Ở đầu cửa sổ RDP, bấm **X (Disconnect)** — **không bấm** "Log off". Hoặc Alt+F4 trong một số client → chọn Disconnect.
- Session RDP vẫn chạy, ứng dụng vẫn chạy, nhưng **màn hình máy bị điều khiển không hiển thị cửa sổ đó** (máy cục bộ vẫn thấy desktop/console của nó).

### Bước 4: Kết nối lại để thấy cửa sổ
Mở mstsc lại → Connect → cửa sổ ứng dụng hiện ra nguyên vẹn.

### Bước 5: Cài đặt âm thanh
**Trên máy điều khiển (client):**
- mstsc → **Show Options → Local Resources → Remote audio → Settings** → chọn **"Play on this computer"**.
- (Nếu cần micrô: chọn "Record from this computer").

**Trên máy bị điều khiển (server), nếu không nghe được:**
- Kiểm tra dịch vụ: `services.msc` → **Windows Audio** và **Windows Audio Endpoint Builder** = Automatic, đã Start.
- Group Policy (gpedit.msc, Home edition không có):
  `Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Session Host → Device and Resource Redirection`
  → bật **"Allow audio and video playback redirection"** = Enabled.
- Hoặc registry (admin PowerShell):

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name fDisableAudioCapture -Value 0
```

- RDP client ghi nhớ vào file `.rdp`: dòng `audiomode:i:0` = phát âm thanh về máy client.

### Lưu ý quan trọng
- **Không đóng/ngắt bằng "Log off"** — sẽ giết ứng dụng.
- Session ngắt kết nối có giới hạn thời gian ngắt (GPO "Set time limit for disconnected sessions", mặc định khá dài). Cần thiết lập:

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name MaxDisconnectedTime -Value 0
```
(0 = không giới hạn; giá trị phút nếu muốn giới hạn)

- Nếu muốn **màn hình máy bị điều khiển lúc ngắt kết nối không thấy gì cả** (chỉ màn hình khóa), hãy **khóa session console cục bộ** (Win+L trên bàn phím máy cục bộ) hoặc bật screensaver yêu cầu mật khẩu. Session RDP vẫn chạy bình thường phía sau.

### Ưu / nhược
- ✅ Miễn phí, built-in, âm thanh + cắt/dán sẵn
- ✅ Cửa sổ "vô hình" ở máy cục bộ ngay sau khi ngắt kết nối
- ❌ Độ trễ cao hơn streaming (giải pháp B/C), giao thức RDP
- ❌ Chỉ dùng được khi máy bị điều khiển có sẵn tính năng RDP (Pro/Enterprise; Home không dùng được làm server)

---

## 3. Phương án B — Màn hình ảo (Virtual Display Driver) + Sunshine/Moonlight (tốt nhất, độ trễ thấp, âm thanh chuẩn)

### Nguyên lý
- **Virtual Display Driver (VDD)** — driver mã nguồn mở cài thêm một "màn hình giả" vào Windows (hiện tên **"VDD by MTT"** trong Display Settings).
- Bạn kéo cửa sổ ứng dụng sang màn hình giả → **máy bị điều khiển (màn hình vật lý) không thấy cửa sổ**.
- **Sunshine** (server, chạy trên máy bị điều khiển) capture màn hình giả và gửi video + âm thanh.
- **Moonlight** (client, chạy trên máy điều khiển) nhận stream, nhìn thấy cửa sổ và nghe âm thanh.

### Bước 1: Cài Virtual Display Driver trên máy bị điều khiển
```powershell
winget install --id=VirtualDrivers.Virtual-Display-Driver -e
```
(hoặc tải installer từ releases của repo `github.com/VirtualDrivers/Virtual-Display-Driver`, chạy Virtual Driver Control → Install; cần cài Microsoft Visual C++ Redistributable mới nhất)

Sau cài: **Settings → System → Display** thấy thêm 1 màn hình "VDD by MTT". Có thể chỉnh độ phân giải trong `C:\VirtualDisplayDriver\vdd_settings.xml`.

### Bước 2: Đưa cửa sổ ứng dụng lên màn hình ảo
- Kéo title bar cửa sổ và thả sang màn hình "VDD by MTT", hoặc dùng **Win+P → Chỉ màn hình 2**, hoặc Settings → Display chọn "Extend these displays".
- Kết quả: cửa sổ hiện trên màn hình giả — **máy cục bộ không thấy**.

### Bước 3: Cài Sunshine trên máy bị điều khiển
- Tải Sunshine (Windows installer) từ lizardbyte.dev, cài và khởi động.
- Mở web UI: `https://localhost:47990` (tạo account/PIN).

### Bước 4: Cấu hình Sunshine bắt màn hình ảo
- Configuration → **Audio / Video** tab → tìm **Display Device ID** (mặc định ghi chú; nếu không thấy, vào **Troubleshooting → Logs**, tìm GUID của màn hình "VDD by MTT", ví dụ `{9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}`).
- Mở **Advanced Display Device Options** → Device Configuration chọn **"Deactivate other displays and activate only the specified display"**.
  → Khi bắt stream, Sunshine tự tắt màn hình vật lý và chỉ stream màn hình ảo; khi ngừng stream, phục hồi lại.

### Bước 5: Cài Moonlight trên máy điều khiển
- Cài **Moonlight** (máy tính/điện thoại/TV). Pairing: nhập PIN/mã từ web UI Sunshine.
- Khi kết nối, bạn thấy toàn màn hình ảo = cửa sổ ứng dụng.
- Âm thanh: bật **Audio** trong Moonlight (Sunshine stream audio của máy chủ đi kèm, dùng Opus).

### Bước 6: Kiểm tra âm thanh
- Trên máy bị điều khiển: **Settings → System → Sound**, thiết bị phát mặc định đang hoạt động (Windows Audio service chạy).
- Nếu không nghe được: kiểm tra Windows Audio trong `services.msc`, kill/restart Sunshine service.

### Variant — Apollo (dễ hơn, virtual display built-in)
**Apollo** (fork của Sunshine, `github.com/ClassicOldSong/Apollo`) — **Windows chỉ**, virtual display kèm sẵn:
- Cài Apollo + client **Artemis** (hoặc Moonlight).
- Khi client kết nối, Apollo **tự tạo màn hình ảo** (không cần config GUID thủ công), tự tắt màn hình vật lý, tự khớp độ phân giải/HDR theo client. Âm thanh đi kèm.

### Ưu / nhược
- ✅ Độ trễ thấp nhất (phù hợp cả chơi game), âm thanh Opus rõ, ổn định
- ✅ Cửa sổ trên màn hình ảo = máy cục bộ chắc chắn không thấy
- ✅ Tương thích nhiều client (máy tính, điện thoại, TV)
- ❌ Cần cài driver (xác thực giá trị mã nguồn mở, cần admin)
- ❌ Sunshine vanilla cần config Display Device ID thủ công; Apollo thì dễ hơn nhiều

---

## 4. Phương án C — Dummy plug (EDID emulator) + Parsec / AnyDesk

### Nguyên lý
- **HDMI/DisplayPort dummy plug** (thuốc giả màn hình, EDID emulator, vài chục nghìn đồng) cắm vào cổng GPU → Windows/GPU nghĩ có monitor → GPU vẫn render.
- Màn hình dummy trở thành **màn hình 2**; kéo cửa sổ ứng dụng lên màn hình 2 → màn hình vật lý không thấy.
- Dùng **Parsec** hoặc **AnyDesk** stream màn hình dummy đi.

### Cài Parsec (chỉ client bên máy điều khiển thấy cửa sổ)
- Cài Parsec trên máy bị điều khiển (host) + máy điều khiển (client).
- **Parsec Warp / Parsec for Teams** có **Virtual Display Driver** riêng — không cần dummy plug (trả phí).
- Nếu dùng dummy plug: cắm dummy, kéo cửa sổ lên màn hình dummy, host Parsec chọn stream màn hình đó.
- Âm thanh: Parsec stream thiết bị phát mặc định của host (Opus 48kHz stereo). Đặt dummy plug (hoặc một virtual audio device) làm default playback nếu muốn âm thanh "chỉ có ở client, không ở máy cục bộ".

### Cài AnyDesk / TeamViewer
- Chỉ stream desktop vật lý/màn hình theo lựa chọn; nếu dùng VDD hoặc dummy plug, chọn màn hình ảo/dummy trong giao diện (AnyDesk cho phép chọn display).
- Âm thanh: AnyDesk có stream audio (cài đặt Audio settings); TeamViewer cũng hỗ trợ.

### Ưu / nhược
- ✅ Dummy plug là giải pháp cứng, ổn định với mọi ứng dụng (có ứng dụng đời cũ không chạy trên màn hình ảo được thì dùng dummy plug)
- ✅ Parsec/AnyDesk dễ dùng, có account và NAT traversal tốt
- ❌ Parsec tính phí cho virtual display (Warp/Teams); dummy plug cần mua
- ❌ Độ trễ cao hơn Sunshine/Moonlight ở cùng mạng

---

## 5. So sánh nhanh

| Phương án | Máy cục bộ thấy cửa sổ? | Âm thanh | Độ trễ | Khó khăn |
|---|---|---|---|---|
| **A. RDP ngắt kết nối** | Không (session ngắt không render) | RDP audio redirection | Cao | Rất dễ |
| **B. VDD + Sunshine/Moonlight** | Không (màn hình ảo) | Opus stream | Thấp | Trung bình |
| **B'. Apollo + Artemis** | Không | Có | Thấp | Dễ |
| **C. Dummy plug + Parsec** | Không (màn hình dummy) | Có | Trung bình | Dễ |
| **C'. Dummy plug + AnyDesk** | Không | Có | Trung bình | Rất dễ |

**Khuyến nghị:**
- Máy điều khiển là PC, cần mượt mà, âm thanh tốt → **Phương án B (VDD + Sunshine/Moonlight)** hoặc **Apollo**.
- Không muốn cài driver/dễ nhất → **Phương án A (RDP)**.
- Ứng dụng cũ kỉ không chạy trên màn hình ảo → **Phương án C (dummy plug)**.

---

## 6. Bảo mật (rất quan trọng)

- **Không mở RDP/Sunshine/Parsec trực tiếp ra Internet công cộng.** Gunakan VPN (Tailscale/ZeroTier) hoặc mapping cổng có firewall, authentication mạnh.
-  máy bị điều khiển nên bật **màn hình khóa** (Win+L) hoặc screensaver mật khẩu khi không có người cục bộ.
- Không dùng account admin cho session RDP thường; dùng account thông thường + elevate khi cần.
- Tắt RDP ngay khi không dùng; Sunshine/Parsec chỉ bật khi cần stream.
- Cập nhật driver VDD/Sunshine thường xuyên (driver không ổn định trên một số build Windows).

## 7. Xử lý sự cố

- **Sunshine không thấy màn hình ảo:** Kiểm tra Device Manager → Display Adapters có "VDD by MTT"; lấy GUID từ Sunshine Troubleshooting logs; đảm bảo cài VC++ Redistributable; restart Sunshine service.
- **Không nghe thấy âm thanh:** Kiểm tra Windows Audio service (services.msc); thiết bị phát mặc định trên máy bị điều khiển; bật Audio trong Moonlight/client; kiểm tra gpedit "Allow audio and video playback redirection" (RDP).
- **Cửa sổ ứng dụng không chạy được trên màn hình ảo:** Một số ứng dụng (game cũ, DRM) chỉ render trên monitor vật lý → dùng dummy plug thay thế VDD.
- **Session RDP bị giết sau khi ngắt:** Kiểm tra GPO "Set time limit for disconnected sessions" = Not Configured hoặc Never; hoặc set MaxDisconnectedTime = 0.
- **Nghịch địa:** Nếu muốn máy cục bộ **cũng thấy** cửa sổ (shadowing), dùng `tscon <sessionID> /dest:console` — nhưng đó là hướng ngược lại, không áp dụng cho bài toán này.

## 8. Tóm tắt quy trình nhanh

**Recommended (Sunshine/Moonlight):**
1. Máy bị điều khiển: `winget install VirtualDrivers.Virtual-Display-Driver` → kéo cửa sổ lên màn hình "VDD by MTT".
2. Cài Sunshine → web UI → Audio/Video → Display Device ID = GUID của màn hình ảo → "Deactivate other displays...".
3. Máy điều khiển: cài Moonlight → pairing → kết nối → thấy cửa sổ + nghe âm thanh.

**Nghhệ thuật nhanh (RDP):**
1. Bật Remote Desktop trên máy bị điều khiển.
2. Kết nối RDP → mở ứng dụng → **Disconnect (X)**, không Log off.
3. Kết nối lại → thấy cửa sổ + âm thanh (đã cấu hình "Play on this computer").
