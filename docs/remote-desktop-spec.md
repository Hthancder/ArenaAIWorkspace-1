# SPEC v3.8 — Remote Desktop qua trình duyệt: HVNC + VNC, window picker, âm thanh server-side, **trải nghiệm điều khiển đầy đủ**

- Phiên bản: **v3.8** (v3.7 + **§38 scaler & độ nét**: tách native vs post-scale, chọn scaler GPU, bậc thang tỉ lệ sạch, sharpening có điều kiện, giới hạn 4:2:0, phân loại text/motion, đo bằng OCR, chống UI nhảy): hai thiết bị một lõi — mobile zero-chrome, grip 3 tầng, radial 8 ô, command registry, flow contract FE↔BE**)
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
| v3.1 | §16 kiến trúc đa ngôn ngữ (Rust+C+JS+Python) · §13 LAN→Tailscale/ZeroTier · §9.6 audio "hỏi mỗi phiên" · elevated tuỳ chọn khi cài · §14 stealth đầy đủ (S1/S2) · §19 chốt quyết định |
| v3.2 | §20 tuỳ chỉnh cho người dùng (3 tầng, dịch ý định → tham số, độ phân giải = lựa chọn có tên) · §21 chẩn đoán, state coverage, error boundary, soak, updater, backup, chia sẻ, phía người bị điều khiển, pháp lý, quy trình test, rủi ro |
| v3.3 | §22 IA/tuyến đường · §23 design system (token, màu, chữ, chuyển động) · §24 đặc tả 12+ màn hình (dashboard, phiên, sheet, settings, admin, tray, wizard, mobile) · §25 component + ma trận state↔UI** · **§26 audit 20 nhóm: dữ liệu, API+lỗi, log, CLI, config reload, cert, proxy, môi trường cài, ma trận hỗ trợ, không third-party, ngân sách client, đa ngữ nhập liệu, clipboard chi tiết, chụp màn hình, thời gian, lưu trữ, ký số, lỗi browser, pin/data, help** · §27 trả lời thẳng |
| **v3.4** | **§28 hai thiết bị khác bản chất · §29 desktop chrome mỏng + phím tắt · §30 mobile zero-chrome (0 nút thường trực, grip 3 độ sâu, 13 gesture, radial 8 ô theo ngữ cảnh, bàn phím không che video, kính lúp/trackpad, one-hand) · §31 command registry 1 nguồn · §32 flow contract (1 controller, intent_id, rev, idempotency, bảng race, SLA) · §33 checklist 2 vỏ + Playwright song song** |
| **v3.5** | **§35 mô hình thực thi: 8 thread, 1 GStreamer pipeline/phiên, vòng đời frame + ownership, hàng đợi có trần + chính sách drop, ngân sách độ trễ phân rã tới từng chặng (gồm jitter buffer — khoản ẩn lớn nhất), timestamps từng chặng, screen-content tuning, chế độ màn hình tĩnh, restart/shutdown theo thứ tự, MMCSS, ngân sách bộ nhớ, 8 bất biến, fault-injection matrix** · §0.2 depth-first |
| **v3.6** | **§36 AI sở hữu gì vs thư viện · 3 nguồn CC + luật `min(...)` · phân loại 4 loại mất gói (nghẽn/ngẫu nhiên/burst/jitter) · máy trạng thái STARTUP/DRAIN/CRUISE/PROBE/BACKOFF có số + chống dao động · phân bổ budget theo thứ tự cứng (audio không bao giờ bị bóp) · IDR storm chống + intra-refresh · chọn FEC vs NACK theo RTT · playout-delay thích ứng · degradation preference theo preset · encoder rate-control · đổi mạng giữa phiên · 22 tham số · 7 profile netem + 7 chỉ số fail CI** |
| **v3.7** | **§37 ba vòng điều khiển lồng nhau (CC 200 ms / trim 500 ms / encoder 16 ms) · đo bitrate tại pacer là sự thật duy nhất · trim loop công thức · NVENC (`rc-mode=cbr`, VBV, zeroLatency, không multipass) · QSV (`BufferSizeInKB` bẫy 8×, LowDelayBRC, sai số lớn nhất) · AMF (EnforceHRD, không filler, yếu ở bitrate thấp) · x264 (`vbv-bufsize` bắt buộc + `sliced-threads` — thiếu là trễ 130 ms) · 10 bất biến chung · xung đột CBR↔tĩnh↔tiết kiệm pin · chi phí đổi cấu hình · giới hạn slot + fallback · 8 kiểm chứng · bảng ánh xạ 4 hãng** |
| **v3.8** | **§38 hai cơ chế hạ res (native vs post-scale) — §36.9 đã gộp sai · vì sao chữ chết (nội suy + 4:2:0 + deblock) · chọn scaler có số (bicubic/area GPU, cấm Lanczos cho text) · bậc thang tỉ lệ sạch 3/4 & 1/2 · sharpening có điều kiện (tắt khi <3 Mbps) · giới hạn 4:2:0 không vượt được · phân loại text/motion để chọn giảm fps hay res · chống UI nhảy khi đổi res · đo bằng **OCR CER** thay vì cảm tính** |

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

### 0.2 Cách spec này được hoàn thiện (depth-first, không rà rộng)

Một lượt rà rộng 20 chỗ thì chỗ nào cũng nông. Spec này được làm theo **một nhánh tại một thời điểm**: chọn chỗ thiếu **quan trọng nhất**, làm tới mức implement được, rồi ghi lại **những nhánh mới rẽ ra** từ chỗ đó, và đi tiếp.

**Hàng đợi nhánh (cập nhật mỗi lượt, theo thứ tự ưu tiên):**

| # | Nhánh | Trạng thái | Rẽ ra từ |
|---|---|---|---|
| 1 | **Mô hình thực thi pipeline thời gian thực** (thread, hàng đợi, buffer, drop, restart, shutdown, ngân sách độ trễ) | ✅ **xong — §35** | toàn bộ sản phẩm |
| 2 | **Transport tuning & điều tiết băng thông** (phân loại mất gói, máy trạng thái CC, budget alloc, IDR storm, FEC/NACK, playout-delay, ladder, CI netem) | ✅ **xong — §36** | §35.6 |
| 2a | **Encoder rate-control theo từng hãng** | ✅ **xong — §37** | §36.10 |
| 2b | **Scaler & độ nét khi hạ resolution** | ✅ **xong — §38** | §36.9, §37.9 |
| 2c | Đo TWCC/REMB trên GStreamer (probe element / Pion sidecar) | ⬜ **chặn Phase 0** | §36.1 |
| 2d | Chọn encoder theo nội dung & theo phiên (chấm điểm) | ⬜ | §37.10 |
| 2e | Ma trận driver/toolchain tối thiểu theo hãng | ⬜ | §37.12 |
| 2f | **BGRA→NV12 & HDR/tonemap trong cùng pass GPU** | ⬜ **kế tiếp** | §38.6 |
| 2g | Phân loại nội dung sâu hơn (text/motion/ảnh/game/DRM) | ⬜ | §38.7 |
| 3 | Fault injection & chaos harness (ACCESS_LOST, audio device mất, mạng đứt, driver reset) | ⬜ | §35.14 |
| 4 | Vòng đời cửa sổ & display (state machine + phục hồi sau crash) | ⬜ | §35.10 |
| 5 | Threat model theo từng bề mặt (HTTP/WS/DC/tray/driver/local) | ⬜ | §35.13 |
| 6 | Multi-session & chia sẻ tài nguyên (1 capture → N encode) | ⬜ | §35.4 |
| 7 | Client perf budget trong CI (đo thật, chặn merge) | ⬜ | §26.11 |
| 8 | Installer/uninstaller: hành vi chính xác + kiểm chứng rollback | ⬜ | §13.7 |
| 9 | Accessibility lượt sâu (screen reader, bàn phím, contrast thực đo) | ⬜ | §6.12 |
| 10 | Legal/consent UX & thoả thuận người bị điều khiển | ⬜ | §2.4 |

Nguyên tắc đi tiếp: **không mở nhánh mới khi nhánh hiện tại còn câu hỏi mở**, trừ khi nhánh mới chặn nhánh cũ.

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
1. ~~Display ảo~~ → **đã chốt ở §20.3**: 4 lựa chọn có tên (Vừa mắt / Chữ to / Nét / Như máy thật / Dọc), đổi được **giữa phiên** trong 2–4 s, nhớ theo thiết bị. Không có "1920×1080 cố định".
2. **Số người dùng:** 1 tài khoản cho chính bạn, hay nhiều người + role? *(mặc định: 1 admin; Tier 2 mới mở multi-user)*
3. **Tier 1 đã đủ cho bản đầu chưa?** *(mặc định: đủ — clipboard/multi-user để Phase 2)*

### 19.3 Ba cảnh báo tôi muốn bạn thấy trước khi tôi code
1. **`Ctrl+Alt+Del` và màn hình login/UAC sẽ không điều khiển được.** Cần service SYSTEM + Winlogon — tôi để Tier 3, mặc định không làm.
2. **Video DRM (Netflix/Prime) sẽ đen** trên màn hình ảo. Không có cách vượt.
3. **S1/S2 stealth có thể bị Windows Defender/EDR gắn cờ** vì bộ dấu hiệu (driver display ảo + ẩn taskbar + input injection + audio cable) trùng với RAT. Cách giảm: ký số binary + driver, không hook API, giữ thông báo tray, whitelist trong AV của tổ chức. Không có cách "chắc chắn không bị flag".

---

# PHẦN IV — NGƯỜI DÙNG & VẬN HÀNH

## 20. Tuỳ chỉnh cho người dùng — dễ, không cần biết kỹ thuật

> Yêu cầu của bạn: *"user là người dùng, họ muốn tuỳ chỉnh theo ý họ, nhưng phải dễ, không phải làm hành động kỹ thuật phức tạp"*.
> Chương này là **yêu cầu**, không phải gợi ý.

### 20.1 Mười nguyên tắc

| # | Nguyên tắc | Nghĩa là |
|---|---|---|
| 1 | **Cấu hình theo ý định, không theo tham số** | Người dùng không chọn "bitrate 8 Mbps"; họ chọn "hình nét hơn" hoặc "đỡ tốn data". Máy tự dịch. |
| 2 | **Không có nút "Lưu"** | Mọi thay đổi áp dụng ngay + có "Hoàn tác" 5 giây. Không có trạng thái "chưa áp dụng" gây bối rối. |
| 3 | **Không bao giờ bắt khởi động lại** | Thay đổi nào cần phiên mới thì ghi rõ "áp dụng từ phiên sau", không bắt làm lại. |
| 4 | **Ba tầng, mặc định chỉ thấy tầng 1** | Tầng 1 "Một chạm" (thứ dùng hằng ngày) · Tầng 2 "Cài đặt" (chữ thường, có giải thích) · Tầng 3 "Nâng cao" (kỹ thuật, mở 1 lần là nhớ). |
| 5 | **Mặc định phải đúng cho 90%** | Nếu người dùng không mở cài đặt gì, trải nghiệm vẫn tốt. Cài đặt là để *tinh chỉnh*, không phải để *dùng được*. |
| 6 | **Mỗi lựa chọn nói hậu quả bằng ví dụ** | Không phải "giảm bitrate" mà "dùng ít data hơn, hình hơi mờ khi chuyển động nhanh". |
| 7 | **Không hỏi lại điều đã trả lời** | Nhớ theo app/thiết bị; chỉ hỏi khi gặp tình huống mới. |
| 8 | **Sai thì tự sửa, và nói ra** | Bật một lựa chọn làm hỏng trải nghiệm → tự quay lại + thông báo, không để người dùng tự phát hiện. |
| 9 | **Không giấu tính năng sau thuật ngữ** | Tên nút dùng động từ thường: "Chữ to hơn", "Đỡ tốn data", "Cho xem màn hình dọc". |
| 10 | **Người dùng luôn thoát được** | Mọi màn hình cài đặt đóng được bằng `Esc`, không có modal chặn, không có bước "bắt buộc làm tiếp". |

### 20.2 Bảng dịch: người dùng nói gì → ta chỉnh gì

| Người dùng nói | Nút/nơi chỉnh | Ta thực sự đổi | Hiệu lực | Ảnh hưởng ai |
|---|---|---|---|---|
| "Chữ nhỏ quá" | `A+` trên toolbar (1 chạm) | zoom hiển thị local 125/150/200% | **tức thì** | chỉ mình |
| "Chữ vẫn nhỏ, tôi muốn app thật sự to" | `⚙ → Kích thước → Chữ to` | hạ độ phân giải display ảo (1280×720) ⇒ UI chiếm tỉ lệ lớn hơn | 2–4 s | cả phiên |
| "Hình mờ / chữ nhoè" | `⚙ → Chất lượng → Nét` | tăng bitrate, ưu tiên chi tiết, giảm khử nhiễu | 1–2 s | cả phiên |
| "Giật, chuột không mượt" | `⚙ → Chất lượng → Mượt` | 60 fps, bitrate thấp hơn, giảm resolution nếu cần | 1–2 s | cả phiên |
| "Tốn 4G quá" | `⚙ → Tiết kiệm data` | 720p30, 1.5 Mbps, tắt audio mặc định | 1–2 s | cả phiên |
| "Tôi xem trên điện thoại dọc" | `⚙ → Kích thước → Dọc` | display ảo 1080×1920 | 3–5 s | cả phiên |
| "Tôi muốn thấy đúng như máy thật" | `⚙ → Kích thước → Như máy thật` | display ảo = resolution màn hình vật lý | 3–5 s | cả phiên |
| "Không muốn nghe" | 🔊 trên toolbar | tắt stream audio (routing giữ nguyên) | tức thì | chỉ mình |
| "Chỉ muốn xem, không điều khiển" | nút "Chỉ xem" | view_only | tức thì | cả phiên |
| "Đừng hiện gợn sóng khi tôi bấm" | `⚙ → Phản hồi → Gợn sóng` | ripple off | tức thì | chỉ mình |
| "Không thấy con trỏ" | `⚙ → Con trỏ → To & viền` | tăng kích thước + viền tương phản | tức thì | chỉ mình |
| "Điện thoại: bấm cứ sai" | `⚙ → Cách chạm` | đổi "Chạm trực tiếp" ↔ "Như trackpad" | tức thì | chỉ mình |
| "Ẩn thanh công cụ" | ⛶ fullscreen | toolbar tự ẩn | tức thì | chỉ mình |
| "Gõ phím tắt bị đóng tab" | `⚙ → Bàn phím → Khoá phím` | keyboard lock (nếu browser hỗ trợ) | tức thì | chỉ mình |

**Quy tắc:** mỗi dòng trong bảng trên phải bấm được **≤ 2 lần** từ màn hình phiên. Nếu cần 3 lần trở lên ⇒ thiết kế sai, đưa ra ngoài hoặc bỏ.

### 20.3 Độ phân giải — ví dụ cụ thể của bạn, giải đúng

#### 20.3.1 Sự thật kỹ thuật làm việc này *dễ*
Màn hình ảo là **display ảo, không nối với cổng xuất vật lý**. Vì vậy đổi độ phân giải/refresh của nó:
- **Không cần đăng xuất** (khác hoàn toàn đổi độ phân giải màn hình thật — thứ thường bắt logoff/khởi động lại ở nhiều máy).
- **Không ảnh hưởng màn hình thật** của người ngồi máy (không nháy, không reflow icon của họ).
- Mất 2–4 s: `ChangeDisplaySettingsEx` trên monitor ảo → DWM re-composite → capture reinit → encoder reinit → keyframe.

⇒ Vì thế ta **cho người dùng chỉnh thoải mái**, kể cả giữa phiên. Đây là lý do thiết kế này dễ chịu: rào cản kỹ thuật của "đổi resolution" chỉ tồn tại với màn hình thật.

#### 20.3.2 Bốn lựa chọn hiện ra (không có con số trần)
| Nhãn hiển thị | Người dùng hiểu | Thực tế cấu hình | Ghi chú |
|---|---|---|---|
| **Vừa mắt** *(mặc định)* | "tự hợp với máy tôi" | `min(khả năng client, 1920×1080)`, tỉ lệ theo khung nhìn client (dọc nếu điện thoại dọc) | Không cần nghĩ |
| **Chữ to** | "cho tôi đọc dễ" | 1280×720 (UI ~1.5× to hơn trên cùng khung) | Dùng cho mắt kém, điện thoại |
| **Nét** | "cho tôi xem chi tiết" | 2560×1440 nếu client + GPU đủ, ngược lại 1920×1080 | Có kiểm tra GPU trước khi cho chọn |
| **Như máy thật** | "đúng bằng máy kia" | = resolution màn hình vật lý của server | Hữu ích khi hỗ trợ kỹ thuật |
| **Dọc** | "tôi xem tài liệu dài trên điện thoại" | 1080×1920 | Tự đề xuất khi client ở orientation dọc |
| *Tự chọn (Nâng cao)* | — | nhập W×H | Ẩn sau "Nâng cao" §20.14 |

- **Không bao giờ** hiện "1920×1080" ở tầng 1. Con số chỉ xuất hiện ở dòng phụ nhỏ (`1280×720 · 30 fps`) để người muốn biết vẫn thấy.
- Nếu chọn "Nét" mà GPU/CPU không kham được → nút vẫn bấm được, nhưng hiện ngay "Máy này hơi yếu cho mức này, có thể giật. [Vẫn thử] [Giữ mức cũ]" — **không chặn**, chỉ cảnh báo. Nếu thử 10 s mà rơi frame >10% → tự quay lại + toast "Đã tự quay lại mức trước cho mượt hơn".

#### 20.3.3 Khác biệt "to chữ" theo 2 cách — khi nào dùng cách nào
| Cách | Đổi gì | Ưu | Nhược |
|---|---|---|---|
| **Zoom local** (`A+`) | chỉ khung nhìn của mình, phóng to pixel | tức thì, không ảnh hưởng ai, không reflow app | ảnh nhoè khi phóng >150%; phải pan |
| **Hạ độ phân giải** | app thật sự render ở không gian lớn hơn | chữ nét, app bố cục lại đúng, không cần pan | 2–4 s, ảnh hưởng người xem khác |
- Mặc định `A+` (nhẹ, tức thì). Nếu người dùng bấm `A+` **2 lần trong 1 phiên** → gợi ý một lần: *"Muốn chữ nét hơn? Đổi sang mức 'Chữ to' (áp dụng cho cả phiên)."* — dạy đúng lúc, không làm phiền.
- **DPI scale 125/150%** = tầng Nâng cao, có cảnh báo: một số app phải khởi động lại mới nhận; app cũ có thể vẽ lệch. Không đưa vào tầng 1 vì hậu quả không đoán trước được.

#### 20.3.4 Nhớ & đồng bộ
- Nhớ theo **thiết bị** (điện thoại ≠ laptop): mở trên điện thoại → tự "Vừa mắt" dọc 720p; mở trên laptop → "Vừa mắt" 1080p. Người dùng không phải chỉnh lại.
- Đổi tay thì ghi nhớ theo thiết bị đó + theo app (nếu người dùng chọn "nhớ cho app này").
- Chính sách của tổ chức (nếu admin đặt trần) **thắng** lựa chọn người dùng; UI ghi "Quản trị viên giới hạn mức này" thay vì disable im lặng.

### 20.4 Chất lượng & độ mượt
- 3 nút ở tầng 1: **Nét** · **Cân bằng (mặc định)** · **Mượt**. Thêm **Tiết kiệm data** (điều kiện: mạng chậm hoặc người dùng bật).
- `Tự động` luôn bật mặc định: máy tự điều chỉnh trong biên ±. Người dùng chọn tay → khoá auto 10 phút rồi tự bật lại (có toast "Đã bật lại tự động").
- Dòng phụ hiện số liệu thật (`8.2 Mbps · 58 fps · 42 ms`) — cho người tò mò, không bắt ai đọc.
- Nếu người dùng chọn "Nét" mà mạng không đủ → hiện "Mạng đang yếu, mức này sẽ giật. [Đổi sang Mượt]".

### 20.5 Cách hiển thị
| Nhãn | Hành vi | Nhớ |
|---|---|---|
| **Vừa khung** (mặc định) | letterbox, đúng toạ độ | theo thiết bị |
| **Đầy màn hình** | crop mép, pan để xem | theo phiên |
| **Đúng điểm ảnh** | 1:1, có thanh cuộn | theo thiết bị |
| **Phóng to** (`A+`, pinch) | 125/150/200% | reset mỗi phiên |
- Chuyển chế độ bằng 1 nút xoay vòng trên toolbar (hiện nhãn hiện tại), không mở menu.
- Khi crop/zoom: luôn có **mini-map** nhỏ ở góc để biết đang xem phần nào của màn hình.

### 20.6 Con trỏ & phản hồi (cho người mắt kém / tay run)
| Lựa chọn | Mặc định | Ghi chú |
|---|---|---|
| Kích thước con trỏ | theo server | có mức "To hơn" và "Rất to" (phóng bitmap, không vỡ nếu ≤200%) |
| Viền tương phản quanh con trỏ | bật khi nền tối? → mặc định **bật nhẹ** | giúp thấy con trỏ trên nền đen (terminal) |
| Gợn sóng khi bấm | bật trên mobile, tắt trên desktop | tắt được 1 chạm |
| "Điểm nhấn" khi double click | tắt | tránh nhiễu |
| Ẩn con trỏ khi chỉ xem | bật | |

### 20.7 Bàn phím & chạm
- **Cách chạm** (mobile): `Chạm trực tiếp` / `Như trackpad` / `Chạm kèm kính lúp (mặc định)`. Ba lựa chọn, có hình minh hoạ động 1 giây.
- **Bàn phím**: hàng phím phụ bật/tắt; vị trí toolbar (dưới/trên); sticky modifier (mặc định bật).
- **Phím tắt của app**: danh sách cố định, hiện trong `⚙ → Trợ giúp phím tắt` (không cho đổi — tránh phá tính nhất quán; đây là chỗ duy nhất ta **không** cho tuỳ chỉnh, và nói rõ lý do).

### 20.8 Âm thanh
- Thanh âm lượng **của riêng mình** (client) — mặc định 70%, nhớ theo thiết bị. Tắt tiếng có nút riêng.
- Nhớ trạng thái tắt tiếng theo app.
- Không có EQ/mixer ở tầng 1; "âm lượng app trên server" là **Nâng cao** (vì nó đổi âm lượng thật của người ngồi máy — xâm lấn).

### 20.9 Ngôn ngữ & định dạng
- `Tiếng Việt` (mặc định) / `English`; tự theo ngôn ngữ trình duyệt lần đầu.
- Định dạng ngày/giờ theo locale; 24h/12h chọn được. Thời lượng phiên hiện "1 giờ 12 phút", không phải "72m".

### 20.10 Giao diện
- Sáng / Tối / Theo hệ thống (mặc định).
- Cỡ chữ UI: Nhỏ / Vừa / Lớn (mặc định Vừa) — áp dụng cả toolbar, không chỉ settings.
- Tương phản cao (mặc định theo `prefers-contrast`).
- Mật độ: thoáng / gọn.
- **Không** cho đổi màu tuỳ ý (tránh phá khả năng đọc và trạng thái ngữ nghĩa).

### 20.11 Thông báo
| Loại | Mặc định | Chọn được |
|---|---|---|
| Cửa sổ bị đóng / app crash | banner | có |
| Có người đang dùng máy | banner vàng | có |
| Mạng yếu | tự ẩn sau 3 s, không lặp | có (mức: tất cả / chỉ quan trọng / tắt) |
| Đã tự đổi chất lượng | toast nhỏ | có |
| Kết nối lại thành công | không hiện (chỉ trạng thái) | có |
- Không có notification đẩy ra ngoài trang (không Web Push) — tránh xin quyền thừa.

### 20.12 Lưu & đồng bộ — ai thắng ai
| Loại cài đặt | Lưu ở | Đồng bộ |
|---|---|---|
| Chính sách (trần chất lượng, allowlist, stealth level, bật/tắt audio) | server | admin đặt, **thắng** mọi thứ |
| Sở thích hiển thị (fit/zoom, theme, cỡ chữ UI, ngôn ngữ) | server theo user | mọi thiết bị của user |
| Sở thích theo thiết bị (mức chất lượng cho điện thoại, cách chạm) | localStorage | chỉ thiết bị đó |
| Theo app (audio route, hide taskbar) | server theo app | mọi phiên của app đó |
Thứ tự thắng: **chính sách > user > thiết bị**. Khi bị chính sách chặn → ghi rõ lý do, không disable im lặng.

### 20.13 Hoàn tác, mặc định, xuất/nhập
- Mỗi thay đổi: toast có **Hoàn tác** 5 s.
- Mỗi mục: "Về mặc định" (↺ nhỏ bên phải) — chỉ hiện khi khác mặc định.
- Mỗi nhóm: "Đặt lại nhóm này".
- Toàn bộ: `⚙ → Nâng cao → Xuất cấu hình` (JSON) / `Nhập` — để chuyển máy hoặc nhờ hỗ trợ.
- Thay đổi **nguy hiểm** (đổi default audio device, bật elevated, tắt thông báo…) → có bước xác nhận **một lần**, không hỏi lại.

### 20.14 Tầng "Nâng cao" — chứa gì và mở thế nào
- Mở bằng `⚙ → Nâng cao → Tôi hiểu các thiết lập này` (một lần, nhớ theo user).
- Chứa: resolution tự chọn, DPI scale, encoder, bitrate/fps thật, cursor mode, kênh datachannel, debug barcode, đo glass-to-glass, công cụ chẩn đoán, xuất log.
- **Không bao giờ** chứa thứ mà bật sai sẽ làm mất dữ liệu hoặc phá máy (ví dụ: không có "tắt mã hoá", không có "tắt audit", không có "chạy như SYSTEM").

### 20.15 Lần đầu dùng — 4 bước, ≤ 60 giây
1. **Đăng nhập** (1 màn hình).
2. **Chọn cửa sổ** — chỉ tay vào 3 chỗ: thumbnail, tìm kiếm, nút Start. Có nút "Bỏ qua".
3. **Điều khiển** — 3 điều duy nhất cần biết: kéo chuột = di chuyển, click = click, gõ = gõ; và `Esc Esc` = dừng điều khiển.
4. **Chất lượng** — "Nếu thấy giật, bấm vào đây" (mở đúng nút).
Không tour dài, không video, không bắt đọc. Có "Xem lại hướng dẫn" trong `⚙ → Trợ giúp`.

### 20.16 Trạng thái rỗng & lỗi — luôn có hành động
| Trạng thái | Không được làm | Phải làm |
|---|---|---|
| Không có cửa sổ nào | "Không có dữ liệu" | "Chưa có cửa sổ nào đang mở trên máy đó. Mở app bạn cần rồi bấm [Tải lại]." |
| Không có quyền xem app đó | disable nút | "App này không nằm trong danh sách được phép. Liên hệ quản trị viên." |
| Mất kết nối >30 s | spinner vô tận | "Đã mất kết nối. [Thử lại] [Chọn cửa sổ khác]" + nhớ cửa sổ cũ |
| Thiếu driver | lỗi kỹ thuật | "Máy chưa cài màn hình ảo. [Cài tự động] (1 phút)" |
| GPU yếu | im lặng giật | "Máy này phù hợp 1080p30" hiện ở picker trước khi Start |

### 20.17 Mobile
- Cài đặt mở bằng **bottom sheet** (không phải modal giữa màn hình), kéo xuống để đóng, nằm trong vùng ngón cái.
- Mỗi mục cao ≥44 px. Không có dropdown nhỏ.
- Thanh trên gộp còn 3 nút + menu `⋯`.
- Không có hover-only hint — mọi gợi ý phải hiện được khi chạm.

### 20.18 Accessibility của chính phần cài đặt
- Điều hướng bằng bàn phím đầy đủ, `Esc` đóng, focus bị giữ trong sheet.
- Mọi toggle có `role="switch"` + `aria-checked`; mọi slider có `aria-valuetext` đọc được ("8 trên 10").
- Không truyền tải bằng màu đơn thuần.
- `prefers-reduced-motion` → tắt animation minh hoạ (thay bằng ảnh tĩnh).
- Kiểm tra với trình đọc màn hình (NVDA) các luồng: login → picker → đổi chất lượng → thoát.

### 20.19 Cách viết chữ (để "dễ" thật sự)
| ❌ Không viết | ✅ Viết |
|---|---|
| Bitrate / FPS / Codec / Latency | Lượng dữ liệu / Độ mượt / (không hiện) / Độ trễ |
| Session | Phiên (hoặc "lần kết nối") |
| Đang khởi tạo peer connection | Đang kết nối… |
| 412 driver_missing | Máy chưa cài màn hình ảo. [Cài ngay] |
| UIPI chặn input | App này chạy quyền quản trị nên có thể không điều khiển được |
| Reconnect failed | Không kết nối lại được. [Thử lại] |
- Câu ≤ 12 từ, chủ động, có chủ thể. Lỗi luôn kèm **một** hành động.

### 20.20 Những thứ **không** cho tuỳ chỉnh (và nói rõ lý do)
| Không cho đổi | Vì sao |
|---|---|
| Tắt mã hoá / hạ TLS | Không thể thoả hiệp bảo mật |
| Tắt audit | Cần cho trách nhiệm & điều tra |
| Tắt thông báo tray "đang bị điều khiển" | §2.4.2 |
| Chọn codec bằng tay | H.264 luôn đúng; chọn sai = không xem được |
| Tự đổi default audio device mà không xác nhận | Nguy cơ làm câm máy (§5.10.3) |
| Chạy như SYSTEM / service | §2.3 |
| Hook hệ thống | §14.3 |
- Nguyên tắc: **tuỳ chỉnh để phù hợp, không phải để vô hiệu an toàn**. Chỗ nào bị giới hạn thì UI nói lý do bằng 1 câu, không giấu.

## 21. Những gì còn thiếu (ngoài spec v3.1) — nhìn rộng

Chương này là kết quả rà lại **toàn hệ thống** theo các trục: vận hành, người dùng, pháp lý, chất lượng, tiến hoá. Mỗi mục đều đã có quyết định, không phải danh sách "để sau".

### 21.1 Chẩn đoán & sửa lỗi (thiếu hoàn toàn ở v3.1)
Người dùng sẽ gặp: "không kết nối được", "giật", "không có tiếng", "gõ không ra chữ". Không thể bắt họ đọc log.

**Nút "Chẩn đoán" (Tier 1, một chạm)** — chạy 12 kiểm tra song song, hiện bảng đơn giản:

| Kiểm tra | Nếu fail → câu chữ + hành động |
|---|---|
| Phiên bản app/tray còn chạy | "Ứng dụng chưa chạy trên máy đó. [Khởi động lại]" |
| Driver màn hình ảo | "Chưa cài màn hình ảo. [Cài tự động]" |
| Thiết bị âm thanh ảo | "Chưa cài dây âm thanh ảo. [Cài]" hoặc "[Tiếp tục không có tiếng]" |
| Encoder khởi tạo | "Máy không có bộ mã hoá phần cứng → dùng CPU (chậm hơn)" |
| Cổng 443 nghe được | "Tường lửa đang chặn. [Sửa tự động]" (cần admin) |
| UDP media (thử 100 gói) | "Tường lửa/router chặn UDP → chất lượng sẽ kém" |
| ICE candidate + STUN | "Mạng chặn kết nối trực tiếp. [Xem hướng dẫn VPN]" |
| Cert HTTPS | "Chứng chỉ không hợp lệ. [Tạo lại]" |
| Màn hình ảo nhận được tín hiệu | "Màn hình ảo không hoạt động. [Khởi động lại driver]" |
| Quyền điều khiển (UIPI) | "Bạn cần chạy ứng dụng bằng quyền quản trị để điều khiển app này" |
| Đo latency 5 s | "Độ trễ hiện tại: 42 ms — tốt" |
| Đo băng thông 5 s | "Băng thông: ~38 Mbps — đủ cho 1080p60" |

- Kết quả: **1 nút "Sửa những gì sửa được"** (firewall rule, khởi động lại driver, cài thiếu) + nút "Sao chép báo cáo" (JSON, **không chứa** nội dung phiên, không chứa mật khẩu, có ảnh chụp stats).
- Tự chạy **một lần** khi kết nối thất bại 2 lần liên tiếp, hiện kết quả thu gọn ("Có 1 vấn đề: tường lửa chặn UDP. [Xem]").

### 21.2 Trạng thái → hành động (state coverage)
Mọi trạng thái phải có: **câu giải thích + 1 hành động chính + đường thoát**. Bảng đầy đủ:

| Trạng thái | Câu | Hành động chính |
|---|---|---|
| Chưa đăng nhập | "Đăng nhập để xem các cửa sổ" | form |
| Đăng nhập sai | "Sai tên hoặc mật khẩu (còn 4 lần thử)" | thử lại |
| Bị khoá | "Tạm khoá 14:32 — thử lại sau" | đếm ngược |
| Không có cửa sổ | §20.16 | Tải lại |
| Đang chuẩn bị | "Đang chuẩn bị màn hình… 2 s" | Huỷ |
| Đang kết nối | "Đang kết nối…" | Huỷ |
| Đang chạy | — | (toolbar) |
| Đang chuyển cửa sổ | "Đang chuyển…" | Huỷ (giữ cửa sổ cũ) |
| Mạng yếu | "Mạng yếu — đã giảm chất lượng" | chi tiết |
| Mất kết nối, đang thử lại | "Đang kết nối lại… (2/8)" | Thử lại ngay / Kết thúc |
| Mất kết nối hẳn | §20.16 | Thử lại / cửa sổ khác |
| App bị đóng | "App đã đóng trên máy đó" | chọn cửa sổ khác |
| Máy bị khoá | "Máy đang khoá — cần mở khoá trên máy thật" | (không có) + giải thích |
| Chỉ xem | nhãn mắt | Yêu cầu quyền điều khiển (T2) |
| Bị admin đóng | "Quản trị viên đã kết thúc phiên" | OK |
| Hết thời gian | "Đã hết thời gian (12 giờ)" | tạo lại |

### 21.3 Xử lý lỗi phía client (chưa có ở v3.1)
| Tình huống | Hiện tại (v3.1) | Phải làm |
|---|---|---|
| JS lỗi giữa phiên | trắng màn hình, treo | **Error boundary**: bắt `window.onerror` + `unhandledrejection` → hiện "Có lỗi, đang khôi phục…" → reload trang (session còn sống nhờ grace 30 s + resume §6.11.1) |
| Mất WS | đã có | + banner nhỏ, không chặn video |
| Không tạo được RTCPeerConnection | im lặng | "Trình duyệt này không hỗ trợ WebRTC" + gợi ý |
| Trình duyệt quá cũ | có thể lỗi khó hiểu | kiểm tra capability **trước khi login** → trang "trình duyệt chưa hỗ trợ" với danh sách |
| Hết bộ nhớ (phiên dài, tab khác nặng) | video đứng | phát hiện `video.played` không tiến → gợi ý reload |
| Storage bị chặn (chế độ riêng tư) | lỗi im lặng khi ghi localStorage | try/catch, chạy không lưu |
| Tab bị kill (Android) | mất phiên | resume + thông báo |
| `navigator.mediaDevices` không có | — | không dùng, nhưng kiểm tra |
| Autoplay audio bị chặn | có | + phát hiện `play()` reject → hiện nút |

### 21.4 Tính bền & tài nguyên (thiếu)
| Vấn đề | Rủi ro thật | Giải pháp |
|---|---|---|
| Phiên chạy nhiều ngày | rò rỉ handle/VRAM → crash | soak test 72 h trong CI; đếm handle (`GetGuiResources`) mỗi phút, cảnh báo khi tăng đơn điệu; tự khởi động lại capture pipeline nếu rò |
| Tray app crash | mất điều khiển giữa phiên | Task Scheduler restart-on-failure + state file restore (§9.2.4) + client thấy `closed` |
| Mất điện khi đang move cửa sổ | cửa sổ mồ côi trên display ảo | state file ghi **trước** khi move; khởi động lại → rescue (§9.2.3) |
| Ổ đĩa đầy (log) | app chết | log rotate 10 MB × 5, không log frame |
| Rò rỉ VRAM nhiều phiên | GPU hết bộ nhớ | đóng duplication đúng thứ tự; đo VRAM/phiên; giới hạn phiên |
| RAM tăng theo thời gian | OOM | mỗi module có trần buffer; drop thay vì queue |
| Driver VDD lỗi | không capture được | phát hiện + hướng dẫn cài lại + đường lui: capture màn hình thật (chế độ suy giảm) |
| Nâng cấp app khi đang có phiên | phiên chết giữa việc | updater kiểm tra phiên đang chạy → hoãn, hoặc hỏi |

### 21.5 Cập nhật & phiên bản
- **Auto-update có kênh** (stable/beta), ký số, kiểm tra chữ ký trước khi chạy.
- **Không tự cập nhật khi đang có phiên**; hiện "Có bản mới — cập nhật khi kết thúc phiên".
- Kiểm tra tương thích: server cũ + client mới → API có version, server trả `min_client`. Ngược lại client cũ + server mới → giữ tương thích 2 phiên bản gần nhất.
- **Migration**: config/state file có `schema_version` + migrate một chiều, có backup trước khi migrate.
- Rollback: giữ 1 bản trước, cho phép quay lại trong 7 ngày.
- Release note hiện **trong app** (không bắt vào web).

### 21.6 Backup & phục hồi cấu hình
- Export/import JSON (đã có §20.13) + backup tự động trước mỗi lần migrate.
- Khôi phục mật khẩu admin: mã hoá bằng DPAPI machine-scope; nếu mất → quy trình reset **offline** (dừng app, chạy `rd.exe reset-admin` tại máy, cần quyền admin OS) — không có "email reset".
- Nếu mất khoá ký JWT → mọi phiên bị đăng xuất, người dùng đăng nhập lại (chấp nhận).

### 21.7 Chia sẻ & cộng tác (Tier 2, đã có handover — bổ sung)
| Tính năng | Chi tiết |
|---|---|
| **Link xem tạm** | tạo link một lần, hết hạn 1–24 h, chỉ view-only, thu hồi được, có audit. Link = token ngẫu nhiên 256-bit, **không** phải mật khẩu user |
| **Xem cùng lúc (2 người)** | 1 người điều khiển + 1 người xem; người xem không chiếm quyền; hiện "2 người đang xem" |
| **Chuyển quyền điều khiển** | nút "Cho [tên] điều khiển" — nguyên tử (atomic), release_all trước khi chuyển (tránh kẹt input) |
| **Xin quyền** | người xem bấm "Xin điều khiển" → người đang điều khiển nhận thông báo chấp nhận/từ chối |
| **Ghi chú trên màn hình (T3)** | whiteboard có nút xoá tất cả; không lưu |

### 21.8 Người dùng phía máy bị điều khiển
- **Icon tray** đổi trạng thái + tooltip "Ai đang điều khiển, từ đâu, bao lâu".
- **Menu tray**: "Xem ai đang kết nối" · "Dừng điều khiển ngay" (ngắt phiên, **không** cần quyền của người điều khiển) · "Chặn người này".
- **Phím tắt khẩn cấp tại máy**: `Ctrl+Alt+Shift+X` → ngắt mọi phiên ngay (hoạt động cả khi app treo UI, vì là hotkey toàn cục do app đăng ký).
- Trước khi phiên bắt đầu: nếu `presence` báo có người đang dùng máy, tray hiện "Sắp có người điều khiển cửa sổ X" 2 s trước (trừ khi đã cấu hình tắt cái này — nhưng vẫn giữ §2.4.2).
- **Người ngồi máy luôn có quyền dừng** — đây là nguyên tắc, không phải tuỳ chọn.

### 21.9 Ranh giới pháp lý & tuân thủ (bổ sung, không phải luật sư)
| Vấn đề | Cách xử lý trong sản phẩm |
|---|---|
| Ghi hình phiên (T3) | mặc định **tắt**; nếu bật, **cả 2 phía** thấy chỉ báo đỏ "đang ghi"; lưu mã hoá; tự xoá sau N ngày (cấu hình) |
| Dữ liệu cá nhân (GDPR-style) | audit giữ 90 ngày cấu hình được; export/xoá theo user; không log nội dung (§9.10) |
| Clipboard ảnh (có thể chứa dữ liệu nhạy cảm) | chỉ explicit, có audit, có thể tắt toàn cục |
| Người dùng ở nước khác | cảnh báo trong docs: mã hoá đúng, nhưng luật nơi bạn dùng có thể yêu cầu thông báo/đồng ý |
| Log chứa IP | IP là dữ liệu cá nhân ở nhiều nơi → nói rõ trong chính sách lưu trữ |

### 21.10 Hỗ trợ khách hàng / vận hành
- **Gói chẩn đoán** (1 file zip): version, config (đã lọc secret), 500 dòng log cuối, kết quả 12 kiểm tra §21.1, thông tin GPU/driver/OS. **Không** chứa mật khẩu/khoá/frame.
- **Xem trước khi gửi**: hiện nội dung gói, người dùng thấy hết trước khi tải lên (không tự upload).
- Tài liệu: 1 trang "Không kết nối được" với 8 nguyên nhân phổ biến theo thứ tự tần suất thực.

### 21.11 Chất lượng & quy trình (engineering)
| Việc | Khi nào |
|---|---|
| Unit test phần thuần (protocol, mapping toạ độ, state machine) | mỗi commit |
| **Test toạ độ tự động**: ảnh mẫu + crosshair 4 góc + giữa, 4 mức DPI, 2 cấu hình màn hình → so pixel | mỗi PR |
| **Test kẹt input**: 20 kịch bản blur/mất mạng | mỗi PR |
| E2E Playwright: login → picker → phiên → đổi chất lượng → thoát | mỗi PR |
| Soak 72 h | hàng đêm |
| Đo §17.3 (glass-to-glass) | mỗi release |
| Fuzz protocol (REST + WSS + datachannel) | mỗi tuần |
| Quét dependency (RustSec, GStreamer CVE) | hàng tuần |
| Test trên máy thật (ma trận §17.2) | mỗi release |
| Đo bundle/latency **client** trên điện thoại cũ (4 năm) | mỗi release |

### 21.12 Rủi ro & phương án (top 8)
| Rủi ro | Khả năng | Ảnh hưởng | Giảm thiểu |
|---|---|---|---|
| Phase 0 không đạt 80 ms | Trung bình | Cao | §16.6 đường lui; quyết định sau 1 tuần, không sau 6 tuần |
| VDD không ổn định trên Win11 build mới | Trung bình | Cao | Kênh Amyuni IDD (thương mại) làm dự phòng; test sớm |
| Defender/EDR gắn cờ (S1/S2) | **Cao** | Cao | Ký số, không hook, giữ thông báo tray, tài liệu whitelist, **không** hứa "không bị flag" |
| Per-app audio API không ổn định theo build | Trung bình | Trung bình | Fallback đổi default device (có watchdog) + hướng dẫn Volume Mixer |
| GStreamer webrtcbin khó dùng | Trung bình | Trung bình | Spike 3 ngày với 1 luồng tối giản trước khi cam kết; thay bằng Pion sidecar |
| Scope creep (Tier 3) | Cao | Trung bình | Tier 1 chốt cứng; mọi thêm mới phải cắt thứ khác |
| Bus factor 1 dev | Cao | Cao | Tài liệu kiến trúc + test tự động + không dùng công nghệ quá lạ |
| Người dùng không đọc hướng dẫn | Cao | Thấp | §20.15/§20.16 + chẩn đoán tự động |

### 21.13 Kế hoạch đo & tiêu chí "phase xong"
| Phase | Xong khi |
|---|---|
| 0 | 1080p60, p95 <80 ms LAN đo bằng barcode; cursor local 0 ms; quyết định stack được ghi lại |
| 1 | 13 mục §17.1 pass; 0 lần kẹt input trong 50 thử; uninstall sạch (máy trở lại như trước); soak 24 h không rò |
| 2 | §21.7 hoạt động; multi-user; chẩn đoán §21.1 pass trên 3 máy khác cấu hình |
| 3 | theo nhu cầu thực tế |

### 21.14 Những thứ **cố tình không làm** (ghi để không ai hỏi lại)
| Không làm | Lý do |
|---|---|
| Điều khiển màn hình login/UAC | §2.3 |
| Hidden desktop `WinSta0\HVNC` | §5.2 (mất state, giống malware) |
| Hook API / `SetWindowsHookEx` | §14.3 |
| Giấu process khỏi Task Manager | §14.5 |
| SFU/nhiều người xem hàng loạt | không cần; P2P đủ |
| App native mobile | yêu cầu là browser |
| HDR streaming | chỉ tonemap |
| Cloud relay | tự chủ, không phụ thuộc bên thứ ba |
| TURN mặc định | §13.1 |
| Đa nền tảng server (macOS/Linux lúc này) | kiến trúc Windows-first; ghi nhận là hướng mở rộng |

### 21.15 Hướng mở rộng sau này (không cam kết)
- Server trên macOS (ScreenCaptureKit) / Linux (PipeWire + XDG portal) — dùng lại client, đổi core.
- Điều khiển **nhiều máy** từ 1 dashboard (danh sách máy → cửa sổ).
- "Text mode" cho mạng cực yếu (chỉ gửi diff UI dạng ảnh nhỏ/vector).
- Chia sẻ ứng dụng cho 2–3 người xem đồng thời qua SFU nhỏ (LiveKit) — chỉ khi có nhu cầu thật.

---

# PHẦN V — THIẾT KẾ GIAO DIỆN

## 22. Kiến trúc thông tin & tuyến đường (IA)

### 22.1 Sơ đồ
```
/                          → chuyển hướng theo trạng thái đăng nhập
├── /login                 → đăng nhập (+TOTP)
├── /windows               → DASHBOARD: cửa sổ + phiên đang mở + trạng thái máy
├── /s/:sid                → PHIÊN ĐIỀU KHIỂN (toàn màn hình)
│     ├── overlay: chuyển cửa sổ (window switcher)
│     ├── overlay: chẩn đoán nhanh
│     └── sheet: cài đặt phiên
├── /settings              → cài đặt (5 tab)
├── /diagnostics           → chẩn đoán 12 bước (§21.1)
├── /admin                 → quản trị (chỉ role admin)
│     ├── /admin/users
│     ├── /admin/sessions
│     ├── /admin/audit
│     ├── /admin/policy
│     └── /admin/server
├── /help                  → trợ giúp + phím tắt + khắc phục sự cố
├── /403 · /404 · /offline → trang lỗi (luôn có 1 hành động)
└── /s/new?wid=..&mode=..  → deep link tạo phiên (sau khi login)
```
**Quy tắc:** tối đa **2 lần bấm** từ bất kỳ đâu tới phiên đang chạy. Không có menu nhiều cấp. Không có trang nào không tới được từ đâu (mọi trang đều có đường về `/windows`).

### 22.2 Điều hướng
| Từ | Tới | Cách |
|---|---|---|
| Login | Dashboard | tự động |
| Dashboard | Phiên | bấm card cửa sổ → chọn "Điều khiển" |
| Dashboard | Phiên đang mở | bấm tile "Tiếp tục" |
| Phiên | Dashboard | nút `←` (có xác nhận nếu đang điều khiển) |
| Bất kỳ | Cài đặt | avatar → Cài đặt, hoặc `Ctrl+,` |
| Bất kỳ | Trợ giúp | avatar → Trợ giúp, `?` |
- Trình duyệt Back trong phiên = **rời phiên** (cần xác nhận sau khi đã điều khiển >5 s; dưới 5 s thì thoát ngay để tránh ma sát).
- Không dùng SPA router phức tạp: mỗi trang là 1 HTML nhỏ, chia sẻ 1 module JS. Đơn giản hơn, back/forward hoạt động tự nhiên.

### 22.3 Phân quyền theo vai
| Vai | Thấy gì |
|---|---|
| `admin` | tất cả + `/admin` + mọi phiên (kể cả của người khác) |
| `user` | dashboard của mình, phiên của mình, cài đặt của mình |
| `viewer` | chỉ xem; không nút điều khiển; ribbon "Chỉ xem" |
| link tạm (§21.7) | **duy nhất** 1 phiên được chia sẻ; không có dashboard, không có avatar, không cài đặt; hết hạn → trang "Link đã hết hạn" |

---

## 23. Hệ thống thiết kế (design system)

### 23.1 Token — lưới & khoảng cách
- Đơn vị gốc **4 px**. Thang: `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`.
- Mọi khoảng cách/kích thước dùng token, **không** số lẻ tuỳ ý.
- Bán kính: `r-sm 6` · `r-md 10` · `r-lg 14` · `r-full 999`.
- Viền: `1px` cho mặc định, `2px` cho trạng thái chọn/focus.
- Đổ bóng: **ưu tiên viền + nền chênh lệch**, chỉ dùng shadow cho overlay (sheet, popover, toast).

### 23.2 Token — màu (vai trò, không phải mã màu)
| Token | Dùng cho | Ghi chú |
|---|---|---|
| `bg` | nền trang | |
| `surface` | card, panel | |
| `surface-2` | hover, input | |
| `border` | viền | đạt 3:1 với nền |
| `text` | chữ chính | 4.5:1 |
| `text-muted` | chữ phụ | ≥4.5:1 với surface |
| `accent` | hành động chính, focus | |
| `danger` | dừng, xoá, mất kết nối | kèm icon, không chỉ màu |
| `warn` | mạng yếu, ai đó đang dùng máy | |
| `ok` | kết nối tốt | |
| `info` | gợi ý | |
- **Dark mặc định ở màn hình phiên** (để video là thứ sáng nhất); dashboard/settings theo hệ thống.
- Không dùng màu để truyền tải trạng thái một mình: luôn kèm chữ hoặc icon (§6.12).
- Kiểm tra mù màu: cặp ok/warn/danger có độ sáng khác nhau + khác icon.

### 23.3 Chữ
| Vai | Cỡ / đậm / cao dòng | Dùng cho |
|---|---|---|
| `h1` | 24 / 600 / 1.3 | tiêu đề trang |
| `h2` | 20 / 600 / 1.35 | tiêu đề nhóm |
| `body` | 14 / 400 / 1.5 | mặc định |
| `body-strong` | 14 / 500 | nhãn nút, tên cửa sổ |
| `small` | 13 / 400 / 1.45 | phụ, mô tả dưới nhãn |
| `caption` | 12 / 400 / 1.4 | badge, số liệu |
| `mono-num` | 13 / tabular-nums | Mbps, ms, fps, giờ |
- Font: `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`. **Không tải webfont** (0 KB, không FOUT, tiếng Việt đúng dấu).
- Số dùng `font-variant-numeric: tabular-nums` để không nhảy khi cập nhật.
- Cỡ chữ UI người dùng chọn được (§20.10) → nhân bằng CSS var, **không** zoom trình duyệt.

### 23.4 Chuyển động
| Loại | Thời lượng | Easing |
|---|---|---|
| hover/press | 120 ms | `cubic-bezier(.2,0,0,1)` |
| mở/đóng panel, sheet | 200 ms | như trên |
| toast, banner | 180 ms vào / 150 ms ra | |
| chuyển cửa sổ (overlay) | 240 ms | |
- **Không** animate thứ nằm trên video (gợi ý về vị trí, tooltip) quá 150 ms — cảm giác trễ.
- `prefers-reduced-motion` → duration 0, chỉ đổi opacity.

### 23.5 Biểu tượng
- SVG inline (sprite 1 file), `24×24`, stroke `1.5`, `currentColor`.
- Không dùng emoji làm icon chức năng (khác nhau giữa OS) — emoji chỉ trong nhãn vui.
- Mỗi icon có `aria-hidden` + nhãn chữ đi kèm khi có thể.

### 23.6 Quy tắc chữ (microcopy)
- Nút = **động từ + đối tượng**: "Kết thúc phiên", không phải "OK".
- Không viết hoa toàn bộ; không dấu chấm cuối nhãn.
- Lỗi: `[điều gì] + [tại sao] + [làm gì]`, ≤ 2 câu.
- Xác nhận nguy hiểm: nêu **hậu quả cụ thể** ("Cửa sổ sẽ quay lại màn hình thật").
- Xưng "bạn", không "quý khách", không "người dùng".
- Số: `< 1000` không phân cách; ≥ 1000 dùng dấu chấm theo `vi-VN` (1.500). Thời gian: "1 giờ 12 phút", không "72m".

### 23.7 Mật độ & vùng chạm
| Ngữ cảnh | Cao tối thiểu | Khoảng cách |
|---|---|---|
| Desktop | 32 px | 8 px |
| Mobile | **44 px** | 8 px |
| Nút trong toolbar phiên | 36 px | 4 px (dùng icon, có tooltip) |
- Vùng ngón cái trên mobile: **1/3 dưới** màn hình. Mọi hành động thường dùng phải ở đó.

---

## 24. Đặc tả từng màn hình

### 24.1 `/login`
```
┌──────────────────────────────────────────────┐
│                                              │
│                  ◉  RD                        │
│            Điều khiển từ xa                   │
│                                              │
│   ┌────────────────────────────────────┐     │
│   │ Tên đăng nhập                      │     │
│   └────────────────────────────────────┘     │
│   ┌────────────────────────────────────┐     │
│   │ Mật khẩu                      👁   │     │
│   └────────────────────────────────────┘     │
│   ┌────────────────────────────────────┐     │
│   │ Mã 2 lớp (nếu đã bật)              │     │
│   └────────────────────────────────────┘     │
│                                              │
│   [        Đăng nhập        ]                │
│                                              │
│   ⓘ Sai mật khẩu 2 lần. Còn 3 lần thử.       │
└──────────────────────────────────────────────┘
```
- Cao 1 cột, tối đa **360 px**; không có ảnh nền lớn (tải chậm, không giúp gì).
- `Enter` submit; `autocomplete="username"/"current-password"`; `autofocus` vào username.
- Sai: thông báo dưới nút, **không** rung/đỏ cả form; đếm số lần còn lại.
- Khoá: thay nút bằng đếm ngược `Thử lại sau 14:32` (đếm realtime).
- TOTP: chỉ hiện ô khi server báo user có TOTP; 6 số, tự chuyển focus.
- Trạng thái: `idle · submitting (nút có spinner, disable) · error · locked`.
- Không có "quên mật khẩu" (không có email) → link "Cần trợ giúp?" mở `/help#reset`.

### 24.2 `/windows` — DASHBOARD (màn hình chính)
```
┌───────────────────────────────────────────────────────────────────────────┐
│ ◉ RD  ·  DESKTOP-01                                     ● Tốt   [👤 ▾]     │
├───────────────────────────────────────────────────────────────────────────┤
│  ⚠ Chưa cài dây âm thanh ảo — phiên sẽ không có tiếng.  [Cài ngay]  [×]   │
├───────────────────────────────────────────────────────────────────────────┤
│  PHIÊN ĐANG MỞ                                              (2)            │
│  ┌────────────────────┐  ┌────────────────────┐                           │
│  │ [thumbnail]        │  │ [thumbnail]        │                           │
│  │ Chrome — Tin tức   │  │ VS Code — app.ts   │                           │
│  │ 12:04 · HVNC · 🔊  │  │ 3:11 · VNC · 🔇    │                           │
│  │ [Tiếp tục] [Kết…]  │  │ [Tiếp tục] [Kết…]  │                           │
│  └────────────────────┘  └────────────────────┘                           │
├───────────────────────────────────────────────────────────────────────────┤
│  CỬA SỔ TRÊN MÁY                                        [⟳ 5s ▾]  [🔍 …]  │
│  Sắp xếp: Gần đây ▾   Lọc: Tất cả ▾                                       │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐                  │
│  │[thumb]    │ │[thumb]    │ │[icon]     │ │[thumb]    │                  │
│  │Chrome     │ │Explorer   │ │Notepad    │ │Excel      │                  │
│  │chrome.exe │ │explorer   │ │notepad.exe│ │excel.exe  │                  │
│  │      [▸]  │ │ ⛶ Ẩn nhỏ  │ │  Đã thu nhỏ│ │ 🛡 Admin  │                  │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘                  │
│                                                                           │
│  (trống)  Chưa có cửa sổ nào đang mở trên máy đó.                         │
│           Mở app bạn cần rồi bấm [Tải lại].                                │
├───────────────────────────────────────────────────────────────────────────┤
│  GẦN ĐÂY:  Chrome · 2 giờ trước    Explorer · hôm qua                     │
└───────────────────────────────────────────────────────────────────────────┘
```
**Cấu trúc (thứ tự ưu tiên từ trên xuống):**
1. **Top bar 56 px**: tên máy, chỉ báo chất lượng kết nối (1 chấm + chữ), menu người dùng.
2. **Banner cảnh báo** (chỉ khi có vấn đề): thiếu driver/cable, GPU yếu, có bản cập nhật, chứng chỉ sắp hết hạn. Tối đa **1** banner tại một lúc (quan trọng nhất); cái khác vào chuông.
3. **Phiên đang mở**: chỉ hiện khi có; card **lớn hơn** card cửa sổ (vì "tiếp tục việc đang làm" là hành động phổ biến nhất). Live thumbnail cập nhật 1 fps (không phải video — rẻ).
4. **Cửa sổ trên máy**: lưới card, tự động 5 s (có nút tạm dừng "⟳ 5s ▾"), tìm kiếm **lọc tức thì phía client** (không gọi API mỗi ký tự).
5. **Gần đây**: 5 mục, cho lần sau bấm nhanh.

**Card cửa sổ — các trạng thái:**
| Trạng thái | Hình | Hành động |
|---|---|---|
| Bình thường | thumbnail hoặc icon, tên cửa sổ, tên exe | hover → nút `Điều khiển` + `Chỉ xem` |
| Đã thu nhỏ | badge "Đã thu nhỏ" | vẫn bấm được; server restore |
| App admin | badge 🛡 + tooltip "Có thể không điều khiển được" | vẫn bấm; trước khi vào hiện cảnh báo 1 lần |
| Đang được người khác stream | overlay mờ + "Đang được [tên] xem" | nút xem (nếu được phép) |
| Bị allowlist chặn | ẩn khỏi danh sách (không hiện "bị chặn" — tránh lộ) | — |
| Không có thumbnail | icon app lớn | — |
| Đang tải | **skeleton** hình chữ nhật, không spinner | — |

**Tương tác:**
- Click card = mở **popover nhỏ** tại chỗ (không phải modal) với 3 dòng: `Điều khiển · Chỉ xem · Âm thanh ▾` + nút `Bắt đầu`. Chọn 1 lần, nhớ theo app.
- Double-click card = bắt đầu với lựa chọn đã nhớ (cho người dùng quen).
- `Tab` đi qua card, `Enter` = như click, `Esc` đóng popover.
- Không có drag-and-drop, không sắp xếp thủ công (tự sắp theo gần đây).

**Live tile phiên đang mở:**
- Thumbnail 1 fps + tên cửa sổ + thời lượng + badge mode + 🔊/🔇.
- Nút chính `Tiếp tục` (to), phụ `Kết thúc` (cần xác nhận).
- "Kết thúc" ở đây = **của tôi**; admin thấy thêm "Kết thúc của người khác" màu danger.

**Mobile `/windows`:** 1 cột; card cửa sổ cao hơn (thumbnail 16:9); bộ lọc thu vào nút `Lọc`; nút "Tải lại" là FAB dưới-phải; top bar gộp còn tên máy + `👤`.

### 24.3 `/s/:sid` — MÀN HÌNH ĐIỀU KHIỂN
```
┌───────────────────────────────────────────────────────────────────────────┐
│ ←  Chrome — Tin tức      HVNC · 🔊 · 12:04     ● Tốt    ⚙  ⛶  🛑  …      │  48px
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│                                                                           │
│                    ┌─────────────────────────────────┐                    │
│                    │                                 │                    │
│                    │          VIDEO (16:9)            │                    │
│                    │      + con trỏ local             │                    │
│                    │                                 │                    │
│                    └─────────────────────────────────┘                    │
│                                                                           │
│  ┌─────────────────────────────────────┐                                  │
│  │ ⚠ Có người đang dùng máy này        │  ← banner chỉ khi cần            │
│  └─────────────────────────────────────┘                                  │
├───────────────────────────────────────────────────────────────────────────┤
│  8.2 Mbps · 58 fps · 42 ms        [A+] [Chất lượng ▾] [Bàn phím] [⌨]      │  40px
└───────────────────────────────────────────────────────────────────────────┘
```
**Vùng:**
| Vùng | Cao | Nội dung | Ẩn khi |
|---|---|---|---|
| Top bar | 48 | `←` · tên cửa sổ · mode/audio/timer · chất lượng kết nối · `⚙ ⛶ 🛑 ⋯` | fullscreen + không hover 3 s |
| Video | co giãn | letterbox/fit/fill, overlay con trỏ + ripple | — |
| Banner | 40 | cảnh báo (tối đa 1) | không có cảnh báo |
| Bottom bar | 40 | số liệu · `A+` · chất lượng · bàn phím | fullscreen + không hover 3 s |
- **Fullscreen**: cả 2 bar trượt lên khi rê chuột vào mép trên/dưới, tự ẩn 2 s sau. Trên touch: 1 tap giữa video → hiện/ẩn.
- Toàn màn hình nền **đen tuyệt đối** (#000) để video không bị viền xám.
- `Esc` lần 1 = thoát fullscreen, lần 2 = hộp "Dừng điều khiển?" — **không** dùng Esc đơn để rời phiên (dễ bấm nhầm khi đang gõ).
- `Esc Esc` nhanh (<600 ms) = **dừng điều khiển khẩn cấp** (§6.8.6), khác với Esc đơn.
- Con trỏ: `cursor: none` chỉ khi đang ở trong vùng video và mode `local` (§6.3.4).

**Chỉ báo "có người đang dùng máy"** — banner vàng, không modal, có nút `Ẩn`; tự hiện lại sau 5 phút nếu còn.

**Overlay `secure_desktop`** (UAC/khoá máy): video bị phủ 40% đen + icon ổ khoá + "Máy đang hiện hộp thoại bảo mật. Cần thao tác trên máy thật." Input **không** gửi. Overlay tự biến mất khi hết.

**Overlay `RECONNECTING`:** video giữ frame cuối + phủ 30% + chấm nhấp nháy + "Đang kết nối lại… (2/8)" + `[Thử lại ngay] [Kết thúc]`.

**Ribbon `Chỉ xem`:** dải màu thông tin mỏng ở góc trên-phải, có mắt; nhấp vào → "Yêu cầu quyền điều khiển" (T2).

**Nút `🛑`:** luôn hiện, một chạm = ngừng gửi input **ngay** (client-side) + hộp "Đã tạm dừng điều khiển. [Tiếp tục] [Kết thúc phiên]". Không hỏi trước khi dừng (dừng phải tức thì), chỉ hỏi khi **kết thúc**.

**Nút `⋯` (menu phụ):** Chụp màn hình · Ảnh trong ảnh (PiP) · Chuyển cửa sổ · Đổi màn hình (nếu có) · Âm thanh (định tuyến) · Con trỏ (chế độ) · Chẩn đoán · Phím tắt · Sa thải phiên.

### 24.4 Overlay "Chuyển cửa sổ" (trong phiên)
```
┌───────────────────────────────────────────────────────────────┐
│  Chuyển sang cửa sổ khác                        [×]           │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│  │[thumb]  │ │[thumb]  │ │[thumb]  │ │[thumb]  │              │
│  │Chrome ● │ │Explorer │ │Notepad  │ │Excel    │              │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘              │
│  Cửa sổ hiện tại có dấu ●. Đang chuyển mất 1–2 giây.          │
└───────────────────────────────────────────────────────────────┘
```
- Mở bằng `Ctrl+Alt+Shift+W` hoặc `⋯ → Chuyển cửa sổ`.
- Không rời phiên, không mất kết nối (§6.9). Video phủ 60% đen, vẫn thấy frame cuối.
- Chọn → overlay chuyển "Đang chuyển…" → tự đóng khi `active`.
- `Esc` đóng, giữ cửa sổ cũ.

### 24.5 Sheet cài đặt **trong phiên** (`⚙`)
Bottom sheet trên mobile, panel phải 360 px trên desktop. Chỉ chứa thứ **liên quan phiên**:
```
Chất lượng      [Nét] [Cân bằng] [Mượt] [Tiết kiệm]
Hiển thị        [Vừa khung] [Đầy màn hình] [1:1] [Phóng to]
Con trỏ         [Theo máy] [To hơn] [Rất to]   ·  Viền tương phản ▢
Âm thanh        🔊 ▢  ·  Nguồn: [Chỉ app này ▾]
Bàn phím        Khoá phím ▢ (Chrome/Edge)  ·  Hàng phím phụ ▢
Cách chạm       [Trực tiếp] [Trackpad] [Kính lúp]      (mobile)
Phản hồi        Gợn sóng ▢
Nâng cao ▸
```
- Mỗi dòng: nhãn · control · dòng phụ 12 px giải thích hậu quả (§20.2).
- Thay đổi áp dụng ngay; toast "Đã đổi chất lượng — [Hoàn tác]".
- Không có nút "Lưu"/"Huỷ"; đóng bằng `Esc`/`×`/chạm ngoài.

### 24.6 `/settings` — 5 tab
| Tab | Nội dung |
|---|---|
| **Chung** | ngôn ngữ, theme (Sáng/Tối/Hệ thống), cỡ chữ UI, mật độ |
| **Điều khiển** | chất lượng mặc định, hiển thị mặc định, con trỏ, cách chạm, phím tắt xem |
| **Âm thanh** | mặc định (hỏi mỗi phiên), âm lượng, nhớ theo app |
| **Thông báo** | mức (tất cả / quan trọng / tắt) |
| **Bảo mật** | đổi mật khẩu, TOTP, phiên đăng nhập (thiết bị), đăng xuất mọi nơi |
- Layout: nav trái 200 px (mobile: segmented trên cùng) + nội dung 1 cột tối đa 640 px.
- Mọi thay đổi lưu ngay; không có nút Lưu.
- Mỗi mục có nút `↺` khi khác mặc định.
- Cuối trang: `Xuất cấu hình` / `Nhập` (§20.13).

### 24.7 `/diagnostics`
```
Kiểm tra máy chủ                                    [Chạy lại]
✓ Ứng dụng đang chạy             ✓ Tường lửa (443)
✓ Màn hình ảo                    ✗ Cổng UDP  ← [Sửa tự động]
✓ Dây âm thanh ảo                ✓ Chứng chỉ HTTPS
✓ Bộ mã hoá (NVENC)              ✓ Quyền điều khiển
✓ Màn hình ảo nhận tín hiệu      ✓ Độ trễ: 42 ms  ✓ 38 Mbps

1 vấn đề: tường lửa/router chặn UDP.
→ Chất lượng sẽ kém, điều khiển vẫn được.
[ Sửa tự động ]   [ Sao chép báo cáo ]   [ Xem chi tiết ]
```
- Mỗi dòng: icon trạng thái + tên **không thuật ngữ** + kết quả; fail thì có hành động ngay trên dòng.
- Chạy song song, mỗi kiểm tra tự timeout 3 s; tổng ≤ 6 s.
- Đang chạy: skeleton + dòng nhấp nháy, không spinner toàn trang.
- Nút "Sao chép báo cáo" → JSON đã lọc (§21.10), có hộp xem trước.

### 24.8 `/admin` — quản trị
```
┌ Tổng quan ─┬ Người dùng ┬ Phiên ┬ Nhật ký ┬ Chính sách ┬ Máy chủ ┐
```
| Mục | Nội dung chính |
|---|---|
| **Tổng quan** | số phiên, CPU/GPU/RAM, băng thông ra, lỗi 24 h, cảnh báo |
| **Người dùng** | danh sách, thêm/sửa/xoá, đổi vai, buộc đổi mật khẩu, reset TOTP |
| **Phiên** | bảng: ai, cửa sổ, mode, bắt đầu, băng thông, nút **Kết thúc** (xác nhận gõ tên) |
| **Nhật ký** | lọc theo loại/người/thời gian, phân trang, xuất CSV. **Không** có nội dung phiên |
| **Chính sách** | trần chất lượng, allowlist app, mức che giấu (S0/S1/S2), bật/tắt clipboard/audio, số phiên tối đa |
| **Máy chủ** | version, cập nhật, cert (hết hạn), driver, cổng, restart app, xuất gói chẩn đoán |
- Bảng dùng **ảo hoá** khi >200 dòng; sắp xếp mọi cột; tìm kiếm server-side.
- Hành động phá huỷ: hộp xác nhận **gõ tên** (người dùng/kết thúc phiên người khác).
- Mobile: bảng → danh sách card; ẩn cột phụ.

### 24.9 Tray app (phía server)
```
◉ RD — Đang chạy
─────────────────────────────
Mở bảng điều khiển…        (mở https://localhost/)
─────────────────────────────
Đang kết nối: 1             ← chỉ hiện khi có phiên
  · Chrome — từ 192.168.1.5, 12 phút
  [ Dừng điều khiển ngay ]
─────────────────────────────
Trạng thái: Màn hình ảo ✓   Dây âm thanh ✓
Chẩn đoán…
Cài đặt…
─────────────────────────────
Thoát
```
- Icon đổi: bình thường (xám) · có phiên (xanh) · có cảnh báo (vàng).
- Tooltip: `RD — 1 phiên đang điều khiển (Chrome, 12 phút)`.
- `Dừng điều khiển ngay` = **không** cần quyền người điều khiển (§21.8).
- Hotkey khẩn cấp toàn cục `Ctrl+Alt+Shift+X` → dừng mọi phiên + toast.

### 24.10 Wizard cài đặt (lần đầu, 5 bước, ≤ 60 s)
```
1/5  Mật khẩu quản trị      ▸ tạo mật khẩu (bắt buộc đổi nếu là mặc định)
2/5  Cách truy cập          ▸ [Trong mạng LAN] [Qua VPN (Tailscale…)] [Internet]
3/5  Kiểm tra môi trường    ▸ 5 dòng ✓/✗ + [Cài những gì còn thiếu]
4/5  Mặc định               ▸ che giấu (S1) · âm thanh (hỏi mỗi phiên) · chất lượng (tự động)
5/5  Xong                   ▸ link truy cập + [Mở bảng điều khiển] + QR để mở trên điện thoại
```
- Thanh tiến trình 5 chấm; mỗi bước **1 quyết định**, không có bước nào bắt đọc.
- Bỏ qua được bước 4 (dùng mặc định). Không bỏ qua 1 và 3.
- Nếu thiếu driver → bước 3 có nút cài; nếu fail → vẫn cho "Tiếp tục không có màn hình ảo" (chế độ VNC-only).

### 24.11 Trang lỗi (luôn có 1 hành động)
| Mã | Nội dung | Hành động |
|---|---|---|
| 403 | "Bạn không có quyền xem mục này." | Về trang chính · Đăng nhập tài khoản khác |
| 404 | "Trang không tồn tại. Có thể phiên đã kết thúc." | Về cửa sổ · Trợ giúp |
| offline | "Mất kết nối mạng." | Thử lại (tự thử 5 s/lần) |
| link hết hạn | "Link xem đã hết hạn (tạo lúc 14:02, hạn 1 giờ)." | Yêu cầu link mới |
| server tắt | "Máy chủ không phản hồi. Có thể ứng dụng đã tắt." | Chẩn đoán · Thử lại |

### 24.12 Mobile — 3 bố cục
**Dọc (mặc định điện thoại):**
```
┌─────────────────────────┐
│ ← Chrome   🔊   ⋯       │ 44
├─────────────────────────┤
│                         │
│     VIDEO (16:9)        │
│                         │
├─────────────────────────┤
│  ⌨  ←  ↑  ↓  →  Ctrl    │ 44  ← hàng phím phụ (tuỳ chọn)
├─────────────────────────┤
│ [✋] [🖱] [🔍] [A+] [⚙]  │ 56  ← toolbar ngón cái
└─────────────────────────┘
```
**Ngang (khi xoay):** video toàn màn hình, 2 bar tự ẩn, toolbar dọc bên phải 48 px.
**Máy tính bảng:** video + panel phải 320 px (cài đặt + danh sách cửa sổ) — như "mission control" thu nhỏ.
- Vùng an toàn: `env(safe-area-inset-*)` cho cả 4 cạnh.
- Không có hover: mọi tooltip phải hiện được bằng chạm-giữ.
- Bottom sheet cho cài đặt (§20.17), cao tối đa 80% và kéo được.

### 24.13 Trạng thái rỗng / tải / lỗi — theo màn hình
| Màn hình | Rỗng | Đang tải | Lỗi |
|---|---|---|---|
| Dashboard | "Chưa có cửa sổ nào…" + [Tải lại] | skeleton 6 card | banner + thử lại |
| Phiên đang mở | ẩn cả section | skeleton 2 tile | ẩn |
| Phiên | — | "Đang chuẩn bị…" + [Huỷ] | lý do + 2 hành động |
| Cài đặt | — | skeleton form | giữ giá trị cũ + toast |
| Nhật ký | "Chưa có hoạt động" | skeleton 8 dòng | thử lại |
| Chẩn đoán | — | skeleton 12 dòng | "không chạy được" + thử lại |

### 24.14 Thông báo trong app (toast & banner)
| | Toast | Banner |
|---|---|---|
| Dùng cho | kết quả hành động ("Đã đổi chất lượng") | trạng thái kéo dài (mất mạng, ai đó dùng máy) |
| Vị trí | dưới-trái (desktop), trên video (mobile) | dưới top bar |
| Tự ẩn | 5 s (lỗi: 8 s hoặc tới khi đóng) | theo sự kiện |
| Số lượng | tối đa 3, cũ nhất bị đẩy | tối đa 1 |
| Có hành động | "Hoàn tác" khi phù hợp | "[Sửa]", "[Xem]" |
- Toast **không** che toolbar và không nằm trên nút `🛑`.
- `aria-live="polite"` cho toast, `role="alert"` cho banner nguy hiểm.

### 24.15 Bàn phím & focus (client)
| Phím | Hành động | Ghi chú |
|---|---|---|
| `Tab` / `Shift+Tab` | điều hướng | **không** gửi sang server khi focus ở UI |
| `Enter` | kích hoạt | khi focus ở card/nút |
| `Esc` | đóng sheet/overlay/fullscreen | |
| `Esc Esc` (<600 ms) | **dừng điều khiển khẩn cấp** | |
| `F11` | fullscreen | hoặc nút ⛶ (Safari không có) |
| `Ctrl+,` | cài đặt | |
| `Ctrl+Alt+Shift+W` | chuyển cửa sổ | cần đăng ký, không xung đột OS |
| `Ctrl+Alt+Shift+D` | HUD chẩn đoán | |
| `?` | trợ giúp phím tắt | |
- Vòng focus **không** bị nhốt trong video; `Tab` ra khỏi video → focus lên toolbar (để vẫn dùng được bàn phím điều hướng UI khi đang ở chế độ điều khiển).
- Có nút "Nhường bàn phím cho máy" (gửi mọi phím, kể cả Tab) — rời trạng thái đó bằng `Esc` 2 lần hoặc nút rõ ràng. **Bắt buộc** vì nhiều app cần Tab.
- Focus ring luôn hiện khi điều hướng bằng bàn phím (`:focus-visible`), 2 px accent + offset 2 px.

### 24.16 Ngôn ngữ & i18n
- Chuỗi trong file `vi.json` / `en.json`, không hardcode.
- Không nối chuỗi (dùng placeholder): `{count} cửa sổ`.
- Số/ngày/giờ qua `Intl.*`; không tự format.
- Sẵn sàng RTL: dùng `margin-inline`/`padding-inline`, không `left/right` cứng.
- Độ dài chuỗi tiếng Anh có thể dài hơn 30% → nút có `min-width` + cho phép xuống dòng, không cắt.

---

## 25. Thành phần (component inventory)

| Nhóm | Thành phần | Trạng thái phải có |
|---|---|---|
| Hành động | Button (primary/secondary/ghost/danger), IconButton, SplitButton | default · hover · active · focus · disabled · loading |
| Nhập | Input, PasswordInput, SearchInput, OTPInput, Toggle, Segmented, Select, Slider | default · focus · invalid · disabled · readonly |
| Hiển thị | Card (window/session/stat), Tile, Badge, Ribbon, Skeleton, Tooltip, EmptyState | — |
| Phản hồi | Toast, Banner, InlineAlert, ProgressDots, Countdown | info · success · warn · danger |
| Lớp phủ | Sheet (bottom/side), Popover, Dialog, Overlay (cursor/ripple/loupe/minimap) | entering · open · exiting |
| Chuyên biệt | VideoStage, CursorLayer, RippleLayer, LoupeLayer, HudStats, QualityPicker, KeyTray, MonitorSwitcher, WindowSwitcher | — |
| Điều hướng | TopBar, TabBar, BreadcrumbBack, UserMenu | — |
| Dữ liệu | Table (ảo hoá), AuditRow, SessionRow | loading · empty · error · sorted |
- Mọi thành phần: **1 file JS export hàm tạo DOM** (không framework), CSS theo BEM + token.
- Mỗi thành phần phải có: trạng thái focus, aria, chịu được cỡ chữ Lớn, chịu được 320 px rộng.

### 25.1 Ma trận trạng thái phiên ↔ UI (bổ sung §7.1)
| State | Top bar | Video | Input | Banner | Hành động chính |
|---|---|---|---|---|---|
| PREPARING | tên cửa sổ, "Đang chuẩn bị…" | skeleton | tắt | — | Huỷ |
| CONNECTING | "Đang kết nối…" | skeleton | tắt | — | Huỷ |
| ACTIVE | đầy đủ + timer | video | bật | nếu cần | — |
| SWITCHING | "Đang chuyển…" | frame cũ | tắt | — | Huỷ (giữ cũ) |
| RECONNECTING | "Đang kết nối lại (n/8)" | frame cuối + phủ | tắt | banner | Thử lại · Kết thúc |
| FAILED | tên cửa sổ | trống | tắt | lý do | Thử lại · Cửa sổ khác |
| CLOSING | "Đang kết thúc…" | mờ | tắt | — | — |
| CLOSED | — | — | — | — | về Dashboard |

---

# PHẦN VI — NHỮNG GÌ CÒN THIẾU (audit v3.3)

## 26. Audit toàn diện — 20 nhóm còn trống, đã xử lý

> Đây là kết quả rà **toàn bộ** spec theo 20 trục. Mỗi mục đều có quyết định, không phải "để sau".

### 26.1 Mô hình dữ liệu (thiếu hoàn toàn)
v3.2 chưa nói **lưu cái gì, ở đâu, bằng gì**. Quyết định: **SQLite** cho dữ liệu có truy vấn, **JSON** cho cấu hình tĩnh, **không** dùng ORM.

```sql
-- users
id INTEGER PK, username TEXT UNIQUE, pwd_hash TEXT (argon2id), role TEXT,
totp_secret BLOB (DPAPI), must_change_pwd INTEGER, disabled INTEGER,
created_at INTEGER, last_login_at INTEGER, failed_count INTEGER, locked_until INTEGER

-- sessions_auth  (refresh token, rotate)
id TEXT PK, user_id INT, token_hash TEXT UNIQUE, device TEXT, ip TEXT,
created_at INT, last_used_at INT, expires_at INT, revoked_at INT, replaced_by TEXT

-- sessions  (phiên điều khiển; một phần ở RAM, phần bền vững ở đây)
sid TEXT PK, user_id INT, wid TEXT, app TEXT, mode TEXT, audio INT,
started_at INT, ended_at INT, end_reason TEXT, bytes_out INT, cursor_mode TEXT

-- prefs  (sở thích theo user / theo thiết bị / theo app)
user_id INT, scope TEXT ('user'|'device'|'app'), key TEXT, value TEXT,
PRIMARY KEY(user_id, scope, key)

-- audit
id INTEGER PK, ts INT, user_id INT, action TEXT, target TEXT, ip TEXT,
result TEXT, detail TEXT (JSON, đã lọc), corr TEXT
-- INDEX (ts), (user_id, ts), (action, ts)

-- shares  (link xem tạm)
token_hash TEXT PK, sid TEXT, created_by INT, created_at INT,
expires_at INT, view_only INT, used_count INT, revoked_at INT

-- windows_recent
user_id INT, wid TEXT, app TEXT, title TEXT, last_at INT
```
**Quy tắc:**
- `-- WAL`, `synchronous=NORMAL`; ghi audit theo lô 200 ms (không fsync mỗi dòng — nhưng **không mất** quá 200 ms khi crash).
- **Không** lưu: nội dung clipboard, keystroke, frame, mật khẩu dạng thô, token dạng thô (chỉ hash).
- `state.json` (§9.2.4) tách riêng: nó là **phục hồi sau crash**, không phải DB.
- Migration: bảng `schema_version` + script một chiều, **backup file .db trước khi migrate**.
- Vacuum/`PRAGMA optimize` mỗi ngày; audit cũ hơn `retention_days` xoá theo lô 1000.

### 26.2 Quy ước API & bảng mã lỗi (thiếu)
**Quy ước:** `/api/v1/...`; JSON UTF-8; mọi thời gian = epoch ms UTC; mọi id là string; phân trang `?cursor=&limit=` (limit ≤ 200); lọc theo `?from=&to=&q=`; `ETag` cho GET tĩnh; mutation **idempotent** qua header `Idempotency-Key` (bắt buộc cho tạo phiên).

**Bảng mã lỗi** — dùng chung cho REST + WS, client dịch sang câu người dùng được:
| `error_code` | HTTP | Câu cho người dùng | Hành động UI |
|---|---|---|---|
| `auth.bad_credential` | 401 | Sai tên hoặc mật khẩu | thử lại |
| `auth.locked` | 423 | Tạm khoá tới {time} | đếm ngược |
| `auth.totp_required` | 401 | Nhập mã 2 lớp | hiện ô OTP |
| `auth.expired` | 401 | Phiên đăng nhập hết hạn | chuyển login |
| `perm.denied` | 403 | Bạn không có quyền | về trang chính |
| `session.limit` | 409 | Đã đạt số phiên tối đa | kết thúc phiên cũ |
| `session.in_use` | 409 | Cửa sổ đang được người khác xem | xem (nếu được phép) |
| `session.gone` | 404 | Phiên đã kết thúc | về dashboard |
| `window.gone` | 404 | Cửa sổ vừa đóng | tải lại danh sách |
| `window.immovable` | 412 | App này không cho di chuyển cửa sổ | dùng chế độ VNC |
| `window.unrestorable` | 412 | Không mở lại được cửa sổ | chọn cửa sổ khác |
| `capture.blocked` | 412 | App này chặn chụp màn hình | chọn cửa sổ khác |
| `capture.exclusive` | 412 | App đang toàn màn hình độc quyền | chuyển borderless |
| `driver.missing` | 412 | Chưa cài màn hình ảo | cài tự động |
| `driver.failed` | 500 | Màn hình ảo không hoạt động | chẩn đoán |
| `audio.device_missing` | 412 | Chưa cài dây âm thanh ảo | cài hoặc tiếp tục không tiếng |
| `audio.busy` | 409 | Thiết bị âm thanh đang bận | thử lại |
| `enc.init_failed` | 500 | Không khởi tạo được bộ mã hoá | dùng CPU |
| `net.no_candidate` | 409 | Không kết nối trực tiếp được | hướng dẫn VPN |
| `net.udp_blocked` | 409 | Mạng chặn UDP | tiếp tục chất lượng thấp |
| `rate.limited` | 429 | Quá nhiều yêu cầu | đếm ngược |
| `server.busy` | 503 | Máy chủ đang bận | thử lại sau |
| `server.version` | 426 | Cần cập nhật ứng dụng | hướng dẫn |
| `policy.blocked` | 403 | Quản trị viên không cho phép | liên hệ admin |
- Client **không** hiện `error_code` trần; luôn map qua bảng này. Có test tự động: mọi code trong server phải có dòng trong bảng i18n (CI fail nếu thiếu).

### 26.3 Log, số liệu, quan sát (thiếu)
| Loại | Nội dung | Nơi |
|---|---|---|
| **App log** | JSON-lines: `ts, level, mod, corr, msg, kv` — xoay 10 MB × 5 | `%LOCALAPPDATA%\RD\logs\` |
| **Audit** | theo §26.1, bền vững, UI xem được | DB |
| **Metrics** | `GET /metrics` (chỉ từ loopback hoặc cần token): phiên đang chạy, fps, encode_ms, rtt, loss, bytes, driver_ok, restart_count | Prometheus text |
| **Health** | `GET /health` → `{ok, version, checks:{...}}` **không cần auth** nhưng **không lộ** chi tiết (chỉ ok/fail từng nhóm) | — |
| **Correlation** | mỗi request/phiên có `corr` 8 ký tự; xuất hiện trong log + gói chẩn đoán | — |
- **Redaction bắt buộc**: mật khẩu, token, cookie, `Authorization`, nội dung clipboard, tiêu đề cửa sổ (có thể chứa thông tin) → **`window_title` chỉ log khi `debug`**. Tiêu đề cửa sổ là dữ liệu nhạy cảm (tên file, URL) — điều này hay bị bỏ qua.
- Log mức: `error` (lỗi thật), `warn` (tự phục hồi được), `info` (đăng nhập, tạo/kết thúc phiên), `debug` (tắt mặc định).
- Không log mỗi frame, mỗi input, mỗi ack.

### 26.4 CLI & vận hành tại máy (thiếu)
```
rd.exe run                    # chạy như bình thường (tray)
rd.exe --config <path>
rd.exe check                  # kiểm tra môi trường, exit code 0/1/2
rd.exe diagnose --json        # 12 kiểm tra §21.1, dạng máy đọc
rd.exe reset-admin            # đặt lại mật khẩu admin (cần quyền OS)
rd.exe doctor --fix           # sửa firewall rule / khởi động lại driver
rd.exe uninstall-clean        # rollback thủ công (§13.7)
rd.exe export-config > a.json
rd.exe version
```
- Mọi lệnh có `--json` để script đọc.
- `rd.exe check` được wizard và gói chẩn đoán gọi lại.
- Không có lệnh nào chạy được mà không cần quyền OS phù hợp (rõ ràng trong `--help`).

### 26.5 Cấu hình: nạp lại & hiệu lực (thiếu)
| Nhóm | Nạp lại không cần restart? | Ghi chú |
|---|---|---|
| Giới hạn/phiên, encoder, cursor, input, stealth | ✅ | áp dụng cho phiên **mới**; phiên đang chạy giữ nguyên (trừ khi ghi rõ) |
| TLS cert | ✅ | đọc lại khi file đổi (watch), không ngắt phiên đang chạy |
| Port, driver | ❌ | cần restart app; UI báo rõ |
| Users/roles | ✅ | từ DB, hiệu lực ngay |
- `SIGHUP`/file-watch → nạp lại + ghi audit `config.reloaded` (kèm diff **đã lọc**, không log mật khẩu).
- Config sai cú pháp → **giữ cấu hình cũ đang chạy**, ghi `error`, hiện banner trong admin. Không bao giờ tự tắt app vì config lỗi.
- Có `rd.exe check --config` để validate trước khi áp.

### 26.6 Quản lý chứng chỉ (thiếu)
| Việc | Cách làm |
|---|---|
| Tạo self-signed | SAN gồm hostname + mọi IP private + `localhost` + Tailscale IP; hiệu lực 825 ngày; RSA 2048 hoặc ECDSA P-256 |
| Cài vào trust | hướng dẫn **theo từng client OS** (Windows/macOS/iOS/Android) + cảnh báo rõ "chỉ cài cho máy bạn kiểm soát" |
| Let's Encrypt (Internet) | hỗ trợ `webroot` + `dns-01`; tự renew 30 ngày trước; cần domain |
| Tailscale cert | gọi `tailscale cert` nếu có |
| Hết hạn | nhắc ở 30/14/7/1 ngày (banner admin + tray); **không** tự gia hạn cert tự ký (phải cài lại trust → bắt buộc người quyết định) |
| HSTS | **chỉ bật khi cert được tin cậy**; nếu self-signed chưa cài trust → tắt HSTS (tránh khoá người dùng ra ngoài) |
| HTTP→HTTPS | 301, trừ `/health` (cho monitoring) |
- Khoá riêng nằm `ProgramData` với ACL hạn chế; hỗ trợ cung cấp PFX có mật khẩu.

### 26.7 Reverse proxy / TLS termination (thiếu)
- Hỗ trợ đứng sau Caddy/nginx: tin `X-Forwarded-For`/`X-Forwarded-Proto` **chỉ từ** `trusted_proxies` (CIDR) đã cấu hình; nếu không cấu hình thì **bỏ qua** các header đó (chống giả mạo).
- WebSocket: hướng dẫn `proxy_buffering off`, `proxy_read_timeout 1h`, `Upgrade`/`Connection`.
- WebRTC **không** đi qua proxy HTTP — phải mở UDP trực tiếp hoặc dùng TURN; nếu chỉ có 443/tcp thì ghi rõ "chất lượng sẽ kém/không hoạt động".
- Có file cấu hình mẫu cho nginx + Caddy trong repo.
- `X-Forwarded-Prefix` (khi chạy dưới subpath) — UI dùng relative URL nên không cần biết prefix.

### 26.8 Môi trường cài đặt đặc biệt (thiếu)
| Môi trường | Vấn đề | Cách xử lý |
|---|---|---|
| **Windows Home** | không có policy/GPO | không phụ thuộc GPO ở đâu cả; dùng Task Scheduler thay |
| **Không có quyền admin** | không cài được VDD/cable/firewall | chế độ **VNC-only** (không cần driver); ghi rõ "HVNC cần quyền admin" |
| **Máy ảo (VMware/Hyper-V/VirtualBox)** | không GPU, không desktop ảo tốt | x264 + 1080p30; cảnh báo; vẫn dùng được |
| **WSL** | không áp dụng (client Linux GUI không có) | không hỗ trợ |
| **Windows trên ARM** | không NVENC/QSV | x264/AMF? — test; preset Low |
| **Windows Server** | không có Store, ít codec | Media Foundation có thể generic-only → test; fallback x264 |
| **RDP đang chiếm console** | capture fail | phát hiện → thông báo "đang có phiên RDP khác"; gợi ý dùng console |
| **Nhiều user trên cùng máy (RDS)** | mỗi session riêng | ngoài phạm vi; yêu cầu tắt RDS |
| **Sau khi cài driver cần reboot** | VDD lần đầu có thể cần | wizard kiểm tra + nói rõ "cần khởi động lại 1 lần" |
| **Antivirus chặn driver** | cài thất bại | hướng dẫn whitelist + kiểm tra chữ ký driver |
| **Màn hình không có (headless)** | vẫn cần desktop ảo | hoạt động (VDD không cần màn hình thật) |
| **Laptop gập nắp** | màn hình tắt, vẫn chạy | display ảo không bị ảnh hưởng; `ES_DISPLAY_REQUIRED` giữ |

### 26.9 Ma trận hỗ trợ & chính sách phiên bản (thiếu)
| Hạng mục | Hỗ trợ | Ghi chú |
|---|---|---|
| Server | Win10 2004+, Win11 22H2+ | test cả 2 nhánh |
| Client | Chrome/Edge ≥ 110, Firefox ≥ 115 ESR, Safari ≥ 16.4 | dưới mức → trang "chưa hỗ trợ" |
| Mobile | Chrome Android ≥ 110, Safari iOS ≥ 16.4 | |
| Màn hình | ≥ 320 px rộng, ≥ 480 px cao | |
| Mạng | ≥ 1 Mbps cho preset Low | |
| RAM client | ≥ 2 GB (Safari iOS cần ít hơn) | |
| Đa ngôn ngữ | vi, en | chuẩn bị thêm không cần đổi code |
| **Chính sách** | hỗ trợ 2 phiên bản lớn gần nhất; bản cũ hơn → cảnh báo + `server.version` 426 | |
- Bảng này hiện trong `/help` và trong gói chẩn đoán.

### 26.10 Không có phụ thuộc bên thứ ba (quyết định, chưa nêu)
- **Không** CDN, **không** Google Fonts, **không** analytics, **không** telemetry mặc định, **không** Sentry, **không** Web Push, **không** third-party script.
- Lý do: (a) không rò IP/usage của người dùng ra ngoài; (b) chạy được trong mạng kín; (c) CSP chặt `default-src 'self'` không cần ngoại lệ.
- Telemetry/crash report là **opt-in** rõ ràng, mặc định **tắt**, và chỉ gửi file người dùng đã xem trước (§21.10).
- Trang offline (`/offline`) là HTML tĩnh, không service worker (tránh phức tạp cache).

### 26.11 Hiệu năng phía client (chưa có ngân sách)
| Chỉ số | Ngân sách |
|---|---|
| JS tổng (chưa nén) | ≤ 220 KB; gzip ≤ 70 KB |
| CSS | ≤ 30 KB (gzip ≤ 10 KB) |
| Không có framework, không bundler | ✔ |
| First paint `/login` (LAN) | < 400 ms |
| Dashboard với 20 cửa sổ | < 700 ms, < 80 ms/frame khi cuộn |
| Thumbnail | JPEG 160 px ≤ 12 KB mỗi cái, cache 5 s, decode ngoài main thread nếu có `createImageBitmap` |
| Memory phiên (1080p60) | < 250 MB (Chrome), < 180 MB (Safari) |
| CPU client | < 15% (decode HW) |
| Pin (mobile) | < 12%/giờ ở preset Cân bằng |
- Kiểm tra bằng Lighthouse + `performance.mark` trong CI; **fail nếu vượt 20%**.
- `content-visibility: auto` cho lưới card; ảnh `loading="lazy"`, `decoding="async"`.

### 26.12 Nhập liệu ngoài tiếng Việt (thiếu)
| Trường hợp | Xử lý |
|---|---|
| **CJK** (Trung/Nhật/Hàn) | client IME → `compositionend` → Unicode; **bắt buộc** không gửi từng ký tự; test với Microsoft Pinyin + Google 日本語 |
| **RTL** (Ả Rập, Do Thái) | Unicode injection; con trỏ/highlight do app server xử lý; test thứ tự chèn |
| **Indic** (Devanagari…) | Unicode; chú ý dấu tổ hợp — gửi nguyên chuỗi như IME trả |
| **Tiếng Việt Telex/VNI** | `compositionend`; test "tieengs"→"tiếng", "dduowngf"→"đường" |
| **Emoji / ngoài BMP** | surrogate pair = 4 event (§6.5.1) |
| **Bàn phím ảo mobile** | textarea ẩn + composition; test Gboard tiếng Việt + iOS tiếng Nhật |
| **Layout khác** (AZERTY, Dvorak) | ký tự OK (Unicode); shortcut theo layout server — ghi rõ (§6.5.8) |
| **Dead keys** | gửi kết quả cuối; test `^e`→`ê` |
| **Gõ bằng tay (handwriting / voice)** | qua IME của client → text; hoạt động |
| Ngưỡng chấp nhận | 12 tổ hợp ngôn ngữ × IME phải pass trong ma trận test |

### 26.13 Clipboard — loại dữ liệu (chỉ nói "text + ảnh")
| Loại | Hỗ trợ | Ghi chú |
|---|---|---|
| Text thuần UTF-8 | ✅ | chuẩn, ≤ 256 KB |
| HTML (rich text) | ⚠️ chỉ dán dạng **text thuần** | giữ HTML sẽ rò style/script; quyết định: **không** hỗ trợ HTML |
| Ảnh (PNG) | ✅ | ≤ 8 MB sau nén; chuyển DIB→PNG ở server |
| Danh sách file | ❌ | trùng chức năng file transfer (T3); tránh đường vận chuyển dữ liệu không kiểm soát |
| Đường dẫn file | ⚠️ dạng text thôi | không tự mở |
- Có **xem trước** trước khi dán vào máy (tránh dán nhầm mật khẩu vào app khác).
- Có nút **xoá clipboard server** sau khi dán (mặc định bật) → giảm rò rỉ.

### 26.14 Chụp màn hình từ xa & in ấn (thiếu)
- Nút `⋯ → Chụp màn hình` = **client chụp frame hiện tại** (không cần server), tải PNG về; ghi tên `chrome-2026-11-07-1402.png`.
- `PrintScreen` gửi sang server → ảnh vào clipboard server (dùng kèm chức năng copy). Không tự tải file về (tránh đường vận chuyển ngầm).
- In từ xa: **không hỗ trợ** (T3 nếu cần); ghi rõ để không ai chờ.

### 26.15 Đồng hồ, múi giờ, NTP (thiếu)
- Mọi thời gian server = epoch ms UTC. Client hiển thị theo múi giờ **của client**, có nhãn khi khác server.
- JWT: skew ±60 s; TOTP: ±1 bước.
- Dashboard hiện giờ **của máy chủ** ở tooltip ("12:04 giờ máy chủ").
- Nếu lệch > 5 phút so với NTP (nếu kiểm tra được) → banner admin "đồng hồ máy chủ lệch, ảnh hưởng đăng nhập 2 lớp".
- Timeout/idle tính bằng **clock đơn điệu** (monotonic), không dùng wall clock (tránh bug khi đổi giờ/NTP nhảy).

### 26.16 Lưu trữ & xoá dữ liệu (thiếu)
| Dữ liệu | Giữ | Xoá |
|---|---|---|
| Audit | 90 ngày (mặc định, cấu hình) | tự động theo lô |
| Log app | 5 × 10 MB | xoay vòng |
| Ảnh clipboard tạm | 0 (không lưu đĩa) | ngay |
| Thumbnail cache | 5 s (RAM) | — |
| Phiên đã kết thúc | metadata 90 ngày | tự động |
| Link chia sẻ | theo hạn + 7 ngày sau | tự động |
| Gói chẩn đoán | người dùng tải, **server không lưu** | — |
| Crash dump | **tắt mặc định**; nếu bật: 7 ngày, local, không upload | tự động |
- Có nút admin **"Xoá dữ liệu của người dùng X"** (GDPR-style) — xoá prefs + audit liên quan, giữ lại dòng audit tối thiểu về việc xoá.

### 26.17 Ký số, SmartScreen, AV (thiếu)
- Binary + driver **nên** ký (EV cert nếu có) — không có thì SmartScreen sẽ cảnh báo "Unknown publisher"; ghi trong `/help` cách bỏ qua một cách có hiểu biết.
- Hướng dẫn whitelist Defender (folder + process) khi cần — **không** tự tắt AV.
- Không có "chống phát hiện" dưới mọi hình thức (§21.14).

### 26.18 Lỗi đặc thù trình duyệt (danh sách kiểm)
| Browser | Lỗi đã biết | Xử lý |
|---|---|---|
| Safari iOS | không fullscreen `<video>` | fullscreen CSS container |
| Safari iOS | audio cần gesture | nút bật tiếng |
| Safari iOS | `navigator.clipboard.readText` cần gesture | nút Paste = gesture |
| Safari mac | Pointer Lock cần gesture, `movementX` bị gia tốc | cảnh báo; vẫn dùng được |
| Firefox | không Keyboard Lock | cảnh báo Ctrl+W (§6.5.3) |
| Firefox | `wheel` delta khác (line vs pixel) | chuẩn hoá `deltaMode` |
| Chrome | mDNS obfuscation | §13.3 |
| Chrome Android | tab bị kill khi ẩn lâu | resume + cảnh báo "giữ tab mở" |
| Mọi browser | autoplay policy | nút bật tiếng |
| Mọi browser | `beforeunload` không đảm bảo | `sendBeacon` + watchdog server |
| Mọi browser | zoom trang (Ctrl+wheel) làm lệch toạ độ | chặn khi focus video + tính theo `getBoundingClientRect` (đã đúng) |

### 26.19 Tiết kiệm pin & dữ liệu (thiếu)
- `navigator.connection.saveData` hoặc `effectiveType` 2g/3g → gợi ý Tiết kiệm; tự hạ preset **một lần** (có toast + hoàn tác).
- Mobile pin yếu (`navigator.getBattery` nếu có) → hạ 30 fps, tắt ripple khi < 20%.
- Khi tab ẩn → 5 fps (§6.11.2) = tiết kiệm pin đáng kể.
- Không giữ `wake lock` mặc định; chỉ giữ khi người dùng bật "giữ màn hình sáng".

### 26.20 Trang `/help` & nội dung trợ giúp (thiếu)
- 4 mục: **Bắt đầu** (3 bước) · **Không kết nối được** (8 nguyên nhân theo tần suất) · **Phím tắt** (bảng đầy đủ §6.5.2 + §24.15) · **Câu hỏi thường gặp** (giới hạn đã biết: DRM, UAC, Ctrl+Alt+Del, NAT).
- Mỗi mục trỏ tới `/diagnostics` khi phù hợp.
- Tìm kiếm trong help là lọc phía client, không cần backend.
- Nội dung nằm trong file markdown → cùng nguồn với docs, không viết 2 lần.

---

## 27. Trả lời thẳng: còn gì thiếu?

### 27.1 Đã đóng (rà 2 lượt, 20 trục ở §26 + 20 lỗ hổng ở §0.1)
Kiến trúc · ngôn ngữ · capture · cursor · input · bàn phím/IME · touch · audio · stealth · mạng · bảo mật · **giao diện (9 chương §22–25)** · tuỳ chỉnh · chẩn đoán · trạng thái/lỗi · bền & rò rỉ · cập nhật · backup · chia sẻ · phía người bị điều khiển · pháp lý · hỗ trợ · quy trình test · rủi ro · **dữ liệu · API · log · CLI · config reload · cert · proxy · môi trường cài · ma trận hỗ trợ · không phụ thuộc bên thứ ba · ngân sách hiệu năng · nhập liệu đa ngôn ngữ · clipboard chi tiết · chụp màn hình · thời gian · lưu trữ · ký số · lỗi browser · pin/data · help**.

### 27.2 **Chưa** thể nói "không còn gì thiếu" — và đây là lý do (thật thà)
Có 4 loại điều **không thể** biết bằng cách viết spec thêm:

| # | Điều chỉ đo được | Cách giải quyết | Khi nào biết |
|---|---|---|---|
| 1 | `d3d11screencapturesrc` + `webrtcbin` + VDD có đạt **p95 <80 ms** không | Phase 0 spike + đo barcode | sau 1–1.5 tuần |
| 2 | Per-app audio routing API có **ổn định trên mọi build Win10/11** không | Phase 0 test trên 4 máy/build | sau Phase 0 |
| 3 | `ITaskbarList.DeleteTab` + `WS_EX_TOOLWINDOW` có bị app phổ biến **tự đảo lại** không | Thử trên 15 app thật (Chrome, VS Code, Excel, Teams, Notepad++, Zalo, Photoshop…) | sau Phase 1 |
| 4 | Trải nghiệm "đủ tốt" thật sự (người dùng có thấy mượt không) | 3 người dùng thử 5 tác vụ, đo thời gian hoàn thành + hỏi 2 câu | sau Phase 1 |

Ngoài 4 điều đó, **về mặt thiết kế** tôi không còn nhóm nào chưa có quyết định. Nếu bạn muốn, tôi có thể rà thêm lượt thứ 3 theo một trục bạn chọn (ví dụ: "chỉ soi bảo mật", "chỉ soi mobile", "chỉ soi vận hành") — nhưng tôi sẽ không tự nói "đã hoàn hảo" trước khi bạn xác nhận hoặc trước khi có kết quả Phase 0.

### 27.3 Việc tiếp theo (đề xuất thứ tự)
1. **Bạn đọc §22–25** (giao diện) — chỗ dễ phải sửa nhất vì nó là gu, không phải kỹ thuật.
2. Chốt 3 câu §19.2 (đang có mặc định).
3. Tôi dựng **Phase 0**: Cargo workspace + spike GStreamer + trang test client + script đo barcode. Không đụng Tier 1.

---

# PHẦN VII — HAI THIẾT BỊ, MỘT HỆ THỐNG

## 28. Nguyên tắc: không "thu nhỏ desktop", mà hai giao diện cùng một lõi

Điện thoại và desktop **khác nhau về bản chất**, không phải về kích thước:

| | Desktop | Điện thoại |
|---|---|---|
| Con trỏ | có, chính xác tuyệt đối | **không có** → phải tạo cảm giác chính xác bằng kỹ thuật khác |
| Hover | có (tooltip, menu) | không có |
| Bàn phím | đầy đủ, luôn sẵn | ảo, che **50% màn hình** khi mở |
| Số tay | 1–2, nghỉ trên bàn | 2 tay cầm, ngón cái **chỉ với tới 60% dưới** |
| Màn hình | 1920×1080, nhiều chỗ cho chrome | 390×844, **mỗi px đều quý** |
| Ngữ cảnh | ngồi, tập trung | đi lại, một tay, mạng chập chờn |
| Thời gian phiên | 30–120 phút | 2–15 phút, gián đoạn nhiều |

⇒ Hệ quả thiết kế: **cùng một lõi (state machine, command registry, transport), hai vỏ khác nhau.**
- Desktop: **chrome mỏng nhưng luôn hiện** — vì có chỗ, và vì hover cho phép giấu nhãn.
- Mobile: **chrome gần như bằng 0**, thay bằng **gesture + một nút "grip" duy nhất** có 3 độ sâu.

Nguyên tắc chung bắt buộc cho cả hai:
1. **Video là nội dung, không phải nền.** Mọi thứ khác phải nhường chỗ.
2. **Mọi hành động có ≤ 2 thao tác.** Nếu 3 → thiết kế sai.
3. **Không có tính năng chỉ tồn tại trong menu.** Tính năng phải có đường tắt (gesture/shortcut) và **cùng một tên** ở mọi nơi.
4. **Phản hồi ≤ 100 ms** cho *mọi* thao tác, bất kể mạng.
5. **Không che nội dung đang cần xem.** (Đây là yêu cầu trực tiếp của bạn.)

---

## 29. Desktop — chrome mỏng, luôn hiện, không che

### 29.1 Ngân sách
| Vùng | Cao | Che nội dung? | Ghi chú |
|---|---|---|---|
| Top bar | 48 px | **có** (trên video) | tự ẩn khi fullscreen + không hover 3 s |
| Bottom bar | 40 px | **có** | như trên |
| Overlay con trỏ/ripple | 0 | không | vẽ trên video, trong suốt |
| Toast | — | **không** | dưới-trái, ngoài vùng video nếu đủ chỗ |
| Banner | 40 px | **có** | chỉ khi có vấn đề, tối đa 1 |
- Chế độ mặc định khi vào phiên: **fullscreen + 2 bar tự ẩn** ⇒ video chiếm ~100%. Bar hiện khi rê chuột vào mép trên/dưới.
- Trong cửa sổ thường (không fullscreen): 2 bar luôn hiện (vì có chỗ), video letterbox.
- **Không bao giờ** có thanh công cụ dọc/ngang thứ ba. Không có panel cố định bên phải (khác bản nháp §24.12 cho tablet — xem §30.11).

### 29.2 Đường tắt desktop (không cần bấm nút)
| Hành động | Đường tắt | Ghi chú |
|---|---|---|
| Đổi chất lượng | `Ctrl+Alt+1..4` (Nét/Cân bằng/Mượt/Tiết kiệm) | hiện HUD nhỏ 1 s |
| Toggle âm thanh | `Ctrl+Alt+M` | |
| Chuyển cửa sổ | `Ctrl+Alt+Shift+W` | mở window switcher |
| Dừng điều khiển | `Esc Esc` | |
| Toàn bộ lệnh | `Ctrl+K` | **command palette** (§31) |
| HUD số liệu | `Ctrl+Alt+Shift+D` | |
| Phóng to chữ | `Ctrl+Alt+=` / `-` | zoom local |
| Chụp màn hình | `Ctrl+Alt+S` | |
| Fullscreen | `F11` / `Ctrl+Alt+F` | |

### 29.3 Chuột phải
- Chuột phải trên video = **gửi right-click sang server**, không mở context menu browser.
- Giữ `Shift` + chuột phải = mở menu **của ứng dụng ta** (Cắt/Chụp/Chuyển cửa sổ). Đây là quy ước để không mất chức năng nào.

---

## 30. Mobile — "zero chrome" nhưng đầy đủ

### 30.1 Ngân sách màn hình (số cụ thể, test được)
| Chỉ số | Ngưỡng |
|---|---|
| **Nút hiện thường trực trên video** | **0** |
| Phần tử chrome thường trực | **2 grip 28×28 px** (mờ 25%) ở 2 góc dưới |
| Diện tích video (dọc, xem) | **≥ 92%** màn hình |
| Diện tích video (ngang) | **≥ 97%** |
| Cao chrome khi đang thao tác | 1 thanh **≤ 44 px**, tự ẩn sau **2.5 s** |
| Số thao tác tới bất kỳ lệnh nào | **≤ 2** |
| Thời gian tới lệnh thường dùng | ≤ 1.5 s |
| Vùng ngón cái (1 tay) | toàn bộ điều khiển chính nằm trong **40% dưới** màn hình |

### 30.2 Ba tầng truy cập — "gộp" đúng nghĩa
```
TẦNG 0 — TRỰC TIẾP trên video (không cần nút)
  tap · double tap · long press · 2 ngón · 3 ngón · pinch · vuốt mép
  → phủ ~80% thao tác hằng ngày

TẦNG 1 — GRIP (1 nút duy nhất, 3 độ sâu)
  chạm        → thanh ngữ cảnh 4 nút (theo thứ hay dùng nhất lúc đó)
  giữ 400 ms  → vòng tròn 8 lệnh (radial) tại ngón
  vuốt lên    → bảng lệnh đầy đủ (command sheet)

TẦNG 2 — BẢNG LỆNH (tất cả, có tìm kiếm)
  mọi lệnh, kèm gesture tương đương để học dần
```
> Một nút, ba độ sâu = **không chiếm chỗ** mà vẫn **đầy đủ**. Đây là câu trả lời cho "gộp chẳng hạn".

### 30.3 Bản đồ gesture đầy đủ
| Gesture | Tác dụng | Ghi chú |
|---|---|---|
| 1 tap | left click tại điểm chạm | ripple xác nhận |
| 2 tap nhanh | double click | gửi down/up/down/up thật (§6.4.2) |
| giữ 500 ms | **right click** (menu ngữ cảnh của app) | rung nhẹ nếu hỗ trợ |
| giữ + kéo | drag (giữ nút trái) | có chỉ báo "đang kéo"; nút "nhả" riêng |
| 2 ngón vuốt | scroll | delta → wheel notch |
| 2 ngón chạm | **right click** (thay thế) | cho người không quen giữ |
| 3 ngón chạm | **mở vòng tròn 8 lệnh** (radial) | |
| 3 ngón vuốt lên/xuống | thanh ngữ cảnh / bảng lệnh | |
| pinch | zoom local (mặc định) hoặc Ctrl+wheel (toggle) | nhãn rõ đang ở chế độ nào |
| vuốt mép trái → phải | quay lại (rời phiên, có xác nhận) | |
| vuốt mép phải → trái | panel cửa sổ nhanh (chuyển cửa sổ) | |
| vuốt mép dưới lên | **bàn phím** (mở để gõ) | đây là cách gõ nhanh nhất |
| 2 ngón chạm 3 lần | dừng điều khiển khẩn cấp | khó bấm nhầm |

**Nguyên tắc chọn gesture:** theo quy ước đã có của iOS/Android (2 ngón = scroll, pinch = zoom, vuốt mép = back) → người dùng **không phải học**. Chỉ 3 ngón và "grip" là mới, và cả hai đều có đường thay thế trong bảng lệnh.

### 30.4 Vòng tròn 8 lệnh (radial) — dùng ngón cái, không cần nhìn
```
                ↖ Dán          ↑ Cuộn lên
        ← Bàn phím                    → Chuột phải
                ↙ Ẩn/hiện       ↓ Cuộn xuống
                      ⏺ (ngón giữ)      ✕ Đóng
```
- Mở tại **vị trí ngón** (không phải giữa màn hình) → không phải di chuyển tay.
- **8 ô cố định vị trí theo giờ**, không xoay theo hướng → dùng được mà **không cần nhìn** (muscle memory). Ô đầu tiên mở tại vị trí ngón; các ô khác ở bán kính 64 px.
- Chọn bằng: nhả ngay tại ô, hoặc kéo tới ô rồi nhả. Kéo ra khỏi vòng = huỷ.
- Nội dung 8 ô **theo ngữ cảnh** (thay đổi theo app đang xem — học từ vài lần đầu, sau đó cố định nếu người dùng ghim):
 | Ngữ cảnh | 8 lệnh |
 |---|---|
 | Mặc định | Bàn phím · Chuột phải · Cuộn lên · Cuộn xuống · Dán · Chuyển cửa sổ · Chụp màn hình · Đóng |
 | App có text (Word, chat) | Bàn phím · Dán · Sao chép · Chọn tất cả · Chuột phải · Cuộn lên · Cuộn xuống · Đóng |
 | Trình duyệt | Bàn phím · Back · Forward · Tab mới · Cuộn lên · Cuộn xuống · Chuột phải · Đóng |
 | Media player | Play/Pause · Tua ±10 s · Toàn màn hình · Âm lượng · … |
- **Ghim được**: người dùng giữ 1 ô 1 s → "Ghim vào thanh ngữ cảnh". Học dần.
- Radial **có nhãn chữ** (không chỉ icon) ở lần đầu 10 lần, sau đó chỉ icon (cấu hình được).

### 30.5 Thanh ngữ cảnh — 4 nút, ngữ cảnh, tự ẩn
Chạm grip → thanh nổi **ngay trên grip**, 44 px, 4 nút:
```
[ ⌨ Bàn phím ] [ 🖱 Chuột phải ] [ ⤢ Cửa sổ ] [ ⚙ ]
```
- Nội dung 4 nút = 4 lệnh **hay dùng nhất trong 10 phút qua** (tự học), không phải cố định.
- Tự ẩn sau 2.5 s hoặc khi chạm video.
- Nằm trong vùng ngón cái; không bao giờ ở trên cùng.

### 30.6 Bảng lệnh — tất cả, có tìm kiếm, có "học"
```
┌───────────────────────────────────────┐
│ 🔍 Tìm lệnh…                    [×]   │
├───────────────────────────────────────┤
│ ⌨  Bàn phím                    (grip) │
│ 🖱  Chuột phải              (giữ 500ms)│
│ ⤢  Chuyển cửa sổ          (3 ngón, …) │
│ 🎚  Chất lượng                      ▸  │
│   · Nét · Cân bằng · Mượt · Tiết kiệm │
│ 👁  Chỉ xem                          ▢ │
│ 🔊  Âm thanh                         ▢ │
│ ⛶  Toàn màn hình                      │
│ 📸  Chụp màn hình                     │
│ 🔍  Kính lúp                         ▢ │
│ ⌖  Cách chạm                    ▸     │
│ 🩺  Chẩn đoán                          │
│ ⏻  Kết thúc phiên                     │
└───────────────────────────────────────┘
```
- Mở bằng: vuốt lên từ grip · 3 ngón vuốt lên · nút `⚙` ở thanh ngữ cảnh.
- Mỗi dòng hiện **gesture tương đương** ở cột phải → người dùng học dần rồi bỏ bảng.
- Tìm kiếm lọc tức thì; gõ được bằng bàn phím ảo.
- Nhóm con mở tại chỗ (accordion), không mở sheet mới.

### 30.7 Bàn phím — gõ mà không bị che
Đây là vấn đề lớn nhất trên điện thoại: bàn phím ảo chiếm ~50% màn hình.
```
Trước khi mở:                     Khi mở bàn phím:
┌───────────────────┐             ┌───────────────────┐
│                   │             │  (video thu nhỏ,  │
│      VIDEO        │             │   neo trên cùng,  │
│                   │             │   vẫn thấy chỗ    │
│                   │             │   đang gõ)        │
│                   │             ├───────────────────┤
│                   │             │ [Ctrl][Alt][⇧][⌫] │ ← hàng chip 36px
│                   │             ├───────────────────┤
│  [grip]     [grip]│             │   BÀN PHÍM ẢO     │
└───────────────────┘             │   (của hệ điều    │
                                  │    hành)          │
                                  └───────────────────┘
```
- **Video KHÔNG bị che** — nó co lại (CSS `visualViewport` + `translate`), neo vùng đang gõ vào giữa phần còn lại. Nếu app có ô nhập liệu, tự pan để ô đó nằm phía trên bàn phím (không thể biết chính xác trên remote → dùng heuristic: giữ **vị trí con trỏ** trong 30% trên của vùng video).
- Hàng chip `Ctrl/Alt/Shift/Esc/Tab/⌫/↑↓←→`: **sticky modifier** — chạm = sáng, áp dụng cho phím kế tiếp rồi tự nhả; chạm 2 lần = khoá.
- Chỉ 1 hàng chip (36 px), không 3 hàng. Các phím khác dùng bàn phím ảo của HĐH (đúng ngôn ngữ, đúng IME, không phải tự vẽ).
- `Done`/`Ẩn bàn phím` luôn ở góc phải hàng chip.
- Không tự đóng bàn phím khi chạm video (gây ức chế) — chỉ đóng khi bấm `Ẩn` hoặc vuốt xuống.

### 30.8 Chính xác — vấn đề "ngón tay to, nút nhỏ"
| Kỹ thuật | Khi nào bật | Hành vi |
|---|---|---|
| **Kính lúp** (mặc định bật) | khi **giữ** ngón | phóng 2.5× vùng dưới ngón, hiện phía trên ngón; kéo để tinh chỉnh; nhả = click |
| **Chế độ trackpad** | người dùng chọn | vuốt = di con trỏ (relative, có gia tốc), chạm = click; có con trỏ ảo |
| **Chế độ chạm trực tiếp** | mặc định | chạm đâu click đó |
| **Lưới tinh chỉnh** | giữ 1 s *sau khi* đã giữ | hiện 2 nút `←→` `↑↓` để dịch con trỏ 1 px |
| **Crosshair mode** | tự bật khi app dưới ngón có control <20 px | hiện đường ngang/dọc mờ để căn |
- Ba chế độ chọn được ở `⚙ → Cách chạm`, có **hình minh hoạ động 1 s** (không phải chữ giải thích).
- Mặc định = **Chạm trực tiếp + kính lúp**: đúng nhất cho người mới, và không cần bật gì.

### 30.9 Một tay với tới (reachability)
- Mọi điều khiển chính ở **40% dưới**; vùng trên cùng chỉ để **đọc** (tên cửa sổ, trạng thái).
- Grip mặc định ở góc **dưới-phải** (hoặc dưới-trái nếu người dùng thuận tay trái — cài đặt 1 chạm).
- Bảng lệnh và thanh ngữ cảnh **trượt lên từ dưới**, không phải dropdown từ trên.
- Không có nút nào ở góc trên-phải (chỗ khó với tay nhất) — trừ nút "về dashboard" và nó có **cả** gesture vuốt mép trái.

### 30.10 Xoay máy & bố cục
| Orientation | Bố cục | Ghi chú |
|---|---|---|
| Dọc | video căn giữa, 16:9 letterbox trên/dưới; grip 2 góc dưới | phần letterbox dùng cho **bàn phím/chip** khi mở → **không che video** |
| Ngang | video toàn màn hình; grip 2 góc dưới; thanh ngữ cảnh dọc mép phải nếu cần | chrome ẩn hoàn toàn |
| Chuyển hướng | giữ nguyên phiên, không reload; tính lại letterbox | gửi `resize` ≤1/10 s (§9.10) |
- Khi xoay, **không** gửi lệnh đổi display ảo (trừ khi người dùng chọn "Dọc" ở §20.3).

### 30.11 Tablet
- ≥ 768 px: video + **panel trượt** bên phải 320 px **chỉ khi mở** (không thường trực).
- Panel chứa: danh sách cửa sổ, cài đặt phiên, chẩn đoán nhanh — **cùng component** với sheet mobile, chỉ khác vị trí.
- Vẫn giữ grip; vẫn ẩn được mọi thứ. Không có "chế độ desktop" riêng.

### 30.12 Tự ẩn & trạng thái
| Trạng thái | Chrome hiện |
|---|---|
| Đang thao tác (chạm trong 2.5 s qua) | thanh ngữ cảnh (nếu mở) |
| Không thao tác 2.5 s | chỉ 2 grip (mờ 25%) |
| Đang xem video/đọc | grip mờ 10% (gần như vô hình) |
| Đang gõ bàn phím | hàng chip 36 px |
| Có cảnh báo | banner 40 px ở dưới (không trên) |
| Đang kết nối lại | overlay trung tâm |
| Chỉ xem | ribbon mỏng góc trên-phải |

---

## 31. Command registry — một nguồn sự thật cho mọi thao tác

Đây là thứ làm cho "gộp" **không** thành mớ hỗn độn và làm FE/BE nhất quán.

### 31.1 Mỗi lệnh có đúng 1 định nghĩa
```jsonc
// commands.json  — sinh ra cho cả client và tài liệu, kiểm tra trong CI
{
  "id": "quality.set",
  "label": "Chất lượng",
  "icon": "gauge",
  "group": "chat-luong",
  "args": [{"name":"preset","type":"enum","values":["sharp","balanced","smooth","low"]}],
  "shortcutDesktop": "Ctrl+Alt+1..4",
  "gestureMobile": "command-sheet>Chat luong",
  "api": {"method":"POST","path":"/api/v1/sessions/{sid}/preset","body":"{preset}"},
  "availableIn": ["active","reconnecting"],
  "roles": ["admin","user"],
  "optimistic": true,          // UI đổi ngay, hoàn tác nếu server từ chối
  "confirm": false,
  "telemetry": "cmd.quality_set"
}
```
- **Một file** định nghĩa **mọi** lệnh (khoảng 45 lệnh). Client sinh: bảng lệnh, thanh ngữ cảnh, radial, keyboard shortcuts, tooltip, trang `/help`, test.
- Server đối chiếu: mỗi `api` phải tồn tại thật; CI **fail** nếu registry trỏ tới route không có hoặc ngược lại.
- Không có lệnh nào "chỉ có trong code". Nếu thêm nút mới mà không thêm vào registry → review chặn.

### 31.2 Nhóm lệnh (đầy đủ)
| Nhóm | Lệnh |
|---|---|
| **Phiên** | kết thúc · tạm dừng điều khiển · tiếp tục · chỉ xem · sao chép link xem · chuyển cửa sổ · đổi mode · đổi màn hình |
| **Chất lượng** | preset (4) · tự động · yêu cầu keyframe |
| **Hiển thị** | vừa khung · đầy · 1:1 · phóng to ± · xoay? (không) · toàn màn hình · PiP |
| **Chạm** | chạm trực tiếp · trackpad · kính lúp · độ nhạy · thuận tay |
| **Con trỏ** | chế độ local/remote/auto · kích thước · viền |
| **Bàn phím** | mở bàn phím · chip modifier · layout · khoá phím · gửi Tab |
| **Âm thanh** | bật/tắt · âm lượng · nguồn (app/máy) · thiết bị |
| **Clipboard** | dán vào máy · sao chép từ máy · xoá clipboard máy |
| **Công cụ** | chụp màn hình · chẩn đoán · HUD số liệu · sao chép báo cáo |
| **Hỗ trợ** | trợ giúp phím tắt · xem lại hướng dẫn · gửi phản hồi (opt-in) |

### 31.3 Ánh xạ 3 nơi dùng
| Lệnh | Desktop | Mobile |
|---|---|---|
| `quality.set` | `Ctrl+Alt+1..4` hoặc `⚙ → Chất lượng` | radial `↑`? không — command sheet → Chất lượng; hoặc thanh ngữ cảnh nếu hay dùng |
| `input.keyboard` | tự nhiên (có bàn phím) | vuốt mép dưới / chip ⌨ |
| `session.stop` | `Esc Esc` / `🛑` | 2 ngón chạm 3 lần / command sheet |
| `window.switch` | `Ctrl+Alt+Shift+W` | vuốt mép phải / radial `⤢` |
- **Cùng một nhãn chữ** ở mọi nơi ("Chuyển cửa sổ", không phải "Switch" ở đây "Đổi cửa sổ" ở kia).
- Test CI: quét UI tìm chuỗi không đến từ registry → fail.

---

## 32. Luồng liền mạch end-to-end (flow contract)

Vấn đề bạn nêu: "luồng phải liền mạch, logic nhất quán kể cả backend hay frontend". Cách làm: **một hợp đồng**, không phải "mỗi bên tự hiểu".

### 32.1 Kiến trúc một chiều
```
gesture/ui  →  CommandBus (client)  →  SessionController (1 instance)
                                          │  intent_id, rev, TTL
                                          ▼
                              HTTP (lệnh)  /  DataChannel (input)  /  WSS (điều khiển nhẹ)
                                          ▼
                                    Server handler
                                          ▼
                              effect (display/audio/input/…)
                                          ▼
                              state(rev++)  →  WSS broadcast
                                          ▼
                              Store (client)  →  render (diff)
```
**Quy tắc tuyệt đối:**
1. **Chỉ 1 `SessionController`** cho mỗi phiên. Không component nào tự gọi `fetch`/`pc`/`ws`. (Ngăn "mỗi nút một đường" — nguồn gốc của không nhất quán.)
2. **Chỉ 1 WebSocket**, 1 supervisor reconnect, 1 backoff. Media/DC do cùng controller quản.
3. **Server là nguồn sự thật của `state`.** Client giữ **bản sao** + ghi rõ `server_rev` nó đang thấy.
4. **Render chỉ từ Store.** Không có `element.textContent = ...` rải rác; mọi hiển thị đi qua 1 hàm `render(state)`.
5. **Không có state ẩn trong DOM.** Trạng thái nằm trong Store, DOM là kết quả.

### 32.2 Vòng đời một lệnh (bảng bắt buộc theo)
| Bước | Việc | Thời gian | Nếu lỗi |
|---|---|---|---|
| 1 | Gesture → `CommandBus.dispatch(id,args)` | 0 ms | — |
| 2 | Kiểm tra `availableIn` + role + `confirm` | <1 ms | khoá nút + lý do |
| 3 | **Optimistic**: Store áp dụng, UI đổi ngay | <16 ms | — |
| 4 | Sinh `intent_id` (uuid v7), gửi HTTP/DC | <5 ms | — |
| 5 | **Phản hồi thị giác** (nút sáng/ripple/HUD) | **≤100 ms** | — |
| 6 | Server xử lý, trả `{ok, rev, state?}` | 20–400 ms | map `error_code` → toast |
| 7 | `rev > server_rev` → áp `state`; ngược lại bỏ | — | — |
| 8 | Nếu optimistic bị từ chối → **hoàn tác** + toast "Không đổi được. [Thử lại]" | — | — |
| 9 | Lệnh lặp trong 500 ms (`intent` khác, cùng đích) → **gộp**, chỉ gửi cái cuối | — | — |

**Bắt buộc:** bước 5 xảy ra **trước** khi biết kết quả mạng. Người dùng phải luôn thấy "đã nhận". Thiếu bước này → cảm giác "app không phản hồi" dù mạng bình thường.

### 32.3 Idempotency & chống lặp
- Mọi mutation gửi `Idempotency-Key: intent_id`; server giữ 60 s → **gửi lại an toàn**.
- Server dedupe theo `(user, intent_id)`; trả lại kết quả cũ nếu trùng.
- Input (mouse/key) **không** idempotent → không retry; dùng `seq` + watchdog (§7.5), mất thì bỏ (move) hoặc release (click).
- Tạo phiên: `POST /sessions` với `Idempotency-Key` = hash(wid+mode+audio+phút) → bấm 2 lần **không** tạo 2 phiên.

### 32.4 Thứ tự & race
| Tình huống race | Luật |
|---|---|
| Bấm "Tạm dừng" đang lúc `switching` | dừng áp dụng **ngay** ở client (không gửi input), lệnh pause xếp hàng chờ `active` |
| Đổi chất lượng 2 lần liên tiếp | chỉ gửi cái cuối (debounce 400 ms), server nhận 1 |
| Đổi cửa sổ khi đang reconnect | bị chặn, toast "Đang kết nối lại…" |
| Kết thúc phiên khi đang `switching` | cho phép, huỷ switch, rồi đóng |
| Toggle audio khi audio đang khởi tạo | xếp hàng, áp sau khi init xong, giữ trạng thái cuối |
| Nhận `state` cũ về muộn | bỏ nếu `rev` ≤ `server_rev` |
| Hai tab cùng user | tab sau vào **read-only + banner** "đang mở ở tab khác", có nút "Tiếp quản" (đóng tab kia) |
- Hàng đợi lệnh có **TTL 3 s**; quá hạn → bỏ + toast, không áp dụng lệnh cũ vào trạng thái mới.

### 32.5 Hợp đồng thời gian
| Thứ | Ngưỡng |
|---|---|
| Phản hồi thị giác cho mọi lệnh | ≤ 100 ms |
| Lệnh thường (đổi chất lượng, toggle) | ≤ 400 ms |
| Bắt đầu phiên (display ảo đã có) | ≤ 2.5 s |
| Chuyển cửa sổ | ≤ 1.5 s |
| Kết thúc + dọn dẹp | ≤ 3 s |
| Reconnect (ICE restart) | ≤ 4 s |
| Nếu vượt ngưỡng 1.5× | hiện "đang xử lý…" (không im lặng) |

### 32.6 Nhất quán về ngôn ngữ & lỗi (FE↔BE)
- **Một** bảng `error_code` (§26.2) — server **chỉ** trả mã, client **chỉ** dịch. Không bên nào tự viết câu cho người dùng.
- **Một** hàm `toast(code, ctx)` — không có `alert()`, không có 2 kiểu thông báo.
- Một nơi quyết định "có hỏi xác nhận không" (`registry.confirm`), không rải `confirm()` khắp code.
- Tên trạng thái (§7.1) dùng **nguyên văn** ở BE, WS, store, UI, test. Không có "active" ở đây "running" ở kia.
- Đơn vị: ms, px, Mbps, byte — ghi trong tên field (`rtt_ms`, `bitrate_kbps`). Không có field mơ hồ.

### 32.7 Liền mạch khi mất mạng (không "vỡ" luồng)
| Mất gì | Người dùng thấy | Khôi phục |
|---|---|---|
| DataChannel | video vẫn chạy, điều khiển không tác dụng | `input_channel_lost` banner + tự tạo lại DC (renegotiation) trong 2 s |
| WebSocket | video vẫn chạy, stats đứng | banner mờ, tự reconnect 1/2/4/8 s |
| Media | overlay RECONNECTING, input tạm dừng | ICE restart, ≤8 lần |
| Cả hai | overlay đầy đủ + nút | như trên |
| Tab bị ẩn/kill | — | resume §6.11.1 |
- **Không bao giờ** `location.reload()` tự động (mất ngữ cảnh, mất scroll, mất bàn phím).

---

## 33. Nhất quán giữa 2 vỏ (checklist test bắt buộc)

| # | Kiểm tra | Desktop | Mobile |
|---|---|---|---|
| 1 | Cùng danh sách lệnh (registry) | ✔ | ✔ |
| 2 | Cùng nhãn chữ | ✔ | ✔ |
| 3 | Cùng mã lỗi → cùng câu | ✔ | ✔ |
| 4 | Cùng state machine, cùng rev | ✔ | ✔ |
| 5 | Mọi lệnh có phản hồi ≤100 ms | ✔ | ✔ |
| 6 | Không lệnh nào chỉ có ở 1 nền tảng | ✔ | ✔ (hoặc có ghi lý do) |
| 7 | Bàn phím điều hướng được toàn bộ | ✔ | ⌨️ (bàn phím ngoài) |
| 8 | Không che nội dung khi đang xem | ✔ (tự ẩn) | ✔ (zero chrome) |
| 9 | Xoay/resize không mất phiên | ✔ | ✔ |
| 10 | Cùng hành vi khi mất mạng | ✔ | ✔ |
- Test tự động: Playwright chạy **cùng kịch bản** trên 2 viewport (1440×900 + 390×844), so sánh **state cuối** và **số request** — nếu khác nhau → fail.

---

## 34. Ba điều tôi muốn nói thẳng về thiết kế này

1. **Mobile không thể "đầy đủ như desktop" nếu đếm nút.** Nhưng có thể đầy đủ nếu đếm **thao tác**: mọi lệnh ở mobile ≤ 2 thao tác, phần lớn ≤ 1. Đó là định nghĩa "đầy đủ" tôi dùng, và §33 là cách kiểm chứng.

2. **Gesture có cái giá: không nhìn thấy thì không biết.** Nên (a) lần đầu dùng có gợi ý động 1 s cho gesture chính; (b) mọi gesture đều có đường thay thế trong bảng lệnh; (c) bảng lệnh in gesture tương đương để học dần. Không có gesture nào là **đường duy nhất**.

3. **Nhất quán FE/BE không đến từ quy ước, mà từ 1 nguồn.** `commands.json` + 1 `SessionController` + 1 bảng lỗi + `rev` monotonic. Nếu thiếu bất kỳ cái nào, sau 3 tháng sẽ có 4 kiểu thông báo lỗi và 3 kiểu trạng thái khác nhau — đây là điều chắc chắn xảy ra nếu không có kỷ luật này.

---

# PHẦN VIII — MÔ HÌNH THỰC THI

## 35. Mô hình thực thi pipeline thời gian thực (nhánh #1 — quan trọng nhất còn thiếu)

> v3.4 nói *"capture → encode → RTP"* như thể đó là một hàm. Nó không phải. Đó là **5 thành phần chạy đồng thời trên 3 loại luồng khác nhau, chia sẻ 4 hàng đợi có trần**, và **mọi thứ về độ trễ/độ ổn định nằm ở đây** — không nằm ở codec, không nằm ở mạng.
> Nếu chương này sai, toàn bộ §17.3 (p95 <80 ms) là không thể, và mọi chương khác chỉ là trang trí.

### 35.1 Nguyên tắc chi phối
| # | Nguyên tắc | Hệ quả cứng |
|---|---|---|
| 1 | **Không hàng đợi nào không có trần.** | mọi queue khai báo capacity + chính sách khi đầy |
| 2 | **Trễ là thứ bị hy sinh trước, không phải frame.** | đầy → **drop**, không bao giờ block producer |
| 3 | **Không block trên đường nóng.** | không mutex dài, không I/O, không cấp phát, không log, không format string |
| 4 | **Không cấp phát trong vòng lặp frame.** | pool + reuse; chỉ cấp phát lúc khởi tạo hoặc khi đổi resolution |
| 5 | **Mọi thành phần restart được độc lập.** | capture chết không được kéo encoder chết |
| 6 | **Chỉ một chiều sở hữu buffer tại một thời điểm.** | ownership chuyển tuyến tính, không copy |
| 7 | **Session kết thúc phải dừng đúng thứ tự.** | nếu không sẽ deadlock hoặc crash driver |
| 8 | **Đo được từng chặng.** | mỗi frame mang timestamp ở 5 điểm |

### 35.2 Sơ đồ thread & pipeline
```
┌─ Thread: net-http (tokio) ──────────────────────────────────────────────┐
│  axum: REST, static, auth        │  tungstenite: WSS signaling          │
│  → tạo/huỷ phiên, đổi cấu hình, ack chỉ số                              │
└───────────────┬─────────────────────────────────────────────────────────┘
                │ (chỉ control-plane; KHÔNG chạm frame)
┌─ Thread: input ─────────────────────────────────────────────────────────┐
│  SCTP recv (move/ctrl) → parse → validate/clamp → SendInput → ack       │
│  yêu cầu keyframe (on-demand) ──┐                                       │
└─────────────────────────────────┼───────────────────────────────────────┘
┌─ Thread: cursor (60–120 Hz tick) ─┼──────────────────────────────────────┐
│  DDAPI pointer metadata → shape hash → (a) phát cshape/cpos (b) compos.  │
└─────────────────────────────────┼───────────────────────────────────────┘
┌─ Thread: presence (1 Hz) ────────┼──────────────────────────────────────┐
│  GetLastInputInfo → someone_local                                       │
└─────────────────────────────────┼───────────────────────────────────────┘
                                  ▼
┌─ Thread: capture [1/GStreamer pipeline] ────────────────────────────────┐
│  d3d11screencapturesrc (DDAPI) → NV12 pool → appsrc + PTS               │
│  watchdog: ACCESS_LOST → recreate; >3 lần/10 s → switch WGC/BitBlt      │
└───────────────┬─────────────────────────────────────────────────────────┘
                │ zero-copy D3D11 texture (cùng adapter)
┌─ Thread: encode [GStreamer streaming thread] ───────────────────────────┐
│  nvh264enc / qsvh264enc / amfh264enc / x264enc → h264parse              │
│  → rtph264pay → webrtcbin (SRTP) → UDP                                  │
└───────────────┬─────────────────────────────────────────────────────────┘
                │ (đi ngược lên) RTCP RR/PLI/TWCC
┌─ Thread: audio [GStreamer] ─────────────────────────────────────────────┐
│  wasapi2src (loopback 48 kHz) → audioconvert/resample → opusenc         │
│  → rtpopuspay → webrtcbin                                               │
└───────────────┬─────────────────────────────────────────────────────────┘
┌─ Thread: gst-bus / supervisor ──────────────────────────────────────────┐
│  nhận lỗi/warning từ mọi pipeline; quyết định restart/hạ cấp; audit     │
└───────────────┬─────────────────────────────────────────────────────────┘
┌─ Thread: stats/audit ───────────────────────────────────────────────────┐
│  gộp số liệu 250 ms → WSS 2 Hz; audit theo lô; không chạm frame         │
└─────────────────────────────────────────────────────────────────────────┘
```
**Tổng: 8 nhóm luồng cho 1 phiên.** Không có luồng nào "chỉ để cho có" — mỗi cái có lý do tách (block khác nhau, ưu tiên khác nhau).

**Vì sao capture và encode tách nhưng *cùng một pipeline** GStreamer: chúng chia sẻ D3D11 device + texture pool ⇒ **zero-copy**. Nếu tách thành 2 process hoặc 2 pipeline riêng, mỗi frame phải đi qua shared memory = +2–6 ms và giảm độ phân giải thực tế.

### 35.3 Vòng đời một frame + ownership (chuỗi 6 mắt xích)
```
① DDAPI AcquireNextFrame  → ② chuyển thành GstBuffer (giữ texture, KHÔNG copy)
   → ③ encoder map đọc (read-only)  → ④ size ≤2 MB: encoder giữ ref tới khi xong
   → ⑤ release buffer về pool  → ⑥ ReleaseFrame (đúng 1 lần)
```
| Mắt xích | Ai sở hữu | Luật |
|---|---|---|
| ①② | capture thread | **phải** `ReleaseFrame` **sau** khi encoder không còn đọc texture. Nếu release sớm → NVIDIA đôi khi trả **NO_ACCESS** hoặc frame rách |
| ③④ | encoder | không được gọi API capture; không được `ReleaseFrame` |
| ⑤⑥ | pool + capture | pool **cố định** (4 buffer cho 1080p NV12 = 4 × 3.1 MB ≈ 12.5 MB) |
**Bất biến (assert trong debug build):**
1. mỗi `AcquireNextFrame` có đúng 1 `ReleaseFrame`
2. buffer về pool **trước** `ReleaseFrame` của frame tương ứng
3. frame id tăng đơn điệu; gap >3 frame ⇒ **bỏ hiển thị** (encoder sẽ gặp "scene jump" — phải force IDR)
4. không có 2 frame cùng PTS
5. không có buffer từ pool cũ sau khi đổi resolution (pool phải được tạo lại)

> Đây là chỗ gây crash khó tìm nhất trong toàn hệ thống: release sớm 1 frame → chạy tốt 40 phút → màn hình xanh. Assert ở trên là bắt buộc ở `debug`, và counter ở `release` trong production.

### 35.4 Hàng đợi — bảng cứng
| Hàng đợi | Trần | Khi đầy | Không bao giờ | Lý do |
|---|---|---|---|---|
| **capture→appsrc** | **1** | drop frame cũ, giữ mới (**latest-wins**) | block | trễ > mất frame |
| **encoder in-flight** | 2 | drop | xếp hàng | giữ 1 frame đang mã hoá + 1 dự phòng |
| **encode→RTP (pacer)** | 30 gói (~50 ms @8 Mbps) | drop gói không trọng yếu | burst vô hạn | tránh "burst" làm đầy buffer mạng |
| **RTCP / control** | không giới hạn (tỉ lệ thấp) | — | — | không được mất feedback |
| **input `move`** | **1** per kênh | drop cũ | block | con trỏ phải mới nhất |
| **input `ctrl`** | 64 | **backpressure** (ngừng đọc SCTP 100 ms) | drop | **không được mất** click/key |
| **audio** | 3 buffer 20 ms | drop cũ | block | giữ ≤60 ms |
| **frame → WSS stats** | 1 (gộp) | ghi đè | xếp hàng | stats không quan trọng bằng frame |
| **Bus message** | 256 | drop + log | block | không được làm chết pipeline |
**Quy tắc chung:** producer **không bao giờ** ngủ; consumer quyết định drop. Mỗi hàng đợi có counter `dropped_total` hiện trong stats (§35.12) — nếu >0 kéo dài ⇒ có vấn đề về hiệu năng, phải thấy được, không im lặng.

### 35.5 Đường input — vì sao "dính tay" hay "dính chặt"
```
SCTP recv → parse (0 alloc, ring buffer 64 KB) → clamp → SendInput → ack(gộp)
```
- **một** thread cho `move` + `ctrl`, nhưng **hai hàng đợi riêng** (§5.7). `move` chỉ giữ **1** vị trí mới nhất ⇒ nếu máy chậm, con trỏ **nhảy** tới vị trí mới chứ không "đi từ từ" (đúng ý người dùng: họ đã di tay tới đó rồi).
- `ctrl` giữ tối đa 64 sự kiện; khi đầy → **ngừng đọc SCTP 100 ms** (backpressure thật) thay vì drop, vì mất 1 keyup = **kẹt phím**.
- `SendInput` là lời gọi kernel có thể tốn **0.1–2 ms** khi hệ thống bận. Không gộp batch (Windows không hỗ trợ batch cho input liên quan đến timing).
- ack: gộp mỗi **500 ms** hoặc **32 sự kiện**, trả `seq` cuối ⇒ client phát hiện kênh chết mà không tốn round-trip mỗi event.
- Latency budget cho thread này: **p99 < 3 ms** từ recv → SendInput xong. Nếu vượt ⇒ ghi `input_worker_slow` + tăng ưu tiên.

### 35.6 Ngân sách độ trễ phân rã (từng chặng, có số)
> Bảng §6.2.1 gộp quá nhiều thứ. Đây là bảng **phải dùng khi implement** — cộng lại phải khớp SLA.

| # | Chặng | Cơ chế | LAN p50 | LAN p95 | Ghi chú |
|---|---|---|---|---|---|
| 1 | Browser event → DC send | rAF batch | 8 | 17 | 1 frame ở 60 Hz |
| 2 | Uplink RTT/2 | UDP | 1 | 3 | |
| 3 | Parse + SendInput | kernel | 0.5 | 2 | |
| 4 | App phản ứng | phụ thuộc app | 8 | 20 | **không kiểm soát được** |
| 5 | DWM composite | vsync | 8 | 17 | |
| 6 | DDAPI acquire | vsync | 8 | 17 | **1 frame trễ cố hữu** |
| 7 | appsrc → encoder | hàng đợi 1 | 0.5 | 3 | |
| 8 | Encode | NVENC low-latency | 4 | 8 | x264: 10–20 |
| 9 | RTP pay + SRTP | CPU | 0.5 | 2 | |
| 10 | Downlink | UDP + **jitter buffer** | **10** | **35** | **khoản ẩn lớn nhất** |
| 11 | Decode | HW | 3 | 8 | |
| 12 | Composite → photon | browser | 8 | 17 | |
| | **Tổng** | | **≈52** | **≈147** | p95 vượt 80 ⇒ phải cắt |
**Cắt ở đâu (theo thứ tự hiệu quả):**
1. **Jitter buffer (10)** — cấu hình được; xem §35.7.
2. **Encode (8)** — hardware + preset low-latency + không B-frame.
3. **DDAPI trễ 1 frame (6)** — không tránh được với DDAPI; WGC cũng tương tự.
4. **Browser (1, 12)** — giảm bằng cách bỏ qua rAF (dùng `pointerrawupdate`) và **cursor local** (đã có, loại bỏ chặng 3–12 khỏi cảm giác con trỏ).
> **Kết luận quan trọng:** SLA **p95 <80 ms** chỉ đạt được nếu jitter buffer ở mức **thấp** (≤2 frame) và mạng LAN sạch. Với mạng có jitter, **p95 thực tế là 110–150 ms**. Phải nói rõ điều này trong `/help` và **đo lại ở Phase 0**; nếu không đạt, hạ kỳ vọng SLA xuống `p95 <120 ms` **một cách có ý thức**, không phải lặng lẽ.

### 35.7 Jitter buffer — quyết định lớn nhất về độ trễ
- Browser tự quản jitter buffer cho video; không có API chuẩn để đặt kích thước. Có 2 cách ảnh hưởng:
  1. **`playout-delay` RTP header extension** (Chromium hỗ trợ): server gửi `min=0, max=…`; đặt **`min=max=0`** ⇒ buffer tối thiểu. Đây là cách chính.
  2. Gửi **pacing đều** + `abs-send-time`/TWCC tốt ⇒ buffer tự co.
- Đánh đổi: buffer = 0 ⇒ mạng jitter 5 ms là **giật hình**. Vì vậy: **thích ứng** — nếu loss/jitter tăng, tăng `max` lên (tối đa 100 ms); khi ổn định 30 s, giảm về 0. Có thể đổi **giữa phiên**, không cần renegotiate.
- Tham số vào `stats` để người dùng thấy: `jitter_buffer_ms`. Nếu >60 ms kéo dài ⇒ banner "mạng không ổn định".

### 35.8 Timestamp & đồng bộ A/V — 5 mốc
| Mốc | Đặt ở | Dùng để |
|---|---|---|
| `t_capture` (QPC) | sau `AcquireNextFrame` | đo chặng 6–8 |
| `t_encode_in` / `t_encode_out` | quanh encoder | đo chặng 8 |
| `pts` (90 kHz) | gán theo **QPC capture**, không theo wall clock | ổn định qua NTP jump |
| `rtp_ts` | suy ra từ `pts` cùng timebase | A/V sync |
| `t_send` | trước `sendto` (hook GStreamer) | đo chặng 9–10 bằng `ack`/TWCC |
- **Audio và video phải dùng cùng gốc QPC**, không phải `GstSystemClock` mặc định nếu 2 pipeline tách. Sai chỗ này = lệch tiếng/hình 200–500 ms (đã nêu ở §5.6 nhưng **cơ chế** là ở đây).
- Clock: `GstSystemClock` (monotonic) — **không** dùng wall clock. Nếu cần map sang wall clock (cho audit), lưu offset 1 lần lúc khởi động.
- Nếu PTS nhảy ngược (sau restart capture) → **reset base**: `new_base = old_base + (last_pts - first_pts_new) + 1 frame`; không để RTP timestamp nhảy ngược (client sẽ treo/hỏi keyframe liên tục).

### 35.9 Tuning theo loại nội dung (screen content)
| Cấu hình | Khi nào | Tác dụng |
|---|---|---|
| `nvh264enc preset=p1 tune=ull bframes=0 rc=cbr zerolatency=1` | mặc định | trễ thấp nhất |
| thêm `intra-refresh=1` (thay keyframe) | mạng hay mất gói | không có IDR đột ngột ⇒ không "khựng" |
| `qos=1` trên pipeline | CPU/GPU yếu | tự bỏ frame thay vì tăng trễ |
| `x264enc tune=zerolatency sliced-threads=1 sliced-threads=4` | fallback CPU | giảm trễ ở x264 |
| bitrate **thấp + text sắc** (không B-frame, `spatial-aq`) | đọc chữ/terminal | chữ không bị nhoè |
| **`h264parse config-interval=-1`** | luôn | gửi lại SPS/PPS trước mỗi IDR ⇒ client vào muộn vẫn giải mã được |
| FEC (ULPFEC + RED) | loss >2% | tăng băng thông 10–30%, giảm giật |
> Screen content (chữ, đường kẻ) **khó mã hoá hơn video tự nhiên** ở cùng bitrate — đây là lý do preset "Nét" (§6.10.1) tồn tại và tại sao 8 Mbps cho 1080p60 desktop có thể **không đủ** khi cuộn trang chữ nhỏ. Ghi rõ để không ai ngạc nhiên.

### 35.10 Thay đổi giữa phiên (cái gì làm pipeline dừng)
| Sự kiện | Dừng gì | Cách làm | Người dùng thấy |
|---|---|---|---|
| Đổi resolution display ảo | capture + encoder + pool | `set_state(PAUSED)` pipeline video → đổi display → tạo lại pool → `PLAYING` | đen 1–3 s + "Đang đổi kích thước…" |
| Đổi preset chất lượng | chỉ encoder | `webrtcbin` giữ nguyên; đổi `bitrate`/`preset` qua property hoặc tạo lại encoder element | không gián đoạn (có thể 1 nhịp) |
| Đổi cursor mode | không dừng gì | bật/tắt `IncludeCursor`/composite | nhịp ~100 ms |
| Chuyển cửa sổ | không dừng pipeline (cùng display) | capture vẫn chạy, không làm gì | 0.5–1.5 s (move window) |
| Đổi mode HVNC↔VNC | capture + có/không move | dừng capture, đổi nguồn, khởi động lại | 1–2 s |
| Mất GPU / driver reset | encoder | fallback x264 + giảm resolution | "Đã chuyển sang CPU" |
| Đổi monitor (VNC) | capture | recreate duplication | 1–2 s |
**Bất biến:** `webrtcbin`, DTLS, SRTP, DataChannel **không bao giờ** bị dựng lại vì thay đổi hiển thị. Nếu phải dựng lại ⇒ đã thiết kế sai.

### 35.11 Chế độ màn hình tĩnh (tiết kiệm CPU/GPU/pin/băng thông)
- Máy không đổi pixel (đọc sách, xem tài liệu, để yên): **không gửi frame** hoặc gửi 1 frame/2 s.
- Phát hiện: so **hash 64×64** của frame; nếu giống 5 frame liên tiếp → vào chế độ tĩnh.
- Thoát: hash đổi, hoặc có input, hoặc có keyframe request, hoặc 2 s timeout.
- Trong chế độ tĩnh: encoder vẫn chạy nhưng `bitrate` giảm về ~50 kbps; audio vẫn đi bình thường.
- Lợi ích thực tế: **pin điện thoại** và **data 4G** — hai thứ người dùng mobile quan tâm nhất (§30). Đo được: giảm 40–70% băng thông khi đọc tài liệu.

### 35.12 Restart & shutdown theo thứ tự (nếu sai → deadlock/crash driver)
```
Khởi động phiên:
  1 pool → 2 capture → 3 video pipeline PAUSED → 4 audio pipeline PAUSED
  → 5 webrtcbin (offer/answer, DTLS) → 6 PLAYING cả hai → 7 bắt đầu input

Dừng phiên (thứ tự NGƯỢC, bắt buộc):
  1 ngừng nhận input (chặn mới, chờ đang xử lý ≤100 ms)
  2 dừng audio PLAYING→NULL
  3 dừng video NULL (giải phóng encoder + texture)
  4 đóng webrtcbin (đợi DTLS close hoặc 500 ms)
  5 ReleaseFrame mọi frame còn treo (assert = 0)
  6 huỷ pool + D3D11 device
  7 restore cửa sổ + audio (§9.2.4, §5.10.3)
  8 xoá state file
```
- Timeout tổng 3 s; nếu vượt ⇒ log `cleanup_timeout` + **vẫn** restore cửa sổ/audio (không được bỏ bước 7 vì đây là thứ ảnh hưởng người dùng thật).
- Restart một thành phần (capture chết): chỉ 2→3 của video; **không** đụng webrtcbin/audio/input.
- Crash toàn process: state file + khởi động lại (§9.2.4) — đây là lý do state file phải ghi **trước** khi move window.

### 35.13 Ưu tiên luồng & tránh bị hệ điều hành "trễ"
| Thành phần | Cơ chế | Vì sao |
|---|---|---|
| capture | `MMCSS "Capture"` + `AvSetMmThreadCharacteristics` | Windows hạ ưu tiên thread khi không có MMCSS ⇒ trễ spike 50 ms |
| encoder | GStreamer thread + MMCSS "Playback" | |
| input | **`THREAD_PRIORITY_TIME_CRITICAL`** + MMCSS | click phải đi ngay |
| audio | MMCSS "Audio" | |
| net/stats/audit | ưu tiên thường | không cần |
- Core affinity: **không** ghim mặc định (gây hại trên máy nhiều P/E-core); chỉ ghim khi đo thấy di cư E-core gây spike.
- Tránh: `timeBeginPeriod(1)` toàn cục (tăng tiêu thụ pin toàn máy) — chỉ dùng trong lúc phiên, và nhả khi kết thúc.

### 35.14 Ngân sách bộ nhớ & VRAM
| Thành phần | Đo | Ngân sách/phiên |
|---|---|---|
| Texture pool video | 4 × 1920×1080 NV12 | ≈12.5 MB VRAM |
| Encoder NVENC session | ~64–128 MB VRAM | tuỳ driver |
| Ring buffer input | 64 KB × 2 | 128 KB |
| Frame metadata | nhỏ | <1 MB |
| Pipeline GStreamer | ~40–80 MB RSS | |
| Jitter/encoder queue | ≤ 3 frame | ≈37 MB RAM/VRAM |
| **Tổng mục tiêu** | | **<200 MB RSS + <200 MB VRAM** |
- Đo bằng `GetProcessMemoryInfo` + `IDXGIAdapter3::QueryVideoMemoryInfo`, đưa vào stats.
- Khi VRAM <150 MB trống → **từ chối tạo phiên mới** với lỗi rõ ràng (tốt hơn là crash giữa phiên).
- Rò rỉ phát hiện bằng: tăng đơn điệu `handle_count`/`VRAM` qua 60 phút ⇒ tự restart pipeline + `audit.warn`.

### 35.15 Ma trận fault-injection (bắt buộc làm trước khi coi là xong Phase 1)
| # | Bơm lỗi | Kỳ vọng |
|---|---|---|
| 1 | `ACCESS_LOST` mỗi 30 s | recreate im lặng, ≤1 s mất hình, không đóng phiên |
| 2 | Capture chết hẳn | switch WGC → BitBlt → nếu vẫn chết: báo, giữ phiên 60 s |
| 3 | Encoder init fail | fallback x264 + giảm 720p + thông báo |
| 4 | GPU bị reset (TDR) giữa phiên | fallback x264, không đóng phiên, không crash |
| 5 | Audio device mất 5 s | video tiếp tục, `audio_unavailable`, tự khôi phục |
| 6 | Mất 30% gói 10 s | adaptive giảm bitrate, không đóng phiên, `move` vẫn dùng được |
| 7 | RTT nhảy 300 ms | không deadlock, stats đúng |
| 8 | SCTP đầy | backpressure `ctrl`, không drop keyup |
| 9 | Input flood 500 evt/s | drop `move`, giữ `ctrl`, rate-limit + 1 warning |
| 10 | Dừng phiên khi đang encode | không crash, assert frame treo = 0, cleanup <3 s |
| 11 | Kill process giữa lúc move window | khởi động lại → cửa sổ được cứu (§9.2.3) |
| 12 | Đổi resolution 10 lần liên tiếp | không rò VRAM/handle, không crash |
| 13 | Sleep/resume máy | phục hồi hoặc đóng sạch, không treo |
| 14 | Màn hình thứ 2 bị rút | capture recreate, không crash |
| 15 | CPU 100% trong 10 s | drop frame, không tăng trễ vô hạn |

---

## 36. Transport tuning & điều tiết băng thông (nhánh #2 — quyết định p95 có đạt hay không)

> §5.6 viết *"adaptive: loss >5% trong 3 s → −25%; loss <1% trong 10 s → +15%"*. Đó là **một câu**, không phải thuật toán: nó sẽ dao động (tăng rồi giảm rồi tăng), không biết băng thông thật, không phân biệt mất gói do nghẽn với mất gói do sóng Wi-Fi, và không nói *giảm cái gì* (bitrate? fps? resolution?).
> Chương này thay thế nó bằng: **ai sở hữu quyết định**, **thuật toán cụ thể có số**, **giảm theo thứ tự nào**, và **kiểm chứng ra sao**.

### 36.1 Ai sở hữu gì (ranh giới với thư viện)
| Việc | Ai làm | Ghi chú |
|---|---|---|
| Ước lượng băng thông khả dụng | **Ta** (từ TWCC + REMB) | không tin mù vào lib; GStreamer's CC chưa đủ tốt cho screen content |
| Quyết định bitrate/fps/resolution | **Ta** (`BitrateAllocator`) | đây là nơi hiểu "chữ nhỏ cần nét" |
| Pacer (nhịp gửi gói) | **Ta** (nếu lib không đủ) hoặc `rtpgccbwe`+`rtpbin` pacer | nếu không pace, encoder bắn burst 200 gói → hàng đợi router đầy → spike trễ |
| Đóng gói RTP/SRTP | webrtcbin | |
| Jitter buffer (nhận) | **Browser** | ta chỉ ảnh hưởng qua `playout-delay` (§36.8) |
| Keyframe | **Ta** (quyết định *khi nào*) | §36.6 |
| FEC / NACK / RTX | Ta bật/tắt + cấu hình | §36.7 |

**Rủi ro phải xác minh ở Phase 0** (ghi rõ vì không thể biết trước): liệu GStreamer 1.22+ expose TWCC feedback đủ để ta tự chạy CC, hay phải (a) dùng `rtpgccbwe` (loss-based, thô), (b) chèn probe element đọc RTCP, hoặc (c) chuyển sang Pion sidecar (§16.6). **Đây là câu hỏi chặn #1 của Phase 0**, cùng với 80 ms.

### 36.2 Ba nguồn thông tin (và tin ai)
| Nguồn | Cho biết | Tin bao nhiêu |
|---|---|---|
| **TWCC** (transport-wide CC feedback, RTCP) | thời điểm *từng gói* tới nơi → mất gói + một-chiều-trễ theo thời gian | **chính** — độ phân giải cao, phát hiện nghẽn sớm |
| **REMB** (browser → ta) | browser ước lượng nhanh | phụ — dùng làm trần, làm mượt |
| **Loss/NACK/PLI counters** (RR) | mất gói thô, chu kỳ | phụ — để phân loại nguyên nhân |

**Luật tổng hợp:** `target = min(delay_based_estimate, loss_based_cap, remb_cap, policy_cap)`.
- `remb_cap` làm mượt EMA 0.3 (browser hay nhảy).
- Nếu TWCC không có (browser/proxy không hỗ trợ) → fallback REMB, và ghi `cc.mode=remb` vào stats để biết chất lượng điều tiết đang kém.

### 36.3 Phân loại mất gói — chỗ §5.6 không có
Không phải mất gói nào cũng là nghẽn. Phân loại bằng cách so **mất gói** với **trễ tăng**:

| Trạng thái | Dấu hiệu | Hành động |
|---|---|---|
| **Nghẽn (congestion)** | mất gói **VÀ** one-way delay tăng liên tục | **giảm mạnh** (×0.85 hoặc ×0.7 nếu nặng) |
| **Mất ngẫu nhiên** (Wi-Fi/4G) | mất gói **NHƯNG** trễ ổn định | **không giảm bitrate**; bật **FEC/NACK** (§36.7) |
| **Burst mất** (chuyển tay 4G) | mất theo cụm 10–40 gói, trễ nhảy rồi về | giảm nhẹ 1 bậc, **không** reset về min; chờ 500 ms |
| **Jitter cao, không mất** | trễ dao động, mất ~0 | **không giảm** bitrate; tăng `playout-delay` (§36.8) |
> Đây là khác biệt lớn nhất so với "loss >5% → −25%": nếu không phân loại, mỗi lần Wi-Fi nhiễu (mất 2% ngẫu nhiên) ta lại hạ chất lượng vô ích, rồi lại nâng, rồi lại hạ → **hình nhấp nháy độ nét** — đúng thứ người dùng ghét nhất.

### 36.4 Máy trạng thái điều tiết (số cụ thể)
```
        ┌──────────┐  2 s ổn định, dưới 70% trần
        │ STARTUP  │──────────────────────────────┐
        │ ×1.5/200ms│                             ▼
        └────┬─────┘                        ┌─────────┐
             │ mất/trễ tăng                │ CRUISE  │◄──────────┐
             ▼                              │ ±5%/s   │           │
        ┌──────────┐  500 ms ổn định        └────┬────┘           │
        │ DRAIN    │──────────────────────────────┘                │
        │ ×0.85    │                                               │
        └──────────┘                          ┌──────────┐         │
             ▲                                │  PROBE   │─────────┘
             │ mất nặng                       │ +10%,1 s │  thành công
        ┌────┴─────┐                          └──────────┘
        │ BACKOFF  │◄──── mất nặng khi PROBE
        │ ×0.7     │
        └──────────┘
```
| Trạng thái | Điều kiện vào | Hành vi | Ra |
|---|---|---|---|
| **STARTUP** | bắt đầu phiên / sau đổi mạng | nhân **1.5× mỗi 200 ms** cho tới khi thấy trễ tăng hoặc mất | trễ tăng → DRAIN |
| **DRAIN** | vừa phát hiện over-use | **×0.85** mỗi 200 ms, tối đa 3 lần (≈ −60%) | 500 ms không mất → CRUISE |
| **CRUISE** | gần băng thông thật | **+5%/s** (chậm, tránh vượt) | mất → phân loại §36.3 |
| **PROBE** | CRUISE 10 s | +10% trong 1 s để dò trần | thành công → CRUISE; thất bại → BACKOFF |
| **BACKOFF** | mất gói do nghẽn | **×0.7** ngay, rồi chờ 1 s | 1 s ổn → CRUISE |
**Clamp & chống dao động (bắt buộc):**
- Trần: `policy_cap` (§6.10.1 preset) và `remb_cap`.
- Sàn: **300 kbps** video (dưới nữa thì thà về "Low" 720p30).
- Thay đổi mỗi bước **≤ ±20%** (trừ BACKOFF được −30%).
- Hysteresis: **không tăng** trong 1 s sau bất kỳ lần giảm nào.
- Không tăng trong **1 s** sau keyframe (vì IDR làm tăng bitrate tạm thời → estimator tưởng nghẽn).
- Nếu bitrate **dao động >20% biên độ trong 5 s** (đo bằng variance) ⇒ **khoá 10 s ở mức thấp hơn**, ghi `cc.oscillation`.

### 36.5 Phân bổ băng thông (thứ tự cứng)
```
target_total (từ §36.4, đơn vị = byte/s thực trên dây)
  ├── overhead RTP/SRTP/UDP/IP      ≈ 4.7% @1200 B payload   (tính trước, không đoán)
  ├── audio (luôn được cấp trước)   Opus 24–32 kbps + DTX; không bao giờ bị bóp
  ├── RTCP/TWCC/keepalive           ≈ 5 kbps (dự phòng)
  ├── FEC nếu bật                   10–30% của video (chỉ khi mất ngẫu nhiên)
  └── video = phần còn lại
```
**Luật:**
1. Audio **không bao giờ** bị giảm vì video. Nếu không đủ cho cả hai → giảm video về sàn, nếu vẫn không đủ → **tắt video tạm** (chỉ audio) + banner. (Hiếm, nhưng phải định nghĩa.)
2. Khi bật FEC, **giảm bitrate video trước** để FEC không ăn vào phần đã cam kết.
3. `target_total` tính bằng **byte trên dây**, không phải bitrate encoder — sai chỗ này thì luôn vượt 5–8% và estimator luôn báo nghẽn.

### 36.6 Keyframe — chính sách chống "IDR storm"
**Chi phí thật:** IDR 1080p60 @8 Mbps ≈ 300–600 KB = **300–600 ms** ngân sách băng thông. 3 IDR trong 1 s = nghẽn tự tạo.

| Kích hoạt IDR | Cho phép? | Điều kiện |
|---|---|---|
| PLI/FIR từ client (mất hình) | ✅ | tối đa **2/giây**, gộp nếu đồng thời |
| Vào phiên / đổi cửa sổ / đổi resolution | ✅ | 1 lần |
| Client vào muộn | ✅ | 1 lần |
| Sau BACKOFF | ✅ nhưng **trễ 200 ms** | để không cộng dồn với mất gói |
| Định kỳ | ⚠️ **mặc định tắt** khi đã bật `intra-refresh`; nếu không có intra-refresh thì 2 s | |
| Idle → active | ✅ | |
**Cơ chế chống storm:** hàng đợi IDR với **coalescing** — nhiều yêu cầu trong 200 ms = 1 IDR; nếu đã có IDR trong 500 ms và client vẫn hỏi ⇒ **tăng `playout-delay`/kiểm tra NACK** thay vì gửi thêm IDR (dấu hiệu mất gói nặng, không phải thiếu keyframe).
**Ưu tiên:** bật `intra-refresh=1` (NVENC/QSV) khi mất gói >1% — không có IDR đột ngột, client luôn phục hồi được sau ≤1 chu kỳ refresh (1–2 s) mà không có spike băng thông.

### 36.7 FEC vs NACK vs RTX — chọn theo loại mất gói
| Cơ chế | Chi phí | Trễ thêm | Dùng khi |
|---|---|---|---|
| **NACK + RTX** | ~1 gói retransmit | +1 RTT (**30–80 ms LAN**) | mất lẻ tẻ, RTT thấp — **mặc định bật cho video** |
| **ULPFEC + RED** | +10–30% băng thông, luôn trả | 0 (không chờ) | RTT cao (>80 ms), mất 1–5% ngẫu nhiên, hoặc 4G |
| **Không gì cả** | 0 | +1 chu kỳ refresh | mất <0.2% |
| **Audio** | — | — | **Opus inband FEC + DTX**; **không** dùng NACK (không kịp) |
**Quy tắc chọn (tự động):**
```
loss_random > 3%  và RTT > 80 ms   → FEC on, NACK on
loss_random > 3%  và RTT ≤ 80 ms   → FEC off, NACK on   (retransmit rẻ hơn)
loss_random ≤ 3%                    → FEC off, NACK on
mất burst (chuyển mạng)             → FEC off, NACK on, chờ 500 ms
```
- FEC **không bao giờ** bật cho audio (Opus inband FEC đã đủ và rẻ hơn).
- Kiểm tra: FEC che được mất gói nhưng **không che được nghẽn** — nếu bật FEC mà vẫn mất, tắt FEC và giảm bitrate (§36.3 phân loại).

### 36.8 playout-delay — cơ chế can thiệp jitter buffer
- Dùng RTP header extension `http://www.webrtc.org/experiments/rtp-hdrext/playout-delay` — **phải** khai báo trong SDP answer (ta kiểm soát answer ⇒ thêm `a=extmap`).
- Giá trị: **min/max delay**, đơn vị 10 ms (ví dụ 0/0 = tối thiểu, 0/10 = tối đa 100 ms). **Xác minh cách pack bit chính xác ở Phase 0** — đây là extension thử nghiệm của Chromium, không phải chuẩn RFC, nên phải test thật với Chrome/Edge/Safari.
- Điều khiển thích ứng:

| Tình trạng | Giá trị gửi | Ghi chú |
|---|---|---|
| Ổn định 30 s | `min=0, max=0` | trễ thấp nhất |
| Jitter tăng nhẹ (mất 0) | `max=30` (300 ms? không — xem dưới) | xem bảng đơn vị |
| Mất gói + jitter | `max=60` | ưu tiên mượt hơn trễ |
| Vừa BACKOFF | `max=100` trong 2 s rồi giảm dần | tránh giật trong lúc thu hẹp |
> **Đơn vị cần kiểm chứng**: nếu đơn vị là 10 ms thì `max=10` = 100 ms. Trong spec ghi **mục tiêu bằng ms** và để hằng số `PLAYOUT_STEP_MS` cấu hình được, test ở Phase 0 rồi chốt. Không được hardcode trước khi test.
- Nếu browser không hỗ trợ extension (Safari?) → không can thiệp được; khi đó **giảm bitrate sớm hơn** (giữ mạng sạch) thay vì trông chờ buffer.
- `jitter_buffer_ms` hiện trong stats để người dùng hiểu vì sao hình giật.

### 36.9 Giảm theo thứ tự nào (degradation preference)
Khi phải giảm, **giảm cái gì trước** là quyết định trải nghiệm, không phải kỹ thuật:

| Preset | Ưu tiên giữ | Thứ tự giảm |
|---|---|---|
| **Nét** (đọc chữ) | **resolution** | fps 60→30 → fps 15 → **cuối cùng mới** hạ resolution |
| **Cân bằng** | resolution + fps | fps 60→30 → resolution 1080p→900p → fps 30→20 |
| **Mượt** (thao tác) | **fps** | resolution 1080p→900p→720p → fps 60→45 |
| **Tiết kiệm** | băng thông | resolution 720p→540p → fps 30→15 |
**Bảng bậc thang (dùng chung, có số):**
```
resolution: 1920×1080 → 1728×972 → 1536×864 → 1280×720 → 1024×576 → 854×480
fps       : 60 → 45 → 30 → 20 → 15
```
- Mỗi lần chỉ đổi **1 bậc**, chờ **2 s** đánh giá lại (tránh nhảy 3 bậc).
- Khi tăng: tăng **ngược thứ tự**, cũng 1 bậc/2 s, và **không vượt** bậc đã biết là ổn định gần nhất (nhớ `safe_ceiling`).
- Đổi resolution = **tạo lại scaler + encoder** (không cần đổi display ảo, không cần move cửa sổ). Downscale bằng **bilinear chất lượng cao** (hoặc GPU `d3d11video` scaler) — scaler rẻ làm **chữ nhoè** đúng ở preset "Nét", tức là phá mục đích.

### 36.10 Encoder rate control (khớp với x264/NVENC thực tế)
| Vấn đề | Quyết định |
|---|---|
| CBR hay VBR? | **CBR + `vbv-bufsize`** ngắn (0.5–1 s) để bitrate bám sát và trễ thấp |
| VBV quá dài | tích frame → trễ tăng; **không** dùng bufsize >1 s |
| x264 `bitrate` + `vbv-maxrate` + `vbv-bufsize` | phải set **cả ba**, thiếu `vbv` thì bitrate vượt trần |
| NVENC `rc=cbr` + `multipass=disabled` + `zerolatency` | không `multipass` (thêm trễ cho lợi ích không đáng) |
| Đổi bitrate giữa phiên | property của encoder, **không** tạo lại element (tránh mất IDR + spike) |
| Đổi resolution/fps | **phải** tạo lại (caps change) ⇒ 1 IDR, 1 nhịp khựng ~200 ms; gộp mọi thay đổi trong 500 ms thành 1 lần |
| Ứng xử khi `target` < mức tối thiểu của codec | clamp, không để encoder tự bỏ qua |

### 36.11 Mạng đổi giữa phiên
| Sự kiện | Xử lý |
|---|---|
| Wi-Fi → 4G, IP đổi | ICE restart (không đổi phiên, không restore cửa sổ) → **về STARTUP**, trần = 60% mức cuối |
| RTT nhảy >2× | giữ bitrate, tăng `playout-delay`, chờ 2 s |
| Đứt 3–30 s | giữ trần cũ **không** reset về min (tránh "khởi động lại từ thấp" mỗi lần rớt mạng ngắn) |
| Đổi VPN/đường đi | coi như mạng mới: STARTUP, xoá `safe_ceiling` |
| Băng thông tăng vọt (về LAN) | PROBE sớm (không chờ 10 s) |

### 36.12 Tham số (một bảng, có default và khoảng)
| Tham số | Default | Khoảng | Ghi chú |
|---|---|---|---|
| `cc.decision_interval_ms` | 200 | 100–500 | nhịp quyết định |
| `cc.startup_gain` | 1.5 | 1.2–2.0 | |
| `cc.drain_factor` | 0.85 | 0.7–0.95 | |
| `cc.backoff_factor` | 0.7 | 0.5–0.85 | |
| `cc.cruise_gain_per_s` | 0.05 | 0.02–0.10 | |
| `cc.probe_interval_s` | 10 | 5–30 | |
| `cc.min_video_bps` | 300 000 | 150k–800k | |
| `cc.max_step_pct` | 20 | 10–30 | |
| `cc.hysteresis_ms` | 1000 | 500–3000 | |
| `overhead_pct` | 4.7 | 4–8 | tính lại khi bật FEC |
| `idr.max_per_s` | 2 | 1–4 | |
| `idr.coalesce_ms` | 200 | 100–500 | |
| `fec.enable_loss_pct` | 3 | 1–8 | |
| `fec.overhead_pct` | 20 | 10–30 | |
| `playout.max_ms` (ổn định) | 0 | 0–100 | |
| `playout.max_ms` (jitter) | 100 | 50–300 | |
| `ladder.resolution_steps` | 6 bậc | — | §36.9 |
| `ladder.step_hold_ms` | 2000 | 1000–5000 | |

### 36.13 Đo & kiểm chứng (phải làm trong CI, không chỉ "chạy thử")
**Kịch bản mạng mô phỏng** (netem trên Linux, hoặc `clumsy`/router thật trên Windows):

| Profile | Trễ | Jitter | Mất | Băng thông | Kỳ vọng |
|---|---|---|---|---|---|
| LAN sạch | 0.5 ms | 0.2 | 0 | ∞ | 1080p60, khớp preset, **0 thay đổi bậc** trong 60 s |
| Wi-Fi tốt | 8 ms | 5 | 0.2% | 30 Mbps | 1080p60, không giảm bitrate (phân loại đúng là "mất ngẫu nhiên") |
| Wi-Fi xấu | 25 ms | 40 | 2% | 10 Mbps | 900p hoặc fps 30, **không dao động** |
| 4G | 45 ms | 25 | 1% | 4 Mbps | 720p30, FEC bật, jitter buffer >0 |
| Nghẽn đột ngột | 20 ms | 10 | 8% trong 3 s | 2 Mbps | BACKOFF trong ≤400 ms, phục hồi ≤2 s |
| Burst (chuyển mạng) | nhảy 200 ms | — | 20% trong 1 s | — | không reset về min, hồi phục ≤3 s |
| Suy giảm dần | — | — | — | 8→1 Mbps trong 20 s | giảm bậc dần, **không nhảy 3 bậc** |
**Chỉ số chấp nhận (fail CI nếu vượt):**
| Chỉ số | Ngưỡng |
|---|---|
| Thời gian phát hiện nghẽn | ≤ 400 ms |
| Thời gian phục hồi sau nghẽn | ≤ 2 s |
| Biên độ dao động bitrate ở trạng thái ổn định | ≤ 20% |
| Số IDR/giây | ≤ 2 |
| Số lần đổi bậc ladder/60 s ở LAN sạch | **0** |
| Trễ tăng thêm do CC (so với không CC) | ≤ 5 ms |
| "Nhấp nháy độ nét" (số lần đổi resolution/5 phút ở Wi-Fi tốt) | **0** |

### 36.14 Nhánh mới rẽ ra từ đây (đã thêm vào hàng đợi §0.2)
| Nhánh | Vì sao rẽ ra từ §36 |
|---|---|
| **#2a Encoder rate-control cụ thể theo từng hãng** (NVENC/QSV/AMF/x264: tham số VBV/HRD, giới hạn bitrate thực tế, sai số ±%) | §36.10 chỉ nêu nguyên tắc; mỗi hãng lệch 5–15% |
| **#2b Scaler & độ nét khi hạ resolution** (chọn scaler GPU, xử lý text sharpening, khi nào thà giảm fps hơn giảm res) | §36.9 |
| **#2c Đo TWCC/REMB thực tế trên GStreamer** (probe element, hoặc Pion sidecar) | §36.1 rủi ro |
| **#3 Fault injection harness** | vẫn chờ, §35.15 |

---

## 37. Encoder rate-control theo từng hãng (nhánh #2a — nơi 5–15% sai số phá vỡ §36)

> §36.10 chỉ nêu nguyên tắc: *"CBR + VBV ngắn"*. Nhưng cùng một câu "CBR 8 Mbps" cho ra **7.4 Mbps trên NVENC, 9.1 Mbps trên QSV, 8.6 Mbps trên x264**. Với §36 (CC đo băng thông thật), sai số đó **không phải chuyện nhỏ**: nếu encoder thật sự bắn 9.1 Mbps trong khi CC nghĩ là 8.0, CC sẽ **luôn** thấy trễ tăng → liên tục BACKOFF → hình mờ vĩnh viễn.
> Chương này chốt: **ba vòng điều khiển lồng nhau**, **đo ở đâu là sự thật**, và **tham số cụ thể cho 4 encoder**.

### 37.1 Ba vòng điều khiển lồng nhau (kiến trúc, không phải chi tiết)
```
        ┌─ Vòng ngoài: CC (§36) ──────────────────────────────┐
        │  nhịp 200 ms · mục tiêu: không nghẽn ·              │
        │  đầu ra: target_total (byte/s TRÊN DÂY)             │
        └───────────────────┬─────────────────────────────────┘
                            ▼  trừ overhead + audio + RTCP + FEC
        ┌─ Vòng giữa: trim loop (§37.2) ──────────────────────┐
        │  nhịp 500 ms · mục tiêu: encoder thật sự bắn        │
        │  đúng target_video · đầu ra: encoder_target         │
        └───────────────────┬─────────────────────────────────┘
                            ▼
        ┌─ Vòng trong: encoder RC (phần cứng/phần mềm) ───────┐
        │  nhịp 1 frame · mục tiêu: bám encoder_target        │
        │  đầu ra: gói RTP                                     │
        └──────────────────────────────────────────────────────┘
```
**Vì sao phải 3 vòng, không phải 2:** CC không thể biết vendor nào đang chạy và lệch bao nhiêu; encoder RC không thể biết mạng đang nghẽn. Vòng giữa là **cái phanh hiệu chuẩn** — nó biến "bitrate khai báo" thành "bitrate thật".
**Hằng số thời gian phải tách xa nhau** (nếu gần nhau → dao động cộng hưởng): 200 ms / 500 ms / 16 ms ⇒ tỉ lệ ≥2.5× giữa các tầng. Không được đổi `decision_interval_ms` xuống dưới 300 ms nếu trim còn 500 ms.

### 37.2 "Bitrate khai báo" ≠ "bitrate thật" — đo ở đâu
| Nơi đo | Giá trị | Tin? |
|---|---|---|
| Property `bitrate` ta set | ý định | ❌ |
| Encoder tự báo (`GstVideoEncoder` stats / vendor query) | gần đúng | ⚠️ nhiều hãng báo sai 3–10% |
| **Byte thật trên dây tại pacer (trước `sendto`)** | **sự thật** | ✅ **nguồn duy nhất** |
| Browser báo nhận được (`bytesReceived`) | sau mất gói | ✅ để tính loss, không để tính bitrate gửi |
**Trim loop (§37.1 vòng giữa):**
```
mỗi 500 ms:
  actual = byte_sent_window * 8 / window_s        # tại pacer, đã gồm overhead
  target = target_video_bps
  ratio  = actual / target
  if ratio > 1.10:  encoder_target *= (1 / ratio_clamped_0.9_1.15)
  if ratio < 0.90:  encoder_target *= 1.05              # nhích lên chậm
  encoder_target = clamp(encoder_target, 0.5*target, 1.3*target)
  hysteresis: không đổi 2 lần liên tiếp cùng chiều nếu |ratio-1| < 0.05
```
- **Không bao giờ** để trim loop bù quá 30% (nếu cần hơn ⇒ encoder/hãng có vấn đề, ghi `enc.trim_saturated` và **đổi encoder** nếu có thể).
- Nếu `ratio > 1.3` kéo dài 3 s ⇒ coi như encoder không tôn trọng CBR ⇒ chuyển sang `VBR + cap cứng` và ghi audit (một số build NVENC/QSV làm vậy với `vbv` quá nhỏ).
- **Khi màn hình tĩnh** (§35.11) `actual` thấp hơn nhiều target ⇒ **tắt trim loop** (không phải lỗi encoder) và CC cũng phải bỏ qua giai đoạn này (§37.8).

### 37.3 NVENC (NVIDIA) — tham số và bẫy
| Tham số | Giá trị | Bẫy |
|---|---|---|
| `rateControlMode` | `NV_ENC_PARAMS_RC_CBR` | **không** dùng `CBR_LOWDELAY` nếu cần bám bitrate chính xác (nó ưu tiên trễ và được phép lệch) |
| `vbvBufferSize` | ~0.5–1 s × bitrate | **quá nhỏ** (≤0.25 s) ⇒ chính NVENC giảm chất lượng đột ngột / drop frame; quá lớn ⇒ trễ |
| `vbvInitialDelay` | ≈ 0.5 × vbvBufferSize | |
| `multiPass` | **NONE** (hoặc `qres` nếu GPU rảnh) | `fullres` thêm 1 frame trễ, không đáng cho screen content |
| `enableLookahead` / `lookaheadDepth` | **0 / false** | có lookahead = thêm trễ bằng N frame |
| `zeroLatencyEnable` | **true** | |
| `frameIntervalP` (B-frame) | **1** (không B) | B-frame = trễ + không hợp screen content |
| `idrPeriod` | 2 s × fps | |
| `enableIntraRefresh` + `intraRefreshPeriod` + `intraRefreshCnt` | **bật** khi loss >1% | xem §37.7 |
| `repeatSPSPPS` | **true** | thiếu ⇒ client vào muộn không giải mã được |
| `sliceMode` | 1 slice/frame (đơn giản) hoặc multi-slice để giảm trễ tail | |
| `presetGUID` | `P1` (fastest) hoặc `P2` | **không** P4+ cho screen: thêm trễ |
| `tuningInfo` | `ULL` (ultra low latency) | |
**Sai số thật thường gặp:** NVENC CBR có **filler data** hoạt động ⇒ đạt sát target (±2%) **nhưng tốn băng thông khi tĩnh**. Trên screen content, NVENC hay **vượt 3–8% trong 1–2 s đầu** (GOP khởi đầu) rồi ổn định ⇒ trim loop phải có **warm-up 2 s** không trim.
**Giới hạn phiên:** consumer card **3–8 phiên** (tuỳ đời). Vượt ⇒ phần cứng trả lỗi khởi tạo, **không phải** mất chất lượng im lặng ⇒ §37.10.

### 37.4 QSV (Intel) — tham số và bẫy
| Tham số | Giá trị | Bẫy |
|---|---|---|
| `RateControlMethod` | `MFX_RATECONTROL_CBR` | |
| `BufferSizeInKB` | **quan trọng nhất** và hay đặt sai: `bitrate_kbps × vbv_s / 8`. Ví dụ 8000 kbps, 0.75 s ⇒ **750 KB** | đặt **KB** nhưng nhiều người đặt theo bit ⇒ buffer bé 8× ⇒ **giảm chất lượng thảm** hoặc drop |
| `TargetKbps` | = mục tiêu | QSV hiểu **kbps**, làm tròn **xuống** ⇒ 7800 kbps nếu ta set 7800.6 |
| `LowDelayBRC` | **bật** (ICQ/LA off) | tắt ⇒ QSV có xu hướng đệm |
| `GopRefDist` | **1** (không B) | |
| `GopPicSize` | 2 s × fps | |
| `MaxFrameSize` (nếu có) | `bitrate/fps × 3` | giới hạn spike 1 frame |
| `NumRefFrame` | 1–2 | nhiều ref = thêm trễ |
| `ExtBRC` / `LookAheadDepth` | **tắt / 0** | |
**Sai số thật:** QSV **thiếu filler** (trừ khi bật), nên trên màn hình tĩnh nó **thấp hơn** target đáng kể — hoàn toàn ổn định với §35.11 nhưng làm trim loop tưởng "encoder yếu". Thêm nữa, QSV **vượt 5–15% khi có text scroll nhanh** (nhiều chi tiết mới) — đây chính là ca làm CC BACKOFF oan nếu trim loop không bù.
> **Kết luận QSV:** sai số lớn nhất trong 4 hãng. Nếu Phase 0 đo trên máy Intel mà thấy `ratio` biến động >15%, phải chấp nhận **target thấp hơn 10%** làm việc (dùng `encoder_target = 0.9 × target`).

### 37.5 AMF (AMD) — tham số và bẫy
| Tham số | Giá trị | Bẫy |
|---|---|---|
| `AMF_VIDEO_ENCODER_RATE_CONTROL_METHOD` | `CBR` | |
| `VBVBufferSize` | 0.5–1 s | |
| `EnforceHRD` | **true** | tắt ⇒ bitrate trôi tự do |
| `FillerData` | **false** (screen content) | bật ⇒ tốn băng thông khi tĩnh |
| `BFrameDeltaQP` / `BFramePattern` | **tắt B-frame** | |
| `MaxNumOfRefFrames` | 1–2 | |
| `PreAnalysis` | **tắt** | thêm trễ |
| `Vbaq` / `EnableVBAQ` | bật nếu muốn vùng tối rõ hơn | ảnh hưởng phân bổ bit, không ảnh hưởng tổng |
| `IntraRefresh` | có, khi cần | |
**Bẫy riêng của AMF:** chất lượng ở **bitrate thấp (<2 Mbps)** kém hơn NVENC rõ rệt với text ⇒ với preset "Tiết kiệm" trên AMD phải **giảm resolution trước**, không ép bitrate.
**Ổn định:** AMF trên driver mới thay đổi property khá thường xuyên ⇒ **phải pin driver version** trong tài liệu và test ở Phase 0, và có fallback x264 nếu element không khởi tạo.

### 37.6 x264 (CPU, fallback) — nơi dễ sai nhất
| Tham số | Giá trị | Bẫy |
|---|---|---|
| `bitrate` | kbps | |
| `vbv-maxrate` + `vbv-bufsize` | **bắt buộc set cả hai**, bufsize = 0.5–1 s × maxrate | **thiếu `vbv-bufsize` ⇒ trần không có hiệu lực**, bitrate vượt 30%+ trong cảnh phức tạp. Đây là lỗi phổ biến nhất |
| `nal-hrd` | `cbr` (nếu cần HRD) + `filler=1` | `filler` tốn băng thông khi tĩnh → **không dùng** cho screen |
| `rc-lookahead` | **0** | >0 = trễ N frame |
| `sync-lookahead` | 0 | |
| `bframes` | 0 | |
| `sliced-threads` | **1 (bật)** + `threads = số core vật lý (≤8)` | **quan trọng:** x264 mặc định dùng *frame-level* threads ⇒ **trễ = số thread × frame time** (8 thread ≈ 130 ms!). `sliced-threads` đổi sang *slice-level* ⇒ trễ 1 frame. Thiếu dòng này, x264 **không bao giờ** đạt <80 ms |
| `tune` | `zerolatency` | |
| `preset` | `veryfast` (hoặc `superfast` nếu CPU yếu) | |
| `keyint` | 2 s × fps; `min-keyint` = keyint | |
| `scenecut` | 0 | cắt cảnh tự phát = IDR ngoài ý muốn → §36.6 |
| `repeat-headers` | 1 | |
| `aud` | 1 | |
| `intra-refresh` | bật khi loss >1% (thay keyint) | |
**Con số thật:** x264 `veryfast` + `sliced-threads` + `zerolatency` ở 1080p60 tốn **25–45% CPU** của một core hiện đại cho mỗi phiên (tuỳ nội dung). Đây là lý do §37.10 giới hạn số phiên phần mềm trên máy yếu.

### 37.7 Quy tắc chung cho cả 4 (bất biến)
| # | Bất biến | Vì sao |
|---|---|---|
| 1 | **Không B-frame** | trễ + không hợp screen content |
| 2 | **Không lookahead / pre-analysis** | mỗi frame lookahead = +16.7 ms |
| 3 | **VBV/HRD luôn khai báo**, ngắn (≤1 s) | bám target, trễ thấp |
| 4 | **`repeat SPS/PPS` = true** | client vào muộn vẫn giải mã được |
| 5 | **Không `scenecut` tự động** | IDR ngoài kiểm soát ⇒ phá §36.4 |
| 6 | **GOP = 2 s × fps**, hoặc **intra-refresh** khi loss >1% | §36.6 |
| 7 | **Đổi bitrate = property**, không tạo lại element | tạo lại = 1 IDR + caps renegotiation |
| 8 | **Đổi resolution/fps = phải tạo lại** | chấp nhận 1 nhịp khựng ~200 ms, gộp thay đổi trong 500 ms |
| 9 | **Đơn vị: kbps cho property, bps trong logic nội bộ** — chuyển đổi ở đúng 1 chỗ | lỗi 1000× là có thật và khó thấy |
| 10 | **Filler data = tắt** | tĩnh thì im, không đốt băng thông (§37.8) |

### 37.8 Xung đột thật: CBR vs màn hình tĩnh vs §35.11
Đây là chỗ 3 chương đụng nhau và **phải quyết định rõ**:
- §36 muốn CBR để CC đo được.
- §35.11 muốn **im lặng hoàn toàn** khi màn hình tĩnh (tiết kiệm pin/data — yêu cầu mobile của người dùng).
- CBR + filler sẽ **đốt 8 Mbps để gửi màu giống nhau** — vô nghĩa và phá mục tiêu pin/data.
**Quyết định:**
1. **Filler = tắt luôn** ⇒ bitrate **được phép thấp hơn target** khi tĩnh.
2. Trim loop **tạm dừng** khi ở chế độ tĩnh (§35.11), và CC **không** dùng pha tĩnh để suy ra băng thông (bỏ mẫu, giữ target cũ).
3. Khi rời chế độ tĩnh: **IDR + 500 ms warm-up**, CC vẫn giữ target cũ (**không** STARTUP lại — mạng chưa đổi).
4. `ratio < 0.5` trong **>5 s** ở trạng thái *động* ⇒ cảnh báo `enc.undershoot` (encoder bị bóp sai hoặc nội dung quá đơn giản — bình thường thì chỉ log).
> Ghi rõ để không ai "sửa" bằng cách bật filler: bật filler là **đánh đổi trực tiếp** pin/data của người dùng mobile lấy một con số cho đẹp trong stats. Không làm.

### 37.9 Chi phí đổi cấu hình giữa phiên (theo từng encoder)
| Thay đổi | NVENC | QSV | AMF | x264 | Ghi chú |
|---|---|---|---|---|---|
| bitrate | ~0 ms (property) | ~0 ms | ~0 ms | ~0 ms | không IDR |
| fps | 1 caps renegotiation (~50–150 ms, 1 IDR) | như NVENC | như NVENC | như NVENC | |
| resolution | tạo lại pool + scaler + encoder: **150–400 ms, 1 IDR** | 200–500 ms | 200–450 ms | 300–600 ms | |
| bật intra-refresh | ~0 ms | ~0 | tuỳ driver | ~0 (option-string lúc init ⇒ **cần tạo lại**) | **x264 phải tạo lại element** |
| đổi preset encoder | cần tạo lại (GUID) | cần tạo lại | cần tạo lại | cần tạo lại | |
**Luật:** mọi thay đổi cần tạo lại element đều phải **gom trong 500 ms** thành 1 lần (người dùng kéo slider chất lượng ⇒ chỉ 1 lần dựng lại).

### 37.10 Giới hạn phiên & chính sách fallback
| Encoder | Giới hạn | Khi vượt |
|---|---|---|
| NVENC (consumer) | 3–8 phiên (tuỳ đời; một số driver mới không giới hạn cứng nhưng giảm tốc) | phiên mới → **QSV/AMF** nếu có → **x264** |
| QSV | 1–2 phiên (tuỳ iGPU) | → x264 |
| AMF | 1–2 phiên | → x264 |
| x264 | giới hạn CPU: **≤ (số core vật lý / 3)** phiên ở 1080p60 | từ chối với lỗi rõ: `server.busy` + gợi ý hạ preset |
- Không bao giờ **im lặng** giảm chất lượng vì hết slot encoder: ghi stat `encoder_fallback=true` + thông báo trong UI phiên ("đang dùng CPU, hình có thể kém mượt hơn").
- Khi dùng x264 ở nhiều phiên, **không** tăng `threads` vượt core/2 mỗi phiên (tranh chấp làm tăng trễ).

### 37.11 Kiểm chứng (bắt buộc, đo chứ không tin)
| Kiểm tra | Cách | Ngưỡng |
|---|---|---|
| Bitrate thật vs target | đo tại pacer 10 s, 3 mức (2/4/8 Mbps) | **±8%** (QSV cho phép ±10%) |
| Vượt trong 2 s đầu GOP | đo 0–2 s | ≤ 20% (rồi trim bù) |
| Trễ encoder tăng thêm | `t_encode_in → t_encode_out` | p95 ≤ 8 ms (HW), ≤ 20 ms (x264 veryfast) |
| Spike khi đổi resolution | đo 2 s quanh | khựng ≤ 400 ms, 1 IDR duy nhất |
| Đổi bitrate giữa phiên | 100 lần lên/xuống | **0** IDR thêm, 0 lần tạo lại element |
| SPS/PPS có trong mọi IDR | parse H.264 stream | 100% |
| Không có B-frame | parse stream (`ffprobe -show_frames`) | 100% |
| x264 `sliced-threads` hiệu lực | so trễ p95 có/không | phải **giảm ≥50%** |
| Filler data tắt | đo bitrate khi màn hình tĩnh | ≤ 100 kbps |

### 37.12 Bảng ánh xạ tham số (một nơi để tra)
| Khái niệm | NVENC | QSV | AMF | x264 |
|---|---|---|---|---|
| Bitrate | `bitrate` (bps/kbps tuỳ element) | `bitrate` (kbps) | `bitrate` (bps) | `bitrate` (kbps) |
| RC mode | `rc-mode=cbr` | `rate-control=cbr` | `rate-control=cbr` | `pass=0` + vbv |
| VBV | `vbv-buffer-size` | `buffer-size` (KB) | `vbv-buffer-size` | `vbv-bufsize` (kbit) |
| B-frame | `bframes=0` | `b-frames=0` | `b-frames=0` | `bframes=0` |
| GOP | `gop-size` | `gop-size` | `gop-size` | `key-int-max` |
| intra-refresh | `intra-refresh=true` | `intra-refresh=true` | `intra-refresh` | `intra-refresh=true` |
| SPS/PPS lặp | `repeat-sequence-header=true` | `header` / `repeat-headers` | `repeat-headers` | `repeat-headers=true` |
| Số thread | — | — | — | `threads` + `sliced-threads=true` |
> Tên property **phải xác minh trên đúng phiên bản GStreamer** dùng (1.22/1.24/1.26 khác nhau đôi chỗ). Ở Phase 0, chạy `gst-inspect-1.0 <element>` và ghi lại vào repo làm tài liệu chuẩn — **không** dựa vào trí nhớ hay blog.

### 37.13 Nhánh mới rẽ ra
| Nhánh | Vì sao |
|---|---|
| **#2b Scaler & độ nét** (vẫn giữ) | §37.9 phụ thuộc scaler khi đổi resolution |
| **#2d Chọn encoder theo nội dung & theo phiên** (chấm điểm: text vs video, GPU rảnh, nhiệt, giới hạn slot) | §37.10 |
| **#2e Đo & pin driver/toolchain theo hãng** (ma trận driver tối thiểu, hành vi khác nhau) | §37.5, §37.12 |
| **#3 Fault injection harness** | vẫn chờ |

---

## 38. Scaler & độ nét khi hạ resolution (nhánh #2b — nơi chữ bị giết)

> §36.9 nói: preset **"Nét"** thì *"cuối cùng mới hạ resolution"*. Nhưng khi buộc phải hạ, **hạ bằng cách nào** quyết định chữ còn đọc được hay không — và có **hai cơ chế hoàn toàn khác nhau** mà §36.9 đã gộp làm một. Chương này tách chúng ra, chọn scaler, và đặt ngưỡng đo được.
> Đây là chương ảnh hưởng trực tiếp tới mục đích sử dụng phổ biến nhất: **đọc chữ trên máy từ xa**.

### 38.1 Hai cơ chế khác nhau — §36.9 đã gộp sai
| | **(A) Hạ resolution của display ảo** ("native lower") | **(B) Hạ resolution sau khi capture** ("post-scale") |
|---|---|---|
| App render ở đâu | **Ở độ phân giải thấp** ⇒ UI lớn hơn, chữ **nét ở res đó** | Ở 1080p như bình thường |
| Sau đó | capture 1280×720, **không scale** | scale 1920×1080 → 1280×720 |
| Chi phí | **1.5–3 s** (đổi display + app nhận `WM_DISPLAYCHANGE`, reflow, có khi phải restart app) | **150–400 ms** (1 IDR) |
| Chữ sau khi xem | **Nét** (nét theo res mới) | **Mờ** (nhòe do nội suy) |
| Bố cục app | Thay đổi (đúng như khi user đổi res thật) | Không đổi |
| Ảnh hưởng người ngồi máy | Có (nếu mode VNC) | Không |
| Dùng khi | người dùng **muốn chữ to/nét** (§20.3 "Chữ to") | cần **giảm băng thông nhanh** giữa phiên (§36.9) |
**Quyết định:**
1. **(B) là mặc định của ladder §36.9** — vì nó nhanh, đảo ngược được, không đụng bố cục app.
2. **(A) chỉ dùng khi người dùng chủ động chọn "Chữ to"**, hoặc khi ladder đã xuống **2 bậc liên tiếp và giữ >20 s** ⇒ gợi ý một lần: *"Muốn chữ nét hơn? Đổi sang 'Chữ to' (áp dụng 2 giây)."* Không tự đổi (vì nó reflow app của người dùng).
3. **Không bao giờ** tự làm (A) mà không nói — nó thay đổi thứ người dùng đang nhìn.

### 38.2 Vì sao hạ resolution giết chữ (cơ chế, không phải cảm tính)
Chữ trên màn hình là **chi tiết tần số cao với biên độ thấp** — đúng loại **kém nhất** cho mọi khâu trong chuỗi:
1. **Downscale nội suy** làm mất cạnh sắc: 10 px cao của chữ thành 6.7 px ở 2/3 scale ⇒ nét thành gradient.
2. **Chroma subsampling 4:2:0** (NV12) làm mất chi tiết **màu** ở cạnh chữ — với chữ đen trên nền trắng thì ít hại, nhưng với **ClearType (subpixel AA)** thì mất luôn phần làm nét ngang ⇒ chữ mảnh hơn, khó đọc hơn.
3. **H.264 ở QP cao** dùng **deblocking filter** ⇒ làm mờ thêm cạnh; và biến đổi DCT **bỏ hệ số tần số cao** trước ⇒ chữ "nhoè đều".
4. **Mắt người** đọc theo **đường viền**, không theo điểm ảnh ⇒ mất cạnh = mất khả năng đọc, ngay cả khi SSIM còn cao.
> Hệ quả: **cùng một bitrate, cùng resolution**, nội dung chữ khó hơn video tự nhiên **2–4×**. Đây là lý do 8 Mbps "đủ cho 1080p60" theo thông lệ game-streaming lại **không đủ** cho desktop văn phòng cuộn nhanh.

### 38.3 Chọn scaler (có số, có bẫy)
| Scaler | Chất lượng chữ | Chi phí 1080p→720p @60fps | Ở đâu | Ghi chú |
|---|---|---|---|---|
| **Nearest / point** | ❌ rất tệ (răng cưa) | ~0 | — | chỉ dùng để test |
| **Bilinear** | ⚠️ mờ đều | ~0 (GPU) | D3D11 VideoProcessor mặc định | "mờ như sương" — đúng vấn đề cần tránh |
| **Bicubic (Catmull-Rom)** | ✅ khá | ~0 (GPU shader) | shader tự viết, `d3d11` compute | mặc định đề xuất |
| **Lanczos-3** | ✅✅ sắc, **có halo** | ~0 GPU / **8–18 ms CPU** | shader GPU | halo quanh chữ ⇒ trông "gai"; không hợp |
| **Area / box (đúng tỉ lệ nguyên)** | ✅✅ sạch, không halo | ~0 GPU | shader, hoặc **1/2 = average 2×2** | **tốt nhất khi tỉ lệ nguyên** |
| **D3D11 VideoProcessor + `Filter=Sharpness`** | ⚠️ tuỳ driver | ~0 | DXVA | driver-dependent, không đoán được |
| **swscale (CPU, `videoscale`)** | ✅ bicubic tốt | **2–5 ms/khung** = 12–30% core | GStreamer soft | dùng khi không có GPU path |
| **swscale lanczos** | ✅✅ | **8–18 ms/khung** | GStreamer | quá đắt ở 60 fps |
**Quyết định:**
1. **Ưu tiên GPU**: D3D11 **compute shader** bicubic hoặc area, chạy **trong cùng D3D11 device** với capture và encoder ⇒ **không copy, không đọc lại CPU**.
2. **Tỉ lệ nguyên thì dùng area/box**: 1920→960 (1/2), 1280→640 (1/2). Đây là ca **nét nhất** và **rẻ nhất**.
3. **Không dùng Lanczos** cho screen content (halo quanh chữ khó chịu hơn là mờ đều).
4. **Fallback CPU** khi không có shader path: `videoscale method=4` (bicubic) — và **hạ fps xuống 30** trước khi dùng, vì 60 fps + CPU scale + CPU encode là quá tải.
5. **Xác minh ở Phase 0** (không thể biết trước): GStreamer 1.22/1.24 có element GPU scaling đủ tốt không (`d3d11convert` mức độ hỗ trợ khác nhau theo phiên bản/driver), hay phải tự viết compute shader trong pipeline. Ghi vào danh sách câu hỏi chặn.

### 38.4 Chọn bậc thang để **tránh tỉ lệ lẻ** (sửa §36.9)
Bảng §36.9 có các bậc 1728×972, 1536×864 — đó là tỉ lệ **0.9** và **0.8**, đều là **tỉ lệ lẻ** ⇒ mờ hơn cần thiết. Thay bằng thang **ưu tiên tỉ lệ nguyên/đơn giản**:
| Bậc | Kích thước | Tỉ lệ từ 1080p | Loại | Ghi chú |
|---|---|---|---|---|
| 0 | 1920×1080 | 1:1 | — | |
| 1 | **1600×900** | 0.833 (5/6) | lẻ nhưng gần "sạch" về số nguyên dọc | dự phòng |
| 2 | **1440×810** | 0.75 (3/4) | **đẹp** | 4 px → 3 px, area filter rất tốt |
| 3 | **1280×720** | 0.667 (2/3) | chấp nhận | 3 px → 2 px |
| 4 | **960×540** | **0.5 (1/2)** | **tốt nhất** | average 2×2, rẻ, nét |
| 5 | **854×480** | ~0.445 | lẻ | chỉ khi buộc |
**Luật:** khi ladder phải chọn bậc, **nhảy tới bậc có tỉ lệ sạch nhất mà vẫn đủ giảm** — ví dụ cần giảm ~35% thì chọn 1280×720 (bậc 3) **chứ không** 1440×810 (giảm 25%) rồi 1280 (giảm 44%). Giảm ít hơn nhưng **sạch hơn** tốt hơn giảm nhiều mà mờ.
> `1600×900` và `854×480` giữ trong bảng nhưng **không dùng trừ khi** các bậc sạch không đủ.

### 38.5 Sharpening — có, nhưng rất hạn chế
| Điều kiện | Làm gì |
|---|---|
| Tỉ lệ ≥ 0.75 (giảm nhẹ) | **không** sharpen — không cần |
| Tỉ lệ 0.5–0.75 | unsharp mask **nhẹ**: radius 0.6 px, amount 0.25–0.35, **chỉ trên luma** |
| Tỉ lệ ≤ 0.5 | amount tới 0.5, radius 0.8 — nhưng **cân nhắc chuyển sang (A) native** thay vì sharpen |
| Không bao giờ | sharpen khi bitrate <3 Mbps (nó tăng chi tiết ⇒ encoder tốn bit hơn ⇒ tệ hơn) |
**Bẫy:** sharpen làm **tăng entropy** ⇒ encoder cần **nhiều bit hơn** để giữ cùng chất lượng. Nếu đang giảm resolution vì **thiếu băng thông**, sharpen là **tự bắn vào chân**. UI/logic phải biết: `if (target_bps < 3Mbps) sharpening = off`.
**Vị trí:** sharpen phải nằm **trong cùng pass GPU** với scale (shader), trước khi chuyển NV12. Nếu sharpen sau khi đã NV12 ⇒ phải làm trên luma (được, nhưng ít hiệu quả hơn).

### 38.6 Vấn đề 4:2:0 — giới hạn thật, không vượt được
- Capture ra **BGRA** (DDAPI), encoder cần **NV12** ⇒ chuyển đổi **mất 3/4 thông tin màu**.
- Ảnh hưởng: chữ **trắng trên nền màu đậm**, icon màu, viền cửa sổ màu → mất sắc cạnh màu.
- Lựa chọn khác: **H.264 High 4:4:4 Predictive** — chất lượng text tốt hơn rõ rệt, nhưng **browser không giải mã được** (Chrome/Safari chỉ có High 4:2:0 / Baseline / Main cho H.264 trong WebRTC). ⇒ **không khả thi**.
- Lựa chọn khác nữa: **VP9 profile 2 (4:4:4)** — Chrome có thể? Nhưng không đảm bảo trên Safari, và hardware decode 4:4:4 hiếm ⇒ **không chọn**.
- ⇒ **Chấp nhận 4:2:0**, và **không** hứa chất lượng màu chính xác. Ghi vào §6.13 (giới hạn trung thực): *"màu ở cạnh chữ có thể lem nhẹ"*.
- Giảm nhẹ: **dither/ordered dithering** khi chuyển BGRA→NV12 giúp mượt gradient (nền tối), **không** giúp chữ. Bật khi nền tối chiếm nhiều (dark mode) — rẻ, có ích.

### 38.7 Khi nào thà giảm fps hơn giảm resolution (bảng quyết định)
Cần biết **nội dung đang là gì**. Phân loại rẻ, chạy mỗi 500 ms:
```
lấy frame 480×270 (downsample rẻ) → tính trung bình |gradient| (Sobel) trên luma
edge_density = % pixel có |grad| > ngưỡng
text_score   = edge_density cao  +  chuyển động thấp–trung bình
motion_score = trung bình |frame_i - frame_i-1| trên 480×270
```
| `text_score` | `motion_score` | Loại | Ưu tiên giữ | Hành động |
|---|---|---|---|---|
| cao | thấp | **đọc tài liệu / code / terminal** | **resolution** | giảm fps 60→30, **không** hạ res; bật sharpen nhẹ |
| cao | cao | cuộn trang chữ, bảng tính | resolution + fps cân bằng | hạ res **1 bậc sạch** trước, rồi fps |
| thấp | cao | video, animation, game 2D | **fps** | hạ res trước (mắt không thấy mờ khi đang động) |
| thấp | thấp | desktop tĩnh | băng thông | vào chế độ tĩnh §35.11 |
| — | — | không xác định được | cân bằng | dùng preset người dùng chọn |
**Đây là lý do ta cần phân loại:** cùng một "giảm 30% bitrate", với tài liệu thì nên giảm **fps**, với video thì nên giảm **resolution**. Nếu chỉ có một ladder cứng, nửa số người dùng sẽ thấy sai.
- **Không** hiện thông tin này cho người dùng (nội bộ). Người dùng chỉ thấy preset họ chọn; hệ thống tự chọn cách giảm **trong biên của preset đó**, trừ khi preset ghi rõ (như "Nét" = giữ res).
- `text_score`/`motion_score` vào stats (debug) để giải thích vì sao hệ thống chọn bậc đó.

### 38.8 Hệ quả lên client: đổi resolution giữa phiên **không được làm UI nhảy**
Khi server đổi encoder resolution, video element đổi kích thước ⇒ nếu client để video tự giãn theo thì **bố cục UI nhảy** và con trỏ mapping phải tính lại giữa lúc người dùng đang bấm.
**Luật:**
1. Video element giữ **kích thước không đổi** (theo display ảo gốc), video stream được **letterbox trong đó**.
2. Cursor mapping dùng `video.videoWidth/videoHeight` (**kích thước stream thật**), không dùng kích thước element ⇒ tự đúng (§10.4 đã đúng, nhưng phải **test** khi res đổi giữa lúc đang kéo chuột).
3. Trong 500 ms quanh lúc đổi: **không** gửi click đầu tiên nếu mapping chưa cập nhật (`videoWidth` đổi chưa kịp) — chờ `resize` event hoặc 1 frame, tối đa 100 ms. Đây là chi tiết nhỏ nhưng gây "click lệch 1 lần" rất khó chịu.
4. Không hiện overlay "đang đổi chất lượng" cho việc **chỉ đổi bitrate/fps**; chỉ hiện cho **đổi resolution** (vì có 1 nhịp khựng thật).

### 38.9 Đo độ đọc được — kiểm chứng khách quan (bắt buộc)
Không thể chỉ nhìn rồi nói "ổn". Dùng **OCR** làm thước đo:
```
1. Server render trang test: 3 cỡ chữ (8pt/10pt/12pt), 3 kiểu (sans/serif/mono),
   nền sáng + nền tối, tiếng Việt có dấu + code + số
2. Chạy qua pipeline ở các cấu hình: res × bitrate × preset (ma trận dưới)
3. Lưu frame ở client (hoặc decode lại) → Tesseract OCR → so với ground truth
4. character_error_rate (CER) = lỗi / tổng ký tự
```
| Cấu hình | CER mục tiêu (8pt, sans, nền sáng) |
|---|---|
| 1080p, 8 Mbps, Nét | **≤ 1%** |
| 1080p, 4 Mbps | ≤ 3% |
| 720p (post-scale), 8 Mbps upscale khi xem | ≤ 4% |
| 720p **native** (A), 8 Mbps | ≤ 2% |
| 720p post-scale, 3 Mbps | ≤ 10% (**báo cho người dùng: chuyển "Chữ to"**) |
| ≤540p | không đặt ngưỡng — **cảnh báo** trong UI |
- Chạy trong CI như một bài test (không phải "thử bằng mắt"), fail nếu vượt 20% so với baseline đã chốt.
- Cũng đo **SSIM trên vùng chữ** (crop vùng có `text_score` cao) — bổ sung cho CER.
- Đây là thước đo **duy nhất** chứng minh "chữ còn đọc được", và nó khách quan với mọi thay đổi codec/scaler sau này.

### 38.10 Chi phí & khả năng đảo ngược (để chọn đúng)
| Thao tác | Chi phí | Khựng | Đảo ngược | Ảnh hưởng app |
|---|---|---|---|---|
| đổi bitrate | 0 | không | tức thì | không |
| đổi fps | 50–150 ms | 1 IDR | tức thì | không |
| đổi res **post-scale** | 150–400 ms | 1 IDR + 1 nhịp | tức thì | không |
| đổi res **native** | 1.5–3 s | rõ | chậm (lại 1.5–3 s) | **có** (reflow) |
| bật/tắt sharpen | chỉ đổi shader param | không | tức thì | không |
| đổi scaler | cần dựng lại pass | 1 IDR | — | không |
**Luật:** trong 1 phiên, **tổng số lần đổi post-scale res ≤ 6** (đếm trong stats). Vượt ⇒ khoá ở bậc an toàn + log `scale.churn` — vì đổi res liên tục khó chịu hơn là hơi mờ.

### 38.11 Cấu hình (bảng tham số)
| Tham số | Default | Khoảng |
|---|---|---|
| `scale.preferred_ratios` | `[1, 0.75, 0.667, 0.5]` | danh sách bậc sạch |
| `scale.method` | `gpu_bicubic` (fallback `cpu_bicubic`) | |
| `scale.sharpen.enable_below_ratio` | 0.75 | 0.6–0.9 |
| `scale.sharpen.amount` | 0.3 | 0–0.6 |
| `scale.sharpen.min_bitrate_bps` | 3 000 000 | |
| `scale.max_changes_per_session` | 6 | 3–15 |
| `content.classify_interval_ms` | 500 | 250–1000 |
| `content.text_edge_threshold` | 0.18 | 0.1–0.3 |
| `content.suggest_native_after_s` | 20 | 10–60 |
| `dither.when_dark_ratio` | 0.6 | 0.4–0.8 |

### 38.12 Nhánh mới rẽ ra
| Nhánh | Vì sao rẽ ra từ §38 |
|---|---|
| **#2f Chuyển đổi màu BGRA→NV12 & xử lý HDR/tonemap trong cùng pass GPU** | §38.6 nói "chấp nhận 4:2:0" nhưng chưa nói *cách* chuyển đúng (matrix, range, dither), và §5.5.2 có HDR tonemap — hai việc này **cùng một shader** |
| **#2g Phân loại nội dung sâu hơn** (text/motion → còn có: video DRM đen, ảnh, biểu đồ, game) | §38.7 chỉ có 2 chiều |
| **#2c Đo TWCC/REMB trên GStreamer** (vẫn chặn Phase 0) | §36.1 |
| **#3 Fault injection harness** | vẫn chờ |
