# SPEC v3.1 — Remote Desktop qua trình duyệt: HVNC + VNC, window picker, âm thanh server-side, **trải nghiệm điều khiển đầy đủ**

- Phiên bản: **v3.1** (v3.0 + **chốt ngôn ngữ/kiến trúc đa tầng**, mạng LAN→VPN, audio hỏi mỗi phiên, stealth đầy đủ)
- Trạng thái: **Đề xuất — CHƯA implement, chờ duyệt**
- Nền tảng: Server **Windows 10 2004+ / Windows 11** · Client **trình duyệt** (không app)

---

## 0. Lịch sử & những gì v3.0 sửa

| Ver | Nội dung |
|---|---|
| v1.0 | WebRTC P2P, HVNC bằng màn hình ảo, 1 phiên, audio loopback, SendInput |
| v2.0 | window picker · dual-mode HVNC/VNC · audio toggle · feature tiers · edge cases |
| v2.1 | sửa lỗi capture/DPI/audio-safety/2 kênh input · state machine · test matrix |
| v3.0 | **chương §6 "Trải nghiệm điều khiển"** + 20 lỗ hổng dưới đây |
| **v3.1** | **§16 kiến trúc đa ngôn ngữ (Rust+C+JS+Python)** · §13 LAN→Tailscale/ZeroTier · §10.3 audio "hỏi mỗi phiên" · elevated tuỳ chọn khi cài · **§14 stealth đầy đủ (ẩn taskbar/Alt+Tab/thumbnail)** · §19 chốt quyết định |

### 0.1 v3.0 sửa gì — danh sách "còn thiếu" (đây là lý do v2.1 chưa đủ)

| # | Lỗ hổng ở v2.1 | Hệ quả thực tế | v3.0 |
|---|---|---|---|
| 1 | Con trỏ: nói "HVNC client vẽ cursor, VNC để trong frame" — nhưng **DDAPI không đưa cursor vào frame**, phải composite; chưa có kênh cursor shape | Client thấy **2 con trỏ** hoặc **không thấy con trỏ**, hoặc con trỏ trễ theo video = cảm giác "lag" ngay từ giây đầu | §6.3 |
| 2 | Không có cơ chế **reset input** | Giữ Ctrl rồi alt-tab ra → Ctrl **kẹt vĩnh viễn** trên máy thật; đang kéo chuột mà mất focus → **nút chuột kẹt**, người dùng máy thật không click được gì | §6.5.4, §7.5 |
| 3 | Không có ngữ nghĩa **hover** | Tooltip không hiện, menu không highlight, dropdown không mở — "không giống dùng thật" | §6.4.3 |
| 4 | Không xử lý **shortcut của chính browser** | Bấm Ctrl+W → **đóng tab, mất phiên**; Ctrl+T mở tab mới; F11 loạn fullscreen | §6.5.3 |
| 5 | Không có **pointer lock** | Không chơi được game/không xoay được mô hình 3D/không kéo được thanh trượt vô hạn | §6.4.6 |
| 6 | Mobile chỉ ghi "touch → chuột" | Trên điện thoại **không thể** bấm chính xác nút nhỏ, không hover, không gõ tổ hợp phím | §6.7 |
| 7 | Không nói **hành vi khi app tự ẩn con trỏ** | Game ẩn cursor → client vẫn vẽ con trỏ → sai | §6.3.5 |
| 8 | Đổi cửa sổ giữa phiên = **phải đóng/mở lại** | Chuyển giữa 2 cửa sổ mất 5–8 s, màn hình đen, rất khó chịu | §6.9 |
| 9 | Màn hình ảo tạo/xoá **mỗi phiên** | Mỗi lần tạo display, Windows **reflow toàn bộ desktop** → icon/cửa sổ của người dùng nhảy loạn | §12.2 |
| 10 | Không xét việc người dùng **kéo cửa sổ vào vùng vô hình** | Cửa sổ biến mất khỏi màn hình thật, người dùng tưởng app crash, **không lấy lại được** | §12.3 |
| 11 | Không xét **rò rỉ hiển thị** | Taskbar hover hiện **thumbnail nội dung** cửa sổ "vô hình"; Alt+Tab, Task View cũng lộ | §14.2 |
| 12 | Reload tab = mất phiên (dù còn grace 30 s) | F5 nhầm → mất 30 s làm việc | §6.11 |
| 13 | Không có đo **độ trễ thật** (glass-to-glass) | Không biết "mượt" hay không một cách khách quan; tối ưu mò | §6.2 |
| 14 | Không phát hiện **có người đang dùng máy** | Hai người cùng điều khiển 1 con trỏ, input đánh nhau, không ai hiểu chuyện gì | §6.8.5 |
| 15 | Chất lượng chỉ adaptive tự động | Người dùng không tự chọn "ưu tiên nét" hay "ưu tiên mượt" | §6.10 |
| 16 | Chỉ có letterbox, không có **fit/fill/zoom local** | Màn hình nhỏ (điện thoại) không đọc được chữ | §6.10.3 |
| 17 | `idle_timeout` = "không input" | Người **chỉ ngồi xem** bị đá ra sau 10 phút | §6.11.3 |
| 18 | Khi move cửa sổ qua màn hình khác DPI | App nhận `WM_DPICHANGED` → **tự resize**, rect lệch, click sai | §9.2.1 |
| 19 | Không có "thoát khẩn cấp" | Không có cách nhanh để ngừng điều khiển khi cần | §6.8.6 |
| 20 | Không có tiêu chí "cảm giác dùng được" | Không biết khi nào coi là xong | §17.3 |

---

## 1. Tóm tắt

Điều khiển máy Windows **từ trình duyệt**, không cần cài gì phía client:

1. **Window picker** — chọn 1 cửa sổ đang mở để điều khiển (có thumbnail, tìm kiếm, cảnh báo app admin).
2. **Hai mode:** **HVNC** (cửa sổ lên màn hình ảo → người ngồi máy không thấy, không nghe) và **VNC** (stream desktop thật).
3. **Âm thanh bật/tắt phía server**, per-app routing, im lặng cục bộ ở HVNC.
4. **Trải nghiệm điều khiển đầy đủ** (§6): con trỏ 0 độ trễ có hình dạng đúng, hover/drag/double-click/scroll/wheel ngang, bàn phím đầy đủ có reset modifier, IME tiếng Việt, touch 2 chế độ + kính lúp, chuyển cửa sổ giữa phiên, chọn chất lượng, resume sau reload.
5. **Mã hoá toàn tuyến:** HTTPS/WSS (TLS 1.3) + **DTLS-SRTP** media + **DTLS-SCTP** input.

---

## 2. Ngữ cảnh & ràng buộc

### 2.1 Bắt buộc
- Client: browser hiện đại trong **secure context (HTTPS)** — WebRTC/DataChannel/audio đều cần.
- Server: Win10 2004+ / Win11, **user đăng nhập tương tác**.
- Server chạy **tray app trong user session**, không phải Windows Service (§2.3).

### 2.2 Ma trận Windows
| Thành phần | Tối thiểu | Ghi chú |
|---|---|---|
| Desktop Duplication API | Win8+ | có sẵn |
| Windows.Graphics.Capture | Win10 1803+ (monitor 1903+) | fallback |
| `IsBorderRequired=false` (bỏ viền vàng WGC) | Win11 / 2022 | Win10 không tránh được |
| `WDA_EXCLUDEFROMCAPTURE` | Win10 2004+ | để *phát hiện* app chặn capture |
| Per-app audio output | Win10 1803+ | Level 2 audio |
| `ITaskbarList.DeleteTab` | Win95+ (shell) | ẩn taskbar button (§14.2) |
| VDD (IddCx) | Win10 2004+ | cần cài driver |
| `navigator.keyboard.lock` (client) | Chrome/Edge 96+ | không có trên Safari/Firefox |
| Pointer Lock (client) | mọi browser | cần user gesture |
| ARM64 | có | không NVENC/QSV → x264 |

### 2.3 Không được là Windows Service
Desktop Duplication, `SendInput`, clipboard, WASAPI loopback đều gắn với desktop của **user session**; process ở **Session 0** không capture và không inject được.
⇒ tray app chạy dưới user (Task Scheduler "At log on").
⇒ **Hệ quả:** không điều khiển được **màn hình login / lock screen / UAC secure desktop**. Muốn có → phải thêm service SYSTEM + Winlogon desktop → **Tier 3, mặc định KHÔNG làm**.

### 2.4 Giả định & đạo đức (đã chốt: **stealth đầy đủ, có thông báo**)
Bạn chọn: **ẩn cả taskbar button, Alt+Tab, thumbnail**. Spec hỗ trợ đầy đủ, nhưng giữ **một** thứ không tắt được — xem §2.4.2.

#### 2.4.1 Mức che giấu (3 cấp, cấu hình được)
| Cấp | Tên | Làm gì | Mặc định |
|---|---|---|---|
| **S0** | `content` | Cửa sổ ở màn hình ảo + audio route cable. Taskbar/Alt+Tab vẫn thấy. | — |
| **S1** | `hidden` | S0 + `ITaskbarList.DeleteTab` (mất taskbar button + thumbnail hover) | ✅ **mặc định khi bật HVNC** |
| **S2** | `deep` | S1 + loại khỏi Alt+Tab/Task View theo cách an toàn nhất có thể (§14.3) + ẩn khỏi `Win+number` | opt-in |

#### 2.4.2 Thông báo — **không tắt được**
- Khi bắt đầu phiên: **toast** hệ thống 1 lần ("Cửa sổ X đang được điều khiển từ xa") + **icon tray đổi màu/khác** trong suốt phiên + tooltip tray ghi rõ ai/ở đâu.
- Khi kết thúc: toast 1 lần.
- Lý do giữ lại dù bạn muốn stealth: (a) nếu cửa sổ "biến mất" mà người dùng máy không biết vì sao, họ sẽ **kill process / khởi động lại máy** → phiên chết và khó debug; (b) đây là ranh giới giữa "công cụ hỗ trợ từ xa" và "RAT" — vượt qua ranh giới đó biến dự án thành malware, kéo theo rủi ro pháp lý và bị AV/EDR gắn cờ (VDD + SetWindowDisplayAffinity + ẩn taskbar + input injection là **đúng bộ signature** mà Defender/EDR săn).
- **Toàn bộ phần ẩn khác đều bật/tắt được**; chỉ 2 dòng toast + icon tray là cố định. Tôi ghi rõ ở đây để bạn quyết định trước khi code, không phải phát hiện giữa đường.
- Nếu bối cảnh là **máy của chính bạn, truy cập từ xa** (§2.5) → toast không làm phiền ai. Nếu bối cảnh là máy của người khác → bạn cần sự đồng ý của họ, và điều đó hợp pháp hơn là ẩn hoàn toàn.

#### 2.4.3 Hệ quả kỹ thuật của S1/S2 (đã có trong §14)
- Ẩn taskbar ⇒ mất luôn **thumbnail hover** ⇒ hết lộ nội dung (§14.2).
- Ẩn Alt+Tab ⇒ **không thể** làm sạch 100% mà không hook (xem §14.3): chọn cách "ít xâm lấn nhất" là `WS_EX_TOOLWINDOW` + `DeleteTab`, chấp nhận một số app (Electron/Chromium) tự thêm lại → phải retry định kỳ.
- **Không** dùng hook toàn cục (`SetWindowsHookEx`/API hooking) — đó là kỹ thuật malware, bị AV chặn, và không cần thiết cho mục tiêu "không thấy nội dung".

### 2.5 Bối cảnh sử dụng (cần xác nhận — ảnh hưởng legal/AV)
Spec giả định: **bạn điều khiển máy của chính bạn** (hoặc máy trong tổ chức của bạn, có sự cho phép) từ xa. Nếu là máy của người khác → phải có sự đồng ý rõ ràng; một số tính năng (S2 + elevated) có thể bị coi là công cụ xâm nhập.

---

## 3. Tính năng theo tier

### Tier 1 — CORE
| Nhóm | Nội dung |
|---|---|
| Auth | argon2id · JWT RS256 (access 15′ + refresh rotate) · lockout |
| Picker | danh sách cửa sổ · thumbnail · tìm kiếm · badge `minimized`/`elevated` |
| Mode | HVNC · VNC |
| Video | H.264 (NVENC→QSV→AMF→x264) · 1080p60 · adaptive · PLI |
| Audio | Opus 48 k · per-app routing · **toggle server-side** · im lặng cục bộ |
| **Điều khiển** | **§6 đầy đủ**: cursor shape, hover, drag, dbl-click, wheel V/H, keyboard lock, pointer lock, reset modifier, IME, touch 2 mode + kính lúp, ripple, chuyển cửa sổ trong phiên |
| Session | 1 phiên · reconnect + ICE restart · resume sau reload · view-only · stats · quality selector |
| Security | HTTPS/WSS · DTLS-SRTP/SCTP · CSP/CORS · audit |

### Tier 2 — FULL
clipboard có nút bấm · multi-session (≤3) · multi-user + TOTP · role · allowlist app · force-close · resolution/fps per phiên · chọn thiết bị audio · đồng bộ layout bàn phím · handover phiên · zoom local · audit export

### Tier 3 — OPTIONAL
file transfer · recording · whiteboard · chat · TURN · multi-display · WoL · reboot · auto-update · login-screen control · printing · voice chat · pressure/stylus · "text mode" cho mạng yếu

### Không làm
SFU/broadcast · app native · HDR streaming · VP9/AV1 · SSO/LDAP · cloud relay · hidden desktop `WinSta0\HVNC` (§15)

---

## 4. Kiến trúc

```
┌──────────────────────────┐  HTTPS/WSS 443 (TLS1.3) signaling      ┌────────────────────────────────────────┐
│ CLIENT — trình duyệt     │ ◄──────────────────────────────────────►│ SERVER — tray app trong user session  │
│ · login / picker / UI    │  UDP: DTLS-SRTP (video/audio)          │ web  auth  session  window-picker      │
│ · RTCPeerConnection      │ ◄═════════════════════════════════════►│ display-manager  capture  encoder      │
│   video/audio recvonly   │  SCTP: DTLS (move + ctrl)              │ audio  input  webrtc  clipboard  audit │
│ · cursor layer (§6.3)    │ ◄─────────────────────────────────────►│                                        │
│ · input capture (§6.4-7) │                                        │   ▼        ▼        ▼        ▼        │
│ · ripple / loupe / hud   │                                        │  VDD    GPU enc  VB-Audio  cursor API  │
└──────────────────────────┘                                        └────────────────────────────────────────┘
```

### 4.1 Thành phần server
| Thành phần | Trách nhiệm | Tier |
|---|---|---|
| `web` | static UI · REST · WSS signaling · health | 1 |
| `auth` | argon2id · JWT · TOTP · role | 1 (2) |
| `window-picker` | EnumWindows → danh sách + thumbnail (§5.4) | 1 |
| `display-manager` | màn hình ảo · move/restore cửa sổ · **window rescue** (§12.3) | 1 |
| `capture` | DDAPI/WGC/BitBlt + recovery (§5.5) + **cursor metadata** (§6.3) | 1 |
| `encoder` | H.264 HW/SW · bitrate · PLI · preset quality (§6.10) | 1 |
| `audio` | routing · WASAPI loopback · Opus · toggle · restore (§5.11) | 1 |
| `input` | 2 datachannel → SendInput · **input state machine** (§7.5) | 1 |
| `cursor` | shape cache + phát shape/pos cho client (§6.3) | 1 |
| `webrtc` | SDP/ICE/DTLS · 2 channel · stats | 1 |
| `session` | state machine · timeout · permission · resume · switch window | 1 |
| `presence` | `GetLastInputInfo` → phát hiện người tại máy (§6.8.5) | 1 |
| `clipboard` | explicit copy/paste (§9.9) | 2 |
| `audit` | log metadata | 1 |

### 4.2 Thành phần client
| Thành phần | Trách nhiệm |
|---|---|
| `webui` | login · picker · session · toolbar · HUD · overlay |
| `webrtc` | peer · offer/answer · ICE restart · codec fallback |
| `input` | pointer/keyboard/IME/touch → `move` + `ctrl` (§6.4–6.7) |
| `cursor` | vẽ con trỏ local + shape cache (§6.3) |
| `render` | video · letterbox/fit/fill · fullscreen · zoom local |
| `hud` | stats · ripple · warnings · latency · quality |
| `clipboard-ui` | nút Copy/Paste (T2) |

---

## 5. Quyết định kỹ thuật nền

### 5.1 Vì sao WebRTC
| | WebRTC (chọn) | noVNC/Guacamole | RustDesk-style |
|---|---|---|---|
| Mã hoá | DTLS-SRTP bắt buộc | WSS tự xử lý | tự xử lý |
| Trễ | thấp (UDP, FEC/NACK) | cao (TCP HOL) | thấp |
| Client | chỉ browser | JS phức tạp | cần app |

### 5.2 HVNC — "vô hình" nghĩa là gì
- Cửa sổ **move sang màn hình ảo (VDD)** — display thật ở tầng OS nhưng **không nối output vật lý** ⇒ pixel không ra cổng HDMI/DP.
- **Không dùng** hidden desktop (`CreateDesktop` / `WinSta0\HVNC`): phải spawn lại app, mất state, giống malware. VDD giữ nguyên process & state ⇒ đúng yêu cầu.
- Audio app → thiết bị render ảo ⇒ loa thật im; server capture loopback thiết bị ảo.
- **Chỉ đổi vị trí cửa sổ + route audio của app đó**, không đổi setting hệ thống.

### 5.3 VNC — "bình thường"
Capture monitor vật lý (hoặc toàn virtual desktop). Input vào console session. Audio loopback default device ⇒ người trước máy **vẫn nghe**.

### 5.4 Window picker
```
EnumWindows(hwnd):
  loại nếu !IsWindowVisible
  loại nếu GetWindow(hwnd, GW_OWNER) != NULL          // owned popup (xem ghi chú dưới)
  loại nếu style & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)
  loại nếu class ∈ {Progman, WorkerW, Shell_TrayWnd, Windows.UI.Core.CoreWindow(shell)}
  loại nếu DwmGetWindowAttribute(DWMWA_CLOAKED) != 0  // UWP suspended / desktop ảo khác
  loại nếu DWMWA_EXTENDED_FRAME_BOUNDS rỗng
  loại nếu PID == server PID
  loại nếu ProcessIdToSessionId(pid) != session của server
  → {wid(hwnd i64), title, app(exe), pid, rect=EXTENDED_FRAME_BOUNDS,
     minimized=IsIconic, display=physical|virtual, elevated, thumb}
```
- **KHÔNG dùng `GetWindowRect`** — dính viền vô hình của DWM/UWP (lệch 7–8 px mỗi cạnh ở Win10) ⇒ click sai mép.
- Owned popup bị loại khỏi danh sách, nhưng **vẫn được capture** vì capture theo *display* chứ không theo hwnd — đây là lý do dialog/menu hiện đúng trong stream (§14.1).
- Thumbnail: `PrintWindow(PW_RENDERFULLCONTENT)` 160 px JPEG q60, cache 5 s; app dùng DirectComposition/GPU → thumbnail đen ⇒ hiện icon + tên (chấp nhận).
- Icon: `SHGetFileInfo` theo exe.
- Cache danh sách 3 s; loại cửa sổ đang được phiên khác stream (`409`).

### 5.5 Capture — ma trận

#### 5.5.1 Chọn nguồn
| Tình huống | Nguồn |
|---|---|
| HVNC | **DDAPI trên monitor ảo** |
| VNC | **DDAPI trên monitor vật lý** |
| `ACCESS_LOST`/`UNSUPPORTED` | re-init DDAPI (≤3 lần/10 s) → **WGC** |
| Game exclusive / DirectComposition | **WGC monitor** (hoặc WGC window nếu cần) |
| Win10 <1803 / trong RDP | **BitBlt** (chậm) |
| Stream 1 cửa sổ không move (T3) | **WGC window item** + `IsBorderRequired=false` |

#### 5.5.2 Lỗi đã biết
| Lỗi | Nguyên nhân | Xử lý |
|---|---|---|
| `DXGI_ERROR_ACCESS_LOST` | đổi display/lock/UAC/resolution | recreate duplication (bắt buộc); `frame_freeze` nếu >1 s |
| Frame đen sau move | DWM chưa composite | `DWMWA_TRANSITIONS_FORCEDISABLED` + chờ 300–1500 ms |
| Đen vĩnh viễn 1 app | app đặt `WDA_EXCLUDEFROMCAPTURE` | `GetWindowDisplayAffinity` → `412 capture_blocked` |
| Đen với DRM (Netflix/Widevine/PlayReady) | HDCP | **không vượt được**; black ≥2 s → `drm_black` |
| Màu bạc | HDR bật | tonemap PQ→SDR **hoặc** ép duplication SDR; có HDR thì **bắt buộc** xử lý |
| Tụt fps nhiều màn hình | cross-adapter copy | capture+encode cùng adapter; khác GPU → shared surface |
| 60 Hz nhưng chỉ 30 fps | `AcquireNextFrame` timeout 16 ms | timeout = 2× frame interval |
| Nhiều phiên cùng monitor | mỗi phiên 1 duplication | share duplication + fan-out (T2) |

#### 5.5.3 Quy trình move cửa sổ (sai thứ tự = hỏng)
```
1  lưu state gốc: monitor, rect, maximized, style, dpi
2  nếu IsIconic  → ShowWindow(SW_RESTORE); chờ 100 ms
3  nếu IsZoomed  → ShowWindow(SW_RESTORE)          // KHÔNG SetWindowPos khi maximized
4  DwmSetWindowAttribute(DWMWA_TRANSITIONS_FORCEDISABLED)
5  SetWindowPos(hwnd, HWND_TOP, x_ảo, y_ảo, w, h, SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED)
     · rect không khớp → thử SWP_NOSENDCHANGING
     · vẫn sai → thử lại 2 lần → 412 window_immovable
6  nếu vốn maximized → ShowWindow(SW_MAXIMIZE)      // maximize theo display ảo
7  BringWindowToTop + SetForegroundWindow (§6.5.5)
8  chờ settle 300–1500 ms hoặc frame đầu khác đen
9  bắt đầu capture
```
**Restore** = 2,3,4,5 với toạ độ gốc → trả maximized/minimized như cũ.
> ⚠️ Restore **trước khi** xoá màn hình ảo, nếu không Windows dồn cửa sổ về màn hình khác với vị trí ngẫu nhiên.

### 5.6 Codec & stream
- **H.264** High@4.2 (Baseline nếu client yếu) · **VP8** fallback · Opus.
- 1080p60 @8 Mbps LAN · 1080p30 @4 Mbps WAN · keyframe 2 s + PLI on demand.
- Adaptive: loss >5% trong 3 s → −25%; loss <1% trong 10 s → +15% (trần config).
- **Lip-sync:** video & audio **cùng một clock gốc** (cùng `GstSystemClock`; nếu tách process → chung clock + RTP timestamp offset). Sai chỗ này = lệch 200–500 ms.
- Audio: Opus 48 kHz, `useinbandfec=1`, `usedtx=1`, 24–32 kbps.

### 5.7 Kênh truyền — 2 DataChannel
| Kênh | SCTP | Nội dung |
|---|---|---|
| `move` | `ordered:false, maxRetransmits:0` | mouse move, wheel, touch move (idempotent) |
| `ctrl` | `ordered:true, reliable` | button/key down-up, text, cursor? , clipboard, resize, ack |

> `move` **không thể** đi chung kênh reliable: mất 1 gói sẽ chặn toàn bộ event phía sau (head-of-line) → chuột "dính" từng đợt. Đây là lỗi kinh điển của VNC-over-TCP.
> Client throttle `move` ≤ **120 msg/s**; server drop >200/s. `ctrl` có `seq`, server `ack` mỗi 500 ms.

### 5.8 Transport & mã hoá
| Lớp | Cơ chế |
|---|---|
| Signaling | HTTPS/WSS · TLS 1.3 (1.2 fallback) · HSTS · CSP · CORS same-origin |
| Media | **DTLS-SRTP bắt buộc**, không có đường plaintext |
| Data | **DTLS-SCTP** |
| Auth | argon2id (m=64MB,t=3,p=1) · JWT RS256 (15′ / refresh 7 ngày rotate + reuse-detect) · cookie HttpOnly+Secure+SameSite=Strict |
| Chống lạm dụng | login 5/phút/IP → lockout 15′ · WS rate limit · clipboard cap · **clamp toạ độ** |
| Cert | bắt buộc hợp lệ; khuyến nghị `tailscale cert` hoặc internal CA |

# PHẦN II — TRẢI NGHIỆM ĐIỀU KHIỂN
> Đây là chương quyết định "dùng có sướng không". Mọi thứ ở đây đều là yêu cầu, không phải "nice to have".

## 6. Trải nghiệm điều khiển

### 6.1 Năm nguyên tắc

| # | Nguyên tắc | Hệ quả thiết kế |
|---|---|---|
| 1 | **Con trỏ phải dính tay** | Con trỏ **không được** đi qua đường video (trễ 30–100 ms). Render local + đồng bộ *hình dạng*. §6.3 |
| 2 | **Không bao giờ kẹt input** | Mọi đường mất focus/đứt mạng phải dẫn tới `release_all`. Có watchdog 3 s. §6.5.4, §7.5 |
| 3 | **Luôn có đường thoát** | `Esc Esc` hoặc nút toolbar → nhả toàn bộ + về view-only trong <200 ms. §6.8.6 |
| 4 | **Suy giảm phải nhìn thấy được** | Mờ dần, banner, đổi màu khung, số liệu — không im lặng "chạy chậm". §6.8 |
| 5 | **Mặc định tốt, không bắt cấu hình** | Mở lên là dùng được; mọi thứ nâng cao ẩn sau 1 nút. §6.10.4 |

### 6.2 Ngân sách độ trễ & cách đo thật

#### 6.2.1 Đường đi của một cú click (trường hợp xấu: cursor_mode=remote)
| Chặng | LAN | WAN | Ghi chú |
|---|---|---|---|
| Browser event → datachannel send | 0.5–2 ms | 0.5–2 ms | rAF batch, latest-wins |
| Uplink | 1–3 | 10–40 | UDP |
| Server parse + `SendInput` | 0.3–1 | 0.3–1 | |
| App phản ứng + DWM composite | 8–16.7 | 8–16.7 | phụ thuộc app |
| Capture (next frame) | 0–16.7 | 0–16.7 | DDAPI có thể trễ 1 frame |
| Encode | 2–8 | 2–8 | NVENC low-latency; x264 5–15 |
| Downlink | 1–3 | 10–40 | |
| Decode + composite | 8–16.7 | 8–16.7 | |
| **Tổng** | **≈35–65 ms** | **≈70–160 ms** | |

#### 6.2.2 Vì sao con trỏ local là bắt buộc
Nếu con trỏ đi qua video, **cảm giác trễ = tổng bảng trên** (35–65 ms LAN) → người dùng thấy "lag" ngay cả khi mọi thứ khác hoàn hảo. Nếu render local: con trỏ **0 ms**, chỉ *phản ứng của app* mới trễ 35–65 ms. Đó là khác biệt giữa "dùng được" và "khó chịu" — và là lý do nguyên tắc #1.

#### 6.2.3 Đo glass-to-glass (bắt buộc có, chế độ debug)
- **Cách 1 — app-level (dùng hằng ngày):** mỗi event `ctrl` mang `client_ts`; server echo lại `acked_ts` + `inject_ts`; client tính client→server→client. Đo được *đường điều khiển*, không đo được capture/encode.
- **Cách 2 — glass-to-glass (khi tuning):** server vẽ ở góc dưới-phải một **barcode nhỏ** chứa `frame_id` + `server_ts` (chỉ bật `debug.barcode=true`). Dùng camera 240 fps quay màn hình client + màn hình server cùng lúc → đọc lệch. Sai số ±4 ms.
- **Cách 3 — kiểm tra nhanh bằng mắt:** server vẽ 1 ô vuông đổi màu mỗi 100 ms; client chụp màn hình 2 lần liên tiếp để so. Không chính xác, dùng khi không có camera.
- KPI: **input→photon p95** LAN < 80 ms; **cursor→photon** (cursor local) = 0.

### 6.3 Con trỏ (cursor) — chi tiết nhất trong toàn spec

#### 6.3.1 Sự thật kỹ thuật nền
- **DDAPI KHÔNG đưa con trỏ vào frame.** Nó trả `PointerPosition` + `PointerShape` (bitmap đơn sắc hoặc màu) trong `DXGI_OUTDUPL_FRAME_INFO`, và **chỉ khi con trỏ đổi**. Muốn có con trỏ trong video phải **tự composite** (server-side).
- **WGC** có tuỳ chọn `IncludeCursor`, mặc định có thể bật/tắt.
- ⇒ Ta **luôn** cần module `cursor` (đọc shape + pos). Việc chọn "vẽ ở server hay client" chỉ là chọn **nơi composite**.

#### 6.3.2 Ba chế độ
| Chế độ | Cách làm | Ưu | Nhược | Dùng khi |
|---|---|---|---|---|
| **`local`** | Ẩn con trỏ khỏi frame; client vẽ con trỏ tại vị trí chuột local, dùng shape nhận từ server | **0 ms**, mượt tuyệt đối | Nếu người thật di chuột thì client không thấy (phải chuyển chế độ) | HVNC, không có người dùng máy, đang điều khiển |
| **`remote`** | Server composite con trỏ vào frame | Trung thực (thấy cả con trỏ của người thật) | Trễ = trễ video | VNC mode; HVNC khi có người dùng máy |
| **`auto`** (default) | Bắt đầu `local`; chuyển `remote` khi phát hiện người tại máy hoạt động (§6.8.5) hoặc khi `view_only` | Cân bằng | Chuyển chế độ gây 1 nhịp "khựng" con trỏ (~100 ms) | Mặc định |

Quy tắc: **không bao giờ có 2 con trỏ cùng lúc.** Khi `local`, server **không** composite; khi `remote`, client **ẩn** con trỏ local. Đây là bug hay gặp nhất khi làm remote desktop.

#### 6.3.3 Kênh cursor shape
```
server → client (ctrl channel, JSON, chỉ khi đổi):
{ "t":"cshape", "h":"a1b2c3", "w":32,"h2":32,"hot":[1,1],"mono":true,
  "and":"<base64>", "xor":"<base64>" }         // mono (đa số)
{ "t":"cshape", "h":"d4e5f6", "w":48,"h2":48,"hot":[4,4],"mono":false,
  "rgba":"<base64>" }                          // màu (hiếm, có alpha)
{ "t":"cpos", "x":523,"y":311, "vis":true }    // vị trí trong không gian màn hình ảo
{ "t":"cpos", "vis":false }                    // app đang ẩn con trỏ
```
- **Hash** = xxhash(shape buffer) → client cache; server chỉ gửi shape khi hash mới. Điển hình 15–40 shape/phiên (ảnh tĩnh) ⇒ tổng <8 KB.
- **`hot`** = hotspot: phải áp đúng, nếu không click lệch 1–16 px tuỳ shape (mũi tên lệch 1 px, crosshair lệch 8 px, I-beam lệch 8 px). **Đây là lỗi rất khó phát hiện bằng mắt** — test bằng crosshair trên ảnh.
- **Scale:** shape trả theo pixel ở DPI của nguồn capture. Nếu client hiển thị scale khác (điện thoại) → scale bitmap theo `dispW/vw`; nhưng ưu tiên dùng **CSS cursor** khi shape khớp bộ chuẩn (arrow, ibeam, hand, wait, crosshair, size-*) — nét hơn ở mọi DPI; chỉ dùng bitmap cho shape lạ (app tự vẽ).
- **Tần suất:** gửi `cpos` tối đa **30 Hz** (con trỏ local đã mượt bằng chuột thật; `cpos` chỉ để đồng bộ khi `remote` hoặc khi có người thật).
- **Animation:** shape `wait`/`progress` đổi liên tục → đã bị giới hạn bởi hash cache + 30 Hz, không gây tải.

#### 6.3.4 Con trỏ khi ở ngoài vùng video
- Client ẩn con trỏ custom, trả lại con trỏ hệ thống của browser khi ra ngoài `<video>` → cảm giác "thoát khỏi màn hình remote".
- Khi ở trong: `video { cursor: none }` và vẽ overlay. Khi `local` mode nhưng chưa từng nhận `cpos` → dùng `cursor: default`.

#### 6.3.5 App tự ẩn con trỏ (game, video player, app fullscreen)
- `cpos.vis=false` → client ẩn overlay con trỏ, **kể cả** ở mode `local`.
- Không đoán; chỉ tin server. (Đây là lỗi #7 của v2.1.)

#### 6.3.6 Con trỏ khi `view_only`
- Luôn `remote` + ẩn con trỏ local + hiện nhãn "Chỉ xem". Người xem thấy con trỏ thật của người đang điều khiển.

#### 6.3.7 Kích thước & DPI
- Shape bitmap đã ở pixel của nguồn capture. Client scale theo tỉ lệ hiển thị; **không** áp scale DPI của client (nếu không con trỏ sẽ to/nhỏ vô lý trên màn hình Retina).
- Ngưỡng: nếu tỉ lệ <0.5 → chuyển sang CSS cursor (bitmap nhỏ quá sẽ nhoè).

### 6.4 Chuột — đầy đủ

#### 6.4.1 Sự kiện phải hỗ trợ
| Sự kiện | Client | Server |
|---|---|---|
| Move (hover, không bấm) | `pointermove` (kể cả không button) | `MOUSEEVENTF_MOVE` |
| Left/Right/Middle down-up | `pointerdown/up` | `MOUSEEVENTF_LEFTDOWN/UP` … |
| Nút 4/5 (back/forward) | `pointerdown` button 3/4 | `XBUTTON1/2` (`MOUSEEVENTF_XDOWN`, `mouseData`) |
| Wheel dọc | `wheel` deltaY | `MOUSEEVENTF_WHEEL` |
| Wheel ngang (shift+wheel, trackpad) | `wheel` deltaX | `MOUSEEVENTF_HWHEEL` |
| Wheel click | button 1 | `MOUSEEVENTF_MIDDLEDOWN` |
| Double / triple click | gửi down/up thật | OS tự nhận (không tự phát minh timing) |
| Drag | `pointerdown` → `pointermove` → `pointerup` + `setPointerCapture` | down, nhiều move, up |
| Text selection drag | như drag | như trên |
| Hover → tooltip / menu highlight | `pointermove` | như trên |

#### 6.4.2 Quy tắc double-click
- **Client KHÔNG tự gộp** thành "doubleclick" event. Gửi đúng chuỗi down/up/down/up với timestamp thật; OS Windows tự nhận theo `GetDoubleClickTime()` (mặc định 500 ms) + `SM_CXDOUBLECLK` (4 px).
- Nếu client thêm debounce 300 ms → double-click sẽ **không bao giờ** hoạt động. Đây là lỗi rất phổ biến.
- Ngược lại: nếu mạng mất gói làm 2 cú click cách nhau 600 ms → OS thấy 2 single click (đúng như người dùng làm, chấp nhận).

#### 6.4.3 Hover (bị bỏ quên nhiều nhất)
- Gửi `pointermove` **kể cả khi không có nút nào bấm**. Nếu chỉ gửi move khi đang drag → tooltip/menu/toolbar không bao giờ highlight, dropdown "hover to open" không mở ⇒ người dùng thấy "app không phản hồi".
- Throttle theo rAF, **latest-wins** (không queue): luôn gửi vị trí mới nhất, bỏ vị trí cũ.
- Khi dùng `pointerrawupdate` (Chrome) + `getCoalescedEvents()`: dùng để *vẽ tay* (whiteboard/oneNote) mới cần mọi điểm; còn điều khiển thì latest-wins là đúng.

#### 6.4.4 Rate & mượt
| Nguồn | Rate | Ghi chú |
|---|---|---|
| Chuột thường | 125 Hz | rAF (~60) là đủ |
| Chuột gaming | 1000 Hz | **không** gửi 1000/s; gộp trong rAF |
| Trackpad | ~90 Hz | gộp, dùng deltaY tích luỹ |
| Vẽ tay (T3) | 240 Hz | dùng coalesced + kênh riêng |

#### 6.4.5 Accel & "Enhance pointer precision"
- Chế độ **absolute** (mặc định): toạ độ tuyệt đối → OS **không** áp acceleration ⇒ con trỏ đi đúng nơi click. Đây là lý do dùng absolute.
- Chế độ **relative** (pointer lock): OS **có** áp "Enhance pointer precision" nếu user bật → đường đi cong. Giải pháp: cảnh báo trong UI "để chơi game, tắt Enhance pointer precision"; **không tự đổi setting hệ thống của user**.

#### 6.4.6 Pointer Lock — chế độ chuột tương đối (Tier 1, quan trọng)
- Bật bằng nút "Chuột tương đối (game)" hoặc tự động khi phát hiện app fullscreen.
- `video.requestPointerLock()` → nhận `movementX/Y` thô → gửi `MOUSEEVENTF_MOVE` (relative, **không** `ABSOLUTE|VIRTUALDESK`).
- Không có pointer lock: **không thể** xoay camera trong game, không kéo được slider vô hạn, không dùng được app 3D.
- Thoát: `Esc` của browser tự nhả lock → client bắt `pointerlockchange` → gửi `release_all`.
- Trên macOS Safari: pointer lock hoạt động nhưng cần gesture; iOS: không có (dùng touch mode).

#### 6.4.7 Kẹt nút chuột (edge case nghiêm trọng)
Kịch bản: đang giữ chuột trái kéo, người dùng alt-tab / mất focus / mạng đứt → `pointerup` **không bao giờ** tới server → máy thật **kẹt nút trái**, người ngồi máy không click được bất cứ thứ gì.
Xử lý 4 lớp:
1. `setPointerCapture` để vẫn nhận `pointerup` khi ra ngoài.
2. `blur` / `visibilitychange` / `pointercancel` / `lostpointercapture` → gửi `{"t":"release_all"}`.
3. `beforeunload` → `navigator.sendBeacon` tới `POST /api/sessions/{sid}/release` (không phụ thuộc WS còn sống).
4. **Server watchdog:** nếu `buttons_held != 0` và không có event nào 3 s → tự `release_all` + gửi warning `input_reset`.
> Lớp 4 là bắt buộc — không có nó, một lần mất mạng là máy thật "chết".

### 6.5 Bàn phím — đầy đủ

#### 6.5.1 Phân loại
| Loại | Cách gửi | Ví dụ |
|---|---|---|
| Ký tự in được | `KEYEVENTF_UNICODE` | `ế`, `ữ`, `€`, `😀` (surrogate pair = 4 event) |
| Tổ hợp | virtual-key + modifier | `Ctrl+C`, `Alt+Tab`, `Ctrl+Shift+S` |
| Phím chức năng/điều hướng | virtual-key | `Esc`, `F5`, `Home`, `Delete`, `Tab` |
| Numpad | `VK_NUMPAD*` | khi NumLock off → `VK_INSERT`… |
| Media/brightness (T3) | `VK_MEDIA_*`, `VK_VOLUME_*` | |

**Quy tắc vàng:** chỉ cần **ra ký tự** → **luôn** dùng Unicode. Virtual-key phụ thuộc **layout của server**; Unicode độc lập layout ⇒ tiếng Việt và mọi ngôn ngữ chạy ngay, không cần đồng bộ layout.

#### 6.5.2 Ma trận shortcut (phải test từng dòng)
| Shortcut | Trạng thái | Ghi chú |
|---|---|---|
| `Ctrl+C/V/X/Z/Y/A/S/F/P` | ✅ chuyển tiếp | `Ctrl+S` phải `preventDefault` ở client |
| `Ctrl+Shift+*` | ✅ | |
| `Alt+Tab` | ✅ | nhưng **Alt+Tab trên client** cũng đổi cửa sổ của client → phải chặn (chỉ khi keyboard lock/ fullscreen) |
| `Alt+F4` | ✅ (gửi được) | đóng app trên server — **hỏi xác nhận** ở client |
| `Win`, `Win+D`, `Win+E` | ✅ | |
| `Win+L` | ⛔ **chặn** | sẽ khoá console thật → mất phiên. Hiện toast |
| `Win+Tab` (Task View) | ✅ (nhưng **lộ** — §14.2) | |
| `F11` | ⚠️ | trùng fullscreen browser → dùng nút UI thay thế |
| `Esc` | ⚠️ | phải phân biệt: Esc để gửi, hay Esc để thoát fullscreen |
| `Ctrl+W` / `Ctrl+T` / `Ctrl+N` | ⛔ mặc định bị browser chiếm | xem §6.5.3 |
| `Ctrl+Alt+Del` | ⛔ **không thể** | SAS bị chặn từ Vista (§6.13) |
| `Ctrl+Alt+Delete` thay thế: nút "Secure attention" | T3 | cần helper service + `SendSAS` |
| `PrintScreen` | ⚠️ | `VK_SNAPSHOT` gửi được; ảnh lưu clipboard server |
| `AltGr` (chuột phải Alt) | ✅ | gửi `Ctrl+Alt` cùng lúc (Windows coi AltGr = Ctrl+Alt) |

#### 6.5.3 Keyboard Lock — sống còn
- Không có nó, **Ctrl+W đóng tab = mất phiên**, Ctrl+T mở tab mới, Ctrl+N cửa sổ mới.
- `await navigator.keyboard.lock()` — yêu cầu: **fullscreen + user gesture + Chrome/Edge 96+**.
- Bật tự động khi vào fullscreen; tắt khi thoát. Hiện nhãn "Đã khoá phím (Ctrl+W được chuyển tiếp)".
- **Safari/Firefox không hỗ trợ** → hiện cảnh báo khi người dùng bấm Ctrl+W: *"Trình duyệt này không cho phép chuyển tiếp Ctrl+W — tab sẽ đóng"*, và gợi ý dùng Chrome/Edge để có trải nghiệm đầy đủ.
- Danh sách phím khoá được: hầu hết phím trừ `Esc` (luôn dùng được để thoát) và các tổ hợp cấp OS.

#### 6.5.4 Reset modifier — bắt buộc
| Tình huống | Kết quả nếu không xử lý |
|---|---|
| Giữ `Ctrl`, alt-tab ra ngoài, nhả `Ctrl` ở máy client | Server thấy `Ctrl` **kẹt vĩnh viễn** → mọi cú click thành Ctrl+click, gõ chữ ra lệnh |
| Giữ `Shift` khi chuyển tab | Shift kẹt → chọn text ngoài ý muốn |
| `CapsLock` | Trạng thái là của server; client hiển thị trạng thái server (không đồng bộ 2 chiều) |
Xử lý: mọi `blur`/`visibilitychange`/`pointercancel`/`release_all` → client gửi `release_all`; server gửi `KEYUP` cho **mọi** phím đang giữ trong `keys_held` (server tự track) **và** thêm `Ctrl/Shift/Alt/Win` cho chắc.

#### 6.5.5 Focus — vì sao click được mà gõ không được
- **Chuột** positional: click trúng cửa sổ ở toạ độ đó **bất kể** foreground.
- **Bàn phím** đi tới **foreground window** của desktop, không phải window ta muốn. Nếu người tại máy đang gõ ở app khác → phím của ta rơi vào app đó (**nguy hiểm**).
- ⇒ Trước mỗi **burst** phím: `AttachThreadInput(GetCurrentThreadId(), GetWindowThreadProcessId(target), TRUE)` → `SetForegroundWindow(target)` → `AttachThreadInput(..., FALSE)`. Chỉ khi target chưa foreground (tránh nhấp nháy).
- Fail (Windows chặn theo policy) → warning `focus_lost` cho client, **không im lặng**.
- Nếu foreground window là **cửa sổ khác** trên màn hình ảo (vd dialog vừa mở) → **không** giành lại; dialog cần focus. Quy tắc: giành focus chỉ khi foreground **không thuộc cùng process** với target, hoặc thuộc process khác hoàn toàn.

#### 6.5.6 Key repeat
- Client **bỏ qua** `event.repeat` → chỉ gửi 1 `keydown`.
- OS server tự repeat (đúng tần số của máy đó). Nếu gửi cả repeat từ client → 2 tầng repeat = gõ nhảy cóc.
- Riêng phím Unicode (text) thì không repeat (giữ phím ra nhiều ký tự là hành vi của app, không phải của ta).

#### 6.5.7 Dead keys & compose
- Layout Âu (FR/DE): `^` + `e` → `ê`. Nếu gửi Unicode từng ký tự → mất dead key.
- Xử lý: gửi `text` theo `compositionend` (client đã compose xong) → server inject Unicode ⇒ kết quả đúng cuối cùng, không cần dead key ở server.

#### 6.5.8 Layout mismatch
- Mặc định: Unicode ⇒ không quan tâm layout.
- Với **shortcut**, VK là layout-dependent: client AZERTY gửi `VK_1` (+Shift) → server QWERTY ra `1` chứ không phải `!`. Chấp nhận (đây là hành vi của máy server).
- Tuỳ chọn T2 "đồng bộ layout": hiển thị layout server trong UI + cho phép chọn (dùng `ActivateKeyboardLayout` — **cảnh báo: đổi layout của user**, chỉ làm khi opt-in).
- Nếu user cần layout khác hoàn toàn → dùng "server-side IME" (§6.6).

### 6.6 IME & tiếng Việt

| Mode | Cơ chế | Dùng khi |
|---|---|---|
| **Client IME (default)** | Client để IME của HĐH client soạn (Telex/VNI, tiếng Nhật…); `compositionstart/update/end` → chỉ gửi **kết quả cuối** ở `compositionend` | 95%: chat, Office, browser, terminal |
| **Server IME (option)** | Client gửi phím thô; IME của server soạn; UI hiện trạng thái IME server | game có chat riêng, app chặn Unicode, remote-in-remote |
| **Không hỗ trợ** | — | app dùng Raw Input + kiểm tra scan code (một số game/anti-cheat) |

Chi tiết bắt buộc:
- **Không gửi ký tự trong lúc composition.** Người gõ Telex "tieengs" → nếu gửi từng bước sẽ ra "tieengs" rồi mới xoá; gửi ở `compositionend` chỉ ra "tiếng".
- `compositionend` có thể trả về chuỗi rỗng (khi xoá hết) → không gửi gì.
- **Backspace trong lúc compose** → không gửi (IME client xử lý).
- **Emoji / ký tự ngoài BMP**: phải gửi **4 KEYEVENTF_UNICODE event** (surrogate pair), không phải 2. Nếu không → ký tự rác.
- **Combining marks** (tiếng Việt dựng sẵn vs tổ hợp): gửi nguyên chuỗi UTF-16 như IME trả; không normalize (app có thể cần dạng cụ thể; normalize NFD sang NFC có thể làm hỏng một số app).
- **Paste/chuỗi dài** (>200 ký tự): **không** inject từng ký tự (chậm + dễ sai). Dùng đường clipboard: set clipboard server → `Ctrl+V` → **restore clipboard cũ sau 300 ms**.
- **RTL** (Ả Rập/Do Thái): Unicode injection hoạt động; con trỏ/highlight do app xử lý.
- Bàn phím ảo mobile: `<textarea>` 1×1 px opacity 0 để iOS/Android hiện bàn phím + composition tiếng Việt; **không** dùng `contenteditable` (gây scroll)。

### 6.7 Touch & mobile

#### 6.7.1 Hai chế độ (người dùng chọn, mặc định theo kích thước màn hình)
| Chế độ | Hành vi | Phù hợp |
|---|---|---|
| **Direct touch** (mặc định trên điện thoại) | Chạm đâu = click đó (absolute). Có con trỏ ảo xuất hiện khi chạm. | Duyệt web, xem ảnh, app đơn giản |
| **Trackpad** | Vuốt để di con trỏ (relative), chạm = click tại vị trí con trỏ. | App desktop phức tạp, menu nhỏ, cần độ chính xác |
| **Direct + kính lúp** | Như direct, nhưng khi **giữ ngón** → hiện kính lúp phóng to vùng dưới ngón, kéo để tinh chỉnh, nhả = click | **Mặc định đề xuất** — giải quyết vấn đề "ngón tay che mất chỗ cần bấm" |

#### 6.7.2 Bảng gesture
| Gesture | Tác dụng | Ghi chú |
|---|---|---|
| 1 tap | left click | |
| 2 tap nhanh | double click | phải gửi trong <500 ms |
| giữ 500 ms | **right click** (menu ngữ cảnh) | có haptic nếu hỗ trợ |
| giữ + kéo | drag (khoá nút trái) | hiện chỉ báo "đang kéo", nút "nhả" riêng |
| 2 ngón vuốt | scroll | delta → wheel notch |
| 2 ngón chạm | right click (thay thế) | |
| pinch | **tuỳ chọn:** zoom local (mặc định) hoặc gửi `Ctrl+wheel` (zoom trong app) | hiện toggle trong toolbar; nhãn rõ đang ở chế độ nào |
| 3 ngón vuốt | hiện/ẩn toolbar | |
| kéo 1 ngón từ mép trái | back (rời phiên, có xác nhận) | |

#### 6.7.3 Toolbar phụ trên mobile
Nút có sẵn (không cần bàn phím): `Esc` `Tab` `Enter` `←↑↓→` `Ctrl` (sticky) `Alt` (sticky) `Shift` (sticky) `Win` `F5` `Chuột trái/phải` `Bàn phím` `Kính lúp` `Chất lượng` `Thoát`.
- **Sticky modifier:** bấm `Ctrl` → sáng lên; cú gõ kế tiếp gửi kèm Ctrl rồi **tự nhả** (giống bàn phím Android). Bấm 2 lần = khoá (giữ tới khi bấm lần nữa).
- Toolbar gọn 1 hàng, tự ẩn sau 5 s không dùng, hiện lại khi chạm mép dưới.

#### 6.7.4 Các vấn đề mobile đã biết
| Vấn đề | Xử lý |
|---|---|
| Bàn phím ảo che nửa màn hình | `visualViewport` API → co vùng video + cuộn cửa sổ; toolbar dồn lên trên bàn phím |
| Mất focus textarea → bàn phím đóng ngoài ý muốn | giữ focus khi chạm video; chỉ đóng khi bấm nút "ẩn bàn phím" |
| iOS chặn fullscreen cho `<video>` | fullscreen bằng CSS trên container (`position:fixed; inset:0`) + `screen.orientation.lock` nếu có |
| Safe area (tai thỏ) | `env(safe-area-inset-*)` cho toolbar |
| Xoay máy | reflow letterbox, gửi `resize` ≤1/10 s |
| Pinch bị browser zoom trang | `touch-action: none` trên video + `meta viewport user-scalable=no` |
| Double-tap zoom của browser | `touch-action: manipulation` / none |
| Kéo từ mép = back của browser | `overscroll-behavior: none` |

### 6.8 Phản hồi & nhận biết

#### 6.8.1 Ripple (xác nhận tức thì)
- Mỗi `pointerdown` → vẽ vòng tròn nhỏ tại điểm chạm, mờ dần 300 ms. Vẽ **trước** khi gửi (không chờ server).
- Tác dụng tâm lý: người dùng biết "đã nhận", không bấm lại 2 lần.
- Tắt được (một số người thấy phiền); mặc định **bật** ở mobile, **tắt** ở desktop (chuột thật đã đủ phản hồi).

#### 6.8.2 Chỉ báo "đang bận / đóng băng"
- >500 ms không có frame mới → video giữ frame cuối + phủ nhẹ + nhãn "Đang chờ máy…" (không xoá đen).
- >3 s → hiện spinner + nút "Kết nối lại".
- Phân biệt: `frame_freeze` (máy treo) vs `network` (mạng) vs `app_closed` — thông điệp khác nhau.

#### 6.8.3 Ping/ack hiển thị
- Góc HUD: `RTT 42 ms · 8.0 Mbps · 58 fps`. Màu: xanh <100, vàng <200, đỏ >200.
- Input ack: nếu `ack` trễ >500 ms → đổi màu nhãn "input" thành vàng.

#### 6.8.4 Thông báo sự kiện server → client
`window_lost`, `window_moved_out`, `minimized`, `drm_black`, `secure_desktop`, `need_admin`, `focus_lost`, `frame_freeze`, `audio_unavailable`, `display_lost`, `input_reset`, `someone_local`, `capture_blocked`
→ map sang câu tiếng Việt cụ thể + hành động gợi ý (không phải "Error 500").

#### 6.8.5 Phát hiện "có người đang dùng máy" (bắt buộc)
- Server poll `GetLastInputInfo()` 1 s/lần. Nếu có input vật lý (chuột/phím) khác nguồn `SendInput` của ta trong 2 s → **`someone_local`**.
  - Phân biệt nguồn: `SendInput` của ta đặt cờ nội bộ `injecting=true` trong ±50 ms quanh lệnh gọi → input ngoài cửa sổ đó = người thật.
- Khi phát hiện: (a) chuyển cursor sang `remote` (thấy con trỏ thật), (b) banner vàng "Có người đang dùng máy này", (c) **không** tự ngắt — chỉ thông báo.
- Lý do: 2 người cùng điều khiển 1 con trỏ mà không ai biết là trải nghiệm tệ nhất có thể.

#### 6.8.6 Nút "Dừng điều khiển" (panic)
- `Esc Esc` (2 lần trong 600 ms) hoặc nút 🛑 trên toolbar → **ngay lập tức**: `release_all` + chuyển `view_only` + hiện banner "Đã tạm dừng điều khiển [Tiếp tục]".
- Không cần round-trip: client tự ngừng gửi input **trước**, đồng thời gọi API. Server cũng nhận `release_all`.
- Đây là đường thoát cho: gõ sai, app hành xử lạ, sợ bấm nhầm.

### 6.9 Chuyển cửa sổ / chuyển mode **giữa phiên** (mới ở v3.0)

Vấn đề v2.1: đổi cửa sổ = đóng phiên + mở phiên mới = 5–8 s + màn hình đen + ICE/DTLS lại từ đầu.

Thiết kế mới:
```
POST /api/sessions/{sid}/window { "wid": 123456 }
  → server: (1) restore cửa sổ cũ (§5.5.3)   [nếu mode=hvnc]
             (2) move cửa sổ mới lên display ảo
             (3) reset input state (release_all)
             (4) giữ nguyên peer/DTLS/SRTP — CHỈ đổi nguồn capture
             (5) gửi PLI → keyframe mới
             (6) trả 200 {state:"switching"} rồi {state:"active"}
```
- Client: phủ "Đang chuyển cửa sổ…" **500–1500 ms**, không mất kết nối, không tải lại trang.
- `POST /api/sessions/{sid}/mode { "mode":"vnc" }` — đổi HVNC↔VNC: tương tự nhưng đổi **nguồn capture + có/không move cửa sổ**; freeze 1–2 s. **Cho phép** (v2.1 cấm — không cần thiết, vì chỉ là thay nguồn capture).
- `POST /api/sessions/{sid}/monitor { "index": 1 }` — đổi monitor (VNC mode, multi-monitor).
- Trong lúc switching: `state:"switching"`, client ẩn input, hiện spinner.

### 6.10 Chất lượng & thích ứng

#### 6.10.1 Preset người dùng chọn được
| Preset | Resolution | FPS | Bitrate | Dùng khi |
|---|---|---|---|---|
| **Nét (Sharp)** | native | 30 | 12 Mbps | đọc chữ, làm việc văn phòng |
| **Cân bằng (Auto/default)** | native | 60 | 8 Mbps + adaptive | mặc định |
| **Mượt (Smooth)** | native | 60 | 4 Mbps | mạng yếu, thao tác nhanh |
| **Tiết kiệm (Low)** | 1280×720 | 30 | 1.5 Mbps | 4G, roaming |
- Đổi preset = đổi encoder config, **không** đổi màn hình ảo (tránh move cửa sổ lần 2).
- Auto: bắt đầu ở Cân bằng, điều chỉnh theo loss/RTT; người dùng chọn tay thì **khoá auto 10 phút**.
- Lưu theo user (localStorage) + có thể ép từ server.

#### 6.10.2 Kiểm tra băng thông trước khi bắt đầu
`POST /api/sessions` → response có `recommended_preset` dựa trên đo 5 s gần nhất của user đó; hoặc hiện ước lượng "~8 Mbps" trước khi bấm Start.

#### 6.10.3 Hiển thị: fit / fill / zoom local
| Chế độ | Mô tả | Dùng khi |
|---|---|---|
| **Fit** (default) | vừa khung, letterbox | mặc định, đúng toạ độ |
| **Fill** | phủ kín, crop mép | điện thoại (đọc chữ to hơn); **cảnh báo: mép bị cắt, phải pan** |
| **1:1** | pixel-perfect, có scroll | kiểm tra UI chính xác |
| **Zoom local** | pinch/`Ctrl+wheel` local transform 1×–4× + pan | đọc chữ nhỏ trên mobile |
- Khi zoom local ≠ 1: **toạ độ phải map qua transform** (dùng `getBoundingClientRect()` + scale) — nếu không click lệch. Đây là lỗi hay gặp.
- Khi ở Fill/zoom, hiện mini-map hoặc nhãn "đang phóng to 2×".

#### 6.10.4 Nguyên tắc "không khó dùng"
- Mọi thứ nâng cao ẩn sau nút ⚙. Màn hình mặc định chỉ có: video + thanh trên (tên cửa sổ, chất lượng, âm thanh, thoát).
- Không có modal chặn khi không cần. Không có bước "chọn codec".
- Mặc định đúng cho 90% người dùng; người còn lại mới mở ⚙.

### 6.11 Vòng đời & khôi phục

#### 6.11.1 Resume sau reload (mới)
- `GET /api/sessions/mine` → danh sách phiên còn sống trong grace 30 s của user.
- Mở trang → nếu có → hiện "Tiếp tục phiên đang mở? [Tiếp tục] [Huỷ]" thay vì bắt tạo mới.
- Tiếp tục: giữ nguyên `sid` + cửa sổ đã ở display ảo → chỉ làm lại SDP/ICE (1–2 s).
- Tránh: tab crash, F5 nhầm, đóng tab nhầm.

#### 6.11.2 Các đường mất kết nối
| Nguyên nhân | Hành vi |
|---|---|
| Tab ẩn >10 s | server giảm 60→5 fps, giữ kết nối; hiện lại → keyframe + 60 fps |
| Mất mạng <30 s | `RECONNECTING`, ICE restart, **không** restore cửa sổ (§7.1) |
| Mất mạng >30 s | `CLOSED` + cleanup + restore cửa sổ; client có nút "Tạo lại phiên" (nhớ cửa sổ cũ) |
| WS chết, media sống | vẫn xem được; WS tự reconnect; HUD báo "mất kênh điều khiển" |
| Media chết, WS sống | `reconnecting`; nếu 30 s fail → đóng |

#### 6.11.3 Idle timeout — định nghĩa lại
v2.1: "không input 10 phút" ⇒ **người chỉ ngồi xem bị đá**.
v3.0: idle = **không input VÀ không có tương tác UI** (không move chuột, không scroll, tab không active) trong 10 phút. Trước khi đá: hỏi "Còn đó không? [Tiếp tục]" ở phút 9. Người đang xem video vẫn bị coi là idle (không tương tác) → cảnh báo là đủ, không đá ngay.

#### 6.11.4 Handover (T2)
Chuyển phiên đang mở cho user khác (admin) mà **không** restore cửa sổ: `POST /api/sessions/{sid}/handover {to_user}` → đổi chủ sở hữu `sid`, kill kết nối cũ, user mới nhận.

### 6.12 Accessibility
- Picker và toàn bộ toolbar **điều hướng được bằng bàn phím** (Tab/Enter/Esc), có `aria-label`.
- Cảnh báo dùng `role="alert"` / `aria-live="polite"` → screen reader đọc.
- `prefers-reduced-motion` → tắt ripple/animation.
- `prefers-contrast: more` → viền rõ hơn; không dùng **chỉ** màu để truyền tải trạng thái (kèm icon/chữ).
- Cỡ chữ HUD theo `rem`, tôn trọng font-size của browser.
- Trạng thái không chỉ bằng màu: "Chỉ xem" có icon mắt, "đang kết nối" có text.

### 6.13 Giới hạn trung thực (phải hiện trong UI, không giấu)
| Không làm được | Lý do | UI nói gì |
|---|---|---|
| `Ctrl+Alt+Del` | SAS bị chặn từ Vista | Ẩn phím; tooltip giải thích; T3 có helper |
| Màn hình login / UAC secure desktop | chạy dưới user session | Banner `secure_desktop`: "hộp thoại bảo mật — cần thao tác trên máy thật" |
| Video DRM (Netflix…) | HDCP | Cảnh báo khi app có DRM đang phát |
| Game fullscreen exclusive + anti-cheat | chặn inject | Gợi ý borderless windowed |
| App chạy quyền admin (nếu server không elevated) | UIPI | Cảnh báo **trước** khi bắt đầu |
| Chuyển `Ctrl+W` trên Safari/Firefox | không có keyboard lock | Cảnh báo khi bấm |
| Symmetric NAT (không TURN) | T1 không có TURN | Lỗi rõ + gợi ý Tailscale |
| Ẩn **sự tồn tại** của cửa sổ (taskbar/Alt+Tab) | giới hạn của màn hình ảo | §14.2 + tuỳ chọn ẩn taskbar button |

---

# PHẦN III — GIAO THỨC, SERVER, CLIENT

## 7. Trạng thái & máy trạng thái

### 7.1 Máy trạng thái phiên
```
IDLE ──POST /sessions──► PREPARING ──► CONNECTING ──DTLS ok──► ACTIVE
                              │             │                    │
                              │ fail        │ fail               │ mất media
                              ▼             ▼                    ▼
                           FAILED        FAILED             RECONNECTING
                              │                                  │ ICE ok
                              │                                  └──► ACTIVE
                              │                                  │ 30 s
                              └──────────► CLOSING ◄─────────────┘
                                              │ cleanup (§8.3)
                                              ▼
                                           CLOSED
```
| State | Ý nghĩa | Có restore cửa sổ? | Client hiện |
|---|---|---|---|
| `PREPARING` | tạo display ảo + move window + route audio | — | spinner "Đang chuẩn bị…" |
| `CONNECTING` | SDP/ICE/DTLS | — | spinner + nút huỷ |
| `ACTIVE` | streaming | — | video |
| `SWITCHING` | đổi cửa sổ/mode/monitor (§6.9) | — | "Đang chuyển…" 0.5–1.5 s |
| `RECONNECTING` | media mất | **KHÔNG** | overlay mờ + frame cuối |
| `FAILED` | không thiết lập được | có | lý do + nút thử lại |
| `CLOSING` | đang dọn dẹp | có | "Đang kết thúc…" |
| `CLOSED` | xong | đã xong | picker |

> **Quy tắc số 1:** chỉ `CLOSING/FAILED` mới restore cửa sổ + audio. `RECONNECTING` **không** — nếu restore rồi kết nối lại thì cửa sổ nhảy về màn hình thật ⇒ **lộ** đúng lúc cần ẩn nhất.

### 7.2 Timeout
| Loại | Giá trị | Ghi chú |
|---|---|---|
| PREPARING → FAILED | 15 s | nếu tạo display/move window treo |
| CONNECTING → FAILED | 15 s | |
| RECONNECTING → CLOSED | 30 s | |
| Đóng tab (không DELETE) | 30 s grace | để resume (§6.11.1) |
| Idle | 10 phút (hỏi lại phút 9) | định nghĩa §6.11.3 |
| Tối đa 1 phiên | 12 h | warning trước 5 phút |
| WSS ping | 15 s | mất 2 lần → reconnecting |

## 8. Giao thức

### 8.1 REST
| Method | Path | Body | Trả |
|---|---|---|---|
| POST | `/api/login` | `{u,p}` | `{access}`, refresh cookie · 401/423/429 |
| POST | `/api/refresh` | — | `{access}` |
| POST | `/api/logout` | — | 204, kill mọi phiên của user |
| GET | `/api/health` | — | `{version,vdd,audio,encoders,os}` |
| GET | `/api/windows` | — | `[{wid,title,app,pid,rect,min,display,elevated,thumb,elevated_warn}]` |
| POST | `/api/sessions` | `{wid,mode,audio,audio_route,view_only,monitor,fps,preset,resolution}` | `200{sid,...}` · `412 driver_missing\|audio_device_missing\|window_immovable\|capture_blocked` · `403 app_not_allowed` · `409 already_streaming` |
| GET | `/api/sessions/mine` | — | phiên còn sống trong grace (resume) |
| GET | `/api/sessions/{sid}` | — | `{state,stats,audio,view_only,warnings,cursor_mode}` |
| DELETE | `/api/sessions/{sid}` | — | 204 (cleanup ≤3 s, đồng bộ) |
| POST | `/api/sessions/{sid}/audio` | `{enabled}` | `{enabled}` (<100 ms) |
| POST | `/api/sessions/{sid}/permission` | `{view_only}` | T2 |
| POST | `/api/sessions/{sid}/window` | `{wid}` | §6.9 |
| POST | `/api/sessions/{sid}/mode` | `{mode}` | §6.9 |
| POST | `/api/sessions/{sid}/monitor` | `{index}` | §6.9 |
| POST | `/api/sessions/{sid}/preset` | `{preset}` | §6.10.1 |
| POST | `/api/sessions/{sid}/keyframe` | — | 204 |
| POST | `/api/sessions/{sid}/release` | — | `sendBeacon` khi unload (§6.4.7) |
| POST | `/api/sessions/{sid}/cursor_mode` | `{mode}` | `local\|remote\|auto` |
| POST | `/api/sessions/{sid}/handover` | `{to_user}` | T2 |
| T2 | `/api/sessions/{sid}/clipboard` | `{text}`/`{image_b64}` | |

### 8.2 WSS signaling
```jsonc
// client → server
{"t":"offer","sid":"..","sdp":".."}
{"t":"ice","sid":"..","candidate":".."}
{"t":"resize","sid":"..","w":1600,"h":900}        // ≤1/10 s
{"t":"ping","ts":1750000000000}
// server → client
{"t":"answer","sid":"..","sdp":".."}
{"t":"ice","sid":"..","candidate":".."}
{"t":"state","sid":"..","state":"active|switching|reconnecting|closing|closed","reason":"app_closed|timeout|admin|..."}
{"t":"stats","sid":"..","kbps":8000,"fps":58,"rtt":42,"loss":0.1,"audio_kbps":24,"enc_ms":4,"cursor_mode":"local"}
{"t":"audio_state","sid":"..","enabled":true,"device":"CABLE Input"}
{"t":"window","sid":"..","wid":123,"title":"...","rect":{...}}
{"t":"warning","sid":"..","code":"window_lost|window_moved_out|minimized|drm_black|secure_desktop|need_admin|focus_lost|frame_freeze|audio_unavailable|display_lost|input_reset|someone_local|capture_blocked|nat_blocked","detail":".."}
{"t":"pong","ts":..}
```
Mọi message kiểm tra `sid.owner == token.sub`.

### 8.3 DataChannel

**`move`** (binary 12 B, unordered):
```
|u16 nx|u16 ny|u8 type|u8 flags|i16 wheel|u16 pad|
type:  1=move_abs  2=move_rel  3=down  4=up  5=wheel  6=touch_down 7=touch_up
flags: bit0=left bit1=right bit2=middle bit3=back bit4=forward
       bit5=ctrl bit6=shift bit7=alt bit8=win
```
**`ctrl`** (json, reliable):
```jsonc
{"t":"key","down":1,"vk":65,"mods":2,"ts":1750000000123}
{"t":"text","s":"ế"}                       // UTF-16, surrogate pair OK
{"t":"btn","down":1,"b":0,"ts":..}         // click (kèm toạ độ cuối cùng đã gửi)
{"t":"wheel","dx":0,"dy":-120,"ts":..}     // khi cần chính xác notch
{"t":"release_all"}                         // §6.5.4 / §6.4.7
{"t":"blur"} / {"t":"focus"}
{"t":"clip","s":".."} / {"t":"clip_img","b64":".."}
{"t":"resize","w":1600,"h":900}
{"t":"layout","name":"vi-VN"}
{"t":"ack","seq":n}
{"t":"ime","on":1}                          // server-side IME
{"t":"ping","ts":..}                        // đo input RTT
```
- Server clamp: `nx,ny ∈ [0,65535]`, `wheel ∈ [-2400,2400]`, `s.length ≤ 8192`.
- `move` ≤120 msg/s (client), server drop >200/s.

### 8.4 Media
- `video` recvonly H.264/VP8; `audio` recvonly Opus.
- `resize` → scale encoder (không đổi display ảo).
- PLI từ browser → server force IDR.
- Khi đổi nguồn capture (§6.9) → PLI + reset timestamp (tránh client bị "chờ" theo timestamp cũ).

## 9. Server — chi tiết

### 9.1 `window-picker` — §5.4
Ngoài ra: `elevated` phát hiện qua `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` thất bại (ACCESS_DENIED) ⇒ app chạy cao hơn ta.

### 9.2 `display-manager`

#### 9.2.1 DPI — bắt buộc `PER_MONITOR_AWARE_V2`
- Không khai báo → Windows **ảo hoá** toạ độ theo scale ⇒ click lệch tới 25% ở 150%.
- Manifest: `<dpiAwareness>PerMonitorV2</dpiAwareness>` + `SetProcessDpiAwarenessContext` (nếu chạy động).
- Khi move cửa sổ từ màn hình 150% sang display ảo 100%, app nhận `WM_DPICHANGED` và **tự resize** control → rect thay đổi. Xử lý: sau move, **đọc lại** `DWMWA_EXTENDED_FRAME_BOUNDS`, cập nhật mapping; **không** giả định rect đã gửi = rect thật.
- Chọn 100% cho display ảo để không có 2 tầng scale (§ khuyến nghị). Cho phép 125/150 nếu user muốn chữ to hơn (config) — nhưng khi đó phải test kỹ.

#### 9.2.2 Vòng đời display ảo — **không tạo/xoá mỗi phiên**
- Tạo display ảo **một lần** khi cài đặt/bật tính năng; **giữ** giữa các phiên (`keep_after_close=true`, default).
- Lý do: mỗi lần thêm/bớt display, Windows **reflow toàn bộ desktop** → icon, cửa sổ của người dùng **nhảy loạn** (đây là lỗi #9 v2.1). Với display được giữ, chỉ cửa sổ target di chuyển.
- Ở chế độ "giữ", display ảo nằm ngoài vùng nhìn, người dùng không thấy gì; con trỏ có thể đi vào vùng đó nếu họ kéo chuột sang — chấp nhận (hoặc đặt nó ở toạ độ xa, vd bên phải màn hình cuối, và ghi chú).
- Nếu buộc phải tạo/xoá (Tier 2 multi-session) → cảnh báo trong UI và thực hiện khi không có ai dùng máy (kiểm tra `GetLastInputInfo`).

#### 9.2.3 Window rescue — cứu cửa sổ khi người dùng kéo vào vùng vô hình
Kịch bản: trong lúc phiên chạy, người ngồi máy kéo cửa sổ "vô hình" sang vùng display ảo (họ không biết) → cửa sổ **biến mất khỏi màn hình thật** và họ **không lấy lại được**.
Xử lý:
1. Server phát hiện: mỗi 500 ms, nếu cửa sổ target có giao với display ảo nhưng **người dùng đang tương tác** (someone_local) → cảnh báo.
2. Khi **kết thúc phiên**, restore về vị trí gốc (§5.5.3) ⇒ cửa sổ trở lại.
3. Nếu phiên kết thúc bất thường (crash) → tray app lúc khởi động đọc state file, restore mọi cửa sổ còn "mồ côi" trên display ảo (§9.2.4).
4. Nếu người dùng kéo cửa sổ ra khỏi display ảo nhưng sang vùng **không tồn tại** (off-screen thật) → không phải việc của ta.

#### 9.2.4 State file (bắt buộc)
`%LOCALAPPDATA%\RD\state.json`:
```jsonc
{ "windows":[{ "hwnd":"...", "origRect":{...}, "wasMax":false, "session":"..." }],
  "audio":{ "defaultDeviceBefore":"{guid}", "perApp":[{ "pid":123,"device":"{guid}" }] },
  "display":"{id}" }
```
- Ghi **trước** khi move/route; xoá sau khi restore thành công.
- Lúc khởi động: nếu file còn → restore (audio trước, cửa sổ sau) → xoá. Đây là lưới an toàn cho crash/power loss.

### 9.3 `capture` — §5.5
- Drop frame khi encoder bận >33 ms (không queue) — latency trên hết.
- Con trỏ: **không** để DDAPI composite; luôn tắt cursor trong frame khi `cursor_mode=local`, bật khi `remote`. Nếu WGC: `IncludeCursor = (mode==remote)`.
- `GetFrameStatistics` để biết frame thật (không phải poll).

### 9.4 `encoder`
| Preset | bitrate | preset enc | tune |
|---|---|---|---|
| Sharp | 12 Mbps | p5 / slow-ish | hỗ trợ chi tiết |
| Balanced | 8 Mbps | p2 (NVENC) | ull |
| Smooth | 4 Mbps | p1 | ull |
| Low | 1.5 Mbps @720p | p1 | ull |
- Keyframe 2 s; `gop = fps*2`; `rc=cbr`; `zerolatency`.
- HW fail giữa phiên → x264 + giảm 720p + warning; **không** kill phiên.
- NVENC session limit (consumer ~3–8) → phiên vượt → x264.

#### 9.4.1 Auto-detect GPU & tự chọn preset (**chốt: máy nào cũng chạy, tự biết mình yếu**)
Không hỏi "máy bạn có GPU gì" lúc cài — **dò lúc chạy**, mỗi lần khởi động và mỗi lần tạo phiên:

```
1. Enumerate adapter (DXGI) → nhận diện vendor + tên + VRAM + feature level
2. Thử khởi tạo encoder theo thứ tự: NVENC → QSV → AMF → MF(x264/OpenH264)
   · thử bằng một session 1280x720 @30 fps 1 giây (throwaway) để chắc chắn chạy được
   · ghi lại "encoder nào thực sự khởi tạo được" (không đoán theo vendor string)
3. Micro-benchmark 3 giây trên nguồn capture thật:
   · đo: encode_ms p50/p95, số frame rơi, CPU%
   · nếu encode_ms p95 > 8 ms  ⇒ tụt 1 bậc preset
   · nếu encode_ms p95 > 16 ms ⇒ tụt tiếp (tối đa xuống "Low")
4. Kết quả ghi cache vào config (kèm hash GPU driver + OS build);
   driver đổi ⇒ dò lại.
```

| Kết quả dò | Preset mặc định | Độ phân giải/FPS |
|---|---|---|
| HW encoder, dư sức (RTX/RX mới) | Balanced | 1080p60 |
| HW encoder yếu (iGPU đời cũ, laptop U) | Smooth | 1080p60 → tự hạ 900p nếu rơi frame |
| Chỉ x264, CPU ≥8 nhân hiện đại | Smooth | 1080p30 |
| Chỉ x264, CPU yếu / máy ảo | Low | 720p30 |

- **Người dùng vẫn đổi được tay** (§6.10.1); auto chỉ là mặc định + trần. Đổi tay thì khoá auto 10 phút.
- Panel `⚙ → Thông tin máy chủ` **hiện rõ**: GPU, encoder đang dùng, encode_ms, lý do chọn preset. Không giấu — nếu hình mờ, người dùng biết vì sao.
- Khi phần cứng không đạt 1080p60: **nói trước** ở picker ("Máy này phù hợp 1080p30"), không để người dùng mở phiên rồi mới thấy giật.

### 9.5 `query-cursor` — implement §6.3
- DDAPI: `PointerShapeBufferSize > 0` → `GetFramePointerShape` → cache theo `PointerShapeInfo.PointerShapeBufferSize + hash`.
- Mono shape: 2 bitmap AND/XOR (mask + image) → gửi dạng `mono:true,and,xor` để client render chính xác (alpha = `!AND`, color = AND?black:XOR).
- Color shape: BGRA có alpha premultiplied → chuyển sang thẳng, gửi PNG nhỏ.
- Hotspot: `Position`/`HotSpot` trong `DXGI_OUTDUPL_POINTER_SHAPE_INFO`.
- `PointerPosition.Visible` → gửi `vis:false` (§6.3.5).
- Fallback: `GetCursorInfo` + `GetIconInfo` 30 Hz (kém hơn, dùng khi DDAPI không cho shape).

### 9.6 `audio` — chi tiết (**chốt: hỏi mỗi phiên**)

#### 9.6.1 Ba lựa chọn hiện ở màn hình chờ tạo phiên
| Lựa chọn | Nhãn UI | Routing | Ai nghe cục bộ |
|---|---|---|---|
| **Chỉ app này** (mặc định, được nhớ theo app) | "Âm thanh của [Chrome]" | per-app → CABLE | không (app đó im trên loa thật) |
| **Toàn bộ máy** | "Toàn bộ âm thanh máy" | đổi default device → CABLE | **máy im hoàn toàn** |
| **Theo màn hình thật** (chỉ mode VNC) | "Âm thanh như đang ở máy" | loopback default device | nghe bình thường |
| **Không có tiếng** | "Tắt tiếng" | không route, không stream | như cũ |

#### 9.6.2 Quy tắc "hỏi mỗi phiên" cho dễ dùng
- Hỏi **một lần** trên màn hình tạo phiên (2 radio + 1 checkbox "nhớ cho app này").
- Nhớ theo **app exe** (không theo cửa sổ): lần sau chọn Chrome → tự điền lựa chọn lần trước; vẫn hiện để đổi.
- **Không hỏi lại** khi resume/switch window trong cùng phiên.
- Nếu chọn "Toàn bộ máy": hiện cảnh báo ngắn **một lần** "Máy sẽ im lặng trong lúc điều khiển. Sẽ tự khôi phục khi kết thúc." + checkbox xác nhận (vì đây là thay đổi ảnh hưởng toàn máy).
- Lựa chọn mặc định **toàn cục** đặt được trong cài đặt (cho người dùng 1 mục đích cố định); mặc định `ask`.

#### 9.6.3 Toggle trong phiên (đã có ở §5.10.2)
- Nút 🔊 trên toolbar bật/tắt **stream**, không đổi routing.
- Đổi **routing** giữa phiên nằm trong `⚙ → Âm thanh` (hiếm dùng): dừng capture, đổi route, khởi động lại capture, reset SSRC; freeze audio 200–600 ms. Không đổi routing tự động bao giờ.

#### 9.6.4 Cài đặt & lỗi — §11.3
### 9.7 `input` — §7.5 (máy trạng thái)
### 9.8 `presence`
- `GetLastInputInfo()` 1 s/lần; so với cờ `injecting` (±50 ms) để phân biệt người thật.
- Nếu `someone_local` → chuyển cursor `remote`, banner; **không** tự ngắt.

### 9.9 `clipboard` (T2) — chỉ explicit
- **Không auto-sync.** Auto-sync 2 chiều: (a) gây vòng lặp, (b) **rò dữ liệu riêng tư** của người ngồi máy (họ copy mật khẩu → sang client).
- "Copy from remote": server đọc `CF_UNICODETEXT`/`CF_DIB` → client `navigator.clipboard.writeText` (nút bấm = gesture).
- "Paste to remote": client đọc clipboard → server `SetClipboardData` + optional `Ctrl+V`; **restore clipboard cũ sau 300 ms** để không ghi đè clipboard của người dùng máy.
- Cap: text 256 KB, ảnh 8 MB (nén PNG q80).

### 9.9b Cài đặt & mức quyền (**chốt: user thường mặc định, elevated là tuỳ chọn**)
| Mức | Cài thế nào | Điều khiển được | Ghi chú |
|---|---|---|---|
| **Standard (mặc định)** | MSI chạy admin **chỉ** để cài (driver/firewall/task), app chạy dưới user thường | app thường | an toàn nhất; stream được cửa sổ admin **nhưng** click/gõ bị UIPI chặn → cảnh báo `need_admin` trước khi bắt đầu |
| **Elevated (opt-in)** | Thêm shortcut/task "Run as administrator" | cả app admin | giảm an toàn: nếu server bị chiếm ⇒ toàn quyền máy; UI cài đặt cảnh báo rõ, cần tick xác nhận |
- Wizard cài đặt **hỏi 1 lần**: "Bạn có cần điều khiển app chạy quyền admin không?" → mặc định **Không**.
- Elevated không tự bật nếu người dùng không chọn; có thể đổi sau trong `⚙ → Nâng cao`.
- Khi server ở mức Standard và user chọn cửa sổ elevated: picker hiện badge + checkbox "Tôi hiểu: chỉ xem, không điều khiển được" (hoặc cho chuyển sang view-only).
- UIPI: **không** dùng `SeDebugPrivilege` như phép màu (§5.8.5).

### 9.10 `auth` / `audit`
Như v2.1, cộng: audit thêm `session.switch_window`, `session.cursor_mode`, `input.reset`, `presence.local_input`. **Không** log nội dung.

### 9.11 Config
```jsonc
{
  "listen":"0.0.0.0:443",
  "tls":{"cert":"...","key":"..."},
  "auth":{"max_sessions":1,"access_min":15,"refresh_days":7},
  "stun":["stun:stun.l.google.com:19302"],
  "display":{"w":1920,"h":1080,"fps":60,"scale":100,"keep_after_close":true,"on_window_drift":"warn"},
  "audio":{"route_default":"ask","remember_per_app":true,"device":"CABLE Input (VB-Audio Virtual Cable)","bitrate_kbps":32},
  "encoder":{"order":["nvenc","qsv","amf","x264"],"preset":"balanced","keyframe_s":2},
  "cursor":{"mode":"auto","shape_max_kb":64},
  "input":{"block_win_l":true,"max_move_hz":120,"stuck_release_ms":3000},
  "session":{"disconnect_timeout_s":30,"idle_timeout_s":600,"max_hours":12,"grace_s":30},
  "clipboard":{"enabled":false,"text_kb":256,"img_mb":8},
  "stealth":{"level":"hidden","notice":"always"},   // S0 content | S1 hidden | S2 deep; notice luôn "always"
  "mode":"auto",                                    // auto | lan | vpn | internet
  "debug":{"barcode":false,"show_latency_hud":false}
}
```

## 10. Client — chi tiết

### 10.1 Màn hình
1. **Login** — lỗi rõ, đếm ngược lockout, gợi ý 2FA.
2. **Picker** — card: thumbnail/icon, title, app, badge `minimized`/`elevated`/`đang dùng`; tìm kiếm; refresh (auto 5 s); chọn **mode**, **audio**, **view-only**; nút Start; nếu có phiên cũ → banner "Tiếp tục phiên".
3. **Session** — `<video>` + overlay cursor + ripple + HUD; toolbar trên: `← picker` · tên cửa sổ · `⚙` (chất lượng, cursor mode, chuyển cửa sổ) · 🔊 · ⛶ · 🛑 · stats.
4. **Overlay** — `RECONNECTING`, warnings (map mã → câu tiếng Việt + hành động).

### 10.2 WebRTC client
```js
const pc = new RTCPeerConnection({iceServers:[{urls:STUN}]});
pc.addTransceiver("video",{direction:"recvonly"});
pc.addTransceiver("audio",{direction:"recvonly"});
const ctrl = pc.createDataChannel("ctrl",{ordered:true});
const move = pc.createDataChannel("move",{ordered:false,maxRetransmits:0});
```
- Offer → WSS → ICE trickle → `ontrack`.
- **Audio autoplay**: iOS/Safari chặn → nút "🔊 Bật tiếng" (chính là gesture).
- Reconnect: WS backoff 1/2/4/8 s (≤8 lần) → `restartIce()` → fail → tạo phiên mới (nhớ `wid` cũ).
- `visibilitychange` → `pause`/`resume`.

### 10.3 Input pipeline (thứ tự xử lý bắt buộc)
```
pointerdown/up        → ripple ngay → ctrl/btn
pointermove (không nút) → [throttle rAF, latest-wins] → move/1
pointermove (có nút)    → [throttle rAF, latest-wins] → move/1
wheel                 → tích luỹ tới notch → ctrl/wheel
keydown               → [skip repeat] → ctrl/text|key
compositionend         → ctrl/text (kết quả cuối)
blur/visibilitychange/pointercancel/lostpointercapture → ctrl/release_all
beforeunload           → sendBeacon /release
```
- Toạ độ: công thức §10.4 (có letterbox + zoom).
- Bỏ qua event ở vùng letterbox (đen).
- `touch-action: none` trên video; `user-select: none`; chặn contextmenu chuột phải của browser (nhưng vẫn gửi right click sang server).

### 10.4 Công thức toạ độ (có zoom + letterbox)
```
// sau khi đã áp scale = zoom local (1..4) và pan (panX, panY)
vw,vh = video.videoWidth, video.videoHeight
dw,dh = videoEl.clientWidth, videoEl.clientHeight
s     = min(dw/vw, dh/vh) * zoom
dispW = vw*s ; dispH = vh*s
offX  = (dw - dispW)/2 + panX
offY  = (dh - dispH)/2 + panY
u = (clientX - rect.left - offX) / dispW      // clamp 0..1
v = (clientY - rect.top  - offY) / dispH
→ u16 = round(u*65535), v16 = round(v*65535)
```
```
// server
X = mon.left + round(u16/65535*(capW-1))
Y = mon.top  + round(v16/65535*(capH-1))
nx = round((X - SM_XVIRTUALSCREEN)*65535/(SM_CXVIRTUALSCREEN-1))
ny = round((Y - SM_YVIRTUALSCREEN)*65535/(SM_CYVIRTUALSCREEN-1))
```

### 10.5 Tương thích
| Browser | H.264 | Opus | DataChannel | Keyboard Lock | Pointer Lock | Ghi chú |
|---|---|---|---|---|---|---|
| Chrome/Edge | ✅ | ✅ | ✅ | ✅ (96+) | ✅ | đầy đủ nhất |
| Firefox | ✅ | ✅ | ✅ | ❌ | ✅ | Ctrl+W không chặn được |
| Safari 16.4+ | ✅ | ✅ | ✅ | ❌ | ✅ (gesture) | audio cần gesture |
| Chrome Android | ✅ | ✅ | ✅ | ❌ | ❌ | touch mode |
| Safari iOS | ✅ | ✅ | ✅ | ❌ | ❌ | fullscreen bị hạn chế |

## 11. Edge cases

### 11.1 Cửa sổ
| Tình huống | Xử lý |
|---|---|
| Minimized | badge; chọn → `SW_RESTORE`; fail → `412 window_unrestorable` |
| Người dùng kéo ra khỏi display ảo | check 1 s/lần; giao <50% → `window_moved_out`; policy `warn` (default) / `keep` |
| Người dùng đóng cửa sổ | `IsWindow` false → `closed/app_closed` → cleanup |
| App treo (>10 s không frame) | `frame_freeze` |
| Nhiều cửa sổ cùng app | định danh bằng `hwnd`, không theo tên |
| Title đổi liên tục | chỉ hiển thị; render bằng `textContent` |
| UWP/Store | `EXTENDED_FRAME_BOUNDS`; nhiều window → chọn cái có title |
| Dialog/menu/popup | vẫn capture được vì capture theo **display** |
| `WDA_EXCLUDEFROMCAPTURE` | `412 capture_blocked` |
| Window maximized khi kết thúc | restore đúng thứ tự §5.5.3 rồi `SW_MAXIMIZE` ở màn hình gốc |
| App tự center lại | `SWP_NOSENDCHANGING`; vẫn fail → `window_immovable` |
| Game fullscreen exclusive | có thể minimize khi move → gợi ý borderless, hoặc `412 exclusive_fullscreen` |
| App multi-process (Chrome/Electron) | nhiều top-level window → user chọn |
| Taskbar / desktop icons | filter theo class |
| Cửa sổ session khác | filter `ProcessIdToSessionId` |
| Kéo cửa sổ khi đang có người thật dùng | §9.2.3 |

### 11.2 Hiển thị / DPI / GPU
| Tình huống | Xử lý |
|---|---|
| Scale 150% | PER_MONITOR_AWARE_V2; toạ độ pixel vật lý; đọc lại rect sau move |
| Multi-monitor toạ độ âm | `SM_XVIRTUALSCREEN` (âm) + `VIRTUALDESK`; **test 2 màn hình lệch size** |
| HDR | tonemap PQ→SDR hoặc ép duplication SDR; **bắt buộc** nếu máy bật HDR |
| GPU hybrid | capture+encode cùng adapter; khác → shared surface |
| Display ảo mất | `display_lost` → recreate ≤3 → FAILED |
| Đổi resolution giữa phiên | `ACCESS_LOST` → recreate + encoder reinit |
| RDP chiếm console | `paused/session_disconnected` → phục hồi khi RDP out |
| Windows Update restart | phiên chết; tray restart sau login |
| Sleep | `SetThreadExecutionState(ES_CONTINUOUS|ES_SYSTEM_REQUIRED|ES_DISPLAY_REQUIRED)` **chỉ khi có phiên** |
| Screen saver | display ảo không bị ảnh hưởng |
| Màn hình vật lý tắt nguồn | capture vẫn chạy |
| Tablet mode / rotation | display ảo cố định landscape |

### 11.3 Âm thanh
| Tình huống | Xử lý |
|---|---|
| App không phát | im lặng, `usedtx` → ~0 bps |
| Người tại máy vẫn nghe (HVNC) | checklist: app output = cable? app thứ 2 phát cùng nội dung? cable bị disable? |
| App cần restart để đổi output | thông báo; **không** kill app |
| Thiếu VB-Audio | `412 audio_device_missing` nhưng **vẫn cho video-only** |
| Cable mất giữa phiên | `audio_unavailable` + retry 5 s; >60 s → tắt audio, giữ phiên |
| Toggle off→on | reset SSRC Opus + re-enumerate device |
| Exclusive mode | không route/capture → ghi chú |
| 44.1 kHz | resample liên tục (ASRC) |
| Drift phiên dài | kiểm tra A/V mỗi 30 s |
| Nhiều phiên 1 cable | trộn → khuyến nghị cable riêng |
| Bluetooth làm default | trễ lớn; không tự đổi device của user |
| Process chết khi đang đổi default | watchdog restore khi khởi động (§9.2.4) |
| **Toggle tắt nhưng PHẢI giữ im lặng cục bộ** | routing giữ nguyên; chỉ dừng stream (§10.3) |

### 11.4 Mode / phiên
| Tình huống | Xử lý |
|---|---|
| Thiếu VDD | `412 driver_missing` + wizard |
| Đổi mode giữa phiên | **được** — `POST /mode` (§6.9), freeze 1–2 s |
| Đổi cửa sổ giữa phiên | **được** — `POST /window`, 0.5–1.5 s, không mất kết nối |
| 2 người cùng 1 cửa sổ | `409`; T2 cho viewer thứ 2 (share pipeline) |
| 2 phiên cùng 1 display ảo | cấm; 1 display/phiên |
| Allowlist chặn | `403` |
| Đóng tab | grace 30 s → có thể resume |
| Mất mạng 10 s / 60 s | §7.2 |
| 2 tab cùng user, limit=1 | tab 2 nhận `409` (hoặc T2: 2 phiên) |
| Logout khi đang stream | kill mọi phiên + cleanup |
| Server shutdown | signal handler → cleanup (§13.4) |
| Console khoá (Win+L/timeout) | HVNC: video **vẫn chạy**, input **bị chặn** → `secure_desktop`; VNC: thấy lock screen, cùng warning |
| UAC prompt | như trên; **không** gửi input (tránh bấm Yes ngoài ý muốn) |
| Fast User Switching | session của ta disconnected → `paused` |
| Phiên 12 h | auto-close + warning 5 phút trước |

### 11.5 Mạng / WebRTC
| Tình huống | Xử lý |
|---|---|
| Symmetric NAT/CGNAT | `nat_blocked` + gợi ý Tailscale (T1 không TURN) |
| UDP bị chặn | lỗi rõ + gợi ý VPN |
| IPv6 only | listen dual-stack |
| Codec mismatch | `codec_mismatch` |
| Loss cao | adaptive + `move` lossy độc lập |
| Datachannel chết, media sống | `input_ack` không về 1.5 s → renegotiate hoặc `input_channel_lost` |
| Media sống, WS chết | vẫn xem; WS tự reconnect; HUD "mất kênh điều khiển" |
| Reverse proxy buffer WSS | `proxy_buffering off`, timeout >1 h |
| Nhiều client | upload = N × bitrate |
| Firewall chặn UDP | wizard + rule |
| Đổi mạng giữa phiên (WiFi→4G) | ICE restart |
| Latency >500 ms | cảnh báo, vẫn dùng được |

### 11.6 Bảo mật
| Tình huống | Xử lý |
|---|---|
| JWT bị lấy | TTL 15′; refresh reuse-detect → revoke all |
| `sid` người khác | 403 |
| XSS qua title cửa sổ | `textContent` + CSP (title do app bên thứ ba đặt — **không tin**) |
| Input độc hại | clamp + validate UTF-16 + giới hạn độ dài |
| Flood datachannel | rate limit + audit |
| Clipboard rò rỉ | mặc định off, chỉ explicit |
| Brute force | lockout theo IP+user |
| Cert hết hạn | fail rõ ràng |
| Token trong URL | không bao giờ |
| CSRF | SameSite=Strict + custom header |
| Server chạy elevated | cần cho app admin; cảnh báo docs, không mặc định |
| Ai đó thấy app biến mất | hành vi đã thông báo (§2.4) + toast + icon tray đổi màu |

### 11.7 Client / mobile / browser
| Tình huống | Xử lý |
|---|---|
| Audio autoplay chặn | nút "Bật tiếng" |
| Bàn phím ảo che màn hình | `visualViewport` + reflow |
| Pinch | local zoom (mặc định) hoặc Ctrl+wheel |
| Xoay máy | reflow + `resize` ≤1/10 s |
| Tab background | giảm fps, pause input |
| Trình duyệt cũ | báo nâng cấp; VP8 fallback |
| Proxy chặn WebSocket | lỗi rõ |
| Ctrl+W/Ctrl+T | keyboard lock; nếu không có → cảnh báo trước |
| Ctrl+wheel của browser (zoom trang) | chặn khi focus video |
| Chuột phải | chặn contextmenu browser, gửi sang server |
| Kéo thả file vào tab | chặn (tránh điều hướng trang) |

## 12. Bảo mật & triển khai
Như v2.1, cộng:
- **Cursor shape** kiểm tra kích thước (≤64 KB), validate hotspot nằm trong bounds trước khi gửi client (chống crash client).
- **`sendBeacon /release`** phải yêu cầu auth (cookie) và chỉ nhận từ chính user.
- **Debug barcode** chỉ bật khi `debug=true` và tự tắt sau 5 phút.
- **Pointer Lock** không ảnh hưởng bảo mật nhưng phải thoát được bằng Esc (browser đảm bảo).

## 13. Mạng & triển khai (chốt: **LAN trước, mở rộng dần**)

### 13.1 Thứ tự ưu tiên (đúng như bạn chọn)
| Cấp | Kịch bản | Cần gì | Trạng thái |
|---|---|---|---|
| **1** | LAN (cùng switch/Wi-Fi) | 443/tcp + UDP media; **không STUN**, cert tự ký OK | **Phase 1 — phải chạy được ngay** |
| **2** | Qua Internet bằng **WireGuard/Tailscale/ZeroTier** | Thêm VPN, app không đổi gì | **Phase 1 — phải chạy được ngay** |
| **3** | Internet không VPN (port-forward + STUN) | Cert hợp lệ + firewall + lockout | Phase 2 — chỉ nếu cần |
| **4** | TURN relay (symmetric NAT) | coturn | Tier 3 |

> Thiết kế **không** phụ thuộc VPN: cùng một binary chạy cả 4 cấp, khác nhau ở config (`stun: []` khi LAN). Không có "bản LAN" và "bản Internet" riêng.

### 13.2 Phát hiện môi trường & tự cấu hình
- Lúc khởi động, server liệt kê IPv4/IPv6 của các interface. Nếu **chỉ có IP private** (10/8, 172.16/12, 192.168/16, link-local) → `mode: lan` → không cần STUN, cảnh báo "chỉ truy cập được trong LAN hoặc qua VPN".
- Nếu phát hiện interface Tailscale (100.64/10) hoặc ZeroTier → gợi ý `mode: vpn`, dùng IP đó làm địa chỉ advertise.
- Client: nếu URL là IP private/Tailscale → tắt STUN, dùng host candidate (nhanh nhất, 0 round-trip). Nếu là tên miền công khai → bật STUN theo config.

### 13.3 LAN — chi tiết
- **mDNS candidate**: Chrome/Edge che host candidate thành `*.local` (mDNS obfuscation). Trong LAN, nếu mDNS bị chặn (firewall/AP isolation) → kết nối fail dù cùng mạng. Xử lý: (a) server advertise IP thật; (b) fallback: nếu sau 3 s chưa có candidate pair → client gọi `POST /api/sessions/{sid}/restart-ice {mdns:false}` và server gợi ý tắt "Anonymize local IPs" trong `chrome://flags`; (c) ghi rõ trong troubleshooting.
- **AP isolation** (Wi-Fi khách): client và server không thấy nhau → phát hiện qua ICE fail nhanh, thông điệp rõ: "Thiết bị không thấy nhau trong LAN — kiểm tra AP isolation / dùng chung subnet".
- **Windows Firewall**: wizard tạo rule cho 443/tcp + UDP range khi cài (cần admin 1 lần).
- **IPv6 link-local**: bỏ qua (không hữu ích cho WebRTC trong LAN có NAT).

### 13.4 VPN — chi tiết
| VPN | Ghi chú |
|---|---|
| **Tailscale** | Dễ nhất: `tailscale cert` lấy cert Let's Encrypt cho `machine.ts.net` ⇒ HTTPS hợp lệ, không cần tự ký. MagicDNS cho tên ổn định. |
| **ZeroTier** | Tương đương; cert phải tự ký hoặc dùng IP. |
| **WireGuard thuần** | Nhanh nhất, nhưng phải tự quản lý key + DNS + cert. |
- Qua VPN, MTU có thể 1280 ⇒ **giảm MTU RTP** hoặc bật fragmentation ở tầng WebRTC; test với gói 1400 B. Nếu quên: video 1080p bị "kẹt" ở 720p do packet loss giả.
- VPN làm tăng RTT 5–30 ms ⇒ vẫn trong ngân sách §17.3.

### 13.5 Port & firewall
| Cổng | Dùng | Ghi chú |
|---|---|---|
| 443/tcp | HTTPS + WSS | hoặc 8443 |
| UDP 50000–50100 | WebRTC media + SCTP | range cố định để firewall dễ; nếu bị chiếm → fallback ephemeral |
| 3478/udp | STUN | chỉ khi mode internet/vpn-public |

### 13.6 Setup 15 phút
1. Cài MSI (admin) → app + tray + firewall rule.
2. Wizard: tạo admin password → sinh cert tự ký (LAN) hoặc nhập cert (Internet) → chọn `mode: lan|vpn|internet`.
3. Wizard kiểm tra: VDD · VB-Audio (tuỳ chọn) · encoder · cổng · IP/interface.
4. Chọn mode mặc định + audio ("hỏi mỗi phiên" mặc định).
5. Mở `https://<host>/` → login → picker.

### 13.7 Uninstall / rollback (bắt buộc)
restore audio (state file) → restore mọi cửa sổ → bỏ ẩn taskbar/Alt+Tab → xoá display ảo (nếu do ta cài) → xoá firewall rule → xoá task/cert/state.

## 14. Che giấu — từng kênh rò rỉ (đã chốt: stealth đầy đủ)

### 14.1 Bảng rò rỉ đầy đủ + cách xử lý
| # | Kênh lộ | S0 content | **S1 hidden (default)** | **S2 deep (opt-in)** |
|---|---|---|---|---|
| 1 | Màn hình chính (pixel) | ❌ ẩn | ❌ ẩn | ❌ ẩn |
| 2 | Loa thật | ❌ ẩn (route cable) | ❌ ẩn | ❌ ẩn |
| 3 | Taskbar button | ✅ lộ | ❌ **ẩn** (`ITaskbarList.DeleteTab`) | ❌ ẩn |
| 4 | Hover taskbar → thumbnail **nội dung** | ✅ lộ | ❌ ẩn (mất button ⇒ mất thumbnail) | ❌ ẩn |
| 5 | `Alt+Tab` | ✅ lộ | ✅ lộ (giới hạn kỹ thuật, xem §14.3) | ⚠️ giảm tối đa |
| 6 | Task View (Win+Tab) | ✅ lộ | ✅ lộ | ⚠️ giảm tối đa |
| 7 | `Win+1..9` tới app | ✅ | ✅ | ⚠️ thường không tới được sau khi ẩn |
| 8 | Volume Mixer thấy app phát vào CABLE | ✅ | ✅ | ✅ chấp nhận |
| 9 | Notification toast của app | ✅ | ✅ | ✅ chấp nhận |
| 10 | Task Manager / process list | ✅ | ✅ | ✅ chấp nhận (không giấu process — đó là malware) |
| 11 | Toast + icon tray "đang được điều khiển" | ✅ cố ý | ✅ cố ý | ✅ cố ý (**không tắt được**, §2.4.2) |
| 12 | Lịch sử Jump List / recent files | ✅ | ✅ | ✅ chấp nhận |
| 13 | Screenshot toàn màn hình của người dùng | ❌ không có cửa sổ | ❌ | ❌ |
| 14 | Screen recording phần mềm khác | ❌ | ❌ | ❌ |
| 15 | `PrintScreen` khi cửa sổ đang active | không active ⇒ không lộ | ❌ | ❌ |

> Ở **S1** (mặc định), 2 kênh còn lộ là **Alt+Tab** và **Task View**. Không thể đóng hoàn toàn mà không hook — xem §14.3 và chấp nhận, hoặc chọn S2.

### 14.2 Ẩn taskbar — chi tiết triển khai
```
ITaskbarList3.CoCreateInstance(CLSID_TaskbarList) → HrInit()
→ DeleteTab(hwnd)   khi bắt đầu phiên
→ AddTab(hwnd)      khi kết thúc (và khi app tự thêm lại)
```
- **Bắt buộc retry**: Electron/Chromium và một số app gọi `SetTaskbarState`/tự `RegisterTab` lại sau vài giây → poll 2 s/lần, nếu `DeleteTab` lại được thì làm; tối đa 20 lần, sau đó ghi audit `hide_taskbar_flaky` (không loop vô hạn).
- **Không** ảnh hưởng chức năng app (chỉ là shell integration). Nếu app crash, explorer tự dọn.
- Khi kết thúc: `AddTab` — nếu app đã thoát thì bỏ qua (`IsWindow` false).
- Nếu Explorer restart giữa phiên → taskbar mới không biết gì → button **hiện lại**; phát hiện qua `RegisterWindowMessage("TaskbarCreated")` → `DeleteTab` lại.

### 14.3 Alt+Tab / Task View — giới hạn thật, và cách "ít xâm lấn nhất"
**Sự thật:** Alt+Tab lấy danh sách từ một cấu trúc nội bộ của `explorer`/`win32k`. Không có API công khai để loại một cửa sổ khỏi Alt+Tab. Các cách tồn tại:

| Cách | Hiệu quả | Rủi ro |
|---|---|---|
| `WS_EX_TOOLWINDOW` trên cửa sổ **top-level** | **Có** — cửa sổ tool window không vào Alt+Tab | Đổi style của app bên thứ ba: một số app (Electron, app tự quản style) sẽ **tự đổi lại**; một số app có thể vẽ lại/đổi hành vi. Phải khôi phục style cũ khi kết thúc. |
| `WS_EX_NOACTIVATE` | Không giúp | Cửa sổ không nhận focus ⇒ **không gõ được** |
| `ITaskbarList.DeleteTab` | Không ảnh hưởng Alt+Tab (chỉ taskbar) | — |
| Owner = hidden window | Không hiệu quả với top-level đã có owner | — |
| Hook `SetWindowsHookEx` / API hook `SwitchToThisWindow` | Hiệu quả cao | **Không làm** — đúng signature malware, bị AV/EDR chặn, dễ crash explorer |
| Ẩn hẳn cửa sổ (`ShowWindow(SW_HIDE)`) | Cửa sổ mất khỏi mọi danh sách | **Không dùng** — cửa sổ bị ẩn thì DWM **không composite** ⇒ **không capture được** |

⇒ **S2 `deep` = `WS_EX_TOOLWINDOW` + `DeleteTab` + poll retry**, chấp nhận:
- Một số app sẽ hiện lại trong Alt+Tab (ghi nhận trong log, UI báo "app này không ẩn được khỏi Alt+Tab").
- Style thay đổi trong lúc chạy có thể làm app vẽ lại 1 lần (nháy) — chấp nhận, có thể tránh bằng cách set style **trước** khi move cửa sổ.
- Khôi phục style gốc khi kết thúc — **bắt buộc**, nếu không app sẽ mãi không hiện lại trong Alt+Tab.

Với Task View (Win+Tab): cùng cơ chế với Alt+Tab ⇒ kết quả tương tự S2.

### 14.4 Không dùng `WDA_EXCLUDEFROMCAPTURE` trên cửa sổ target
Nó sẽ chặn **luôn** capture của ta. Chỉ dùng để *kiểm tra* xem app khác có đặt cờ đó không (§11.1).

### 14.5 Kết luận trung thực (giữ nguyên tinh thần, cập nhật số liệu)
- **S1 (mặc định)**: người ngồi máy **không thấy nội dung, không nghe tiếng, không thấy app trên taskbar**. Họ vẫn thấy app trong **Alt+Tab / Task View**.
- **S2 (opt-in)**: giảm thêm Alt+Tab/Task View, nhưng **không đạt 100%** và có thể làm vài app hành xử lạ.
- **Không bao giờ**: giấu process khỏi Task Manager, hook hệ thống, tắt thông báo tray — đó là ranh giới malware.

## 15. Tham khảo (chỉ ý tưởng, không copy code)
| Nguồn | Lấy gì | Không lấy gì |
|---|---|---|
| RustDesk | feature set, privacy mode bằng virtual display, Opus | cần app native |
| tanetakumi/remote-window-control | kiến trúc gần nhất: picker + Pion + WGC→ffmpeg→VP8 + DC input | không auth, không HVNC |
| agent-desktop | SendInput absolute + VIRTUALDESK, DPI, UIPI | — |
| noVNC / Guacamole | input mapping, keyboard/IME phía browser, **cách vẽ cursor local** | transport TCP |
| Sunshine / Apollo | pipeline capture→encode, virtual display, loopback | game streaming, cần client app |
| VDD (MIT) | **dùng trực tiếp** | — |
| VB-Audio Cable | **dùng trực tiếp** | — |
| EarTrumpet | ý tưởng per-app routing | không bundle |
| GStreamer webrtcbin / Pion | media stack | — |
| HVNC kits | hiểu hidden desktop | **không dùng**: mất state, giống malware |
| MS Learn | DDAPI cursor shape, WGC, SendInput, WASAPI, UIPI, DPI, ITaskbarList | — |

## 16. Kiến trúc đa ngôn ngữ (chốt: mỗi tầng dùng ngôn ngữ tốt nhất *cho tầng đó*)

### 16.1 Nguyên tắc chọn ngôn ngữ
Có một luật duy nhất chi phối toàn bộ: **đường nóng (hot path) không được băng qua ranh giới process**.

Đường nóng = `capture → cursor → encode → RTP` và `input → SendInput`. Ngân sách §17.3 là **input→photon p95 <80 ms LAN**; một lần IPC tuần tự (pipe/JSON/gRPC) tốn 0.2–2 ms **mỗi chiều, mỗi sự kiện**, cộng scheduler jitter 1–15 ms khi hệ thống tải. Với 120 sự kiện/giây, chỉ cần tách process ở đây là mất luôn mục tiêu độ trễ.

⇒ **Mọi thứ trên đường nóng nằm trong MỘT process native.**

Ngoài đường nóng thì ngược lại: dùng ngôn ngữ nào *rẻ nhất cho tầng đó*, kể cả khi phải thêm 3 toolchain.

### 16.2 Phân tầng

| Tầng | Ngôn ngữ | Vì sao đúng tầng này | Ước lượng |
|---|---|---|---|
| **Core native** (capture, cursor, encoder, webrtc, audio, input, session) | **Rust** + gọi thư viện C (GStreamer) trực tiếp qua FFI | `windows` crate phủ 100% API cần (DDAPI, WGC, SendInput, WASAPI, DWM, ITaskbarList) mà vẫn an toàn bộ nhớ khi thao tác với buffer GPU/cursor bitmap — đúng chỗ dễ crash nhất. 1 binary, không runtime phụ thuộc. | ~9–12 kLOC |
| **Media pipeline** | **C** (GStreamer: `d3d11screencapturesrc`, `nvh264enc`/`qsvh264enc`/`amfh264enc`, `wasapi2src`, `webrtcbin`) | Không tự viết encoder/WebRTC. GStreamer có sẵn đúng bài toán, đã tối ưu, có plugin phần cứng cho cả 3 hãng GPU. Rust chỉ *điều khiển* nó. | 0 (dùng lib) |
| **Web/signaling** | **Rust** (`axum` + `tokio-tungstenite`) trong **cùng process** với core | Signaling là I/O, không phải hot path, nhưng ở cùng process thì tạo phiên/đổi cửa sổ không cần IPC. | ~1.5 kLOC |
| **Tray + settings UI** | **Rust** (tray menu) + **web UI cục bộ** (chính HTML/JS của client, mở ở `https://localhost/`) | Tránh kéo theo .NET runtime chỉ để làm 1 menu tray. Cấu hình dùng lại web UI ⇒ 1 bộ UI, không viết 2 lần. | ~0.3 kLOC |
| **Client** | **HTML + CSS + JavaScript ES2022** (ES modules, không bundler, không framework) | Trình duyệt là runtime duy nhất cần. Không build step ⇒ sửa 1 dòng là reload, debug trực tiếp trên máy khách. Có `// @ts-check` + JSDoc để VS Code vẫn bắt lỗi type. | ~1.8–2.5 kLOC |
| **Driver màn hình ảo** | **C** (VDD có sẵn, IddCx/WDK) | Kernel mode — **không tự viết**, dùng VDD (MIT). | 0 (reuse) |
| **Đóng gói** | **WiX (XML)** + **PowerShell** | MSI + đăng ký Task Scheduler + cài VDD/VB-Audio + kiểm tra môi trường. | ~600 dòng |
| **Test & CI** | **Python** (pytest + Playwright cho browser) + PowerShell | Điều khiển browser thật, đo latency, chạy ma trận §17.2. Không dùng Python ở runtime. | ~1.5 kLOC |
| **Công cụ đo** | **Python** (đọc barcode từ video camera) | §6.2.3 glass-to-glass. | ~200 dòng |

### 16.3 Vì sao **không** dùng một ngôn ngữ duy nhất
| Nếu chỉ dùng... | Vấn đề cụ thể |
|---|---|
| Rust thuần | Không vấn đề gì về kỹ thuật — nhưng UI cấu hình/tray phải viết bằng GUI toolkit (egui/tauri) ⇒ nặng hơn web UI dùng lại. **Đây vẫn là phương án dự phòng tốt nhất.** |
| C# thuần | WebRTC (SIPSorcery) chưa chắc có H.264 ổn; phải kéo .NET runtime + chờ GC pause trên đường capture (dù hiếm, pause 5–20 ms = 1 frame rơi). |
| C++ thuần | Nhanh nhất về lý thuyết, nhưng ~40% thời gian dev sẽ dành cho memory safety/UB ở đúng những chỗ (buffer cursor, mapped texture) khó debug nhất. |
| Go thuần | Capture phải CGO, encoder phải ffmpeg subprocess ⇒ +5–20 ms và thêm 1 process trên hot path. **Vi phạm luật §16.1.** |
| JS/Electron | Không có đường capture/encode đủ tốt; native addon = vẫn phải C++/Rust. |

### 16.4 Cái giá của đa ngôn ngữ (chấp nhận, có kiểm soát)
| Rủi ro | Cách kiểm soát |
|---|---|
| Nhiều toolchain (Rust, MSVC, GStreamer SDK, WiX, Python) | 1 script `bootstrap.ps1` cài hết, pin version; CI dùng cùng image. |
| Debug xuyên ngôn ngữ | Ranh giới rõ: Rust ⇄ C *chỉ* qua GStreamer API và Win32. **Không** có tầng "Rust gọi C# gọi Python". |
| Client JS khó bảo trì | ES modules + JSDoc types + `// @ts-check`; lint bằng `tsc --noEmit` trong CI, không thêm build step. |
| Bus factor | Tài liệu kiến trúc (§16.2) + hướng dẫn build trong README. |

### 16.5 Nếu sau này buộc phải tách process
Chỉ khi có lý do cứng (ví dụ: encoder crash làm sập web server). Khi đó:
- Không dùng JSON/gRPC trên hot path.
- Dùng **shared-memory ring buffer** (iceoryx hoặc mmap tự viết) cho frame + input event; control-plane mới dùng IPC thường.
- Đo lại §17.3 ngay; nếu p95 vượt 100 ms ⇒ quay lại single-process.

### 16.6 Dự phòng nếu Rust + GStreamer vướng
Phase 0 (§18) là cổng kiểm tra. Nếu `d3d11screencapturesrc` + `webrtcbin` không đạt, thứ tự thay thế:
1. Capture tự viết bằng Rust (`windows` crate + DDAPI trực tiếp) → đẩy frame vào `appsrc` → GStreamer chỉ encode/RTP.
2. Đổi `webrtcbin` → Pion (chạy như **sidecar process**, chấp nhận +3–8 ms ở chặng signaling/media, không ảnh hưởng chặng input).
3. C++ + GStreamer (Sunshine-style) nếu cả 2 cách trên thất bại.

## 17. Acceptance & test

### 17.1 Chức năng
1. Picker đúng; chọn → stream <2.5 s.
2. HVNC: cửa sổ không còn trên màn hình thật; loa thật im; client thấy + nghe.
3. VNC: thấy desktop thật.
4. Audio toggle: tắt → client im **và** loa thật vẫn im; bật → <1 s.
5. Input: click đúng 4 góc + giữa ở 100/125/150/200% DPI, 1 và 2 màn hình; hover hiện tooltip; drag; double-click; wheel dọc+ngang; nút 4/5.
6. Tiếng Việt: Telex "tieengs" → "tiếng"; emoji; paste chuỗi dài.
7. Keyboard: Ctrl+C/V/S; Alt+Tab; không gửi Win+L; Ctrl+W chuyển tiếp (Chrome).
8. Reset: giữ Ctrl → alt-tab → nhả → server không kẹt modifier; giữ chuột trái → mất mạng → server tự nhả ≤3 s.
9. Chuyển cửa sổ giữa phiên <1.5 s, không mất kết nối.
10. Resume sau F5.
11. Mã hoá: Wireshark chỉ thấy TLS/DTLS-SRTP.
12. Cleanup: đóng tab → 30 s sau cửa sổ restore, audio restore, không rò handle/VRAM.
13. Bảo mật: lockout; `sid` người khác → 403.

### 17.2 Ma trận test
OS (Win10 22H2, Win11 23H2/24H2) × DPI (100/125/150/200) × monitor (1, 2 cùng size, 2 khác size + phụ bên trái) × GPU (NVENC, QSV, AMF, x264) × browser (Chrome, Edge, Firefox, Safari mac, Chrome Android, Safari iOS) × mode (HVNC, VNC) × audio (có/không cable, cable mất giữa phiên) × app (Notepad, Chrome, Explorer, Office, admin/elevated, game borderless, Netflix, terminal) × trạng thái (bình thường, khoá console, UAC, RDP chiếm console) × mạng (LAN, WiFi 5% loss, Tailscale, đổi mạng) × thời lượng (10′, 2 h).

### 17.3 Tiêu chí "cảm giác dùng được" (đo được, không cảm tính)
| Chỉ số | Ngưỡng |
|---|---|
| **Cursor→photon** (cursor local) | **0 ms** — không có độ trễ cảm nhận |
| Input→photon p95, LAN | **< 80 ms** |
| Input→photon p95, WAN | < 200 ms |
| Không có "2 con trỏ" trong bất kỳ chế độ nào | 0 lần/10 phút |
| Kẹt modifier/nút sau 50 lần mất focus/thay đổi | **0 lần** |
| Double-click thành công (test 50 lần) | 100% |
| Hover hiện tooltip trong Explorer toolbar | 100% |
| Click chính xác ±1 px (crosshair trên ảnh) | 100% |
| Chuyển cửa sổ giữa phiên | < 1.5 s, không đen > 300 ms |
| Frame drop khi cuộn trang dài | < 2% |
| Thời gian tới "dùng được" từ mở URL | < 15 s (đã login) |

## 18. Roadmap

| Phase | Nội dung | Ước tính |
|---|---|---|
| **0** | **Spike (cổng quyết định):** Rust + GStreamer `d3d11screencapturesrc` → `webrtcbin` → browser 1080p60; DDAPI cursor shape + client render; đo glass-to-glass. **Nếu không đạt p95 <80 ms ⇒ đổi stack theo §16.6 trước khi viết tiếp.** | 1–1.5 tuần |
| 1 | Tier 1: auth, picker, HVNC move/restore, display ảo giữ, encoder auto-detect, input đầy đủ (§6.3–6.7), audio "hỏi mỗi phiên" + toggle, stealth S1, reconnect, resume, cleanup, uninstall | 5–7 tuần |
| 2 | Tier 2: clipboard, multi-session, multi-user/TOTP, allowlist, switch window/mode/monitor giữa phiên, preset, zoom local, handover, stealth S2 | 3–4 tuần |
| 3 | Tier 3 theo nhu cầu thực tế (file transfer, recording, TURN, whiteboard…) | — |
| — | Ma trận test §17.2 + hardening + đo lại §17.3 | 2 tuần |
| **Tổng** | | **≈ 12–15 tuần (1 dev)** |

## 19. Quyết định đã chốt & còn mở

### 19.1 Đã chốt (v3.1)
| # | Quyết định | Ghi ở |
|---|---|---|
| 1 | **Ngôn ngữ:** Rust (core + web + tray) · C/GStreamer (media) · HTML/JS (client) · Python (test/CI) · C (VDD có sẵn) · PowerShell+WiX (đóng gói). Luật: **hot path 1 process** | §16 |
| 2 | **GPU:** auto-detect lúc chạy + micro-benchmark + tự hạ preset; người dùng đổi tay được | §9.4.1 |
| 3 | **Mạng:** LAN trước (không STUN) → Tailscale/WireGuard/ZeroTier → port-forward+STUN (Phase 2) → TURN (T3). Một binary, khác config | §13 |
| 4 | **Audio:** hỏi mỗi phiên, nhớ theo app; toggle stream riêng; routing không tự đổi | §9.6 |
| 5 | **Quyền:** user thường mặc định; elevated là opt-in khi cài, có cảnh báo | §9.9b |
| 6 | **Stealth:** mặc định **S1 hidden** (ẩn taskbar + thumbnail); **S2 deep** opt-in (Alt+Tab giảm tối đa); toast + icon tray **không tắt được** | §2.4, §14 |

### 19.2 Còn mở — chỉ 3 câu, không chặn Phase 0
1. **Display ảo:** cố định 1920×1080@60 hay theo màn hình thật? *(mặc định spec: 1920×1080@60, đổi được per phiên — nếu bạn không nói gì tôi giữ mặc định)*
2. **Số người dùng:** 1 tài khoản cho chính bạn, hay nhiều người + role? *(mặc định: 1 admin; Tier 2 mới mở multi-user)*
3. **Tier 1 đã đủ cho bản đầu chưa?** *(mặc định: đủ — clipboard/multi-user để Phase 2)*

### 19.3 Ba cảnh báo tôi muốn bạn thấy trước khi tôi code
1. **`Ctrl+Alt+Del` và màn hình login/UAC sẽ không điều khiển được.** Cần service SYSTEM + Winlogon — tôi để Tier 3, mặc định không làm.
2. **Video DRM (Netflix/Prime) sẽ đen** trên màn hình ảo. Không có cách vượt.
3. **S1/S2 stealth có thể bị Windows Defender/EDR gắn cờ** vì bộ dấu hiệu (driver display ảo + ẩn taskbar + input injection + audio cable) trùng với RAT. Cách giảm: ký số binary + driver, không hook API, giữ thông báo tray, whitelist trong AV của tổ chức. Không có cách "chắc chắn không bị flag".
