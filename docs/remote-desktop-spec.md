# SPEC v3.30 — Remote Desktop qua trình duyệt **cho dùng cá nhân**: HVNC + VNC, window picker, âm thanh server-side, trải nghiệm điều khiển đầy đủ

- Phiên bản: **v3.30 — §58.6–§58.10 ba lỗi chỉ hiện khi chạy thật (kill sai, FIN≠RST, đọc stderr treo) + 5 test HTTP thật** · trước đó: **v3.29 — §58 đường dùng được ngay hôm nay: xem màn hình thật bằng MJPEG trong trình duyệt (0 dependency, 0 dòng JS ở client)** · trước đó: **v3.28 — §57 tầng bảo mật thành code có test: `security.rs` 7 module, 100 test, 10/14 kiểm chứng §41.10 tự động, 1 XSS thật được sửa** · trước đó: **v3.27 — §56.10 GitHub Actions đã xanh sau khi user cập nhật billing: clippy + test + Windows build + smoke-run** · trước đó: **v3.26 — §56.9 tìm ra nguyên nhân thật của `startup_failure`: account bị khoá vì billing, không phải file CI** · trước đó: v3.25 — §56.7 compile thật: 16/16 test xanh, bắt được 3 lỗi · §56.8 GitHub Actions của repo này đang tắt (không phải lỗi file)** · trước đó: v3.24 — §56 code + GitHub Actions · trước đó: **v3.23 — §54 nới lỏng (bỏ luật cứng không cần), §55 camera + micro máy chủ** · trước đó: **v3.22 — §53 host là laptop Dell 7467: QSV trước NVENC, nắp/pin/nhiệt/Wi-Fi 1x1** · trước đó: **v3.21 — §52 máy hybrid iGPU+1050: topology quyết định, DDAPI fail trên GPU rời** · trước đó: **v3.20 — §51.10–14: VRAM 4 GB, trần 1440p, sửa lỗi AdapterRAM** · trước đó: **v3.19 — thêm §51 hồ sơ GTX 1050, bẫy adapter, P0 cụ thể** · trước đó: **v3.18 — thêm §48 mô hình tuỳ chỉnh, §49 chống vỡ UI, §50 tính năng còn thiếu** · trước đó: **v3.17 — thêm §47 khởi động cùng Windows + vòng đời process + trải nghiệm theo thời gian** · trước đó: **v3.16 — thêm §46 "máy có ở đó không" (ngủ/reboot/đổi IP/khoá màn hình)**, lĩnh vực G còn trống · trước đó: **v3.15** — phạm vi thu hẹp về 1–2 người dùng (§0.3). Bản v3.14 là bản "sản phẩm": có cert, EULA, RBAC, accessibility, đóng gói ký số. Tất cả những thứ đó **đã cắt** ở đây — xem §0.3.1 để biết cắt gì và cắt có an toàn không. Lịch sử đầy đủ v1.0→v3.14 ở §0.
- Trạng thái: **Đề xuất — phần [CỨNG] đã thành code có test (§57), phần còn lại chờ P0.** Sau v3.15 spec **không còn chương lý thuyết nào cần viết**; từ v3.28 việc viết mới là **code + test cho từng chương**, và việc còn lại của bạn là **P0 (đo thật)** trên laptop.
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
| **v3.9** | **§39 vì sao gộp 1 pass (10–13 ms → 2–4 ms) · 4 lỗi chuẩn: matrix BT.709, range limited 16–235, chroma **left-sited**, dither TPDF · chuỗi 7 bước đúng thứ tự · ma trận số cụ thể · scale ở **gamma** (không linear — linear làm chữ mờ) · HDR PQ→SDR với 203 nits + BT.2020→709 · bỏ alpha · giới hạn ICC/10-bit/4:4:4 · pseudo-HLSL 1 dispatch · 3 fallback · **7 test pattern CI** (grey ramp/color bars/1px chroma line/HDR)** |
| **v3.10** | **§40 audio: routing ≠ capture · AudioPolicyConfig không có API tài liệu (rủi ro #1) · 3 mức routing (per-app → toàn máy → như VNC) + **kiểm chứng bằng EnumerateSessions** (phát hiện cả rò rỉ `audio_leak`) · app chỉ đọc thiết bị lúc khởi động · WASAPI loopback không có event khi im lặng ⇒ polling · `IMMNotificationClient` (không giành lại default device của người dùng) · **ASRC chống drift ±100 ppm = 720 ms/2 h** · toggle dùng `NULL` + SSRC mới · 12 test chấp nhận · Bluetooth client +150–300 ms không sửa được** · **§0.2 bản đồ 8 lĩnh vực, luật ≤2 lượt liên tiếp mỗi lĩnh vực** |
| **v3.11** | **§41 threat model: 10 tài sản · 10 vị trí P1–P10 · **lật giả định nền — client KHÔNG tin cậy, agent tin về hành vi nhưng không tin về dữ liệu** · 3 hệ quả kiến trúc · 20 mối đe doạ T1–T20 theo ranh giới · 5 quyết định *bắt nguồn từ threat model* (client không gửi `hwnd`; không endpoint chạy lệnh; transfer/clipboard mặc định tắt; `X-Frame-Options: DENY`; người ngồi máy luôn dừng được) · token rotate + reuse detection · P6 quyền phủ quyết · supply chain/chống downgrade · 9 rủi ro chấp nhận · 14 kiểm chứng** |
| **v3.12** | **§42 multi-session — phát hiện ràng buộc bị bỏ qua: 1 desktop = 1 con trỏ + 1 focus ⇒ chỉ 1 controller/session, N viewer** · input lease (server-side, TTL, release_all trước khi chuyển) · bảng chia sẻ vs cách ly 13 tài nguyên · admission control theo VRAM/RAM/CPU/slot/display có số (thay cho "max 3") · giới hạn display slot của VDD = câu hỏi chặn Phase 0 · fanout 1 encode → N SRTP (PLI theo **stream** không theo peer) · cách ly lỗi + tự phục hồi sau TDR · fairness 4 mức · **10 bảo đảm cách ly phải test (I1–I10), fail ⇒ tắt multi-session** · refcount dọn sau 5 s** |
| **v3.13** | **§43 client perf: vì sao client dễ chết hơn server (6 nền tảng, Safari iOS kill tab ~200–400 MB, GC không kiểm soát) · 15 chỉ số ngân sách có cách đo · quyết định render (video element ≠ canvas; cursor = div transform; HUD 2 Hz) · **10 chỗ tốn tiền thật** (#1 forced reflow từ `getBoundingClientRect` mỗi pointer event — bug phổ biến nhất, không thấy bằng mắt) · kiến trúc JS (0 dependency, 12 module, `render(state)`) · perf-probe + **CI gate thật** (size/type/perf/leak, baseline 7 ngày) · 3 giới hạn cứng mobile · overlay 0 ms main thread · 8 nguồn rò rỉ + test 50 lần vào/ra** |
| **v3.26** | **Chẩn đoán sai của tôi đã được sửa** — §56.8 từng kết luận "Actions bị tắt ở mức repo". Sai. Thí nghiệm quyết định: thay `ci.yml` bằng **6 dòng** `run: echo` ⇒ workflow **chạy được** (3 s) và annotation hiện nguyên văn: ***"The job was not started because your account is locked due to a billing issue."*** ⇒ ① Actions **không hề bị tắt**, ② repo **public cũng không** thoát được lock ở mức account, ③ `startup_failure` chỉ là cách GitHub hiển thị **cùng một lỗi billing** khi không có workflow nào nạp được. Đã khôi phục `ci.yml` đầy đủ. **Việc cần làm duy nhất: xử lý billing ở account, không phải sửa gì trong repo** |
| **v3.25** | **Compile thật, không phải hứa** — cài Rust 1.95 trong sandbox bằng gói npm `@rust-sandbox/rust-1-95-x86_64-linux` (vì `static.rust-lang.org` và `objects.githubusercontent.com` đều bị chặn ⇒ rustup không dùng được), rồi chạy `cargo build`/`test`: **16/16 xanh**, `-D warnings` sạch, `rd --demo` in ra 3 chuỗi pipeline. **Bắt được 3 lỗi mà đọc spec không thấy**: ① `mfh264enc` thiếu `b-frames=0` ⇒ test `every_encoder_is_zero_latency` **đỏ** đúng như thiết kế; ② 2 warning `dead_code` sẽ làm CI đỏ ⇒ bin chuyển sang dùng `rd_spike_lib` thay vì `mod`; ③ `Thresholds.vram_block_mb` tồn tại = **vi phạm §54.2** (VRAM không bao giờ được Block) ⇒ xoá, thay bằng `vram_low()` chỉ Warn + test `vram_low_is_a_banner_never_a_block` · thêm `spike/check.sh` (3 s, thay CI khi Actions không chạy) · **§56.8: Actions trên repo này trả `startup_failure` 0 s cho cả một workflow 7 dòng** ⇒ tắt ở mức repo, cần bạn bật trong Settings |
| **v3.24** | **Code + CI có thật** (`spike/`, `.github/workflows/ci.yml`): 4 file Rust **0 dependency** — `machine.rs` (adapter/VRAM/`cross_adapter()`/trần display), `pipeline.rs` (sinh chuỗi GStreamer desktop·camera·mic, `b-frames=0`, không multipass/lookahead), `policy.rs` (guard **3 mức**, mặc định **Warn**), `tests/spec_conformance.rs` (**14 test = spec thành assertion**) · CI 2 job: ubuntu `clippy -D warnings` + `cargo test` + **in pipeline ra log để đọc bằng mắt**; windows `build --release` + **smoke-run `rd.exe --demo`** + upload artifact `rd-windows-x64` · **5 test chặn đúng lỗi tôi từng mắc** (pin 15% chỉ warn · bắt buộc `capture-api=dxgi` · mọi encoder `b-frames=0` · "Xem phòng" không kéo capture desktop · Microsoft Basic Render không bao giờ thắng VRAM) · **ranh giới rõ**: CI không chạy được capture/NVENC/p95/VDD/khởi động/LED webcam ⇒ P0 vẫn 6 bước trên máy thật, nhưng từ nay *"CI xanh = code đúng"* thay vì *"tin tôi đi"* · đề xuất kế tiếp A `security.rs` / B `config.rs` / C `signaling.rs` / D client shell |
| **v3.23** | **Nới lỏng theo phản hồi người dùng** — tôi đã biến mọi thứ thành luật cứng: đếm được **~78 luật có số + 33 test "bắt buộc"** cho một công cụ 1–2 người. §54 phân 3 loại **[CỨNG] ≤ 20 / [MỀM] / [GỢI Ý]**, hạ nhãn 10 chỗ (VRAM, RAM, pin, nhiệt, Wi-Fi power save…), **P0 rút 11 → 6 bước/45 phút**, phần còn lại "làm khi gặp"; **8 thứ vẫn cứng** (TLS, auth, `release_all`, thứ tự restore, không kill bản cũ, không lưu tiêu đề, 1 controller, không tắt được dấu hiệu bị điều khiển); CI đếm `[CỨNG] ≤ 20` · cập nhật máy: **RAM 8 GB, Wi-Fi đã nâng lên Intel AC 8265 (2×2, 867 Mbps)** ⇒ 2 mối lo cũ (§53.7 1×1, §53.8 4 GB) **giảm hẳn** · **§55 camera + micro máy chủ**: `mfvideosrc` + `wasapi2src` (cùng code chọn thiết bị với §40), **cùng `webrtcbin`, transceiver riêng**, **không dùng NVENC** (giữ dGPU ngủ), camera 640×480 ≈ 0.6–1.2 Mbps **trừ trước** khỏi bitrate màn hình, PiP 160×120 trong STAGE (không thêm thanh thứ 3), **AEC `webrtcdsp` + `webrtcechoprobe`** lấy reference từ loa máy chủ (ta **có sẵn**), camera/mic **mặc định tắt**, **luôn hiện dấu hiệu đang bật**, **đóng thiết bị** khi hết phiên, intercom = bước 2 có push-to-talk |
| **v3.22** | **Host là LAPTOP Dell Inspiron 7467** (i5-7300HQ 45 W · HD 630 · GTX 1050 4 GB · panel 14″ 1080p) ⇒ **đảo 3 kết luận**: không cắm cáp được nên hybrid **vĩnh viễn**; trần display **1440p → 1080p** (panel 1080p, tiết kiệm 78% pixel); "sửa topology rồi hãy tối ưu code" chỉ còn đường `vdd_settings.xml` · **kết luận ngược trực giác: dùng QSV trên iGPU HD 630, để 1050 ngủ** — capture+encode **cùng adapter = 0 copy**, giảm **10–20 W** trong thân 14″, dGPU về D3cold · `order: qsv trước nvenc` (quyết định theo máy) · **Optimus D3cold ⇒ frame đầu +200–800 ms** ⇒ warm-up 5 frame, đo riêng 2 giây đầu · **gập nắp mặc định = Sleep = giết phiên** (nguyên nhân số 1 "không kết nối được" với laptop host) + lời khuyên **để nắp mở** vì máy này thoát nhiệt ở bản lề · **nhiệt**: phiên remote tệ hơn chơi game vì tải **liên tục phẳng**; 3 việc giảm nhiệt (QSV, kê đáy, **giới hạn CPU 99% tắt turbo**) + banner > 95 °C · **pin**: Sleep/Hibernate mặc định phá phiên, banner khi chạy pin, **từ chối tạo phiên nếu pin < 15%** · **máy có RJ-45 ⇒ dùng cáp, không Wi-Fi** (Intel 3165 **1x1**, power save gây spike 20–200 ms) + 4 thứ phải tắt nếu buộc dùng Wi-Fi · **RAM gốc 4 GB là ràng buộc thật** (không phải app — app < 200 MB, mà là host tự swap) ⇒ guard `ram_low_refuse_mb` · 3 cài đặt Dell âm thầm phá phiên (Thermal Management, Battery Extender, SupportAssist auto-update) · P0 laptop 11 bước **khác thứ tự desktop** (cold start, pin, nhiệt, nắp) |
| **v3.21** | **Có iGPU ⇒ máy hybrid, và §51.4 chưa đủ mạnh**: tài liệu Microsoft nói DDAPI **theo thiết kế** trả `DXGI_ERROR_UNSUPPORTED` khi chạy trên **GPU rời** trong hệ hybrid; `DuplicateOutput` **bắt buộc** device cùng adapter với output; trên hybrid `EnumOutputs` của iGPU **có thể trả 0 output**; và display ảo **có thể có trong Windows mà không có trong DXGI** (VDD #483) ⇒ `E_FAIL` = **pipeline chết**, không phải chậm · **4 topology A/B/C/D** và phán quyết từng cái · **VDD có `<gpu><friendlyname>`** (mặc định `default` = OS tự chọn = thường iGPU) + changelog 25.7.23 chọn render adapter **theo LUID từ PCI bus** ⇒ đây là công tắc quyết định · topology C (chéo adapter) tốn **1.76 GB/s copy + 2–5 ms + 1 nhân CPU** ⇒ chọn **C1 QSV** thay vì copy sang NVENC · **thang leo khi `E_FAIL`**: EnumDisplayDevices → WGC theo monitor-handle → báo `unsupported_topology` **kèm cách sửa**, **không bao giờ** tự chuyển sang capture màn hình thật · vòng dò adapter mới: **bỏ Microsoft Basic Render (0x1414)**, **không hạ preset khi lệch LUID** (hạ preset không sửa được copy chéo) · **P0-g** trước P0-a · `/diagnostics` + `capture_luid/encode_luid/same` · §48 T2 thêm "GPU mã hoá" |
| **v3.20** | **Xác nhận VRAM 4 GB** ⇒ §51.3 đảo kết luận: **VRAM không phải ràng buộc** trên máy này; trần display ảo **1920×1200 → 2560×1440**; "giật" có **4 nguyên nhân khác** và cách phân biệt bằng số (`encode_ms p95 < 8 ms` ⇒ **không phải GPU**) · trần cứng thật là **băng thông đường quét ảo** (Pascal **không có DSC**) chứ không phải VRAM ⇒ 4K có thể phải lùi **30 Hz** · cảnh báo **1050 Ti OEM low-profile bị hạ xung** (NVENC không bị, **DWM bị**) · **`Win32_VideoController.AdapterRAM` là `uint32` ⇒ tràn số với card ≥ 4 GB** — phải dùng `nvidia-smi` hoặc DXGI `DedicatedVideoMemory` (§9.4.1 bước 1b sửa theo) · cấu hình `config.json` chốt cho máy này · còn 2 câu: **có iGPU không** (quyết định bẫy LUID) và driver version |
| **v3.19** | **§51 máy chủ thật (GTX 1050)**: GitHub dùng được để **đọc source**, **không** để đo (runner không GPU) · 1050 = NVENC thế hệ 6: H.264 1080p60 dư, **không AV1**, **không HEVC B-frame** (không dùng), trần phiên **12** với driver mới (không thành vấn đề — ta dùng 1–2) · **ràng buộc thật là 2 GB VRAM ⇒ trần display ảo 1920×1200**, không phải tốc độ; hết VRAM **không báo lỗi, chỉ giật** ⇒ banner < 300 MB · **bẫy tìm từ source**: `d3d11screencapturesrc` khi `capture-api=wgc` tạo device theo **adapter index bạn truyền** (mặc định `-1`), khi `dxgi` thì theo **adapter sở hữu monitor** ⇒ máy 2 adapter (iGPU + Optimus) có thể capture và NVENC ở **2 LUID khác nhau** = copy staging +3–8 ms hoặc `not-negotiated` ⇒ P0 phải kiểm **LUID trùng** · **tin tốt P0-b**: GStreamer **có TWCC** (`rtptwcc`, `twcc-stats`) và webrtcbin tự quảng cáo `transport-cc`, **không có REMB**; ta vốn không cần CC trong GStreamer vì §36 là CC của ta ⇒ P0-b hạ từ "đổi stack" xuống "nối extmap + đọc 1 property" · VDD **25.7.23 / VDC đã ký**, cài cả display + audio trong app · 12 bước P0 cụ thể cho máy này |
| **v3.18** | **§48 tuỳ chỉnh**: 3 tầng **có số cứng** (T1 = 12 mục, T2 ≤ 20, T3 = file) · **4 phạm vi** (app/server/user/**device**) và thứ tự thắng `device > user > server > app` (device thắng để điện thoại 4G dùng "Mượt" mà laptop LAN vẫn "Nét"); mục thuộc **server** thì **không** cho ghi đè theo thiết bị · thay thanh trượt bằng **preset** (T1 không có ô số) · tìm bằng từ người dùng nghĩ ("trễ", "mờ") chứ không bằng tên tham số · **4 điều kiện để một mục được vào UI** (chống phình lại 60 mục) · "không thắt khởi động lại" + nhãn `áp dụng từ phiên sau` · **§49 chống vỡ UI**: thang **6 tầng z cố định** (0 literal `z-index`), **máy trạng thái bề mặt** (1 dialog / 1 sheet / 1 toast / 1 banner / Esc đóng đúng 1), banner **đẩy** layout không phủ, toast neo trong STAGE, test cỡ chữ 200% + 320 px + tiếng Việt + ảnh chụp baseline · **§50** 8 tính năng còn thiếu (lịch sử phiên, ghim cửa sổ, ảnh cuối khi mất mạng, chuyển app trên mobile, âm báo, chế độ mạng yếu, gửi file 1 chiều, không ghi hình) |
| **v3.17** | **§47 khởi động & vòng đời process** — chỗ hở thực tế nhất: §13.6 chỉ có 1 dòng "At log on". **4 cách tự chạy, chỉ 1 cách đúng** (Task Scheduler At-logon dưới user; **Session 0 = app chạy mà không capture được** — bẫy phổ biến nhất) · **2 cờ Task Scheduler mặc định sai**: không chạy trên pin + dừng khi rút sạc (⇒ app tắt lúc đi họp, không báo gì) · **delay 20 s** vì driver/DWM chưa sẵn sàng + retry 3×10 s + web server mở ngay · mutex `Local\` + "đã có bản khác" + **không bao giờ kill bản cũ** · **`state.json` có 4 trạng thái** (thiếu / crash / **reboot ⇒ không restore gì** / hỏng) và **HWND bị tái sử dụng** ⇒ phải khớp bộ 4 · restore **đúng thứ tự cứng** ①audio → ②cửa sổ → ④xoá display sau cùng · `install.ps1 -Restart` thay binary khi đang chạy · **first-run 5 trạng thái** + QR ở `/setup` là khoảnh khắc quyết định · **bảng hỏng dần theo thời gian** (10 s → tuần 1 → tháng 6) · 14 edge case khởi động + 7 test |
| **v3.16** | **§46 "Máy có ở đó không?"** — lỗ hổng chỉ lộ khi dùng thật: mọi chương trước giả định máy chủ **đang chạy, đã đăng nhập, trả lời được**. 5 lỗi khác nhau bị gộp thành 1 thông báo "không kết nối được" · phân biệt `refused` vs `timeout` từ browser (4 mẹo, không đạt 100%) · `SetThreadExecutionState` **chỉ khi có phiên** + nhả ngay (bug "app làm nóng pin") · **WoL: browser KHÔNG gửi được UDP** ⇒ không hứa nút "đánh thức"; bẫy **Fast Startup** · reboot sau Windows Update: "Run whether user is logged on or not" chạy **Session 0 = vô dụng**, auto-logon là **đánh đổi bảo mật của bạn** không phải mặc định · đổi IP ⇒ **Tailscale MagicDNS là đường chính** + DHCP reservation · khoá màn hình: phát hiện qua `WTSConnectState`, **không** gửi input mù · 5 lỗi → 5 câu → 5 nút |
| **v3.15** | **§0.3 Thu hẹp phạm vi: dùng cá nhân, 1 người, 1 máy.** Cắt khỏi spec: **EV cert / ký driver / SmartScreen / EULA / SBOM / GDPR / pháp lý** · **accessibility cho người khiếm thị** (screen reader qua audio, NVDA test, WCAG, UIA over the wire) · **multi-user / role / TOTP / `/admin` / handover / chia sẻ link** · **đóng gói MSI + wizard + chữ ký số / auto-update có kênh** · **RBAC, SLA, self-hosted runner, ma trận hỗ trợ nhiều OS, soak 72 h, fuzz định kỳ**. Thay bằng: **§0.3 phạm vi**, **9 điều kiện cài chạy được ngay trên máy của bạn**, **3 khoản $0 duy nhất**, và **4 thứ đổi hành vi thiết kế** (setup 30 phút; HVNC = chế độ có công tắc; 1 profile cài đặt thay 5 tab; CI = 1 workflow) |
| **v3.14** | **§44 input sâu: 2 lớp (intent vs raw) không bao giờ trộn · 15 dòng máy trạng thái input với 5 bất biến (kẹt phím) · server-side IME: 3 cách, chọn A (VK thô) và từ chối TSF · game/Raw Input/injected flag, không hứa vượt anti-cheat · remote-in-remote (2 tầng trễ, phím bị nuốt) · **accessibility: screen reader chạy trên MÁY SERVER, tiếng đọc đi qua audio stream — 0 đồng và hoạt động thật** · release_all nhảy hàng · 7 giới hạn an toàn · 10 test** · **§45 build/licence: GStreamer LGPL động OK, `gst-plugins-ugly`+x264 = GPL hoá cả app, openh264 tự build = tự gánh patent → thứ tự NVENC→QSV→AMF→MediaFoundation, **không ship x264** · GitHub Actions free nhưng **không test được GPU/desktop** ⇒ self-hosted runner · 2 khoản phải trả tiền (EV cert ký driver, VB-Audio tổ chức) · driver ký = cái bẫy thực tế nhất** |

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

### 0.2 Bản đồ nhánh — **đã dừng ở v3.15** (phạm vi thu hẹp, xem §0.3)

**Sai lầm đã mắc (v3.5 → v3.9):** đi 5 lượt liền trong **một** nhánh (video pipeline §35–39) tới mức đo ΔE2000, trong khi **cả một hệ thống con** (âm thanh §40) mới chỉ có kết luận, và **bảo mật, multi-session, đóng gói** vẫn là dòng tóm tắt.

**Cách đúng:** spec được chia thành **8 lĩnh vực**. Mỗi lượt tôi chọn **lĩnh vực nông nhất** (hoặc bị chặn), đào **một tầng**, rồi **chuyển lĩnh vực khác** — chỉ quay lại khi có lý do cụ thể. Dấu ● số tầng đã đào.

| Lĩnh vực | Trạng thái cuối | Có còn phải đào? |
|---|---|---|
| **A. Video/capture/encode** | ●●● §35–§39 — sâu nhất | **không** — chỉ còn P0 phải **đo** (p95, TWCC) |
| **B. Âm thanh** | ●● §40 | không |
| **C. Input & bàn phím** | ●● §44 | không (còn #18, nhỏ) |
| **D. Giao diện & trải nghiệm** | ●●● §22–25, §28–34, §47, **§48, §49**, §50 | sâu nhất về **trải nghiệm**: vòng đời process (§47), mô hình tuỳ chỉnh (§48), chống vỡ UI (§49), tính năng còn thiếu (§50) |
| **E. Bảo mật & tin cậy** | ●● §41 | **thu nhỏ**: giữ auth + HTTPS + token; bỏ EULA/GDPR/SBOM (§0.3.1) |
| **F. Vận hành & triển khai** | ●● §42, §45 | **thu nhỏ**: 1 phiên, `install.ps1`, $0 |
| **G. Bền vững & tiến hoá** | ●● **§46** | dữ liệu thì đóng (2 file JSON, không DB — §26.16), nhưng **máy ngủ/reboot/đổi IP** mới là vấn đề thật ⇒ §46 |
| **H. Hiệu năng client** | ●● §43 | không (còn #15, nhỏ) |

**Hàng đợi — KHÔNG còn nhánh nào để rà.** Spec đã đủ để code. Hai việc còn lại không phải "viết thêm chương":

| # | Việc | Vì sao không viết được nữa bằng giấy bút |
|---|---|---|
| **P0-a** | Đo **p95 glass-to-glass** trên máy bạn | phụ thuộc GPU/driver/Windows build thật của bạn |
| **P0-b** | Nối **extmap transport-cc** + đọc `rtpsession:twcc-stats` | **đã hạ rủi ro**: source cho thấy TWCC **có** (không có REMB, không có CC — §51.5). Chỉ cần chứng minh `bitrate-sent` giảm khi bóp băng thông |
| **P0-g** | **Topology + LUID capture == LUID NVENC** (§52) | máy **có iGPU** ⇒ DDAPI có thể **fail hẳn** trên GPU rời (§52.1 #1) chứ không chỉ chậm; và display ảo có thể **không có** trong `EnumOutputs` ⇒ **P0 phải làm bước này trước khi đo p95**, nếu không số đo vô nghĩa |
| **P0-c** | VDD tạo được mấy display, có ổn định | §42.6 |
| **P0-d** | Máy ngủ/reboot có phục hồi sạch không | §46.10 (test 1–6) |
| **P0-e** | Cài → reboot → login có tự chạy, không cần bấm gì | §47.9 (test 1–7, ~10 phút) |

> **Luật luân chuyển (≤2 lượt/lĩnh vực) đã hoàn thành nhiệm vụ.** v3.15 dùng nó để **cắt**; v3.16 tìm ra lĩnh vực trống **máy ngủ/reboot** (§46); v3.17–18 đào nốt **trải nghiệm** (§47 vòng đời, §48 tuỳ chỉnh, §49 chống vỡ UI, §50 tính năng thiếu).
> **Không còn nhánh nào để rà.** Từ v3.18, mọi việc còn lại là **P0 — đo thật** (§0.2 bảng dưới), không phải viết thêm chương.

### 0.3 PHẠM VI THẬT: **1–2 người, 1–2 cái máy, không phát hành**

> **Chốt lại (quan trọng nhất trong toàn spec):** đây là **công cụ của cá nhân/gia đình** — bạn (và nhiều nhất là **một người nữa**: vợ/chồng, anh em, người thân) ngồi ở đâu đó mở trình duyệt điều khiển **máy Windows của chính mình**. Không phát hành, không có tổ chức, không bán, không có "người dùng thứ 10".
> Spec v3.0–v3.14 đã bị **kéo về phía sản phẩm** (cert, EULA, RBAC, accessibility, đóng gói ký số). Mục này cắt những thứ đó và **nói rõ cái gì không được cắt** — vì cắt sai chỗ thì công cụ hỏng thật, không phải chỉ thiếu tính năng.

**Ranh giới "1–2 người" (dùng để quyết định giữ hay cắt):**

| Giữ nếu… | Cắt nếu… |
|---|---|
| người thứ 2 là **người bạn tin** (gia đình), và họ chỉ cần **một** trong hai: tài khoản riêng của chính họ, hoặc **link xem tạm** | cần phân quyền, cần biết ai đã làm gì, cần thu hồi quyền của một người → đó là sản phẩm |
| họ dùng **máy của chính họ** (2 máy, mỗi người 1 mật khẩu riêng) | 2 người cùng điều khiển **1 máy** cùng lúc → **không thể** về mặt Win32 (§42.1), dù có làm gì đi nữa |
| cần **chuyển phiên giữa 2 thiết bị của cùng 1 người** (điện thoại ↔ laptop) | cần nhiều người **xem cùng lúc** như họp/hỗ trợ → SFU, ngoài phạm vi |

⇒ Kết quả cụ thể của ranh giới này: **giữ 2 tài khoản** (mỗi người 1 cái, không role, không policy), **bỏ TOTP/`/admin`/handover**, **giữ 1 link xem tạm**. Xem bảng dưới.

#### 0.3.1 Đã cắt (và hậu quả chấp nhận)

| # | Hạng mục đã cắt | Nằm ở đâu (coi như lịch sử) | Vì sao bỏ | Hậu quả — chấp nhận được vì… |
|---|---|---|---|---|
| 1 | **EV cert, ký driver, attestation/Partner Center, SmartScreen** | v3.14 §45.3–45.4, §26.17 | **VDD đã được ký sẵn** — bản phát hành chính thức ký qua SignPath Foundation (miễn phí cho dự án mở). Ta **dùng bản phát hành**, không tự build driver ⇒ không cần cert của mình | Không có. Nếu sau này bạn fork/sửa driver VDD thì mới quay lại khoản này |
| 2 | **EULA, privacy notice, third-party licences, SBOM công bố** | v3.14 §45.9 (#19), §41.8 | không phát hành cho ai ⇒ không có nghĩa vụ công bố | Giữ lại **một** việc: `LICENSES.md` ghi nguồn VDD/plugin (5 phút, để 6 tháng sau bạn còn biết cái gì đang chạy trên máy) |
| 3 | **Accessibility: screen reader qua audio, NVDA, WCAG, UIA over the wire** | §44.6 (nay là ghi chú "đã cắt"), §20.18, §6.12, #17 | không có người dùng khiếm thị | Bỏ hẳn. Vẫn **giữ** `aria-label` ở picker vì nó là 3 dòng HTML, nhưng không test, không hứa |
| 4 | **Role, TOTP, `/admin`, handover, xem cùng lúc, policy** | §3 Tier 2, §22.3, §24.8, §21.6, §6.11.4 | không ai cần phân quyền giữa 2 người tin nhau | **Giữ 2 tài khoản** (mỗi người 1 mật khẩu, cùng quyền — không role) + **1 link xem tạm** (§21.6). `/admin` xoá vì không có gì để quản |
| 5 | **Đa phiên (multi-session) như *tính năng*** | §42 (toàn chương) | bạn không cần 3 phiên song song | §42 giữ làm **tài liệu giới hạn**: nếu bạn vô tình mở 2 tab, hệ thống phải trả `409` + cho **chuyển tab** thay vì phá cả hai. Đó là **phòng thủ**, không phải tính năng |
| 6 | **MSI, wizard 5 bước, auto-update có kênh + chữ ký** | §24.10, §13.6, §21.5, v3.14 §45.7 | cài 1 lần trên 1 máy | Cài bằng **script** (`install.ps1` 4 bước) — nhưng **uninstall vẫn phải sạch** (§13.7), xem 0.3.3 |
| 7 | **GDPR/retention/export dữ liệu, "xoá dữ liệu người dùng X"** | §21.8, §26.16 | luật về dữ liệu của *người khác*; đây là dữ liệu của bạn | Audit rút xuống **1 file log xoay vòng 5×10 MB**, không bảng DB, không retention job |
| 8 | **SLA nhiều mức, fairness 4 mức, admission control, fanout N viewer** | v3.14 §42.4–42.5, §42.9, §42.11 | chỉ có 1 phiên | Giữ **nguyên tắc**: quá tài nguyên thì báo lý do, không crash. Bỏ công thức |
| 9 | **CI 2 tầng, self-hosted runner, perf gate + baseline 7 ngày, soak 72 h, fuzz định kỳ, ma trận OS/browser** | v3.14 §45.2, §43.12, §21.11, §17.2 | test trên máy bạn = chính là môi trường thật | `cargo test` + 1 lần chạy tay mỗi release. **Mất** khả năng phát hiện regression tự động — chấp nhận, 1 người dùng |
| 10 | **Nhiều Windows user session / RDS / Fast User Switching** | #14 | đắt, không cần | — |
| 11 | **Ứng dụng native, SFU/broadcast, HDR streaming, cloud relay** | §3 "Không làm" | đã bị loại từ trước | — |

> **Không đụng tới:** §35–§39 (pipeline, CC, encoder, scale, màu), §40 (âm thanh), §6.3–6.7 (con trỏ/chuột/bàn phím), §44.1–44.5 (2 lớp input, máy trạng thái, IME). Đó là **kỹ thuật**, không phải production — và chúng quyết định "dùng có sướng không". Cắt chúng là cắt đúng thứ bạn cần.

#### 0.3.2 Ba khoản tiền — bây giờ là **$0** (thay §45.3)

| Thứ cần | Cách $0 | Ghi chú thật |
|---|---|---|
| Màn hình ảo (HVNC) | **VDD bản phát hành đã ký sẵn** (SignPath Foundation ký miễn phí) | Cài qua `winget install VirtualDrivers.Virtual-Display-Driver` hoặc VDC app. **Không** tự build driver |
| HTTPS | **cert tự ký** cho LAN, hoặc `tailscale cert` (free) nếu đi qua Tailscale | Trình duyệt cần secure context ⇒ cert tự ký **bắt buộc phải cài trust** trên máy bạn dùng để điều khiển (§26.6) |
| Âm thanh | **Virtual Audio Driver của cùng nhóm** (virtual speaker, thay VB-Audio) | ⚠️ Bản này **còn beta và cần `bcdedit /set testsigning on`** ⇒ **phải tắt Secure Boot** để chạy. Nếu bạn không muốn tắt Secure Boot: **VB-CABLE** (miễn phí cho cá nhân, đã ký sẵn) — chọn cái này nếu ưu tiên "không đụng vào bảo mật máy". Cả 2 đều là "cable": app phát ra loa ảo, ta capture loopback từ đó |

> Nếu bạn hỏi "có phải trả đồng nào không": **không**, với 1 điều kiện — bạn dùng **bản driver có sẵn**, không fork. Đó là toàn bộ khác biệt giữa "$0" và "$200–500/năm".

#### 0.3.3 Chín điều **không được cắt** (cắt là hỏng thật, không phải thiếu tính năng)

Không có cái nào trong đây là "production". Chúng là thứ mà **một người dùng hằng ngày** sẽ đau nếu thiếu:

| # | Giữ | Vì sao với **1 người dùng** vẫn bắt buộc |
|---|---|---|
| 1 | **Đăng nhập (≤2 tài khoản, không TOTP)** | Bất kỳ ai trong LAN/cùng Wi-Fi mở được URL đó. Không có auth = mở toang máy cho cả quán cà phê |
| 2 | **HTTPS** | Không chỉ bảo mật: **WebRTC và clipboard API yêu cầu secure context**, `http://` không chạy được |
| 3 | **Chống kẹt phím/nút** (§44.2, `release_all`) | Đây là lỗi bạn gặp **nhiều lần mỗi tuần** khi dùng thật: chuyển tab khi đang giữ Ctrl ⇒ máy kẹt Ctrl ⇒ phải reboot |
| 4 | **Restore cửa sổ + audio + display khi đóng tab / crash** (§6.11, §9.2.3, §13.7) | Nếu app chết giữa phiên, cửa sổ của bạn **mắc kẹt trên màn hình ảo** và bạn không thấy nó nữa. Đây là thứ tệ nhất có thể xảy ra với 1 người dùng |
| 5 | **`Ctrl+Alt+Shift+X` dừng khẩn cấp tại máy** | Bạn đi công tác, có người ngồi vào máy bạn. 5 dòng code |
| 6 | **Watchdog audio**: nếu app chết, default device phải được trả lại (không để máy câm) | §5.10.3 — lỗi "câm máy" là lỗi tệ nhất của loại app này |
| 7 | **Không ship codec GPL** (`gst-plugins-ugly`, x264) — dùng NVENC/QSV/AMF/MF (§45.1, §37) | Vẫn đúng, và nó **miễn phí**. x264 chỉ bật khi bạn tự build trên máy dev |
| 8 | **Uninstall sạch** (§13.7) dưới dạng `uninstall.ps1` | 1 lần, khi bạn đổi máy hoặc gỡ. Không có nó, driver/display ảo/task cũ ở lại vĩnh viễn |
| 9 | **Timeout an toàn**: mất mạng >30 s thì đóng, phiên >12 h thì đóng | Không có, một buổi sáng mở máy ra sẽ thấy phiên "ma" từ hôm qua vẫn giữ display ảo |

#### 0.3.4 Bốn chỗ **hành vi thiết kế đổi** vì đã bớt scope

| Trước (bản production) | Bây giờ (bản cá nhân) | Vì sao tốt hơn cho bạn |
|---|---|---|
| Wizard 5 bước, ≤60 s, có bước "chính sách" | **1 trang `/setup`**: mật khẩu → chọn mạng (LAN/Tailscale) → kiểm tra 5 dòng (VDD/cable/encoder/cổng) → xong. **~30 phút** tính cả cài driver | Ít bước hơn, và bước bạn thật sự cần (kiểm tra driver) vẫn còn |
| `/settings` 5 tab, ~60 mục | **1 trang, ~12 mục**: chất lượng, hiển thị, con trỏ, âm thanh, phím tắt, ngôn ngữ | 60 mục là để phục vụ nhiều người có khẩu vị khác nhau. Bạn chỉ cần 12 |
| Stealth 3 cấp S0/S1/S2 + policy | **1 công tắc "Ẩn khỏi màn hình thật"** (bật = HVNC) + 1 công tắc phụ "ẩn cả taskbar" | Bạn không cần "chính sách"; bạn cần biết cửa sổ đang ở đâu |
| CI 2 tầng + self-hosted runner + baseline | **1 workflow local**: `cargo test`, `cargo build --release`, `node ci/size-gate.mjs` | Máy bạn **chính là** môi trường thật ⇒ không cần runner thứ hai để test capture |

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
- App phải **tự chạy sau khi login** — không cần bấm gì, và phải sống sót qua reboot/kill (§47).
- **Máy phải thức và đã đăng nhập** thì mới kết nối được. Đây không phải chi tiết nhỏ: nó là nguyên nhân số 1 của "không kết nối được" ⇒ **§46** (giữ thức chỉ khi có phiên, WoL thật ra không làm được từ browser, reboot sau Windows Update, đổi IP, khoá màn hình).

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

### 2.4 Che giấu — 2 công tắc, và một thứ không tắt được
Bạn là người duy nhất dùng máy này, nên không có "mức che giấu theo chính sách" (§0.3.4). Chỉ có 2 công tắc:

| Công tắc | Bật thì | Mặc định |
|---|---|---|
| **Ẩn khỏi màn hình thật** | cửa sổ được move lên display ảo + audio route qua cable ⇒ người ngồi máy không thấy nội dung, không nghe tiếng | ✅ **bật** (đây chính là HVNC) |
| **Ẩn cả khỏi taskbar** | thêm `ITaskbarList.DeleteTab` (mất taskbar button + thumbnail hover) | ✅ bật khi công tắc trên bật |

- Tắt công tắc đầu ⇒ **VNC mode**: stream màn hình thật, không cần display ảo, không cần driver.
- Không có "S0/S1/S2": ở bản cá nhân, "mức che giấu" chỉ là **bạn có muốn ẩn hay không**. Chi tiết từng kênh rò rỉ vẫn ở §14 (hữu ích để biết cái gì *vẫn* lộ).

#### 2.4.1 Một thứ không tắt được: **thông báo đang bị điều khiển**
- Bắt đầu phiên: **toast** 1 lần ("Cửa sổ X đang được điều khiển từ xa") + **icon tray đổi màu** + tooltip ghi rõ từ đâu/bao lâu. Kết thúc: toast 1 lần.
- Vì sao vẫn giữ dù bạn muốn ẩn: (a) nếu cửa sổ "biến mất" mà chính bạn quên vì sao, bạn sẽ kill process hoặc reboot ⇒ phiên chết, khó tìm nguyên nhân; (b) đây là **ranh giới giữa "công cụ của tôi" và RAT** — bộ dấu hiệu (display ảo + ẩn taskbar + input injection) là đúng thứ Defender săn; giữ thông báo là cách rẻ nhất để không bị gắn cờ nặng hơn.
- 1 dòng code, không ảnh hưởng gì khi bạn là người duy nhất nhìn màn hình.

#### 2.4.2 Hệ quả kỹ thuật (đã có trong §14)
- Ẩn taskbar ⇒ mất **thumbnail hover** ⇒ hết lộ nội dung (§14.2). Phải **retry** vì Electron/Chromium tự thêm lại tab.
- **Alt+Tab / Task View vẫn thấy app** — không thể sạch 100% nếu không hook (và không hook, §14.3). Chấp nhận: người duy nhất có thể thấy là bạn.
- **Không** dùng hook toàn cục (`SetWindowsHookEx`/API hooking) — kỹ thuật malware, bị AV chặn, không cần thiết.

### 2.5 Bối cảnh sử dụng (cần xác nhận — ảnh hưởng legal/AV)
Spec giả định: **bạn điều khiển máy của chính bạn** (hoặc máy trong tổ chức của bạn, có sự cho phép) từ xa. Nếu là máy của người khác → phải có sự đồng ý rõ ràng; một số tính năng (S2 + elevated) có thể bị coi là công cụ xâm nhập.

---

## 3. Tính năng theo tier

### Tier 1 — CORE
| Nhóm | Nội dung |
|---|---|
| Auth | argon2id · JWT (access 15′ + refresh rotate) · lockout · **≤2 tài khoản** (bạn + 1 người thân; không TOTP, không role — §0.3.1 #4) |
| Picker | danh sách cửa sổ · thumbnail · tìm kiếm · badge `minimized`/`elevated` |
| Mode | HVNC · VNC |
| Video | H.264 (NVENC→QSV→AMF→x264) · 1080p60 · adaptive · PLI |
| Audio | Opus 48 k · per-app routing · **toggle server-side** · im lặng cục bộ |
| **Điều khiển** | **§6 đầy đủ**: cursor shape, hover, drag, dbl-click, wheel V/H, keyboard lock, pointer lock, reset modifier, IME, touch 2 mode + kính lúp, ripple, chuyển cửa sổ trong phiên |
| Session | 1 phiên · reconnect + ICE restart · resume sau reload · view-only · stats · quality selector |
| Security | HTTPS/WSS · DTLS-SRTP/SCTP · CSP/CORS · audit |

### Tier 2 — FULL (bản cá nhân: "dễ chịu hơn", không phải "nhiều người hơn")
clipboard có nút bấm · link xem tạm (1 link, view-only) · đổi preset/zoom local · chuyển cửa sổ/mode/monitor giữa phiên · chọn thiết bị audio · chế độ "bàn phím thô" (§44.3) · ẩn cả taskbar (S1)
> **Đã bỏ khỏi Tier 2** (vì là nhu cầu của sản phẩm, không phải của bạn): multi-session như *tính năng*, multi-user, role, TOTP, allowlist app, force-close, handover, audit export, stealth S2 "policy". Xem §0.3.1 #4–5.
### Tier 3 — OPTIONAL
**gửi 1 file 1 chiều (tuỳ chọn, §50.3)** · TURN · "text mode" cho mạng yếu (§50.1 #6) — **không làm**: recording · whiteboard · chat · multi-display (đã có `switch monitor`) · WoL trong app (§46.3 nói rõ vì sao không) · reboot · auto-update · login-screen control · printing · voice chat · pressure/stylus

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
| `auth` | argon2id · JWT · lockout (**≤2 tài khoản, cùng quyền**, không TOTP/role — §0.3.1 #4) | 1 |
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
| `ACCESS_LOST`/`UNSUPPORTED` | re-init DDAPI (≤3 lần/10 s) → **WGC** → **kiểm topology (§52.6)**: trên máy hybrid `UNSUPPORTED` là **lỗi chọn adapter**, re-init bao nhiêu lần cũng vô ích |
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

#### 6.11.4 Chuyển phiên giữa 2 thiết bị của bạn (thay "handover cho user khác")
Không có user khác (§0.3.1 #4). Tình huống thật: đang xem trên điện thoại, muốn chuyển sang laptop.
`POST /api/sessions/{sid}/takeover` → tab/thiết bị mới nhận, kết nối cũ bị đóng **sau khi** server nhận `release_all` từ thiết bị cũ (§42.2). Không đổi chủ sở hữu, không restore cửa sổ.

### 6.12 Bàn phím dùng được (không phải accessibility — đã cắt, §0.3.1 #3)
- Picker và toolbar **điều hướng được bằng Tab/Enter/Esc**; mọi nút có nhãn chữ (không chỉ icon).
- `prefers-reduced-motion` → tắt ripple/animation.
- Trạng thái không chỉ bằng màu: "Chỉ xem" có icon mắt, "đang kết nối" có chữ.
- Không test NVDA, không WCAG, không `aria-live` cho nội dung remote (nội dung remote là pixel — không có cách nào đọc được).

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
SETUP ──lưu config──► IDLE          (chỉ lần đầu: /setup, ~30 phút cài driver)
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
| **Kết nối tới máy chủ** | **2.5 s** | client `fetch /api/health` với `AbortController`; fail <300 ms ⇒ `refused` (app tắt), đúng 2.5 s ⇒ timeout (máy ngủ/off) — §46.7 |
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
| POST | `/api/sessions/{sid}/takeover` | — | thiết bị khác tiếp quản (§6.11.4, §42.2) |
| POST | `/api/sessions/{sid}/share` | `{ttl_min}` | link xem tạm, view-only (§21.6) |
| GET | `/api/history` | `?from=&to=` | `[{ts,sid,user,app,titleHash,mode,duration_s,end_reason,bytes_out}]` — ≤500 dòng (§50.2) |
| GET | `/api/pins` · POST · DELETE | `{wid,label}` | ghim cửa sổ hay dùng (§50.1 #2) |
| POST | `/api/upload` | multipart ≤50 MB | 1 chiều client→server, **chỉ khi bật** (§50.3); chặn `exe/ps1/bat/scr/lnk`, lưu `Downloads\RD\`, trả `{path,size,sha256}` |
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
- Lúc khởi động: **4 trạng thái** của file, **thứ tự restore cứng**, và cách nhận diện cửa sổ còn sống (`HWND` bị tái sử dụng) ⇒ **§47.4**. Đây là lưới an toàn cho crash/power loss.

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
1b. Đọc **DXGI_ADAPTER_DESC1.DedicatedVideoMemory** (KHÔNG dùng WMI `AdapterRAM` — nó là uint32, tràn số với card ≥4 GB — §51.12)
    ⇒ chọn TRẦN resolution: <3 GB → 1920x1200; 3–6 GB → 2560x1440; 6–10 GB → 4K@60 (lùi 4K@30 nếu SetDisplayConfig fail); >10 GB → 4K@60
1c. Kiểm LUID: adapter sở hữu monitor capture == adapter NVENC mở. Lệch ⇒ **KHÔNG hạ preset** (vô ích, xem §52.7)
    mà chọn QSV trên adapter capture HOẶC chấp nhận staging + ghi cross_adapter=true (§52.5)
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
| **GTX 1050 Ti (4 GB), desktop** | Balanced | **1080p60@1440p, trần 1440p** — §51.10 |
| **Laptop hybrid (HD 630 + 1050)** | Balanced | **QSV 1080p60@1080p, dGPU ngủ** — §53.2 (đảo thứ tự: qsv trước nvenc) |

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
| **Standard (mặc định)** | `install.ps1` chạy admin **1 lần** (firewall/task/cert), app chạy dưới user thường | app thường | an toàn nhất; stream được cửa sổ admin **nhưng** click/gõ bị UIPI chặn → cảnh báo `need_admin` trước khi bắt đầu |
| **Elevated (opt-in)** | Thêm shortcut/task "Run as administrator" | cả app admin | giảm an toàn: nếu server bị chiếm ⇒ toàn quyền máy; UI cài đặt cảnh báo rõ, cần tick xác nhận |
- `/setup` hỏi **1 lần**: "Có cần điều khiển app chạy quyền admin không?" → mặc định **Không**.
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
  "auth":{"max_sessions":1,"access_min":15,"refresh_days":7},   // 1 user duy nhất, không role
  "deployment":"personal",          // personal = bỏ qua policy/role/SBOM (§0.3)
  "stun":["stun:stun.l.google.com:19302"],
  "display":{"w":1920,"h":1080,"fps":60,"scale":100,"keep_after_close":true,"on_window_drift":"warn"},
  "audio":{"route_default":"ask","remember_per_app":true,"device":"CABLE Input (VB-Audio Virtual Cable)","bitrate_kbps":32},
  "encoder":{"order":["nvenc","qsv","amf","x264"],"preset":"balanced","keyframe_s":2},
  "cursor":{"mode":"auto","shape_max_kb":64},
  "input":{"block_win_l":true,"max_move_hz":120,"stuck_release_ms":3000},
  "session":{"disconnect_timeout_s":30,"idle_timeout_s":600,"max_hours":12,"grace_s":30},
  "clipboard":{"enabled":false,"text_kb":256,"img_mb":8},
  "stealth":{"hide_from_desktop":true,"also_hide_taskbar":false,"notice":"always"},  // 2 công tắc, không phải "level S0/S1/S2" (§0.3.4)
  "mode":"auto",                                    // auto | lan | vpn | internet
  "debug":{"barcode":false,"show_latency_hud":false},
  "share":{"enabled":true,"max_ttl_h":24}          // 1 link tạm (§21.6)
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
| Sleep | `SetThreadExecutionState` **chỉ khi có phiên**, `ES_DISPLAY_REQUIRED` chỉ ở VNC, **nhả ngay** khi đóng (§46.2) |
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
| Console khoá (Win+L/timeout) | HVNC: video **vẫn chạy**, input **bị chặn** → `secure_desktop`; VNC: thấy lock screen, cùng warning. Phát hiện **trước** khi bạn bấm bằng `WTSConnectState` (§46.6) |
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

### 13.6 Setup (~30 phút, một lần, trên máy của bạn)
| # | Việc | Thời gian |
|---|---|---|
| 1 | `winget install VirtualDrivers.Virtual-Display-Driver` (đã ký sẵn) hoặc VDC app | 5′ |
| 2 | Cài cable âm thanh: **VB-CABLE** (đã ký, không cần tắt Secure Boot) — hoặc Virtual Audio Driver nếu chấp nhận `testsigning on` (§0.3.2) | 5′ |
| 3 | `install.ps1`: copy binary + **Task Scheduler At-logon (delay 20 s, chạy cả trên pin)** + firewall rule 443/UDP + sinh cert tự ký — cấu hình chính xác ở **§47.2** | 2′ |
| 4 | **Cài trust cert** trên máy bạn dùng để điều khiển (Windows/macOS/iOS/Android — §26.6) | 5′ |
| 5 | `/setup`: mật khẩu → chọn LAN hay Tailscale → 5 dòng kiểm tra → xong | 3′ |
| 6 | Mở `https://<host>/` trên điện thoại, thử 1 phiên | 5′ |
> Không có wizard 5 bước có ảnh, không có bước "chính sách", không có bước "che giấu". Bước 3–5 là **bắt buộc**; 1–2 có thể bỏ (mất HVNC / mất tiếng).

### 13.7 Uninstall / rollback (bắt buộc — `uninstall.ps1`)
Thứ tự **cứng**, sai thứ tự = cửa sổ của bạn mắc kẹt hoặc máy câm tiếng:
```
1. restore audio (đọc state.json)      → 2. restore mọi cửa sổ về màn hình thật
→ 3. AddTab lại (bỏ ẩn taskbar)        → 4. xoá display ảo do ta tạo
→ 5. xoá firewall rule + Task Scheduler → 6. xoá cert tự ký khỏi store
→ 7. xoá config/state/log
```
- Nếu `state.json` mất (ổ hỏng, cài lại Windows): có **nút "Đưa mọi cửa sổ về màn hình chính"** trong tray — dùng `EnumWindows` + `SetWindowPos`, không cần state.
- **Không** gỡ VDD/cable tự động nếu chúng đã có từ trước khi cài (kiểm bằng thời điểm cài đặt).

## 14. Che giấu — từng kênh rò rỉ (bản cá nhân: 2 cột)
Đây là danh sách **để biết cái gì vẫn lộ**, không phải để hứa "ẩn hoàn toàn". Ở bản cá nhân, "người nhìn thấy" hầu như luôn là bạn.

### 14.1 Bảng rò rỉ
| # | Kênh lộ | HVNC bật | HVNC tắt (VNC) |
|---|---|---|---|
| 1 | Màn hình chính (pixel) | ❌ ẩn | ✅ lộ (đúng ý) |
| 2 | Loa thật | ❌ ẩn (route cable) | ✅ lộ |
| 3 | Taskbar button | ❌ ẩn (nếu bật công tắc 2) | ✅ lộ |
| 4 | Hover taskbar → thumbnail nội dung | ❌ ẩn (mất button ⇒ mất thumbnail) | ✅ lộ |
| 5 | `Alt+Tab` | ⚠️ **vẫn lộ** (giới hạn kỹ thuật, §14.3) | ✅ lộ |
| 6 | Task View (Win+Tab) | ⚠️ vẫn lộ | ✅ lộ |
| 7 | `Win+1..9` | ✅ thường không tới được sau khi ẩn tab | ✅ |
| 8 | Volume Mixer thấy app phát vào CABLE | ✅ chấp nhận | — |
| 9 | Notification toast của app | ✅ chấp nhận | ✅ |
| 10 | Task Manager / process list | ✅ chấp nhận (không giấu process — đó là malware) | ✅ |
| 11 | Toast + icon tray "đang được điều khiển" | ✅ cố ý (**không tắt được**, §2.4.1) | ✅ |
| 12 | Jump List / recent files | ✅ chấp nhận | ✅ |
| 13 | Screenshot toàn màn hình | ❌ không có cửa sổ trên màn hình thật | ✅ |
| 14 | Screen recording phần mềm khác | ❌ | ✅ |
| 15 | `PrintScreen` khi cửa sổ active | không active ⇒ không lộ | — |

> Chỉ **Alt+Tab / Task View** là không đóng được (§14.3). Với 1 người dùng, đây là mức "đủ tốt" — đừng đánh đổi bằng hook hệ thống.

### 14.2 Ẩn taskbar — chi tiết triển khai
```
ITaskbarList3.CoCreateInstance(CLSID_TaskbarList) → HrInit()
→ DeleteTab(hwnd)   khi bắt đầu phiên
→ AddTab(hwnd)      khi kết thúc (và khi app tự thêm lại)
```
- **Bắt buộc retry**: Electron/Chromium và vài app gọi `RegisterTab` lại sau vài giây → poll 2 s/lần, tối đa 20 lần, sau đó ghi log `hide_taskbar_flaky` (không loop vô hạn).
- Không ảnh hưởng chức năng app (chỉ shell integration). App crash ⇒ explorer tự dọn.
- Kết thúc: `AddTab` — app đã thoát thì bỏ qua (`IsWindow` false).
- Explorer restart giữa phiên → button hiện lại; phát hiện qua `RegisterWindowMessage("TaskbarCreated")` → `DeleteTab` lại.

### 14.3 Alt+Tab / Task View — giới hạn thật
**Sự thật:** Alt+Tab lấy danh sách từ cấu trúc nội bộ của `explorer`/`win32k`. Không có API công khai để loại một cửa sổ khỏi Alt+Tab.

| Cách | Hiệu quả | Rủi ro |
|---|---|---|
| `WS_EX_TOOLWINDOW` trên cửa sổ top-level | **Có** — tool window không vào Alt+Tab | đổi style app bên thứ ba: Electron/app tự quản style sẽ **tự đổi lại**; một số app vẽ lại (nháy). Phải khôi phục style cũ khi kết thúc |
| `WS_EX_NOACTIVATE` | Không giúp | cửa sổ không nhận focus ⇒ **không gõ được** |
| `ITaskbarList.DeleteTab` | Không ảnh hưởng Alt+Tab | — |
| Hook `SetWindowsHookEx` / API hook | Hiệu quả cao | **Không làm** — signature malware, AV chặn, dễ crash explorer |
| `ShowWindow(SW_HIDE)` | Mất khỏi mọi danh sách | **Không dùng** — DWM không composite ⇒ **không capture được** |
⇒ Bản cá nhân: **không bật `WS_EX_TOOLWINDOW` theo mặc định**. Nó là một tuỳ chọn trong `Nâng cao` (vì nó sửa style của app khác — rủi ro thật, lợi ích nhỏ khi bạn là người duy nhất nhìn màn hình).

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
| **Đóng gói** | **PowerShell** (`install.ps1` / `uninstall.ps1`) | copy binary + Task Scheduler + firewall rule + sinh cert + kiểm tra môi trường. **Không WiX, không MSI** (§0.3.1 #6). | ~150 dòng |
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
| Nhiều toolchain (Rust, MSVC, GStreamer SDK, Python) | 1 script `bootstrap.ps1` cài hết, pin version. |
| Debug xuyên ngôn ngữ | Ranh giới rõ: Rust ⇄ C *chỉ* qua GStreamer API và Win32. **Không** có tầng "Rust gọi C# gọi Python". |
| Client JS khó bảo trì | ES modules + JSDoc types + `// @ts-check`; lint bằng `tsc --noEmit` trong CI, không thêm build step. |
| Bus factor | Tài liệu kiến trúc (§16.2) + hướng dẫn build trong README. |

### 16.5 Nếu sau này buộc phải tách process
Chỉ khi có lý do cứng (ví dụ: encoder crash làm sập web server). Khi đó:
- Không dùng JSON/gRPC trên hot path.
- Dùng **shared-memory ring buffer** (iceoryx hoặc mmap tự viết) cho frame + input event; control-plane mới dùng IPC thường.
- Đo lại §17.3 ngay; nếu p95 vượt 100 ms ⇒ quay lại single-process.

### 16.6 Dự phòng nếu Rust + GStreamer vướng
Phase 0 (§18) là cổng kiểm tra. **Đã hạ rủi ro cho P0-b bằng cách đọc source (§51.5):** TWCC **có** (`rtptwcc`, `rtpsession:twcc-stats`), webrtcbin tự quảng cáo `transport-cc`, **không có REMB** và **không có CC** — nhưng ta không cần CC trong GStreamer vì §36 chính là CC. Chỉ khi **không nối được extmap** mới phải xét phương án 2.
Nếu `d3d11screencapturesrc` + `webrtcbin` không đạt, thứ tự thay thế:
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
13. Bảo mật: lockout sau 5 lần sai; URL/`sid` không đoán được (token ngẫu nhiên).

### 17.2 Test — 1 máy, không ma trận
Bản cá nhân: **1 OS, 1 DPI, 1 GPU, 1 trình duyệt chính + 1 trình duyệt phụ trên điện thoại**. Ma trận đầy đủ (OS × DPI × GPU × browser × app × mạng) là việc của sản phẩm — đã cắt (§0.3.1 #9).

| Cần test | Cách |
|---|---|
| 1 máy Windows + DPI thật của bạn | test tay 8 mục §21.10 |
| Điện thoại của bạn (1 iOS **hoặc** 1 Android) | mở URL thật, thử touch + bàn phím ảo |
| Trình duyệt phụ (Chrome/Edge/Firefox) | chỉ test luồng chính: login → picker → phiên → thoát |
| Mạng | LAN + (nếu dùng) Tailscale. **Không** cần netem, không cần 4 profile loss |

### 17.3 Tiêu chí
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
| Phase | Nội dung | Ước tính |
|---|---|---|---|
| **P0** | **Spike (cổng quyết định):** Rust + GStreamer `d3d11screencapturesrc` → `webrtcbin` → browser 1080p60; DDAPI cursor shape + client render; đo glass-to-glass. **p95 >120 ms ⇒ đổi stack (§16.6) trước khi viết tiếp**. Trên **GTX 1050 Ti 4 GB**: `capture-api=dxgi`, trần **1440p**, kiểm **LUID capture == LUID NVENC** (§51) | 1–1.5 tuần |
| **P1** | **Dùng được hằng ngày:** auth 1 user, picker, HVNC move/restore + khôi phục khi crash, encoder auto-detect, input đầy đủ (§6.3–6.7), audio "hỏi mỗi phiên" + toggle, reconnect, resume, `install.ps1`/`uninstall.ps1` | 4–6 tuần |
| **P2** | **Dễ chịu:** preset/zoom, bố cục mobile, chuyển cửa sổ giữa phiên, link xem tạm, chế độ bàn phím thô | 2–3 tuần |
| — | ~~Tier 2 sản phẩm, Tier 3, ma trận test, hardening~~ | **đã cắt** (§0.3.1) |
| **Tổng** | | **≈ 8–11 tuần (1 dev, dùng cá nhân)** |

## 19. Quyết định

### 19.1 Đã chốt (v3.1)
| # | Quyết định | Ghi ở |
|---|---|---|
| 1 | **Ngôn ngữ:** Rust (core + web + tray) · C/GStreamer (media) · HTML/JS (client) · Python/Node (test). Luật: **hot path 1 process**. **Không WiX** — cài bằng PowerShell (§45.3) | §16 |
| 2 | **GPU:** auto-detect lúc chạy + micro-benchmark + tự hạ preset; người dùng đổi tay được | §9.4.1 |
| 3 | **Mạng:** LAN trước (không STUN) → Tailscale/WireGuard/ZeroTier → port-forward+STUN (Phase 2) → TURN (T3). Một binary, khác config | §13 |
| 4 | **Audio:** hỏi mỗi phiên, nhớ theo app; toggle stream riêng; routing không tự đổi | §9.6 |
| 5 | **Quyền:** user thường mặc định; elevated là opt-in khi cài, có cảnh báo | §9.9b |
| 6 | **Che giấu:** 2 công tắc (**ẩn khỏi màn hình thật** = HVNC, **ẩn cả taskbar**) đều mặc định bật; `WS_EX_TOOLWINDOW` chỉ trong Nâng cao; toast + icon tray **không tắt được** | §2.4, §14 |

### 19.2 Đã đóng hết (không còn câu hỏi chặn)
1. ~~Display ảo~~ → chốt ở §20.3: 4 lựa chọn có tên (Vừa mắt / Chữ to / Nét / Dùng thật), đổi giữa phiên 2–4 s.
2. ~~Số người dùng~~ → **1** (§0.3). Hết.
3. ~~Tier 1 đủ chưa~~ → **đủ**, và bản cá nhân còn ít hơn Tier 1 (§18).
> Câu còn mở **duy nhất** là câu kỹ thuật, không phải sản phẩm: **p95 thật trên máy bạn là bao nhiêu** (đo ở P0) và **VDD tạo được mấy display** (§42.6). Cả hai chỉ trả lời được bằng cách chạy.
### 19.3 Ba cảnh báo tôi muốn bạn thấy trước khi tôi code
1. **`Ctrl+Alt+Del` và màn hình login/UAC sẽ không điều khiển được.** Cần service SYSTEM + Winlogon — tôi để Tier 3, mặc định không làm.
2. **Video DRM (Netflix/Prime) sẽ đen** trên màn hình ảo. Không có cách vượt.
3. **Stealth (HVNC) có thể bị Defender gắn cờ** vì bộ dấu hiệu (driver display ảo + ẩn taskbar + input injection) trùng với RAT. Cách giảm: **thêm exclusion cho thư mục app** trên máy bạn, không hook API, giữ thông báo tray. Không có cách "chắc chắn không bị flag".

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
Chỉ còn **2 tầng** (bỏ tầng "chính sách/admin" — không có admin, §0.3.1 #4):

| Loại | Lưu ở | Ghi chú |
|---|---|---|
| Cài đặt chung (chất lượng, hiển thị, con trỏ, audio mặc định, ngôn ngữ) | `config.json` trên server | mọi thiết bị của bạn dùng chung |
| Cài đặt theo thiết bị (mức chất lượng cho điện thoại, cách chạm, zoom) | `localStorage` | chỉ thiết bị đó; đổi máy thì mất — chấp nhận |
| Theo app (audio route, ẩn taskbar) | `config.json` | áp cho mọi phiên của app đó |
Thứ tự thắng: **thiết bị > chung**. Cài đặt nào không áp được → nói lý do trong UI, không disable im lặng.

### 20.13 Hoàn tác, mặc định, xuất/nhập
- Mỗi thay đổi: toast có **Hoàn tác** 5 s.
- Mỗi mục: "Về mặc định" (↺ nhỏ bên phải) — chỉ hiện khi khác mặc định.
- Mỗi nhóm: "Đặt lại nhóm này".
- Toàn bộ: `⚙ → Nâng cao → Xuất cấu hình` (JSON) / `Nhập` — để chuyển máy hoặc nhờ hỗ trợ.
- Thay đổi **nguy hiểm** (đổi default audio device, bật elevated, tắt thông báo…) → có bước xác nhận **một lần**, không hỏi lại.

### 20.14 Tầng "Nâng cao" — chứa gì và mở thế nào
- Mở bằng `⚙ → Nâng cao` (**1 lần bấm, không cần tick "tôi hiểu"** — bỏ ma sát vô nghĩa). Danh sách T2 ≤ 20 mục gom **theo triệu chứng** ("trễ", "mờ") ⇒ **§48.1**.
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

### 20.18 Chỉ cần **bàn phím dùng được** (không phải accessibility)
Đã cắt accessibility/WCAG/NVDA (§0.3.1 #3). Giữ 4 dòng vì chúng là **thói quen tốt, miễn phí**:
- Mọi thứ bấm được bằng chuột cũng bấm được bằng `Tab`/`Enter`/`Esc` (cần khi tay đang cầm điện thoại / dùng 1 tay).
- Focus ring rõ ràng (không `outline: none`).
- `prefers-reduced-motion` → tắt ripple/animation (chống say tàu xe khi xem trên điện thoại).
- Không truyền tải trạng thái chỉ bằng màu (kèm icon) — để nhìn được dưới nắng, ngoài trời.

### 20.19 Cách viết chữ
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
> Danh sách đầy đủ + 4 điều kiện để một mục **được vào UI** ⇒ **§48.5**. Mục ở đây là tóm tắt.

| Không cho đổi | Vì sao |
|---|---|
| Tắt mã hoá / hạ TLS | Không thể thoả hiệp bảo mật |
| Tắt log phiên | Khi có sự cố (kẹt phím, cửa sổ mắc) log là thứ duy nhất cứu bạn |
| Theme tự do / CSS tuỳ biến | 4 theme là đủ; tự do = vỡ layout (**§49**) |
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

### 21.5 Cập nhật & sao lưu — bản cá nhân
| Việc | Cách làm (không ký số, không kênh update) |
|---|---|
| Cập nhật | **`git pull` + `cargo build --release` + `install.ps1 -Restart`** (§47.6: app đang chạy khoá file ⇒ phải shutdown-clean trước). Không auto-update, không server update, không chữ ký gói (bạn là người build ra nó) |
| Đang có phiên | nhắc "đóng phiên rồi hãy cập nhật" — **không** tự cập nhật giữa phiên |
| Sao lưu | **2 file**: `config.json` + `state.json` — copy là xong |
| Trước khi migrate schema | tự copy `config.json.bak-<ngày>` (1 dòng code, cứu bạn đúng 1 lần) |
| Mất mật khẩu | sửa tay `config.json` hoặc `rd.exe reset-admin` tại máy. Không có "email reset" |
| Rollback bản lỗi | `git checkout <tag trước>` + build lại |

### 21.6 Chia sẻ — chỉ còn **1 link tạm**
Không role, không "xem cùng lúc", không handover (§0.3.1 #4). Có **tối đa 2 tài khoản** (bạn + 1 người thân) — cùng quyền, mỗi người 1 mật khẩu; không ai xem được mật khẩu/phiên của người kia (§41.7).

| Giữ lại | Chi tiết |
|---|---|
| **Link xem tạm** | `POST /api/sessions/{sid}/share {ttl_min}` → view-only 1–24 h, thu hồi được, token 256-bit **riêng** (không phải mật khẩu của bạn). Dùng khi muốn người nhà xem màn hình mà không đưa mật khẩu — ~20 dòng code |
| Hết hạn | trang "Link đã hết hạn" (§24.11) |
| Không làm | chuyển quyền điều khiển, "xin quyền", whiteboard |

### 21.7 Người ngồi máy — chính là bạn
- **Icon tray** đổi trạng thái + tooltip "đang được điều khiển từ 192.168.1.5, 12 phút".
- **Menu tray**: "Đang kết nối từ đâu" · "Dừng điều khiển ngay".
- **Phím tắt khẩn cấp `Ctrl+Alt+Shift+X`** → ngắt mọi phiên ngay, hoạt động cả khi UI app treo (hotkey toàn cục).
- Không có "chặn người này", không có `presence` riêng — chỉ có bạn.
- **Người ngồi máy luôn có quyền dừng** — nguyên tắc, không phải tuỳ chọn (§2.4.2).

### 21.8 Pháp lý — 3 dòng
Đã cắt GDPR/retention/export/consent (§0.3.1 #7): dữ liệu ở đây là **của bạn**.

| Chỉ cần biết | |
|---|---|
| Điều khiển máy **của chính bạn** | không vấn đề pháp lý. Đây là 100% trường hợp của spec |
| Máy của người khác | phải có sự đồng ý của họ. Không ngoại lệ, không có tính năng nào để lách (§2.4.2) |
| Ghi hình (nếu bật) | chỉ quay màn hình của bạn; chỉ báo đỏ cả 2 phía là đủ |

### 21.9 Chẩn đoán khi có sự cố
- **Nút "Chẩn đoán"** (tray + `/diagnostics`): **8 kiểm tra** — display ảo có chưa? cable có? encoder nào chọn được? 443 mở? cert còn hạn? WASAPI loopback có frame? GPU driver? có phiên "ma" đang giữ display?
- **1 file log**: `%LOCALAPPDATA%\RD\rd.log`, xoay 5×10 MB, mỗi phiên 1 `corr` id ⇒ grep 1 lệnh ra cả phiên.
- Không gói zip, không upload, không trang support. Bạn đọc log của chính mình.

### 21.10 Chất lượng — 1 người, 1 workflow
| Việc | Khi nào | Ghi chú |
|---|---|---|
| `cargo test` (protocol, toạ độ §5.9, state machine §7.1/§44.2, CC §36.4) | mỗi lần build | phần thuần, không cần GPU |
| `node ci/size-gate.mjs` | mỗi lần sửa client | §43.12, 3 dòng |
| **8 mục test tay** (dưới) | trước lần dùng quan trọng | máy bạn **là** môi trường thật |
| Soak 2 h + mở/đóng 20 lần | khi sửa capture/encode | phát hiện rò VRAM/handle; **không** cần 72 h |

**8 mục test tay (5 phút — thay ma trận §17.2):** ① cửa sổ lên display ảo, màn hình thật **không** thấy ② click đúng 4 góc ③ Telex "tieengs" → "tiếng" ④ giữ Ctrl → alt-tab → nhả ⇒ **không kẹt** ⑤ tắt audio ⇒ loa thật vẫn im ⑥ F5 ⇒ resume ⑦ đóng tab ⇒ cửa sổ + audio trở lại ⑧ `Ctrl+Alt+Shift+X` dừng ngay.
> Ma trận §17.2 (OS × DPI × GPU × browser × app × mạng) đã cắt: bạn có **1** máy, **1** DPI, **1** GPU, **1** trình duyệt.

### 21.11 Rủi ro thật (top 6)
| Rủi ro | Khả năng | Ảnh hưởng | Giảm thiểu |
|---|---|---|---|
| **Defender gắn cờ** (VDD + ẩn taskbar + input injection = bộ dấu hiệu RAT) | **Cao** | Trung bình | thêm **exclusion cho thư mục app** trên máy bạn (1 lần). Không ký số, không "chống phát hiện" (§21.13) |
| P0 không đạt 80 ms | Trung bình | Cao | đường lui §16.6; quyết định sau ~1 tuần, không sau 6 tuần |
| VDD hỏng sau Windows update | Trung bình | Cao | ghim version VDD; hỏng thì **VNC-only** vẫn dùng được (§26.8) |
| App chết giữa phiên ⇒ cửa sổ mắc trên display ảo | Trung bình | **Cao** | §0.3.3 #4: khôi phục lúc khởi động + nút "đưa cửa sổ về màn hình thật" |
| Máy câm tiếng sau khi dùng | Trung bình | Cao | watchdog restore default device (§5.10.3) — chạy cả khi app crash |
| 3 tháng sau quên code | Cao | Trung bình | `docs/` + `cargo test` + chính spec này |

### 21.12 "Xong" nghĩa là gì (3 mốc)
| Mốc | Xong khi |
|---|---|
| **P0 — spike** | 1 cửa sổ → display ảo → browser 1080p60, cursor local 0 ms, đo được p95. p95 >120 ms ⇒ đổi stack (§16.6) **trước khi** viết tiếp |
| **P1 — dùng được hằng ngày** | 8 mục test tay §21.10 pass; 0 lần kẹt input trong 50 thử; đóng tab ⇒ mọi thứ trở lại; mở/đóng 20 lần không rò |
| **P2 — dễ chịu** | preset + zoom local + bố cục mobile + audio toggle + chuyển cửa sổ giữa phiên <1.5 s. **Dừng ở đây** nếu đã đủ |

### 21.13 Những thứ **cố tình không làm** (ghi để không hỏi lại)
| Không làm | Lý do |
|---|---|
| Điều khiển màn hình login/UAC | §2.3 |
| Hidden desktop `WinSta0\HVNC` | §5.2 (mất state, giống malware) |
| Hook API / `SetWindowsHookEx` | §14.3 |
| Giấu process khỏi Task Manager | §14.5 |
| SFU/nhiều người xem | không cần; P2P đủ |
| App native mobile | yêu cầu là browser |
| HDR streaming | chỉ tonemap |
| Cloud relay / TURN mặc định | tự chủ, §13.1 |
| **EV cert / ký driver / SmartScreen / EULA / SBOM** | **§0.3.1 #1–2** |
| **Multi-user, role, TOTP, `/admin`, handover** | **§0.3.1 #4** |
| **Accessibility cho người khiếm thị** (screen reader qua audio, UIA over the wire) | **§0.3.1 #3** |
| **MSI + wizard 5 bước + auto-update có kênh** | **§0.3.1 #6** |
| **CI 2 tầng + self-hosted runner + soak 72 h + ma trận OS** | **§0.3.1 #9** |

### 21.14 Hướng mở rộng (ghi để khỏi nghĩ lại)
- Server trên **Linux** (PipeWire + XDG portal) / **macOS** (ScreenCaptureKit) nếu sau này đổi máy — dùng lại client, đổi core.
- **Nhiều máy** từ 1 dashboard — chỉ khi bạn có máy thứ hai.
- ~~SFU/broadcast, text mode, voice chat~~ — không cần cho 1 người dùng.

---

# PHẦN V — THIẾT KẾ GIAO DIỆN

## 22. Kiến trúc thông tin & tuyến đường (IA)

### 22.1 Sơ đồ
```
/                          → chuyển hướng theo trạng thái đăng nhập
├── /login                 → đăng nhập (≤2 tài khoản, không TOTP)
├── /windows               → DASHBOARD: cửa sổ + phiên đang mở + trạng thái máy
├── /s/:sid                → PHIÊN ĐIỀU KHIỂN (toàn màn hình)
│     ├── overlay: chuyển cửa sổ (window switcher)
│     ├── overlay: chẩn đoán nhanh
│     └── sheet: cài đặt phiên
├── /settings              → cài đặt (~12 mục, 1 trang — §0.3.4)
├── /diagnostics           → chẩn đoán 12 bước (§21.1)
├── /history               → lịch sử phiên của tôi, đọc-only, ≤500 dòng (§50.2)
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

### 22.3 Không có phân quyền
Đã cắt role/admin/viewer (§0.3.1 #4). Có **2 loại người dùng** thôi:

| Ai | Thấy gì |
|---|---|
| **bạn** (đăng nhập bằng mật khẩu) | mọi thứ: dashboard, phiên, cài đặt |
| **người nhận link xem tạm** (§21.6) | **duy nhất** 1 phiên, view-only, không dashboard, không cài đặt; hết hạn ⇒ "Link đã hết hạn" |

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
│   └────────────────────────────────────┘     │
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
- Không TOTP (§0.3.1 #4): ≤2 tài khoản, mật khẩu + lockout là đủ. Không có "quên mật khẩu" qua email (§21.5).
- Trạng thái: `idle · submitting (nút có spinner, disable) · error · locked`.
- Không có "quên mật khẩu" (không có email) → link "Cần trợ giúp?" mở `/help#reset`.

### 24.2 `/windows` — DASHBOARD (màn hình chính)
```
┌───────────────────────────────────────────────────────────────────────────┐
│ ◉ RD  ·  DESKTOP-01                                     ● Tốt   [👤 ▾]     │
├───────────────────────────────────────────────────────────────────────────┤
│  ⚠ Chưa cài dây âm thanh ảo — phiên sẽ không có tiếng.  [Cài ngay]  [×]   │
├───────────────────────────────────────────────────────────────────────────┤
│  PHIÊN ĐANG MỞ                                              (1)            │
│  ┌────────────────────┐                                                   │
│  │ [thumbnail]        │   ← chỉ 1 phiên/lúc (§42.2). Tab thứ 2 sẽ thấy     │
│  │ Chrome — Tin tức   │     "Tiếp tục ở tab này".                          │
│  │ 12:04 · HVNC · 🔊  │                                                   │
│  │ [Tiếp tục] [Kết…]  │                                                   │
│  └────────────────────┘                                                   │
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

### 24.6 `/settings` — **1 trang, 12 mục** (thay 5 tab) · **nguồn duy nhất: §48.1**
> Danh sách 12 mục, phạm vi (server/device) và hiệu lực của từng mục nằm ở **§48.1** — không chép lại ở đây để không có 2 nguồn sự thật.
60 mục trong 5 tab là dành cho nhiều người có khẩu vị khác nhau. Bạn cần 12.

| Nhóm | Mục (mặc định in đậm) | Kiểu |
|---|---|---|
| **Hình** | Chất lượng (**Tự động** / Nét / Mượt) · Tỉ lệ khung (**Vừa**) · Hiển thị (**Dùng thật** / Vừa mắt / Chữ to / Nét) | 3 segmented |
| **Điều khiển** | Con trỏ (**Tự động** / Cục bộ / Theo video) · Cách chạm (**2 ngón cuộn**) · Bàn phím (**Ý định** / Thô) | 3 segmented |
| **Tiếng** | Mặc định (**Hỏi mỗi phiên** / Bật / Tắt) · Nhớ theo app (**Bật**) | 2 toggle |
| **Chung** | Ngôn ngữ (**Tiếng Việt**) · Theme (**Hệ thống**) · Thông báo (**Quan trọng**) | 3 select |

- Mọi thay đổi **lưu ngay**, không có nút Lưu; mỗi mục có `↺` khi khác mặc định.
- Cuối trang: `Xuất` / `Nhập` cấu hình (§20.13) + `⬇ Nâng cao` (§20.14) chứa 8 mục ít dùng (bitrate trần, keyframe, cursor size max, MMCSS, debug barcode…).
- Không có tab "Bảo mật" (không TOTP, không phiên thiết bị) — chỉ 1 dòng "Đổi mật khẩu".

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
- Nút "Sao chép báo cáo" → JSON của 8 kiểm tra (không chứa token/mật khẩu), dán vào chat cho chính bạn khi cần nhớ lại.

### 24.8 Không có `/admin`
Đã cắt (§0.3.1 #4): không multi-user, không role, không policy, không bảng audit phân trang.
Thay bằng: **`/diagnostics`** (8 kiểm tra) + **1 file log** (§21.9). Các công tắc vận hành (âm thanh, che giấu, preset mặc định, link xem tạm) nằm trong `/settings`.

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
- `Dừng điều khiển ngay` = **không** cần quyền người điều khiển (§21.7).
- Hotkey khẩn cấp toàn cục `Ctrl+Alt+Shift+X` → dừng mọi phiên + toast.
- Mục **Thông tin cài đặt…** (port, cert hết hạn, driver version, task name, thư mục) — để 3 tháng sau bạn không phải nhớ gì (§47.7).
- Nếu app khởi động lúc **thiếu driver**: tray vàng + *"Chờ driver…"*, **không** im lặng (§47.2.1).

### 24.10 `/setup` — 4 bước, chỉ hiện khi chưa có mật khẩu
```
1/4  Mật khẩu        ▸ tạo mật khẩu (bắt buộc, không cho bỏ trống)
2/4  Mạng            ▸ [Trong LAN] [Qua Tailscale]     → tự điền listen/cert/STUN
3/4  Kiểm tra        ▸ 5 dòng ✓/✗: display ảo · cable âm thanh · encoder · cổng 443 · cert
4/4  Xong            ▸ link truy cập + QR để mở trên điện thoại
```
- 4 bước (không phải 5): bước "chính sách/che giấu" đã bỏ — đó là 2 công tắc trong `/settings`.
- Bỏ qua được bước 2 (mặc định LAN). **Không** bỏ qua 1 và 3.
- Bước 3 thiếu driver/cable ⇒ có nút cài (mở `winget`) và vẫn cho "Tiếp tục không có màn hình ảo" (⇒ VNC-only, §26.8).

### 24.11 Trang lỗi
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

### 26.1 Mô hình dữ liệu — **2 file JSON + 1 log** (thay 7 bảng SQLite)
v3.3 dựng 7 bảng SQLite cho một sản phẩm nhiều người dùng. Với **1 người** (§0.3), mỗi bảng đó là một nguồn lỗi không đổi lại được gì:

| Bảng cũ | Bản cá nhân dùng gì |
|---|---|
| `users`, `sessions_auth` | **mảng ≤2 phần tử trong `config.json`**: `{user, pwd_hash(argon2id), refresh_hash, failed_count, locked_until}` — mỗi người 1 mật khẩu, **cùng quyền** (không role) |
| `prefs` | chính `config.json` (§9.11) — 1 người thì "prefs theo user/thiết bị/app" là 3 tầng không cần |
| `sessions` | **`state.json`** (đã có, §9.2.4 — phục hồi sau crash). Phiên đang chạy nằm trong RAM |
| `audit` | **`rd.log`**: 1 dòng JSON/sự kiện, xoay 5×10 MB |
| `shares` | 1 object trong `config.json` (tối đa vài link, tự dọn khi hết hạn) |
| `windows_recent` | 10 phần tử trong `config.json` (để dashboard gợi ý cửa sổ hay dùng) |
| `schema_version` | 1 số trong `config.json` + tự copy `.bak` trước khi migrate (§21.5) |

**Quy tắc (ít hơn hẳn, và đúng hơn):**
- Ghi `config.json` **nguyên tử**: ghi `.tmp` → `fsync` → `rename`. Không có WAL, không có transaction, không có tranh chấp writer ⇒ **toàn bộ nhánh #6 (dữ liệu & migration) không còn lý do tồn tại**.
- `state.json` chỉ để phục hồi sau crash; xoá sau khi restore thành công.
- **Không** lưu: clipboard, keystroke, frame, token dạng thô (chỉ hash), mật khẩu dạng thô.
- Log không chứa nội dung phiên (không tiêu đề cửa sổ đầy đủ? — **có** tiêu đề, vì đây là máy của bạn và nó giúp tìm lỗi; chỉ không ghi nội dung *bên trong* app).

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
| **Laptop gập nắp** | màn hình tắt, vẫn chạy | **mặc định Windows là SLEEP, không phải "vẫn chạy"** ⇒ §53.5: đặt "Do nothing" hoặc tốt hơn là **để nắp mở** (máy này thoát nhiệt ở bản lề) |
| **Máy ngủ / vừa reboot / IP đổi** | không kết nối được, không rõ vì sao | **§46**: 5 lỗi → 5 câu → 5 nút |
| **Windows Update tự restart lúc đêm** | app không chạy tới khi đăng nhập | §46.4: giảm số lần reboot + `last_seen` để nói rõ "vừa khởi động lại lúc 03:12" |

### 26.9 Cái gì cần chạy được (không phải "ma trận hỗ trợ")
Đã cắt ma trận OS × browser × RAM và "chính sách 2 phiên bản" (§0.3.1 #9). Chỉ cần:

| Hạng mục | |
|---|---|
| Server | chính máy bạn — Win10 2004+ hoặc Win11. **Không** hỗ trợ phiên bản khác |
| Client | trình duyệt bạn đang dùng (Chrome/Edge 110+, Safari 16.4+) + **1 trình duyệt trên điện thoại của bạn** |
| Nếu trình duyệt cũ hơn | trang "chưa hỗ trợ" — bạn tự update, không cần hỗ trợ ngược |
| Phiên bản app | 1 bản duy nhất. Không có `min_client`, không có tương thích 2 phiên bản |

### 26.10 Không có phụ thuộc
- **Không** CDN, **không** Google Fonts, **không** analytics, **không** telemetry mặc định, **không** Sentry, **không** Web Push, **không** third-party script.
- Lý do: (a) không rò IP/usage của người dùng ra ngoài; (b) chạy được trong mạng kín; (c) CSP chặt `default-src 'self'` không cần ngoại lệ.
- Không có telemetry, không crash report, không gửi gì ra ngoài. Gói chẩn đoán là **file bạn tự lưu**, không upload (§21.9).
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
- JWT: skew ±60 s. Không TOTP (§0.3.1 #4).
- Dashboard hiện giờ **của máy chủ** ở tooltip ("12:04 giờ máy chủ").
- Nếu lệch > 5 phút so với NTP → dòng cảnh báo ở `/diagnostics` "đồng hồ máy lệch (ảnh hưởng JWT)".
- Timeout/idle tính bằng **clock đơn điệu** (monotonic), không dùng wall clock (tránh bug khi đổi giờ/NTP nhảy).

### 26.16 Lưu trữ (bản cá nhân: không có DB, không có retention job)
| Dữ liệu | Ở đâu | Xoá thế nào |
|---|---|---|
| Cấu hình | `config.json` | bạn sửa tay |
| Trạng thái phục hồi sau crash | `state.json` | tự xoá sau khi restore thành công |
| Log | `rd.log`, 5×10 MB | xoay vòng tự động; muốn sạch thì xoá file |
| Clipboard / frame / keystroke | **không lưu ở đâu cả** | — |
> Đã cắt khỏi §26.1 (bảng SQLite 7 bảng): `users`/`sessions_auth`/`audit`/`shares`/`windows_recent` không cần khi chỉ có 1 người. Cần đúng **2 file** + 1 log. Đây là điều làm bản cá nhân **ít lỗi hơn** bản sản phẩm: không có migration DB, không có WAL, không có tranh chấp writer (đó là toàn bộ nhánh #6 — **không còn cần**).

### 26.17 Ký số, SmartScreen — **không áp dụng**
Đã cắt (§0.3.1 #1): bạn dùng VDD **bản phát hành đã ký sẵn** và binary do chính bạn build trên máy mình ⇒ không có SmartScreen, không có Authenticode, không có EV cert.
Chỉ còn 1 việc: khi Defender cảnh báo, thêm **exclusion cho thư mục app** (§21.11). Không "chống phát hiện" dưới mọi hình thức (§21.13).
- Hướng dẫn whitelist Defender (folder + process) — **không** tự tắt AV.
- Không có "chống phát hiện" dưới mọi hình thức (§21.13).

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
- Ngân sách chiều cao ở trên **chưa đủ** để chống đè: thang lớp, máy trạng thái bề mặt (1 dialog/1 sheet/1 toast/1 banner), banner **đẩy** layout thay vì phủ ⇒ **§49**.

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
- Khi **RAM khả dụng < 500 MB** → **cảnh báo** ở picker, **không** từ chối ([MỀM], §54.3). Trên host 8 GB gần như không gặp; nếu gặp thì thủ phạm là app khác, không phải ta (§53.8).
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
| 13 | Sleep/resume máy | phục hồi hoặc đóng sạch, không treo (§46.10 test 1) |
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

---

## 39. Một pass GPU: scale + màu + tonemap + NV12 (nhánh #2f — nơi màu lệch và chữ mờ)

> §38 chọn **GPU bicubic**, §5.5.2 có **HDR tonemap**, §38.6 nói **"chấp nhận 4:2:0"**. Ba câu đó là **cùng một shader**. Nếu làm rời nhau: mỗi frame 1080p đi qua GPU **3 lần** (scale → tonemap → BGRA→NV12), mỗi lần đọc+ghi texture ≈ **3–4 ms** ⇒ **10–12 ms/frame** chỉ để di chuyển pixel — ăn hết ngân sách encode 4–8 ms (§35.6).
> Chương này gộp thành **1 pass**, và xử lý 4 chỗ mà 90% dự án remote desktop làm sai: **matrix**, **range**, **chroma siting**, **dither**.

### 39.1 Vì sao phải 1 pass (số cụ thể)
| Cách làm | Số pass | Chi phí 1080p60 | Ghi chú |
|---|---|---|---|
| Rời: scale → tonemap → convert | 3 | **10–13 ms/frame** | + 3 texture 1080p tạm (mỗi cái ~8 MB RGBA) |
| Gộp: 1 compute shader | 1 | **2–4 ms/frame** | đọc 1 texture, ghi thẳng NV12 (2 plane) |
| Gộp nhưng qua `d3d11convert` + `videoscale` | 2 | 5–8 ms | phụ thuộc driver, khó kiểm soát matrix/range |
**Quyết định:** 1 **compute shader** (hoặc pixel shader nếu compute không có), trong **cùng D3D11 device** với capture và encoder, đọc texture capture, ghi **NV12 hai plane** (`R8` luma + `R8G8` chroma), đặt **cùng hàng đợi** với encoder.

### 39.2 Bốn thứ làm sai màu/chữ (và cách đúng)
| # | Lỗi | Triệu chứng người dùng thấy | Nguyên nhân |
|---|---|---|---|
| 1 | **Sai matrix** (BT.601 vs BT.709) | đỏ thành cam, xanh lá thành vàng nhạt — **lệch màu toàn ảnh** | desktop HD dùng **BT.709**; dùng 601 thì R/G/B lệch 5–15% |
| 2 | **Sai range** (full vs limited) | đen thành xám, trắng thành 235 — **ảnh bạc / mất tương phản** | capture trả full (0–255); H.264 mặc định limited (16–235) |
| 3 | **Sai chroma siting** | chữ màu bị **lem sang phải**, viền đỏ/xanh ở mép | 4:2:0 MPEG-2 = chroma **left-sited**, không phải centered |
| 4 | **Không dither** | nền tối bị **dải màu (banding)**, gradient thành bậc thang | 8-bit + chuyển sang limited range làm giảm số mức khả dụng |
Cộng 2 lỗi ít gặp nhưng khó tìm: **alpha** (capture trả BGRA có alpha=255 nhưng một số app/DWM cho alpha thấp → nếu nhân alpha thì tối ảnh) và **gamma** (scale ở linear space làm chữ mờ — §39.5).

### 39.3 Chuỗi biến đổi đúng (thứ tự bắt buộc)
```
① texture capture (BGRA8 hoặc RGB10A2 nếu HDR)
   ↓ bỏ alpha (dùng 1.0), giữ giá trị non-linear sRGB
② [chỉ HDR] decode PQ → linear nits → tonemap (BT.2408) → giảm về BT.709 primaries
③ scale  ← ở **gamma space** (non-linear), KHÔNG ở linear (§39.5)
         ← bicubic hoặc area theo §38.3
④ [chỉ khi giảm nhiều] unsharp nhẹ trên luma (§38.5)
⑤ RGB (BT.709, full) → **YUV BT.709 limited** bằng matrix chuẩn (§39.4)
⑥ dither 8-bit có nhiễu tam giác (TPDF) khi ghi xuống R8/R8G8 (§39.6)
⑦ ghi NV12: Y plane full-res, UV plane half-res với **chroma left-sited** (§39.7)
```
**Một chi tiết dễ sai:** bước ② phải xảy ra **trước** bước ③ nếu là HDR (scale trên nội dung PQ mà không decode là sai hoàn toàn), nhưng bước ③ phải ở **gamma space** ⇒ với HDR, decode PQ → tonemap → **encode lại gamma 2.2** rồi mới scale. Tức là có 1 lần "về SDR gamma" trước khi scale. Đừng scale trực tiếp trên nits linear.

### 39.4 Ma trận chuyển màu (dùng đúng số này)
Nguồn: **sRGB / BT.709 primaries, full range, gamma ~2.2 (đã là non-linear)** → **YUV BT.709 limited**:

```
Y  =  0.2126·R' + 0.7152·G' + 0.0722·B'                          (R' = non-linear)
U  = (B' − Y) / 1.8556                       → + 128
V  = (R' − Y) / 1.5748                       → + 128

rồi limited:  Y' = 16 + Y·219/255 ;  U' = 16 + U·224/255 ; V' = 16 + V·224/255
```
Dạng ma trận tại chỗ (để implement, đã gộp range):
```
Y_lim  = (16/255) + (219/255)·( 0.2126 0.7152 0.0722)·RGB
U_lim  = (128/255) + (224/255)·(−0.1146 −0.3854  0.5000)·RGB
V_lim  = (128/255) + (224/255)·( 0.5000 −0.4542 −0.0458)·RGB
```

| Nguồn | Dùng matrix | Dùng range |
|---|---|---|
| Desktop SDR, monitor HDTV (≥720p) | **BT.709** | full → **limited** |
| Desktop SDR trên màn hình SD? (hiếm) | BT.601 | — |
| **HDR** (DXGI `RGB_FULL_G2084_NONE_P2020`) | **BT.2020** → rồi chuyển primaries về 709 | full (PQ) |
**Phải khai báo `VUI` trong H.264 stream** (`color_primaries=1`, `transfer=1`, `matrix=1`, `range=limited`) — nếu không khai báo, browser đoán và có thể đoán sai ⇒ màu lệch. NVENC/QSV/x264 đều có property (`--colorprim bt709 --transfer bt709 --colormatrix bt709 --range limited` cho x264); **kiểm tra bằng `ffprobe`** trong CI.

### 39.5 Scale ở gamma space hay linear? (ngược với trực giác)
| Cách | Kết quả trên chữ | Kết quả trên ảnh |
|---|---|---|
| Scale ở **linear** | **mờ hơn** và **sáng hơn** — cạnh chữ bị "phình", chữ nhỏ mất nét | đúng vật lý, mượt hơn |
| Scale ở **gamma (non-linear)** | **nét hơn**, tương phản cạnh giữ tốt | hơi tối ở vùng sáng |
**Quyết định: scale ở gamma space** — vì mục tiêu là **đọc chữ**. Đây là ngược với kết luận của đồ hoạ 3D (nơi linear là đúng), và đây là lý do nhiều pipeline "chuẩn" lại cho ra chữ mờ. Ghi rõ để không ai "sửa" thành linear.
- Ngoại lệ: nếu nội dung là **ảnh/video** (`text_score` thấp — §38.7), scale linear cho kết quả tự nhiên hơn; nhưng khác biệt nhỏ, **không** đáng để có 2 nhánh shader. Chọn 1: gamma.

### 39.6 Dither (rẻ, hiệu quả, hay bị bỏ qua)
- Lý do: H.264 8-bit + limited range ⇒ chỉ còn **219/255** mức cho luma ⇒ nền tối (dark mode, terminal) bị **banding**.
- Cách: **TPDF** (triangular PDF) = `noise = (rand01() - rand01()) * 1.0`; cộng vào **trước khi** quantize; cho **luma và chroma**.
- Nhiễu phải **khác nhau mỗi frame** với **static pattern** để tránh "nhiễu đứng yên" — dùng bảng 64×64 blue-noise + offset theo frame id (**không** dùng `rand()` mỗi pixel: đắt + tạo nhiễu trắng xấu).
- Bật **mặc định**; tắt khi `dither.when_dark_ratio` (§38.11) thấp. Chi phí: ~0 trên GPU.
- **Không** dither khi nội dung là video sáng (không có banding, nhiễu là lãng phí bit).

### 39.7 Chroma siting & NV12 (lỗi lem màu)
- 4:2:0 **MPEG-2 / H.264 mặc định = chroma left-sited**: mẫu chroma nằm ở **cột chẵn, dòng chẵn** (góc trên-trái của khối 2×2), **không** ở tâm khối.
- Vì vậy khi tính UV cho khối (2x, 2y): dùng **lấy mẫu tại (2x, 2y)** hoặc trung bình **4 pixel (2x..2x+1, 2y..2y+1)** rồi ghi vào vị trí (x, y). Nếu lấy mẫu **centered** ⇒ chữ màu lem **nửa pixel sang phải** — nhìn kỹ thấy viền xanh/đỏ ở mép chữ cỡ nhỏ.
- Khai báo `chroma_loc` trong VUI nếu codec hỗ trợ; H.264 coi là left-sited theo mặc định ⇒ **không** set gì thêm.
- **Test bắt buộc:** ảnh test có **đường kẻ dọc màu đỏ 1 px trên nền đen**; sau pipeline phải thấy đường **1 px, đúng vị trí**, không lem sang phải. Đây là test duy nhất bắt được lỗi siting.

### 39.8 HDR — tonemap đúng (không "ám vàng", không "cháy trắng")
| Bước | Làm gì |
|---|---|
| Phát hiện HDR | `DXGI_OUTDUPL_DESC` color space = `RGB_FULL_G2084_NONE_P2020` (hoặc `G10`/`G12`), hoặc `Get-AdvancedColorInfo` |
| Decode | PQ (SMPTE ST 2084) → **linear nits** (0–10000) |
| Điểm trắng tham chiếu | **SDR white = 203 nits** (theo BT.2408) — **không** dùng 100 nits (sẽ tối) |
| Tonemap | **BT.2408 EETF** (khuyến nghị) hoặc Reinhard/Narkowicz `x/(1+x)`; clamp đỉnh ~1000 nits |
| Gamut | **BT.2020 → BT.709**: ma trận 3×3, **clamp** sau khi chuyển (ra ngoài gamut là bình thường với nội dung HDR) |
| Encode lại | gamma **2.2** (không phải sRGB EOTF chính xác — chênh không đáng, rẻ hơn) |
| Ghi VUI | `transfer=1` (BT.709) ở đầu ra |
**Ba lỗi phổ biến và triệu chứng:**
1. Dùng 100 nits cho SDR white ⇒ **ảnh tối**, mất chi tiết vùng tối.
2. Không chuyển BT.2020→709 ⇒ **màu bão hoà quá mức** (đỏ cháy, xanh neon).
3. Tonemap **sau** khi đã downscale ⇒ nén dải động vào ít pixel ⇒ mất chi tiết. Tonemap **trước** scale (như §39.3).
> **Giới hạn trung thực:** sau tonemap, HDR trên remote sẽ **không** giống HDR gốc. Ghi vào §6.13: *"nội dung HDR sẽ được chuyển sang SDR, màu không chính xác như màn hình HDR thật"*.

### 39.9 Alpha & nền trong suốt
- DDAPI trả BGRA với alpha thường = 255. **Bỏ alpha**, dùng 1.0. Không nhân alpha (một số app để alpha 0 ở vùng chưa vẽ ⇒ nhân sẽ ra đen).
- Cửa sổ có **acrylic/mica trong suốt**: DWM đã composite lên desktop nên capture đã có nền — **không** cần xử lý alpha.
- **Không** hỗ trợ nền trong suốt trong stream (H.264 4:2:0 không có alpha). Ghi rõ.

### 39.10 Nơi nào không kiểm soát được (và không nên cố)
| Thứ | Tại sao bỏ qua |
|---|---|
| **ICC profile** của màn hình server (wide gamut) | Capture trả pixel **sau** khi DWM composite theo profile. Chuyển ngược ICC là **không xác định** (không có API đọc "đã áp profile gì"). Kết quả: trên màn hình wide-gamut, màu có thể hơi bão hoà so với màn hình client. **Chấp nhận + ghi rõ.** |
| **Màu màn hình client** | Client hiển thị theo profile của nó; không thể đúng tuyệt đối. |
| **H.264 10-bit** | Browser WebRTC không hỗ trợ High10 ⇒ luôn 8-bit. |
| **4:4:4** | §38.6 — không khả thi. |
> Nguyên tắc: chuyển đổi **đúng theo chuẩn** (709/limited/siting/dither), và **ghi rõ** phần không kiểm soát được. Không hứa "màu chính xác như màn hình thật".

### 39.11 Sơ đồ shader (một pass, pseudo-HLSL)
```hlsl
// input:  Texture2D<float4> src (BGRA8 hoặc RGB10A2)
//         cbuffer: scale params, matrix, range, hdr params, dither seed
// output: RWTexture2D<float> yPlane; RWTexture2D<float2> uvPlane
[numthreads(8,8,1)]
void CS(uint3 id : SV_DispatchThreadID) {
    float2 uv = (id.xy + 0.5) * texelSize;          // sample center
    float3 c  = SampleBicubic(src, uv).rgb;         // gamma space
    c = ExcludeAlpha(c);                            // bỏ alpha
    if (isHDR) {                                    // §39.8
        c = PQToLinear(c) * sdrWhiteScale;          // 203 nits ref
        c = TonemapBT2408(c);
        c = LinearToGamma(BT2020to709(c));
    }
    if (doSharpen) c = UnsharpLuma(c, uv, amount);  // §38.5
    float y, u, v;
    RGBtoYUV709Limited(c, y, u, v);                 // §39.4
    yPlane[id.xy]   = Dither(y, id.xy);             // §39.6
    if (all(id.xy % 2 == 0))                        // left-sited, 1 sample per 2x2
        uvPlane[id.xy/2] = float2(Dither(u,id.xy), Dither(v,id.xy));
}
```
- **Một** dispatch cho toàn frame; với 1080p ≈ 32 400 nhóm 8×8 — GPU rảnh thừa sức.
- **Không** dùng barrier giữa các bước trong pass; mọi thứ tuần tự trong shader.
- Upscale **không** xảy ra ở đây (`(A) native` §38.1 do Windows/app làm).

### 39.12 Khi không có compute shader
| Fallback | Khi nào | Hệ quả |
|---|---|---|
| **Pixel shader** trong cùng device | compute bị chặn (hiếm) | chậm hơn ~1 ms/frame, vẫn 1 pass |
| **D3D11 VideoProcessor** | muốn ít code | **matrix/range do driver** ⇒ phải kiểm tra màu bằng test; rủi ro |
| **CPU `videoscale` + `videoconvert`** | GPU không dùng được (VM, driver lỗi) | **4–10 ms/frame**; bắt buộc **hạ fps xuống 30** trước |
| **WARP** (software D3D) | — | **không dùng** cho 1080p60 |
- Chọn fallback **theo đo đạc ở Phase 0**, không theo giả định: chạy cả 2 đường và so `PSNR` với reference + thời gian.

### 39.13 Kiểm chứng màu (bắt buộc trong CI)
**Bộ test pattern** render trên desktop ảo rồi chụp lại qua pipeline:

| # | Pattern | Kiểm tra | Ngưỡng |
|---|---|---|---|
| 1 | Grey ramp 0→255, 256 bậc | banding? black/white level đúng? | đen = **16±1**, trắng = **235±1** (limited); không có bậc thang nhìn thấy |
| 2 | Color bars (SMPTE) | matrix đúng? | ΔE2000 mỗi thanh **< 4** (so với reference tính bằng công thức chuẩn) |
| 3 | Đường kẻ dọc đỏ 1 px trên đen | chroma siting | đường còn 1 px, **không lem phải** >0.5 px |
| 4 | Chữ 8pt trên nền tối (dark mode) | dither + độ nét | không banding; CER ≤1% (§38.9) |
| 5 | Chữ màu trên nền trắng | 4:2:0 bleed | đo độ lem ≤ ngưỡng baseline, **không tệ hơn** |
| 6 | Ảnh HDR (PQ) test | tonemap | không cháy trắng vùng sáng, không bệt vùng tối; ΔE < 8 vs reference tonemap |
| 7 | Cửa sổ có acrylic | alpha | nền đúng, không đen |
**Đo bằng:** decode lại stream (ffmpeg) → so pixel với reference **đã tính bằng công thức trong §39.4**. Fail CI nếu ΔE/RMSE vượt ngưỡng. Cộng `ffprobe` kiểm tra VUI (`color_matrix=bt709`, `color_range=tv`).

### 39.14 Chi phí (đo, không đoán)
| Nội dung | 1080p60 | 1080p30 |
|---|---|---|
| 1 pass compute, scale 1.0 (chỉ màu) | 1.2–2 ms | 0.6–1 ms |
| 1 pass, scale 0.667 + sharpen | 2–4 ms | 1–2 ms |
| + HDR tonemap | +0.3–0.8 ms | +0.2–0.4 ms |
| Fallback CPU | 4–10 ms (**+ fps ≤30**) | 2–5 ms |
> Nếu vượt 6 ms ở GPU ⇒ kiểm tra: đang **đọc lại texture về CPU** (map) chưa? Đó là lỗi phổ biến nhất — pass phải ở hoàn toàn trên GPU, **không** `Map()` trừ khi fallback CPU.

### 39.15 Nhánh mới rẽ ra
| Nhánh | Vì sao rẽ ra từ §39 |
|---|---|
| **#2h Đồng bộ 3 nguồn màu giữa capture ↔ scaler ↔ encoder** (DXGI color space, GStreamer caps negotiation `video/x-raw(memory:D3D11Memory)`, NV12 vs P010) | §39.3 cần khai báo caps chính xác nếu không GStreamer tự chèn `videoconvert` CPU ⇒ mất toàn bộ lợi ích |
| **#2i Đa màn hình & per-monitor HDR** (màn hình 1 SDR, màn hình 2 HDR) | §39.8 giả định 1 display; thực tế có thể khác nhau |
| **#3 Fault injection harness** | vẫn chờ, **kế tiếp đề xuất** |

---

## 40. Âm thanh: routing, capture, drift, toggle (nhánh #4 — cả một hệ thống con còn nông)

> §5.10 và §9.6 mô tả audio bằng **kết luận** — *"per-app routing dùng Audio Policy Config API, nếu không ổn định thì fallback đổi default device"*. Đó là câu **không implement được**: không có API per-app routing **có tài liệu** trên Windows, "ổn định" không định nghĩa, và "fallback" là đổi hành vi **toàn máy** của người dùng.
> Chương này tách audio thành **hai bài toán khác nhau** (routing vs capture), nói rõ cái nào **không có API chính thức**, và định nghĩa **cách kiểm chứng routing đã thành công** — thứ thiếu hoàn toàn.

### 40.1 Vì sao audio khó hơn video
| | Video | Audio |
|---|---|---|
| Nguồn | 1 (display) — **luôn có** | nhiều app, **có thể không có gì đang phát** |
| "Đúng" nghĩa là gì | đúng pixel | **đúng cả về nội dung lẫn thời điểm** (lệch 40 ms đã nghe ra) |
| Đổi cấu hình | 1 IDR, 150–600 ms | mất tiếng 200–600 ms, dễ nghe thấy hơn nhiều |
| API | DDAPI (tài liệu đầy đủ) | routing per-app **không có API tài liệu** |
| Drift | không (frame theo vsync) | **có thật**: clock thiết bị ≠ clock hệ thống |
| Lỗi phổ biến | màu lệch | **mất tiếng vĩnh viễn trên máy người dùng** (nếu routing sai và không watchdog) |
> Video hỏng thì thấy ngay. Audio hỏng thì **hoặc** người dùng mất tiếng máy thật, **hoặc** người ngồi máy nghe tiếng lẽ ra phải im (phá HVNC). Cả hai đều tệ hơn "hình hơi mờ".

### 40.2 Tách đôi bài toán (spec cũ gộp làm một → mọi lẫn lộn từ đây)
| Bài toán | Câu hỏi | Ai kiểm soát | Độ tin cậy |
|---|---|---|---|
| **A. Routing** | "âm thanh của app X **đi vào đâu**?" | Windows mixer / AudioPolicyConfig | ⚠️ **không có API chính thức** |
| **B. Capture** | "làm sao **lấy** âm thanh từ thiết bị Y vào stream?" | WASAPI loopback | ✅ tài liệu đầy đủ, tin cậy |
- §5.10 trộn hai cái này nên đọc thành "nếu routing không được thì capture cũng hỏng" — không đúng: capture loopback **luôn** làm được, chỉ có *nội dung* nó bắt được là tuỳ routing.
- **Hệ quả thiết kế:** nếu routing thất bại, ta vẫn **stream được** — chỉ là sai nội dung (hoặc im lặng). Đây là trạng thái **phải phát hiện và nói ra**, không phải im lặng.

### 40.3 Routing — các cơ chế thật trên Windows (và rủi ro từng cái)
| # | Cơ chế | Phạm vi | Tài liệu | Rủi ro |
|---|---|---|---|---|
| 1 | **AudioPolicyConfig** (`AudioPolicyConfigFactory`, COM không tài liệu; EarTrumpet dùng) | **per-app** | ❌ **không** | thay đổi giữa các build Windows; interface GUID/version phải dò; có thể ngừng hoạt động sau update |
| 2 | **Settings → Volume Mixer** (Win11 22H2+) | per-app, qua UI | ✅ (UI) | **không điều khiển được bằng API** ⇒ chỉ hướng dẫn người dùng |
| 3 | **`IPolicyConfig::SetDefaultEndpoint`** (không tài liệu) | **toàn máy** | ❌ | đổi trải nghiệm **của mọi app** + rủi ro mất tiếng nếu crash (§5.10.3 watchdog) |
| 4 | **`ISimpleAudioVolume`** | per-app, **chỉ âm lượng**, không đổi thiết bị | ✅ | không giải quyết routing |
| 5 | **APO / virtual device là default** | toàn máy | ✅ | như 3 |
| 6 | **App tự cho chọn output** (VLC, OBS, một số DAW) | per-app | ✅ | chỉ app đó; hướng dẫn người dùng |
> **Sự thật phải chấp nhận:** Windows **không** cung cấp API per-app routing có tài liệu, **không** có API để "di chuyển session audio sang thiết bị khác" một cách chính thức. Mọi giải pháp đều dựa trên COM không tài liệu (1, 3) hoặc UI (2).
> **Đây là rủi ro #1 của toàn bộ tính năng audio** và phải kiểm chứng ở Phase 0 trên nhiều build. Nếu AudioPolicyConfig không dùng được: chuyển sang **mô hình khai báo** (§40.5) chứ không phải cố vá.

### 40.4 Chiến lược routing: 3 mức, tự chọn, có kiểm chứng
```
Mức A — per-app (ưu tiên, đúng yêu cầu HVNC)
   thử AudioPolicyConfig cho (app pid, endpoint = CABLE Input)
   → KIỂM CHỨNG (§40.6): session của pid có xuất hiện trên CABLE không?
   → thành công: dùng
   → thất bại: xuống mức B, và NÓI RA
Mức B — toàn máy (fallback)
   SetDefaultEndpoint(CABLE Input) + watchdog + state file (§5.10.3)
   → cảnh báo 1 lần: "máy sẽ im lặng trong lúc điều khiển"
Mức C — không đổi gì (chế độ "nghe như VNC")
   loopback trên default device thật; người ngồi máy VẪN nghe
   → dùng cho mode VNC, hoặc khi người dùng chọn "như đang ở máy" (§9.6.1)
```
**Luật chọn mức:**
1. Người dùng chọn ở màn hình tạo phiên (§9.6.1); mức A là mặc định cho HVNC.
2. **Không tự xuống B mà không nói** — vì B làm **im cả máy**. Toast: *"Không tách riêng được tiếng của app này. [Đổi cả máy (máy sẽ im)] [Chỉ nghe như VNC]"* — người dùng quyết.
3. Mức C **không bao giờ** tự chọn cho HVNC (phá mục đích "không nghe").
4. Sau khi chọn, **lưu theo app exe** (§9.6.2), lần sau áp dụng luôn — nhưng **vẫn kiểm chứng** rồi mới tin.

### 40.5 App chỉ đọc thiết bị lúc khởi động (bẫy lớn nhất về UX)
- Rất nhiều app khởi tạo WASAPI **một lần** khi mở và **không** theo dõi đổi thiết bị: Chrome/Electron (một số bản), game, app cũ.
- → đổi routing **không có tác dụng** cho tới khi app khởi động lại.
- **Không được** kill app của người dùng. Thiết kế:
  | Tình huống | Hành vi |
  |---|---|
  | Kiểm chứng thấy session **không** xuất hiện trên CABLE | hiện gợi ý **một lần**: *"App này cần khởi động lại để chuyển âm thanh. [Tôi tự làm] [Bỏ qua]"* (nút đầu chỉ hiện nếu app không có dữ liệu chưa lưu — ta **không thể biết**, nên **không** cung cấp nút tự restart) |
  | App đang phát (state Active) nhưng trên default device thật | cảnh báo `audio_routing_stale` + trạng thái "Đang phát ở loa thật" |
  | Không phát gì | không cảnh báo (không biết được) |
- Ghi vào §6.13 (giới hạn trung thực): *"một số app cần khởi động lại mới đổi được thiết bị âm thanh"*.

### 40.6 Kiểm chứng routing — vòng lặp bắt buộc (thứ §5.10 thiếu hoàn toàn)
Sau khi đổi routing, **không tin** kết quả trả về. Kiểm chứng bằng **trạng thái thật**:
```
1. IAudioSessionManager2 trên device đích (CABLE) → EnumerateSessions
2. lấy IAudioSessionControl2::GetProcessId cho từng session
3. tìm pid của app target
   → thấy + state == Active      : OK (đang thật sự phát vào CABLE)
   → thấy + state == Inactive    : OK về routing (chưa phát gì)
   → KHÔNG thấy                   : routing thất bại → §40.5
4. lặp lại sau 2 s và 10 s (một số app tạo session muộn)
```
- Đây cũng là cách phát hiện **"app không phát tiếng"** cho UX (§9.6.4): không có session Active nào trên CABLE ⇒ hiện gợi ý.
- Và là cách phát hiện **rò rỉ**: session Active của app target **vẫn còn** trên loa thật sau khi đã route ⇒ `audio_leak` — cảnh báo **ngay** (đây là lỗi phá HVNC nghiêm trọng nhất).

### 40.7 Capture — WASAPI loopback, các bẫy cụ thể
| Bẫy | Chi tiết | Xử lý |
|---|---|---|
| **Event-driven loopback không fire khi im lặng** | `AUDCLNT_STREAMFLAGS_EVENTCALLBACK` + loopback: khi không có app phát, **không có event** ⇒ stream "treo" và không bao giờ chạy lại | **Dùng polling timer 10 ms** (không dùng event callback) cho loopback; hoặc event + timer dự phòng |
| Loopback trả **gói im lặng** chứ không phải "không có gì" | vẫn nhận buffer 0 | tốt: giữ stream sống; nhưng **không** đẩy lên encoder — dùng DTX (§40.9) |
| **Exclusive mode** | app chiếm device exclusive ⇒ loopback **fail** (`AUDCLNT_E_DEVICE_IN_USE`) | báo `audio.exclusive_mode`, gợi ý đổi sang shared, **không** tự đổi |
| **Format** | device mix format có thể 44.1/48 kHz, 16/24/float32, mono/stereo/5.1 | dùng `AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | SRC_DEFAULT_QUALITY` nếu cần; mặc định xin **48 kHz float32 stereo** và để WASAPI chuyển |
| **`AUDCLNT_E_DEVICE_INVALIDATED`** | device bị rút/xoá/driver reset | reinit + thông báo; **không** crash pipeline |
| Buffer quá nhỏ | < 10 ms ⇒ underrun, tiếng rè | 2 buffer × 10 ms là tối thiểu; 3 × 10 ms an toàn hơn (+10 ms trễ) |
| **Sample rate mismatch** giữa lúc init | đổi rate khi đang chạy | phải reinit; phát hiện qua invalidated |
| Không có gì phát **trong 20 s** | session Inactive | vẫn capture (giữ stream), nhưng **không gửi** gói → tiết kiệm pin/data (§35.11 tinh thần) |

### 40.8 Device change notification — không thể thiếu
`IMMNotificationClient` trên `IMMDeviceEnumerator`:

| Callback | Dùng cho |
|---|---|
| `OnDefaultDeviceChanged` | phát hiện người dùng đổi default giữa phiên (⇒ nếu đang mức B, **giành lại**? **KHÔNG** — ghi nhận + cảnh báo; nếu giành lại sẽ đánh nhau với người dùng) |
| `OnDeviceStateChanged` (Disabled/Unplugged/Removed) | `audio_unavailable` + retry §5.10 |
| `OnDeviceAdded` | nếu cable xuất hiện lại → khôi phục |
| `OnDevicePropertyChanged` | đổi tên/format |
**Luật quan trọng:** nếu người dùng **chủ động** đổi default device giữa phiên (mức B) → **không giành lại**. Ghi audit + toast *"Bạn vừa đổi thiết bị âm thanh — phiên vẫn chạy nhưng âm thanh có thể không còn nữa"*. Đánh nhau với người dùng là cách chắc chắn nhất để bị gỡ cài đặt.

### 40.9 Drift & đồng bộ A/V — phần khó nhất, §5.6 chỉ nói "cùng clock"
**Vấn đề thật:** clock của thiết bị âm thanh và clock hệ thống (QPC) lệch nhau. Thiết bị rẻ: **±100 ppm** ⇒ **360 ms/giờ**. Sau 1 phiên 2 giờ: lệch **720 ms** — không nghe được nữa (tiếng đi trước/sau hình gần 1 giây).

| Cách | Cơ chế | Chất lượng | Chọn? |
|---|---|---|---|
| Không bù | — | lệch 6 ms/phút | ❌ |
| **Đệm thích ứng (drop/dup 1 frame khi tràn/cạn)** | rẻ | nghe thấy "tách" mỗi 10–60 s | ❌ |
| **ASRC (resample thích ứng)** | resample liên tục với tỉ lệ điều chỉnh chậm | không nghe thấy | ✅ **chọn** |
| Đồng bộ theo RTCP SR ở client | browser tự làm | cần base timebase đúng | ✅ bắt buộc kèm |
**Triển khai ASRC (cụ thể):**
```
- nguồn: 48 kHz từ WASAPI (theo clock thiết bị) → đích: 48 kHz theo QPC/90 kHz RTP
- đo: độ đầy buffer trung bình (mục tiêu 30 ms)
- điều khiển: PI controller → tỉ lệ resample r ∈ [0.995, 1.005]
  · sai số < 5 ms  → r = 1.0 (không chỉnh, tránh hao CPU)
  · sai số 5–100 ms → r = 1 ± k·error, |k·error| ≤ 0.005
  · sai số > 100 ms → resync nhanh (r = 1 ± 0.02) trong ≤ 200 ms
- giới hạn: |r−1| ≤ 0.5% ⇒ sai lệch cao độ ≤ **8.6 cent** (không nghe ra với giọng nói)
- resampler: `speex_resampler` hoặc `swr` (chất lượng 5–7); bật `resampler` **1 lần**, không tạo lại mỗi buffer
```
- **A/V sync tổng thể:** audio PTS gán theo QPC **sau khi** đã qua ASRC (§35.8 đã yêu cầu cùng gốc QPC). Client dùng RTCP SR để map sang timebase của nó ⇒ nếu hai bên đúng, lệch < 20 ms.
- **Kiểm tra lệch A/V mỗi 30 s** trong stats: `av_skew_ms`. Nếu >60 ms kéo dài 10 s ⇒ banner (và đây là **bug**, không phải "mạng").

### 40.10 Toggle âm thanh — ngữ nghĩa triển khai (đã có §5.10.2, đây là cơ chế)
| Trạng thái | Routing | Pipeline | Gói RTP | Client |
|---|---|---|---|---|
| **ON** | giữ | PLAYING | gửi | nghe |
| **OFF** | **giữ** (§5.10.2) | `NULL` (không PAUSED — giải phóng thiết bị) | **dừng** | im; badge 🔇 từ WSS `audio_state` |
| **Chuyển OFF→ON** | giữ | reinit → PLAYING | SSRC **mới** | đợi gói đầu, ~200–600 ms |
| **Chuyển ON→OFF** | giữ | `NULL` | dừng ngay | im ngay (<50 ms) |
**Chi tiết dễ sai:**
1. **Không để client tự suy ra "mất kết nối"** vì không thấy gói audio — trạng thái lấy từ WSS `audio_state`, không từ "không có RTP".
2. **Đổi SSRC khi bật lại** — nếu giữ SSRC cũ, client có thể chờ theo timestamp cũ (§5.10.2 đã nêu; đây là lý do).
3. `NULL` (không `PAUSED`) để **nhả thiết bị** — nếu không, cable bị giữ và app khác không dùng được.
4. Nếu OFF trong lúc đang **route mức B** (đổi default device) ⇒ routing **vẫn giữ** ⇒ máy vẫn im. Đúng yêu cầu §5.10.2.
5. Toggle 100 lần liên tiếp: không rò handle/thiết bị; có test (§40.13).

### 40.11 Nhiều phiên & thiếu cable
| Tình huống | Xử lý |
|---|---|
| **1 phiên (bản cá nhân)** | 1 cable là đủ. Không có trường hợp trộn vì chỉ 1 phiên được sống (§42.2) |
| (nếu sau này cần) 2 cable | mỗi phiên 1 cable ⇒ cách ly thật — nhưng đừng làm khi chưa cần |
| Không có cable | mức C (nghe như VNC) hoặc video-only (§9.6.4) |
| Cable bị xoá | `audio_unavailable` + retry 5 s; >60 s ⇒ tắt audio, **giữ phiên** |
| Đổi cable giữa phiên (mức B) | coi như đổi default ⇒ `on_device_state`; nếu cable mới có → reinit |

### 40.12 Ngân sách độ trễ & jitter buffer phía client
| Chặng | ms |
|---|---|
| WASAPI buffer (3 × 10) | 30 |
| ASRC | ~2 |
| Opus encode (20 ms frame) | 20 (một frame) |
| Mạng (LAN) | 2–10 |
| **Browser jitter buffer cho audio** | **20–80** (không kiểm soát được) |
| Decode + render | 10–20 |
| **Thiết bị client** | 5 (có dây) / **150–300 (Bluetooth)** |
| **Tổng** | **90–160 ms (có dây)** |
> Bluetooth của **client** thêm 150–300 ms — đây là lý do phổ biến nhất của "tiếng không khớp hình" mà **không sửa được từ server**. Ghi vào §6.13 + gợi ý dùng tai nghe có dây.

### 40.13 Kiểm chứng (bắt buộc)
| # | Test | Ngưỡng |
|---|---|---|
| 1 | Routing per-app: route Chrome, phát video | session của Chrome **xuất hiện trên CABLE**, **không còn** trên loa thật |
| 2 | Rò rỉ: sau route, kiểm 10 s | **0** session Active của pid trên loa thật |
| 3 | Drift 2 giờ | `av_skew_ms` p95 **< 20 ms**, không nghe "tách" |
| 4 | Toggle 100 lần | không rò handle (`GetGuiResources`/`GetProcessHandleCount` không tăng đơn điệu); mỗi lần <600 ms |
| 5 | Im lặng 30 s | **không** gói RTP (DTX), bitrate < 2 kbps |
| 6 | Rút cable giữa phiên | video tiếp tục, `audio_unavailable`, khôi phục khi cắm lại |
| 7 | App exclusive mode | `audio.exclusive_mode`, video OK, không crash |
| 8 | Device 44.1 kHz | resample đúng, không rè, pitch không đổi |
| 9 | Người dùng đổi default giữa phiên (mức B) | **không** giành lại, có toast, phiên vẫn chạy |
| 10 | Chữ "ế" trong audio? (không áp dụng) | — |
| 11 | Restore sau uninstall/crash | default device đúng như ban đầu (**bắt buộc**, §11.4) |
| 12 | cable bị xoá giữa phiên | phiên báo `audio_device_missing`, hình **không** dừng; cắm lại ⇒ tự phục hồi (§40.8) |

### 40.14 Metrics trong stats
`audio_kbps`, `audio_state` (on/off), `audio_route` (app/machine/vnc), `routing_verified` (bool!), `av_skew_ms`, `audio_buf_ms`, `asrc_ratio`, `dropped_samples`, `device` (tên + id hash).

### 40.15 Nhánh mới rẽ ra
| Nhánh | Vì sao |
|---|---|
| **#4a Âm thanh vào (micro) & voice chat** | nếu Tier 3 làm voice, cần capture mic + echo cancellation — **ngược chiều** với audio ra |
| **#4b Trộn nhiều app thành 1 stream có kiểm soát** (mức "cả máy" nhưng loại trừ app) | mức B hiện thô: im tất cả |
| **#5 Threat model** (vẫn chờ) | |
| **#6 Multi-session & tài nguyên** (vẫn chờ) | |

---

## 41. Threat model & ranh giới tin cậy (nhánh #1 — lĩnh vực E)

> §10 liệt kê **biện pháp** (JWT, DTLS, clamp, CSP). Đó không phải threat model. Threat model hỏi: **ai** ở **đâu**, **làm được gì**, và **ta tin ai**.
> Khi viết ra, nó lật một giả định nền của toàn spec cũ: **agent trên máy Windows là thành phần được tin cậy, trình duyệt là thành phần không được tin cậy** — ngược với trực giác "server chạy trên máy người dùng còn client thì đã đăng nhập nên đáng tin".

### 41.1 Tài sản (cái gì cần bảo vệ, theo mức tổn thất)
| # | Tài sản | Mất/ lộ thì sao | Mức |
|---|---|---|---|
| A1 | **Nội dung màn hình** (mật khẩu gõ, tin nhắn, tài liệu, email) | toàn bộ lý do tồn tại của sản phẩm đều là rủi ro | **Cao nhất** |
| A2 | **Điều khiển bàn phím/chuột** của máy Windows | kẻ tấn công = toàn quyền máy (mở PowerShell, cài gì cũng được) | **Cao nhất** |
| A3 | Âm thanh trong phiên (họp, gọi) | nghe lén nội dung | Cao |
| A4 | Clipboard & file (T2/T3) | rò dữ liệu 2 chiều | Cao |
| A5 | Mật khẩu & refresh token của người dùng | chiếm phiên, chiếm máy | Cao |
| A6 | Khoá riêng TLS & khoá ký JWT | giả mạo server cho **mọi** người dùng | Cao |
| A7 | Nhật ký (metadata: ai xem gì, khi nào) | suy ra hành vi, giờ giấc | Trung bình |
| A8 | Danh sách cửa sổ / tên app | lộ "máy này đang làm gì" | Trung bình |
| A9 | Sự tồn tại của phiên (người ngồi máy có biết không) | §2.4: **cố ý** thông báo, không phải tài sản bí mật | Thấp (theo thiết kế) |
| A10 | Tài nguyên máy (CPU/GPU/RAM) | DoS, hao pin | Thấp |

### 41.2 Vị trí kẻ tấn công (10 vị trí, mỗi vị trí làm được gì)
| # | Vị trí | Năng lực | Ví dụ trong sản phẩm này |
|---|---|---|---|
| P1 | **Kẻ trên mạng** (LAN/VPN, chặn gói được) | nghe, chèn, phát lại, cắt | ARP spoof trong LAN; VPN provider |
| P2 | **Người dùng web độc hại khác** (có tài khoản, không có quyền) | gọi API với tài khoản của họ | user A cố mở phiên của user B; dò `sid` |
| P3 | **Trình duyệt / máy client bị chiếm** | đọc mọi thứ client thấy, điều khiển phiên | malware trên laptop người điều khiển |
| P4 | **Trang web độc hại** (không có tài khoản) | dụ người dùng, CSRF, clickjacking, XSS | link phishing tới `/s/:sid` |
| P5 | **Trình duyệt có extension độc** | đọc/sửa DOM, đọc clipboard, chụp API | extension "tiện ích" cài vào Chrome |
| P6 | **Người ngồi trước máy** (có quyền OS nhưng không phải admin, không có mật khẩu RD) | dùng máy, đọc file của mình, đọc log, chặn app | nhân viên dùng máy bị hỗ trợ |
| P7 | **Người có quyền admin OS trên máy server** | đọc state file, đọc khoá, hook agent | — |
| P8 | **Kẻ tấn công supply chain** | thư viện/driver/update độc | plugin GStreamer, bản update giả |
| P9 | **Nhà cung cấp hạ tầng** (VPN provider, CDN) | thấy metadata, chặn | Tailscale, ISP |
| P10 | **Chính agent** bị lỗi (không phải kẻ tấn công, nhưng gây hại) | dùng sai API, rò dữ liệu, crash | bug trong code của ta |
> **Không** đưa vào: kẻ có quyền SYSTEM trên máy đích (coi như đã mất máy) — không hệ thống remote desktop nào chống được; và kẻ kiểm soát máy client + token (coi như đã chiếm phiên).

### 41.3 Ranh giới tin cậy — quyết định nền
```
   ┌──────────── KHÔNG TIN CẬY ────────────┐        ┌──────── TIN CẬY (có điều kiện) ────────┐
   │ Trình duyệt client                    │        │ Agent trên máy Windows                 │
   │ · DOM, JS, extension                  │◄──────►│ · capture, encode, input, audio        │
   │ · mọi thứ gửi từ đây phải kiểm tra    │  TLS/  │ · **được tin**: nó điều khiển máy thật │
   │ · KHÔNG được tin: toạ độ, input, sid  │  DTLS  │ · nhưng KHÔNG được tin: input thô      │
   └───────────────────────────────────────┘        └────────────────────────────────────────┘
                    ▲                                              ▲
                    │                                              │
              người dùng đăng nhập                          người ngồi máy (P6) + admin (P7)
```
> **Áp dụng cho bản cá nhân (v3.15):** threat model này **giữ nguyên**. Lý do rất cụ thể: "client" không chỉ là bạn — nó là **bất kỳ ai trong LAN** mở được URL đó. Thiết kế "server không tin client" là thứ duy nhất khiến việc chỉ có 1 mật khẩu vẫn an toàn (§0.3.3 #1). Cái **đã bỏ** chỉ là phần nhiều người/quyền hạn (role, policy, audit export).

**Ba hệ quả lật ngược so với spec cũ:**
1. **Client không được tin** ⇒ agent phải **kiểm tra lại mọi thứ** client gửi: toạ độ (clamp), phím (validate UTF-16), `sid` (thuộc user), lệnh (đúng quyền), tần suất (rate limit). §10 có nói nhưng như "biện pháp"; ở đây nó là **luật kiến trúc**.
2. **Agent được tin về *hành vi*, không được tin về *dữ liệu*** ⇒ agent được phép `SendInput` (vì đó là chức năng), nhưng **không** được phép tự quyết định vượt quyền của user (ví dụ: agent chạy elevated thì phiên thường **không** được tự động hưởng quyền đó — phải có cờ §9.9b).
3. **`window list` là dữ liệu do agent sinh** ⇒ client **không bao giờ** gửi `hwnd` tuỳ ý; agent chỉ chấp nhận `wid` **nằm trong danh sách nó vừa trả** (cache 3 s). Nếu không, client có thể đưa `hwnd` của cửa sổ bất kỳ (kể cả cửa sổ của app nhạy cảm người dùng không cho xem). **Đây là lỗ hổng leo thang quyền thật** trong thiết kế "client chọn cửa sổ".

### 41.4 Bảng mối đe doạ theo ranh giới
| # | Ranh giới | Mối đe doạ | Vị trí | Tác động | Giảm thiểu | Còn lại |
|---|---|---|---|---|---|---|
| T1 | Client→Agent: danh sách cửa sổ | gửi `hwnd` tuỳ ý để stream cửa sổ người dùng không cho phép | P2,P3 | **xem trộm nội dung** | `wid` phải nằm trong danh sách agent vừa trả (cache + TTL 3 s); allowlist; audit `wid` | — |
| T2 | Client→Agent: input | input flood, toạ độ ngoài biên, key sequence làm treo app | P3 | DoS app, hành vi ngoài ý muốn | clamp, rate limit, `release_all` watchdog (§7.5), không cho `Win+L`/SAS | app vẫn có thể bị làm treo |
| T3 | Client→Agent: lệnh | gọi lệnh của user khác / lệnh ngoài state | P2 | chiếm phiên | mọi request kiểm `sid.owner == token.sub`; `availableIn` check server-side (không chỉ UI) | — |
| T4 | Client↔Agent: media | nghe lén, chèn frame | P1 | xem trộm | DTLS-SRTP bắt buộc; không có đường plaintext; cert hợp lệ | P1 kiểm soát cả hai đầu (MITM) nếu cert không được xác minh ⇒ §41.6 |
| T5 | Client: XSS qua dữ liệu agent | tên cửa sổ do app bên thứ ba đặt ⇒ chèn HTML | P2 (đặt tên app) | chạy JS trong origin ⇒ chiếm phiên | `textContent` mọi nơi, CSP `default-src 'self'`, không `innerHTML` với dữ liệu server, **không** render thumbnail từ HTML | — |
| T6 | Client: trang độc hại | CSRF (POST tạo phiên), clickjacking (nút "kết thúc"/"cho phép") | P4 | tạo phiên / thao tác ngoài ý muốn | SameSite=Strict, custom header cho mutation, `X-Frame-Options: DENY` / `frame-ancestors 'none'`, **không** nhận token từ query | — |
| T7 | Client: extension | đọc DOM, đọc clipboard, đọc video | P5 | mất toàn bộ nội dung | **không thể chống** — ghi rõ trong §6.13; khuyến nghị profile riêng / không extension | chấp nhận |
| T8 | Client: máy bị chiếm | keylogger, screenshot | P3 | như trên | **không thể chống** | chấp nhận |
| T9 | Token bị lộ (log, shoulder-surf, malware) | dùng lại | P3 | chiếm phiên | access 15′, refresh rotate + **reuse detection**, cookie HttpOnly, revoke all, IP/UA audit | refresh bị lộ **trước** khi dùng lần đầu = không phát hiện được |
| T10 | Agent: state file / khoá | đọc khoá JWT ⇒ giả token | P7 | toàn quyền | khoá trong `ProgramData` ACL + **DPAPI**, state file chỉ có vị trí cửa sổ (không bí mật), không lưu secret trong log | P7 = đã mất máy |
| T11 | Agent: log | rò tiêu đề cửa sổ, IP, clipboard | P6 | suy ra hành vi | **không log** tiêu đề/clipboard mặc định; redaction bắt buộc (§26.3); log rotate; audit 90 ngày | P6 đọc được metadata phiên |
| T12 | Agent: driver/update | driver giả, update giả | P8 | toàn quyền | ký số binary + driver; **verify signature trước khi chạy**; update qua HTTPS + signature; pin hash | P8 kiểm soát nhà cung cấp cert |
| T13 | Người ngồi máy (P6) | chặn/kết thúc phiên, xem log | P6 | mất phiên (nhưng **đúng thiết kế** — §21.7) | **không** chống: người ngồi máy **luôn** có quyền dừng | chấp nhận (đây là tính năng) |
| T14 | Người ngồi máy: `SetWindowDisplayAffinity` | đặt `WDA_EXCLUDEFROMCAPTURE` lên app của họ ⇒ ta không capture được | P6 | phá phiên (DoS) | phát hiện + `412 capture_blocked` + thông báo | chấp nhận (họ có quyền trên máy của họ) |
| T15 | Client: clipboard (T2) | dán nội dung độc vào app (macro, công thức Excel, URL) | P3/P5 | thao tác ngoài ý muốn | chỉ dán khi **bấm nút**, có xem trước, không auto-sync; không dán file/HTML | người dùng vẫn có thể tự dán |
| T16 | Agent: `SendInput` vào app elevated | leo quyền qua UIPI | P2 (nếu agent elevated) | điều khiển app admin | agent elevated **chỉ khi** người dùng chọn (§9.9b); phiên thường không hưởng | nếu bật elevated, đây là đánh đổi đã biết |
| T17 | Agent: audio | rò tiếng máy thật khi routing sai | P10 | phá HVNC | kiểm chứng session enumeration (§40.6) + `audio_leak` cảnh báo | app exclusive mode không kiểm chứng được |
| T18 | Metadata: `GET /api/windows` | liệt kê cửa sổ liên tục ⇒ biết người dùng đang làm gì | P2 (user khác) | **giám sát ngầm** | rate limit `/windows` (30/phút), audit mỗi call, **không** trả tiêu đề cho user không phải chủ máy | theo dõi được trong giới hạn rate limit |
| T19 | Toàn hệ: replay | phát lại request tạo phiên | P1 | phiên trùng | `Idempotency-Key` + nonce; TLS đã chống replay trong phiên | — |
| T20 | Toàn hệ: cert không được xác minh | client bỏ qua cảnh báo cert ⇒ MITM | P4/P1 | chiếm toàn bộ | **hard fail** nếu cert không hợp lệ (không cho "tiếp tục anyway" trong app); hướng dẫn cài cert | người dùng *có thể* bấm qua cảnh báo của trình duyệt |

### 41.5 Năm quyết định thiết kế **bắt nguồn từ threat model** (không phải từ tiện lợi)
| # | Quyết định | Từ mối đe doạ | Nếu làm khác thì sao |
|---|---|---|---|
| D1 | **Client không bao giờ gửi `hwnd`; chỉ gửi `wid` đã có trong danh sách** | T1 | leo thang: xem cửa sổ người dùng không cho phép, kể cả cửa sổ của app khác |
| D2 | **Không có endpoint "chạy lệnh"/"mở file"** trên agent | A2 | biến agent thành backdoor; mọi phiên đều có thể chạy lệnh dù người dùng chỉ muốn xem |
| D3 | **File transfer & clipboard mặc định TẮT**, chỉ bật tường minh | A4 | đường vận chuyển dữ liệu không kiểm soát giữa 2 máy khác nhau về chính sách |
| D4 | **`X-Frame-Options: DENY` + không nhận token trong URL** | T6 | clickjacking nút "cho phép điều khiển"; link chứa token lọt vào lịch sử/referrer |
| D5 | **Người ngồi máy luôn có quyền dừng, và toast/icon tray không tắt được** | T13 + §2.4 | biến sản phẩm thành RAT; mất khả năng phân biệt với malware khi bị EDR soi |

### 41.6 Token & phiên — chi tiết (thay cho 3 dòng ở §10)
| Hạng mục | Thiết kế | Vì sao |
|---|---|---|
| Access token | JWT **HS256**, **15 phút**, chứa `sub`, `role`, `sid_scope`, `jti`, `iss`, `aud` — *(v3.28: RS256 → HS256, lý do §57.4 D-1)* | ngắn để giảm giá trị đánh cắp |
| Refresh token | **opaque** `rt.<id>.<secret>`, lưu **hash** SHA-256 trong DB, **rotate mỗi lần dùng**, TTL **7 ngày** (§9.11 — con số 30 ngày không tồn tại) | rotate phát hiện trộm |
| Reuse detection | dùng refresh cũ ⇒ **revoke toàn bộ chuỗi** + audit + buộc đăng nhập lại | chuẩn công nghiệp |
| Nơi lưu | `HttpOnly; Secure; SameSite=Strict; Path=/api` | JS không đọc được ⇒ XSS không lấy token |
| Access token ở client | trong **memory** (không localStorage) | localStorage bị extension/JS đọc |
| Binding | refresh gắn `device_id` (random, trong cookie riêng) + UA hash; lệch ⇒ cảnh báo, không chặn | giảm giá trị token bị đánh cắp, không phá UX |
| Revoke | logout → revoke chain; "đăng xuất mọi nơi"; **đổi mật khẩu ⇒ revoke tất cả** | |
| Clock | skew ±60 s; `jti` chống replay trong 15 phút | |
| Password | **PBKDF2-HMAC-SHA256 210 000 vòng** *(v3.28: argon2id → PBKDF2, lý do §57.4 D-2)*, salt 16 byte, min 12 ký tự, không cấm ký tự đặc biệt, **kiểm tra danh sách phổ biến** offline | |
| Lockout | 5 lần / 15 phút / (IP+user); đếm cả **user không tồn tại** để không lộ user | |
| Timing | so sánh hash **hằng thời gian**; trả lỗi giống nhau cho user sai/không tồn tại | |

### 41.7 Người ngồi máy (P6) — đối xử thế nào
Đây là ranh giới **không rõ ràng nhất** và phải nói rõ:

| Họ được phép | Không được phép | Ta xử lý |
|---|---|---|
| Dùng máy của họ, mở app, kéo cửa sổ | tắt agent, kill process (nếu không phải admin) | nếu họ tắt: phiên `closed`, client thấy lý do rõ, **không** tự khởi động lại trong 60 s (tôn trọng ý định) |
| Dừng phiên bất kỳ lúc nào (§21.7) | đọc token | — |
| Đọc log của chính họ | đọc log của người dùng khác | log theo user, ACL |
| Cài app hiển thị `WDA_EXCLUDEFROMCAPTURE` | — | `412 capture_blocked`, không cố vượt |
| Đổi default audio device | — | không giành lại (§40.8) |
**Nguyên tắc:** người ngồi máy có **quyền phủ quyết** với phiên, nhưng **không** có quyền xem bí mật của người điều khiển (token, mật khẩu). Hai chiều đều phải tôn trọng.

### 41.8 Supply chain — bản cá nhân (4 dòng thay vì 7)
Đã cắt Authenticode/SBOM/signature gói update (§0.3.1 #1–2, #6). Còn lại thứ **thật sự** bảo vệ bạn:

| Hạng mục | Yêu cầu |
|---|---|
| **Driver (VDD, cable)** | chỉ dùng **bản phát hành đã ký** (đã ký sẵn bởi nhà cung cấp); ghim version + hash vào `LICENSES.md`; **không** tự build/ký |
| **GStreamer plugin** | ghim version + hash; app **tự set** `GST_PLUGIN_PATH`, **không** kế thừa env (một `GST_PLUGIN_PATH` độc = chạy code lạ trong process của bạn) |
| **Rust deps** | `cargo deny check` (licence + RustSec) chạy tay trước mỗi lần build release — **không** build script lạ |
| **Client assets** | không third-party, không CDN (CSP `default-src 'self'`) — §26.10 |

### 41.9 Rủi ro chấp nhận (ghi rõ, không giấu)
| # | Rủi ro | Vì sao chấp nhận | Người dùng cần biết |
|---|---|---|---|
| R1 | Client bị chiếm (P3) ⇒ lộ toàn bộ nội dung | không thể chống từ server | §6.13 |
| R2 | Extension độc (P5) | không thể chống | §6.13 + khuyến nghị profile riêng |
| R3 | Admin OS trên máy đích (P7) | đã mất máy | — |
| R4 | Người ngồi máy tắt agent / chặn capture | quyền của họ | — |
| R5 | VPN provider thấy metadata (P9) | chấp nhận; không log nội dung | — |
| R6 | Cert tự ký bị người dùng bấm qua cảnh báo | giáo dục + hard-fail trong app | §41.6 |
| R7 | Defender gắn cờ (HVNC + inject) | bản chất kỹ thuật | §21.11 |
| R8 | App exclusive-mode audio không kiểm chứng được | giới hạn Windows | §40.7 |
| R9 | Xem trộm trong giới hạn rate limit `GET /windows` (T18) | cần cho UI | chỉ chủ máy xem |

### 41.10 Kiểm chứng bảo mật (không chỉ đọc code)
| # | Kiểm tra | Cách |
|---|---|---|
| 1 | `wid` lạ bị từ chối | test: gửi `wid` không có trong danh sách ⇒ 403 + audit |
| 2 | `sid` người khác | 2 user, chéo `sid` ⇒ 403 ở **mọi** endpoint + WSS |
| 3 | XSS qua tên cửa sổ | test: đặt tên cửa sổ `<img onerror=...>` ⇒ không chạy |
| 4 | CSRF | POST từ origin khác, không custom header ⇒ 403 |
| 5 | Clickjacking | `X-Frame-Options` + thử nhúng iframe ⇒ bị chặn |
| 6 | Token reuse | dùng refresh cũ ⇒ toàn bộ chain revoke, các phiên khác chết |
| 7 | Plaintext media | Wireshark: chỉ TLS/DTLS, không H.264/Opus thô (§17.1) |
| 8 | Cert | cert sai ⇒ hard fail, không có nút "tiếp tục" |
| 9 | Rate limit | 100 req/s `/windows` ⇒ 429, audit |
| 10 | Fuzz | REST + WSS + DataChannel: 1 triệu input ngẫu nhiên ⇒ không panic, không crash |
| 11 | Input không vượt biên | toạ độ ±2^31 ⇒ clamp, không lái chuột ra ngoài |
| 12 | Log redaction | grep log sau 100 phiên ⇒ **0** token, 0 clipboard, 0 nội dung app |
| 13 | `config.json` hỏng | ghi `.tmp`+rename ⇒ không mất cấu hình; file hỏng ⇒ app dùng mặc định + báo rõ |
| 14 | Bị gắn cờ | thêm exclusion + xem Defender history; **không** cố "vượt" (§21.11) |

### 41.11 Nhánh mới rẽ ra
| Nhánh | Lĩnh vực | Vì sao từ §41 |
|---|---|---|
| **#2 Multi-session: tài nguyên, cách ly, 1 capture → N encode** | F | T1/T3 phức tạp hơn khi nhiều phiên; cách ly session là yêu cầu bảo mật |
| **#3 Đóng gói & vòng đời cài đặt** | F | §41.8 (ký số, verify) chỉ thực thi được ở installer |
| **#9 Consent UX người bị điều khiển** | E | T13 + §2.4: cần thiết kế cụ thể, không chỉ "có toast" |
| **#10 Cert/proxy/trust chain sâu** | E | T20 + §41.6 |
| #4 Hiệu năng client | H | |
| #5 Input sâu | C | |

---

## 42. Một phiên tại một thời điểm — vì sao không thể nhiều hơn (nhánh #2 — lĩnh vực F, đã thu hẹp)

> **Chương này đã thu hẹp ở v3.15.** v3.12 viết nó như tính năng "3 phiên song song"; §0.3.1 #5 cắt tính năng đó. Nhưng **§42.1 (ràng buộc 1 con trỏ / 1 focus) là kiến trúc của Win32 — nó vẫn đúng**, và nó là lý do bạn không thể mở 2 tab. Phần còn lại: cách **từ chối đúng** và cách **không mất dữ liệu** khi chuyển tab.

> §3 hứa **Tier 2: 3 phiên song song**. §37.10 mới nói *giới hạn slot encoder*. §41 nói cách ly là yêu cầu bảo mật. Nhưng câu hỏi chưa ai đặt: **3 phiên trên CÙNG một Windows user session có thật sự chạy được không?**
> Câu trả lời là **không, không phải cho input** — và lý do là một thứ nằm ngoài mọi thứ spec đã bàn.

### 42.1 Ràng buộc nền: **một desktop chỉ có MỘT con trỏ và MỘT focus**
Windows (user session) có **một** `GetCursorPos` toàn cục và **một** foreground window cho **toàn bộ desktop** — bất kể có bao nhiêu display ảo, bao nhiêu cửa sổ. Điều này không phải giới hạn của ta; nó là kiến trúc của Win32.

Hệ quả trực tiếp:

| Thao tác | Thực tế |
|---|---|
| `SendInput` absolute tới display ảo **A** | con trỏ hệ thống **rời** display B, **đi** sang A. Chỉ cửa sổ ở A nhận message |
| Phiên B gửi click tới display ảo **B** | con trỏ **rời** A ⇒ phiên A **mất hover**, mất drag đang giữ, tooltip tắt |
| Hai phiên cùng gửi `pointermove` | con trỏ **nhảy qua lại** giữa 2 display ở 120 Hz ⇒ **cả hai đều không dùng được** |
| Hai phiên cùng gõ phím | tất cả đi vào **một** foreground window ⇒ phiên này gõ vào app của phiên kia |
> **Kết luận cứng: trên cùng một Windows user session, tại một thời điểm chỉ có ĐÚNG MỘT phiên được điều khiển.**
> Đây không phải "nên tránh" — hai phiên điều khiển đồng thời sẽ **phá cả hai**, và tệ hơn: phiên A có thể gõ vào cửa sổ của phiên B (**rò rỉ chéo**).

### 42.2 Bản cá nhân: **1 phiên tại một thời điểm** — và 3 dòng phòng thủ
Đã cắt multi-session như tính năng (§0.3.1 #5). Nhưng **không** xoá chương này, vì ràng buộc §42.1 là có thật và bạn sẽ vô tình đụng nó:

| Tình huống bạn sẽ gặp | Hành vi phải có | Code |
|---|---|---|
| Mở 2 tab cùng lúc (1 tab cũ còn sống trong grace 30 s) | tab thứ 2 nhận `409 already_streaming` + nút **"Tiếp tục ở tab này"** (giết phiên cũ, xin keyframe) | ~10 dòng |
| Chuyển từ điện thoại sang laptop giữa phiên | như trên: 1 cú bấm là chuyển, `release_all` **trước** khi cấp cho tab mới | ~15 dòng |
| App cũ chưa đóng hẳn, bạn mở app mới | khởi động mới phát hiện `state.json` còn ⇒ hiện "Có phiên cũ, khôi phục?" thay vì tạo display thứ 2 | ~20 dòng |
> **Bỏ hẳn** (chi tiết ở v3.12 §42.3–42.5, §42.9, §42.11): input lease, xin quyền, waiting, FIFO, force-handover, fairness 4 mức, fanout N viewer, admission control theo VRAM/RAM, bảng 13 tài nguyên.
> **Giữ:** đúng **1** phiên; khi tạo phiên mới fail thì báo **lý do cụ thể** (hết display slot ≠ hết VRAM); tài nguyên giải phóng sau 5 s delay (§42.13) để F5 không phá display.

### 42.6 Display slot — vấn đề **đổi nghĩa** khi chỉ có 1 phiên
Windows giới hạn số display trên một adapter (**thường 4–8**, tuỳ driver); mỗi display ảo của VDD là display **thật** ở tầng OS. Với 3 phiên, đây là điểm chết. **Với 1 phiên, nó gần như không còn là vấn đề** — nhưng còn **hai** hệ quả thật:

1. **Display ảo được giữ lại sau khi đóng phiên** (§9.2.2) ⇒ sau vài chục lần dùng, số display ảo **tích tụ**. Trên laptop 1 màn hình, 4 display ảo là chạm trần.
   ⇒ Luật: **tối đa 2 display ảo tồn tại** (`display.keep_max = 2`). Tạo cái thứ 3 ⇒ **tái sử dụng** cái đang rảnh (reset + move cửa sổ vào) thay vì tạo mới; nếu cái rảnh còn cửa sổ mồ côi ⇒ rescue (§9.2.3) rồi mới tái sử dụng.
2. **Chừa 1 slot cho màn hình thật**: nếu không còn slot ⇒ `503 display_exhausted` kèm việc cần làm ("đưa 1 cửa sổ về màn hình thật để giải phóng display"), **không** thử lại vô hạn, **không** tự xoá display đang có cửa sổ.

> Vẫn giữ nguyên: **chưa biết chắc** VDD chịu được mấy display và có ổn định không ⇒ đây là một trong **hai** câu hỏi chặn P0 (cùng p95/TWCC). Kiểm chứng: tạo 4 display ảo liên tiếp, capture từng cái, xoá — xem cái nào fail.

### 42.7 Âm thanh
Không có "nhiều phiên". Chỉ 1 cable: nếu tab 2 chiếm audio thì tab 1 mất tiếng — **đúng**, vì chỉ 1 tab được sống (§42.2). Không cần logic cách ly.
Watchdog restore default device (§40) chỉ chạy khi **không còn phiên nào**.

### 42.13 Dọn tài nguyên — chỉ cần đúng 1 luật
Refcount về 0 ⇒ **hẹn 5 s** rồi mới dọn (F5 / reconnect xảy ra trong cửa sổ này). Có phiên mới trong 5 s ⇒ huỷ hẹn.
Áp dụng cho: D3D11 device, encoder, cable. **Không** áp dụng cho màn hình ảo (nó được **giữ lại** sau khi đóng phiên — §9.2.2 — chính là lý do phải có "khôi phục phiên cũ" ở §42.2).

### 42.14 Metrics cần xem (rút từ 10 xuống 6)
`sid`, `fps_sent`, `bitrate`, `rtt`, `loss`, `freezeCount`, `vram_mb`, `cpu_pct`, `display_slots_used`, `restore_pending` (cửa sổ chưa được trả về màn hình thật).
Đã bỏ: `lease_holder`, `role`, `input_rejected`, `fairness_action`, `admission_rejected_reason` — không còn khái niệm tương ứng.

### 42.15 Kiểm chứng — 4 test (thay 10)
| # | Test | Ngưỡng |
|---|---|---|
| 1 | Mở tab 2 khi tab 1 đang chạy | `409` + 1 cú bấm chuyển được; **0** kẹt phím trên máy thật |
| 2 | F5 giữa phiên | resume, **không** tạo display thứ 2, không mất tiếng |
| 3 | Kill app giữa phiên rồi mở lại | `state.json` ⇒ "khôi phục phiên cũ?"; cửa sổ vẫn ở display ảo |
| 4 | Đóng phiên | sau 5 s: encoder/cable/D3D giải phóng; display ảo **vẫn còn** (đúng như thiết kế) |

### 42.16 Nhánh mới
| Nhánh | Lĩnh vực | Trạng thái |
|---|---|---|
| ~~#3 Đóng gói MSI~~ | — | **đã cắt** (§0.3.1 #6) — còn `install.ps1`/`uninstall.ps1` (§45.3) |
| ~~#13 Lease UX~~ | — | **đã cắt** (không còn lease) |
| ~~#14 Nhiều Windows user session~~ | — | **đã cắt** (§0.3.1 #10) |
| **#20 Máy không GPU / VNC-only** (chỉ Media Foundation, hoặc không có display ảo) | A/F | còn — §45.2, ảnh hưởng P1 |
| #7 UI state thực thi | D | còn |

---

## 43. Hiệu năng client — ngân sách, cách đo, và cách chặn (nhánh #4 — lĩnh vực H)

> §26.11 đặt ngân sách (JS ≤220 KB, first paint <400 ms, pin <12%/giờ) nhưng **không có cách nào chặn**. Đó là "mong ước", không phải ràng buộc: một PR thêm 80 KB library vẫn merge được, và 3 tháng sau client là 900 KB.
> Chương này quan trọng hơn vẻ ngoài của nó: **trên điện thoại, hiệu năng client quyết định "dùng được hay không" nhiều hơn cả độ trễ mạng.** Một client 40 ms/frame overlay + 60 fps video đã là 30 fps cảm nhận, dù đường truyền hoàn hảo.

### 43.1 Vì sao client dễ chết hơn server (dù code ít hơn 5×)
| Ràng buộc | Server | Client |
|---|---|---|
| Nền tảng | **1** (Windows, ta kiểm soát) | **6+** (Chrome/Edge/Firefox/Safari × desktop/mobile) |
| CPU | core hiện đại | **điện thoại 4 năm tuổi**, bị throttle vì nhiệt |
| Bộ nhớ | 8–32 GB | **Safari iOS kill tab ở ~200–400 MB** (không cảnh báo) |
| Runtime | native | JS với JIT, GC **không kiểm soát được** (`Major GC` 30–80 ms) |
| Đo | dễ | phải qua Stats API, `performance.mark`, và **không đo được mọi thứ** |
| Người dùng | 1 | mỗi người 1 thiết bị, không debug được từ xa |
> Hệ quả: mọi thứ ở đây phải bảo thủ **2×** so với server, và phải **đo trên thiết bị thật**, không chỉ trên máy dev.

### 43.2 Ngân sách (một bảng, có cách đo từng dòng)
| # | Chỉ số | Ngân sách | Đo bằng | Fail CI? |
|---|---|---|---|---|
| 1 | JS tổng (chưa nén, không gzip) | **≤ 220 KB** | `du` sau build | ✅ |
| 2 | JS gzip | ≤ 70 KB | `gzip -9 \| wc -c` | ✅ |
| 3 | CSS | ≤ 30 KB (gzip ≤ 10) | | ✅ |
| 4 | Không có dependency runtime | **0** | `package.json` không có `dependencies` | ✅ |
| 5 | First contentful paint `/login` (LAN, cold) | < 400 ms | Lighthouse / Playwright trace | ✅ |
| 6 | Dashboard 20 cửa sổ: interactive | < 700 ms | Playwright `TBT` + `measure()` | ✅ |
| 7 | Dashboard cuộn | ≥ 55 fps | Playwright + `requestAnimationFrame` sampling | ✅ |
| 8 | **Chi phí overlay mỗi frame** (cursor+ripple+HUD) | **≤ 2.5 ms p95** | `performance.now()` quanh vẽ | ✅ |
| 9 | **Main-thread long task** khi đang xem | **0 task > 50 ms / 60 s** | `PerformanceObserver('longtask')` | ✅ |
| 10 | Memory phiên 1080p60 (Chrome desktop) | < 250 MB | `performance.memory` / CDP | ⚠️ |
| 11 | Memory phiên (Safari iOS) | < 180 MB (**hard**) | Instruments / CDP không có ⇒ manual | ⚠️ |
| 12 | Rò rỉ qua 2 h | RSS tăng < 15% | soak + `measureUserAgentSpecificMemory()` | ✅ |
| 13 | Pin (mobile, Cân bằng) | < 12%/giờ | 30 phút đo, ngoại suy | ⚠️ |
| 14 | Số frame decode drop (khi CPU rảnh) | < 1% | `getStats()` `framesDropped` | ✅ |
| 15 | Nhiệt: không throttle trong 10 phút | fps p95 ≥ 55 | thiết bị thật | ⚠️ |
> Dòng **8 và 9** là hai dòng quan trọng nhất và hay bị bỏ: overlay vẽ sai cách sẽ ăn 10–20 ms/frame, và long task (JSON parse, DOM rebuild) làm **giật cả video** dù video decode trên GPU.

### 43.3 Đường render — cái gì chạy ở đâu (quyết định)
```
┌─ Compositor (GPU, ngoài main thread) ─────────────────────────────┐
│  <video> (decode HW → texture → composite)                        │
│  overlay layer: <canvas 2d> hoặc vài <div> transform (cursor)     │
└───────────────────────────────────────────────────────────────────┘
┌─ Main thread (JS) ────────────────────────────────────────────────┐
│  input capture (pointer/key) → gửi DataChannel                    │
│  cursor position update (từ local pointer, không từ server!)       │
│  ripple animation (canvas)                                        │
│  HUD cập nhật 2 Hz (không phải 60 Hz)                              │
└───────────────────────────────────────────────────────────────────┘
```
**Quyết định cụ thể:**

| Việc | Cách | Vì sao không dùng cách khác |
|---|---|---|
| Video | **`<video>` element** với `srcObject` | Canvas + `drawImage` mỗi frame = copy + main thread ⇒ mất HW decode path, +8–15 ms/frame |
| Con trỏ | **`<div>` với `transform: translate3d()`**, 1 element, cập nhật trong `pointermove` | Canvas vẽ lại mỗi move = 1 clear + 1 draw = tốn; div transform do compositor xử lý, **0 ms main thread** |
| Ripple | `<canvas>` riêng, **chỉ vẽ khi có ripple**, tự dừng rAF khi hết | vẽ liên tục = 60 fps vô ích |
| HUD số liệu | cập nhật **2 Hz** bằng `textContent` | 60 Hz = 60 lần layout/giây; `textContent` rẻ hơn `innerHTML` 10× |
| Letterbox | CSS `object-fit: contain` trên video | tự tính toán + `transform` thủ công dễ sai khi resize |
| Zoom local | CSS `transform: scale()` trên **container** | đổi `width/height` = reflow + video re-decode |
| Đo vị trí chuột | `getBoundingClientRect()` **cache**, invalidate khi resize/scroll | gọi mỗi `pointermove` = **forced reflow** (đắt nhất trong list này) |

### 43.4 Chỗ tốn tiền thật (theo thứ tự, đo được)
| # | Nguyên nhân | Chi phí điển hình | Cách tránh |
|---|---|---|---|
| 1 | **Forced reflow** khi lấy `getBoundingClientRect()`/`offsetX` mỗi pointer event | **0.2–2 ms/event × 60 = 12–120 ms/s** | cache rect; chỉ tính lại khi `resize`/`scroll`/zoom |
| 2 | **`canvas` vẽ lại toàn bộ** overlay mỗi frame | 3–8 ms/frame | chỉ vẽ vùng thay đổi, hoặc dùng div transform cho cursor |
| 3 | **JSON.parse** message lớn (clipboard, stats history) | 2–20 ms, 1 lần nhưng **long task** | giới hạn kích thước, parse trong Worker nếu >64 KB |
| 4 | **Rebuild DOM** danh sách cửa sổ (20 card) mỗi 5 s | 8–25 ms + layout | diff keyed, hoặc chỉ update text/hash-diff thumbnail |
| 5 | **Thumbnail decode** 20 ảnh JPEG | 30–120 ms tổng | `createImageBitmap` **trong Worker**, `loading` tuần tự, cache theo hash |
| 6 | **`innerHTML`** với dữ liệu server | parse HTML + XSS risk | `textContent` + `createElement` |
| 7 | **CSS filter/backdrop-filter** trên overlay | 2–6 ms/frame trên mobile | chỉ dùng khi tĩnh |
| 8 | **Shadow blur lớn** trong canvas | 4–12 ms/frame | vẽ sẵn ảnh blur, hoặc bỏ |
| 9 | `requestAnimationFrame` **luôn chạy** khi không cần (ripple/HUD) | 1–3% CPU | tự huỷ rAF khi không có hoạt ảnh |
| 10 | **Timer 2 Hz cập nhật HUD** khi tab ẩn | pin | dừng hết timer khi `hidden` |
> Dòng 1 là **bug hiệu năng phổ biến nhất** trong app kiểu này và **không nhìn thấy bằng mắt** — chỉ đo mới biết.

### 43.5 Kiến trúc JS để giữ ngân sách (không framework, có kỷ luật)
| Quyết định | Lý do |
|---|---|
| **ES modules, không bundler** | 0 KB build tooling, browser tự cache từng module; không có "bundle phình" |
| **1 file/chức năng**, tổng ≤ 12 module | dễ đọc, dễ kiểm kích thước |
| **Render = `render(state)` thuần**, không JSX, không reactive proxy | diff thủ công theo `data-key`; proxy = overhead mỗi lần đọc |
| **Không dùng `class` cho component**, dùng closure + object | tránh `this` bug, nhỏ hơn |
| **Không polyfill** (Safari 16.4+ / Chrome 110+ là baseline) | polyfill = KB vô ích |
| **Không thư viện icon** — SVG sprite 1 file, chỉ icon đang dùng | font icon = tải cả bộ |
| **Không webfont** (§23.3) | |
| **Worker chỉ cho**: thumbnail decode, parse clipboard lớn | Worker = +tầng phức tạp, chỉ dùng khi có số chứng minh cần |
| **Không service worker** | cache phức tạp, lợi ích thấp vì app cần mạng |
| **JSDoc + `// @ts-check`** trong CI (`tsc --noEmit`) | type safety **không** tốn runtime KB |
| Đo kích thước trong CI, **fail nếu vượt** | đây là cơ chế thực thi duy nhất có tác dụng |

### 43.6 Bộ đo — phải chạy được trong CI (không phải "mở DevTools xem")
```js
// perf-probe.js — bật bằng ?perf=1, tự tắt ở production
export const probe = {
  marks: {}, longTasks: [], frames: [],
  start() {
    new PerformanceObserver(l => l.getEntries().forEach(e =>
      this.longTasks.push({ t: e.startTime, d: e.duration }))).observe({entryTypes:['longtask']});
    this._rafLoop();
  },
  _rafLoop() {
    let last = performance.now();
    const tick = (t) => { this.frames.push(t - last); last = t;
      if (this.frames.length > 600) this.frames.shift();
      this._id = requestAnimationFrame(tick); };
    this._id = requestAnimationFrame(tick);
  },
  overlay(ms) { this.marks.overlay = (this.marks.overlay||[]).concat(ms); },
  summary() { /* p50/p95 của frames, overlay, longTasks */ }
};
```
- **Chỉ bật khi `?perf=1`** hoặc qua header debug — không chạy ở production (rAF loop liên tục = tốn pin).
- `summary()` xuất JSON → Playwright đọc → so với ngân sách §43.2 → **fail CI**.
- Đo **trên 3 cấu hình**: desktop Chrome, **mobile Chrome throttled 4× CPU** (Playwright `--cpu-throttling`), và Safari iOS thật (manual, mỗi release).
- Thêm `video.getVideoPlaybackQuality()` để lấy `droppedVideoFrames` / `totalVideoFrames` — chỉ số **thật** về decode, không phải fps JS.
- `pc.getStats()` → `framesDecoded`, `framesDropped`, `jitterBufferDelay`, `freezeCount` — đối chiếu với server stats (nếu lệch ⇒ lỗi mạng/pipeline).

### 43.7 Máy ảo hoá thời gian: điểm mù và cách xử lý
| Việc **không** đo được trong CI | Thay bằng |
|---|---|
| Nhiệt/throttle thật của điện thoại | chạy 10 phút trên thiết bị thật, mỗi release; ngưỡng fps p95 |
| Pin | đo 30 phút + ngoại suy; so **tương đối** giữa 2 bản |
| GC thật của Safari iOS | `measureUserAgentSpecificMemory` không có ⇒ theo dõi `memory` qua Instruments (manual) |
| Kill tab do bộ nhớ (iOS) | test thủ công: mở 5 tab nặng + phiên 30 phút |
| Độ trễ cảm nhận | §17.3 đo glass-to-glass, không đo bằng CI |
> Nguyên tắc: **CI chặn hồi quy**, thiết bị thật xác nhận trải nghiệm. Không giả vờ CI đo được mọi thứ.

### 43.8 Mobile: ba giới hạn cứng phải thiết kế quanh
| Giới hạn | Số thật | Hệ quả thiết kế |
|---|---|---|
| **Safari iOS kill tab** khi bộ nhớ cao | ~200–400 MB (không cảnh báo, không catch được) | giữ memory < 180 MB: 1 video, không giữ frame buffer lớn, giải phóng thumbnail ngay sau khi vẽ, **không** cache ảnh lớn |
| **JIT bị hạn chế** ở một số chế độ (iOS standalone PWA cũ) | chậm 2–3× | không phụ thuộc micro-optimization; giữ code đơn giản |
| **`requestAnimationFrame` bị throttle** ở 30 Hz trên một số máy iOS (ProMotion không mở cho web) | 30 fps | **không** giả định rAF = 60 Hz khi đo; dùng `video.getVideoPlaybackQuality()` làm chuẩn |
| Android Chrome kill tab khi ẩn lâu | phổ biến | resume + thông báo (§6.11.1); lưu `sid` vào `sessionStorage` |
| Canvas 2D trên mobile chậm hơn desktop 3–5× | | hạn chế canvas: chỉ ripple, không vẽ cursor |

### 43.9 Overlay con trỏ — thiết kế để **0 ms main thread**
Đây là chỗ dễ phá ngân sách nhất vì nó chạy theo con trỏ (60–120 Hz).
```html
<div id="stage" style="position:relative; contain: layout paint size;">
  <video></video>                                     <!-- compositor -->
  <div id="cursor" style="will-change:transform;
       transform: translate3d(0,0,0); contain: strict;">
     <img id="cursorShape" />                          <!-- đổi src khi shape đổi -->
  </div>
  <canvas id="ripple" style="pointer-events:none"></canvas>
</div>
```

| Quy tắc | Lý do |
|---|---|
| Cursor = **`transform: translate3d(x,y,0)`**, không `left/top` | `left/top` gây **layout**; transform chỉ composite |
| `will-change: transform` + `contain: strict` | tách layer, không reflow phần còn lại |
| Đổi **shape** bằng cách đổi `img.src` (data URI, đã cache) | đổi `background-image` cũng được nhưng `src` dễ cache hơn |
| Scale shape bằng `transform: scale()`, **không** đổi width/height | tránh layout |
| Ẩn cursor = `opacity: 0` (không `display:none`) | `display` gây layout mỗi lần |
| Ripple canvas: **chỉ** 1 canvas, xoá từng vòng khi hết hạn, tạm dừng rAF khi hết vòng | |
| **Không** dùng `filter: drop-shadow` cho viền cursor (đắt trên mobile) — dùng ảnh shape có viền sẵn (server gửi kèm biến thể "có viền") | |
> Đo: `overlay()` gọi `performance.now()` quanh phần cập nhật, **không** quanh việc browser composite (không đo được từ JS). Ngân sách 2.5 ms p95 là cho **phần JS**.

### 43.10 Rò rỉ bộ nhớ — 8 nguồn thật trong app kiểu này
| # | Nguồn | Cách phát hiện | Cách tránh |
|---|---|---|---|
| 1 | `createImageBitmap`/`Blob URL` thumbnail **không revoke** | memory tăng khi refresh 5 s | `URL.revokeObjectURL` + `bitmap.close()` sau khi vẽ |
| 2 | Listener trên `window`/`document` không gỡ | tăng theo số lần vào/ra phiên | 1 `AbortController` cho mỗi phiên, `abort()` khi đóng |
| 3 | `setInterval` HUD không clear | CPU/pin khi đã rời phiên | timer thuộc về controller, clear trong `dispose()` |
| 4 | **rAF loop** không cancel | pin | `cancelAnimationFrame` trong `dispose()` |
| 5 | `DataChannel`/`RTCPeerConnection` không `close()` | memory + kết nối treo | `pc.close()` bắt buộc trong `dispose()` |
| 6 | Cache cursor shape **không giới hạn** | app gửi 1000 shape lạ ⇒ phình | LRU 64 shape, mỗi shape ≤64 KB |
| 7 | Mảng `frames`/`marks` của probe **không cắt** | phình khi bật perf | cửa sổ trượt (đã có trong code mẫu) |
| 8 | Giữ reference tới frame/`ImageData` | phình theo resolution | không lưu `ImageData`; chỉ lưu metadata |
**Test:** vào/ra phiên **50 lần** trong 1 trang ⇒ memory không tăng >10%; sau `dispose()` không còn listener/timer (kiểm bằng cách đếm qua `AbortSignal`).

### 43.11 Throttle khi tab ẩn & tiết kiệm pin
| Trạng thái | Video | Overlay | HUD | Timer |
|---|---|---|---|---|
| Tab active | bình thường | bật | 2 Hz | bật |
| Tab ẩn >10 s | server hạ 5 fps (§6.11.2) | tắt rAF | **dừng** | chỉ WS ping |
| Mobile màn hình tắt | như trên + `visibilitychange` | — | — | — |
| Pin <20% | hạ 30 fps, tắt ripple | tắt | 2 Hz | bật |
| `saveData` | như Tiết kiệm (§36.9) | tắt | 2 Hz | |
- **Không** giữ `wake lock` mặc định (tốn pin); chỉ khi người dùng bật "giữ màn hình sáng".
- `document.hidden` → **dừng hết rAF và timer thường**; chỉ giữ WS ping 30 s.

### 43.12 Kiểm chứng — 3 dòng, chạy trên máy bạn
Đã cắt CI gate 2 tầng + baseline 7 ngày + nightly leak (§0.3.1 #9). Còn lại thứ **vẫn bắt được lỗi thật**:
```powershell
node ci/size-gate.mjs                     # JS ≤220 KB / gzip ≤70 KB / 0 dependency  (§43.2)
npx tsc --noEmit -p client/jsconfig.json  # type gate
npx playwright test perf/                 # overlay p95 ≤2.5 ms · 0 long task >50 ms · memory <250 MB
```
- **Size gate là quan trọng nhất** và nó là 3 dòng: nó chặn đúng thứ đã giết nhiều client loại này (thêm 1 library ⇒ 900 KB ⇒ điện thoại 4 năm tuổi không tải nổi).
- Playwright dùng **video giả lập** `.webm` gắn vào `<video>` — đủ để đo overlay/render/GC, không cần server. Path WebRTC thật đo bằng **tay** (8 mục §21.10).
- Bỏ: baseline tương đối, leak test 50 lần tự động (làm tay khi sửa vòng đời phiên), mobile 4× CPU throttling (máy bạn tự nhiên chậm hơn hoặc không).

| Nhánh | Lĩnh vực | Trạng thái |
|---|---|---|
| **#15 Render thích ứng theo thiết bị** (chọn preset/overlay theo `hardwareConcurrency`, `deviceMemory`) | H | **giữ** — với 1 người dùng vẫn có nghĩa: điện thoại cũ của bạn khác laptop |
| ~~#16 Giám sát client từ xa / opt-in telemetry~~ | — | **đã cắt** (§0.3.1 #3/#9) |
| #5 Input sâu | C | ✅ xong §44 |

---

## 44. Input sâu: IME, Raw Input, remote-in-remote (nhánh #5 — lĩnh vực C)

> §5.7/§5.8/§6.4–6.7 mô tả **hành vi mong muốn**. Chương này bổ sung: **máy trạng thái input** (thứ quyết định kẹt phím — lỗi bạn sẽ gặp nhiều lần mỗi tuần), **khi nào server-side IME thật sự cần và giá của nó**, **game/Raw Input**, **remote-in-remote**. Phần **accessibility đã cắt** theo yêu cầu (§0.3.1 #3) — xem ghi chú ở §44.6.
> Input là tài sản **A2 (mức cao nhất)** trong §41: kẻ tấn công có input = toàn quyền máy.

### 44.1 Hai lớp input (tách ra thì mọi thứ rõ)
| Lớp | Client gửi gì | Server làm gì | Ai quyết định kết quả |
|---|---|---|---|
| **Lớp ý định** (intent) | `{"t":"text","s":"ế"}`, `{"t":"key","vk":65,"mods":2}` | inject Unicode hoặc VK | **client** (IME/subject của nó) |
| **Lớp thô** (raw) | `{"t":"raw","sc":30,"down":1}` (scan code) | inject scan code | **server** (layout + IME của nó) |
- Mặc định: **lớp ý định**. Lớp thô là opt-in (Tier 2, §44.3).
- **Không bao giờ** trộn: nếu client đang ở lớp thô thì không gửi `text`; nếu ở lớp ý định thì không gửi `raw`. Trộn ⇒ ký tự nhân đôi. Đây là bug kinh điển.

### 44.2 Máy trạng thái input — bảng chuẩn (thứ thay cho "gửi keyup khi blur")
Server giữ **trạng thái** cho mỗi phiên; mọi chuyển trạng thái phải qua đây:

```
input_state = {
  keys_held:      set<VK>          // phím vật lý đang giữ
  unicode_pending: bool             // đang gửi surrogate pair (2 event chưa đủ)
  buttons_held:   bitmask           // L/R/M/X1/X2
  mods:           bitmask           // Ctrl/Shift/Alt/Win do *client* giữ
  ime_composing:  bool              // client đang composition
  layer:          'intent'|'raw'
  lease:          holder_sid|null
}
```

| Sự kiện | Chuyển trạng thái | Bất biến phải giữ |
|---|---|---|
| `key down` | thêm vào `keys_held` | nếu VK đã có ⇒ **bỏ** (client gửi repeat) |
| `key up` | xoá khỏi `keys_held` | nếu không có trong set ⇒ vẫn gửi (an toàn) nhưng đếm `odd_keyup` |
| `text` (1 code unit) | gửi 1 cặp UNICODE | nếu là **high surrogate** ⇒ giữ `unicode_pending`, chờ low |
| `text` (low surrogate) khi `unicode_pending` | gửi cặp thứ 2, xoá cờ | nếu không có pending ⇒ **bỏ** (dữ liệu hỏng) |
| `composition*` | `ime_composing=true` | **không gửi** gì trong lúc compose (§6.6) |
| `compositionend` | gửi `text`, `ime_composing=false` | nếu rỗng ⇒ không gửi |
| `button down/up` | cập nhật `buttons_held` | up không khớp ⇒ vẫn gửi |
| `release_all` | gửi up cho **mọi** `keys_held` + mọi `buttons_held` + Ctrl/Shift/Alt/Win; xoá sạch | đây là **đường duy nhất** đảm bảo không kẹt |
| mất lease | `release_all` **rồi** mới nhường | thứ tự ngược = input chồng |
| watchdog 3 s không event + `keys_held≠∅` hoặc `buttons_held≠0` | `release_all` + `input_reset` warning | §6.4.7 lớp 4 |
| đổi layer | `release_all` trước | tránh nửa nọ nửa kia |
**Bất biến kiểm tra được (assert + test):**
1. Sau bất kỳ chuỗi sự kiện nào, nếu client im ≥3 s thì `keys_held = ∅` và `buttons_held = 0`.
2. Không bao giờ có 2 `down` liên tiếp cho cùng VK mà không có `up`.
3. `release_all` luôn idempotent.
4. Không gửi `text` khi `ime_composing = true`.
5. Không có surrogate lẻ tồn tại >1 s (nếu có ⇒ bỏ + log).

### 44.3 Server-side IME — có thật sự cần? (câu trả lời có giá)
**Khi nào cần:** app cần **key event thật** chứ không nhận Unicode — game có chat box riêng, app dùng Raw Input + kiểm tra scan code, app remote-in-remote, một số app Java/Qt cũ.
**Có 3 cách làm, giá rất khác nhau:**

| Cách | Cơ chế | Ưu | Nhược | Chọn? |
|---|---|---|---|---|
| **A. Gửi VK thô, để IME của server soạn** | client gửi `vk` thay vì `text`; IME (Telex/Japanese) trên server xử lý | không cần API đặc biệt; dùng đúng IME đã cài trên máy đó | phụ thuộc IME/layout của **máy người dùng** (có thể không cài Telex, hoặc layout AZERTY); trạng thái IME hiển thị ở đâu? | ✅ **chọn cho Tier 2** |
| **B. TSF (Text Services Framework) client-side ảo** | tự viết TSF text service để "đánh" chữ vào app | chính xác nhất về mặt kỹ thuật | **rất đắt** (COM text service, phải đăng ký, phải per-process), dễ crash app, và **chỉ hoạt động với app dùng TSF** | ❌ không làm |
| **C. Gửi scan code (lớp thô) + layout do client chỉ định** | client gửi `sc` + layout name; server `ActivateKeyboardLayout` | độc lập IME server | **đổi layout của máy người dùng** (xâm lấn, §40.8 tinh thần) ⇒ chỉ khi opt-in | ⚠️ chỉ trong chế độ "chơi game" |
**Quyết định:** Tier 1 = **lớp ý định (Unicode)**. Tier 2 = thêm **chế độ "bàn phím thô"** (client gửi `vk`/`sc`), hiện rõ trong UI: *"Chế độ bàn phím thô: dùng bàn phím/IME của máy kia. Gõ tiếng Việt sẽ phụ thuộc máy đó có Telex."* Và **cảnh báo layout** nếu layout server ≠ layout client (đọc được qua `GetKeyboardLayout`).
**Không** cam kết "gõ được tiếng Việt trong mọi app ở mọi chế độ" — chỉ cam kết ở lớp ý định.

### 44.4 Game, Raw Input, DirectInput
| Thực tế | Chi tiết |
|---|---|
| `SendInput` tạo input **được đánh dấu injected** (`LLKHF_INJECTED` / `LLMHF_INJECTED`) | hầu hết Raw Input app **vẫn nhận**; app lọc injected thì **không** |
| Anti-cheat (kernel-level) | chặn/không quan tâm; **không thể** vượt, và **không nên thử** (§21.13) |
| Game fullscreen-exclusive | đã có ở §11.1 (khuyến nghị borderless) |
| Chuột relative + Pointer Lock | §6.4.6 — bắt buộc cho game 3D |
| `SendInput` với `MOUSEEVENTF_MOVE` relative | một số game đọc `WM_INPUT` relative ⇒ hoạt động; một số đọc `GetCursorPos` delta ⇒ cần absolute; **gửi cả hai** ở chế độ game (absolute + relative cùng lúc sẽ nhân đôi → chỉ chọn 1, cấu hình được) |
| Phát hiện "app không nhận input" | nếu 500 ms sau khi gửi mà không có phản hồi thị giác **và** không có thay đổi focus, **không** kết luận được — chỉ ghi stats. Không hứa "phát hiện app chặn input" |
> Ghi vào §6.13: *"một số game/anti-cheat sẽ không nhận điều khiển từ xa"*.

### 44.5 Remote-in-remote (máy server đang là client của VNC/RDP khác)
| Vấn đề | Xử lý |
|---|---|
| `SendInput` vào app đang là **RDP client** | hoạt động; nhưng RDP client tự gửi tiếp input tới máy xa ⇒ ta điều khiển **2 tầng** ⇒ trễ cộng dồn, và `Ctrl+Alt+Del` mất tác dụng |
| Phím bị **RDP client bắt** (Alt+Tab, Win) | RDP giữ lại cho máy local ⇒ app đích không nhận. Không sửa được từ phía ta |
| Secure desktop của tầng dưới | `secure_desktop` warning có thể **không** xuất hiện (vì desktop của ta vẫn là Default) ⇒ người dùng bấm mà không thấy gì xảy ra |
| Phát hiện | kiểm tra process đang foreground có phải `mstsc.exe`/`vncviewer`/`vmware`/`VirtualBox` ⇒ banner nhẹ: *"Máy đang điều khiển một máy khác — có thể có 2 tầng trễ"* |
| Không cố sửa | đây là giới hạn bản chất; chỉ cần **thông báo** để người dùng hiểu vì sao trễ gấp đôi |

### 44.6 (đã cắt) Accessibility cho người khiếm thị
Bản v3.14 có 6 biện pháp a11y (screen reader chạy trên máy server để tiếng đọc đi qua audio, UIA over the wire, NVDA test). **Đã cắt theo yêu cầu** (§0.3.1 #3): không có người dùng khiếm thị trong phạm vi này.
Giữ đúng 1 dòng, vì nó miễn phí: **UI client bấm được bằng bàn phím** (§20.18) — cần khi bạn dùng 1 tay trên điện thoại, không phải vì accessibility.

### 44.7 Ưu tiên & gộp khi tải (nối §35.5)
| Lớp | Hàng đợi | Khi tải |
|---|---|---|
| `pointermove` | 1 (latest-wins) | drop cũ |
| `wheel` | 8 | gộp delta cùng dấu, drop nếu >8 |
| `btn down/up` | 64 | **backpressure**, không drop |
| `key down/up` | 64 | **backpressure**, không drop |
| `text` | 32 | backpressure (không gộp được) |
| `release_all` | **ưu tiên tuyệt đối** | xử lý **trước** mọi thứ đang chờ (nhảy hàng) |
> `release_all` nhảy hàng là chi tiết nhỏ nhưng quan trọng: nếu nó xếp sau 60 event move đang chờ, người dùng đã nhả chuột 100 ms trước mà máy vẫn đang drag.

### 44.8 An toàn input (nối §41.4 T2, cụ thể hoá)
| Kiểm tra | Ngưỡng | Khi vượt |
|---|---|---|
| Toạ độ | `u16` luôn; clamp `[0,65535]` | không thể vượt (kiểu dữ liệu) |
| Tốc độ `move` | >200/s | drop + `input_flood` stat |
| Tốc độ `ctrl` | >100/s | 429-style: drop + warning 1 lần |
| Độ dài `text` | >256 code unit / message | từ chối message |
| Chuỗi `keys_held` | >16 phím | release_all + reset (dấu hiệu bất thường) |
| Unicode không hợp lệ (surrogate lẻ) | — | bỏ, log, không crash |
| `vk` ngoài danh sách cho phép | — | bỏ (danh sách: 0x01–0xFF trừ các VK cấm: `VK_LWIN/RWIN` khi `block_win`, SAS 0x2E) |
| Phím cấm | `VK_LWIN`+`L` (§5.8.4), `Ctrl+Alt+Del` | chặn, toast |
> Mọi giới hạn này **phải có test** với dữ liệu hỏng (§41.10 #10–11).

### 44.9 Độ chính xác & cảm giác
| Vấn đề | Xử lý |
|---|---|
| Chuột gaming 1000 Hz | gộp trong rAF (§6.4.4) |
| Touch precision | kính lúp + trackpad (§30.8) |
| **Sub-pixel** | không thể (toạ độ 16-bit trên virtual desktop) — nhưng 1920 rộng = bước 0.03 px nên **không đáng lo** |
| **Tăng tốc chuột của client** | ở chế độ absolute, `clientX` đã tính gia tốc của HĐH client ⇒ vị trí tuyệt đối vẫn đúng; ở relative (pointer lock) **không** dùng được nếu client bật accel — cảnh báo (§6.4.5) |
| Cursor shape "lạ" (app tự vẽ) | bitmap + hotspot (§6.3.3) |
| Con trỏ ẩn bởi app | `cpos.vis=false` (§6.3.5) |

### 44.10 Metrics & test
Metrics: `input_events_in/out`, `input_rejected`, `input_flood`, `odd_keyup`, `surrogate_dropped`, `release_all_count`, `layer`, `keys_held_count`, `ime_composing`.

| # | Test | Ngưỡng |
|---|---|---|
| 1 | 20 kịch bản blur/mất mạng (§17.1 dòng 8) | 0 lần kẹt modifier/nút |
| 2 | Giữ Ctrl → mất mạng → kết nối lại | `keys_held = ∅` sau 3 s |
| 3 | Emoji (4 event) | đúng ký tự, không rác |
| 4 | Tiếng Việt Telex 200 từ | CER 0 (so với text mong đợi) |
| 5 | CJK (Microsoft Pinyin) 50 câu | đúng |
| 6 | Gửi surrogate lẻ / 1 MB text / vk cấm | bỏ an toàn, không crash |
| 7 | 500 event/s trong 10 s | drop `move`, giữ `ctrl`, 1 warning |
| 8 | `release_all` khi có 60 move đang chờ | xử lý **trước** (đo timestamp) |
| 9 | Layer switch giữa `intent`↔`raw` | 0 ký tự nhân đôi |
| 10 | App lọc injected input | không kết luận sai; ghi stats đúng |

| Nhánh | Lĩnh vực | Trạng thái |
|---|---|---|
| ~~#6 Mô hình dữ liệu & migration~~ | G | **đã cắt** — chỉ 2 file JSON + 1 log (§26.16), không còn DB |
| ~~#17 UIA over the wire~~ | — | **đã cắt** (§0.3.1 #3) |
| **#18 Chế độ "bàn phím thô"** (chọn layout, hiện IME của server) | C/D | còn — nhỏ, làm cùng P2 |

---

## 45. Build & cài đặt — bản cá nhân: **$0**, không cert, không CI 2 tầng (viết lại từ v3.14)

> v3.14 trả lời câu "có dùng được nguồn free/GitHub không" theo hướng **phát hành sản phẩm**: EV cert, ký driver, self-hosted runner, SBOM. §0.3 đã cắt hướng đó. Đây là bản đúng với phạm vi: **bạn build trên máy bạn, cài trên máy bạn**.

### 45.1 Licence — chỉ 5 dòng thật sự ảnh hưởng bạn
| Thành phần | Licence | Bạn cần làm gì |
|---|---|---|
| Rust + crate (`windows`, `tokio`, `axum`, `serde`, `rustls`) | MIT/Apache-2.0 | không gì cả |
| GStreamer core + `base/good/bad` | LGPL-2.1 | link **động** (DLL) — mặc định đã vậy |
| **`gst-plugins-ugly` (x264enc)** | **GPL-2.0** | **đừng cài plugin này** trên máy nếu bạn định đưa code cho ai. Tự dùng thì không sao về pháp lý, nhưng đừng để nó thành đường phát hành |
| **VDD** | MIT | dùng bản phát hành; nếu fork/sửa driver thì mới phải lo chữ ký |
| **VB-CABLE** | free cho **cá nhân** | đúng phạm vi của bạn ⇒ $0 |

> Không ship codec nào: encoder là **NVENC → QSV → AMF → Media Foundation** (§37, §39 — **miễn phí** vì chỉ gọi driver/OS). x264enc chỉ dùng như fallback trên máy dev, và **không** đưa vào bản bạn chia sẻ.
> `LICENSES.md` 5 dòng: ghi URL + licence của VDD, cable, GStreamer. Không phải nghĩa vụ pháp lý — để 6 tháng sau bạn còn biết máy mình đang chạy cái gì.

### 45.2 Ba thứ cần — và tại sao bây giờ là **$0**
| Cần | Cách $0 | Điều kiện |
|---|---|---|
| **Màn hình ảo (HVNC)** | VDD **bản phát hành đã được ký sẵn** — dự án được **SignPath Foundation ký miễn phí**, và có trên **winget** (`VirtualDrivers.Virtual-Display-Driver`) | Bạn **dùng** bản phát hành, không tự build driver ⇒ **không cần EV cert, không cần tắt Secure Boot** |
| **HTTPS** | cert tự ký (LAN) hoặc `tailscale cert` (free) | phải **cài trust cert** trên máy bạn dùng để điều khiển. Không có cách vừa $0 vừa không cài gì (trừ khi dùng Tailscale) |
| **Âm thanh** | **VB-CABLE** (đã ký, cài là chạy) — hoặc Virtual Audio Driver của cùng nhóm dự án | ⚠️ Virtual Audio Driver **còn beta, cần `bcdedit /set testsigning on`** ⇒ **phải tắt Secure Boot**. Nếu không muốn đụng vào bảo mật máy: **chọn VB-CABLE** |

> **Câu trả lời gọn:** không mất đồng nào, **với điều kiện bạn dùng driver có sẵn, không fork**. Toàn bộ "$200–500/năm" ở bản v3.14 là giá của việc **tự ký driver** — chỉ cần khi bạn sửa VDD hoặc phát hành cho người khác.

### 45.3 Build — không cần GitHub Actions
```powershell
# build-release.ps1  (chạy trên máy bạn, ~10 phút lần đầu, ~2 phút các lần sau)
cargo build --release            # + cargo test trước khi build
node ci/size-gate.mjs            # §43.12 — 1 dòng
# copy rd.exe ra %LOCALAPPDATA%\RD\ + tạo shortcut "At log on"
```

| Việc | Có cần GitHub không? |
|---|---|
| Lưu code | Repo **riêng tư** free là đủ (bạn không cần public) |
| Build | **Không.** Build trên máy bạn = đúng môi trường thật, không cần cache, không cần runner |
| Test capture/encode/audio | **Không.** Máy bạn có GPU và desktop thật — thứ mà GitHub-hosted runner **không có** (bản v3.14 §45.2). Đây là **lợi thế** của bản cá nhân |
| Phát hành | **Không phát hành.** Không MSI, không Releases, không auto-update |
> GitHub Actions chỉ có nghĩa khi có nhiều máy/người. Ở đây nó **chậm hơn** build local và test được ít hơn.

### 45.4 Bốn việc vẫn phải làm (không phải production, là để không tự làm khổ mình)
| # | Việc | Vì sao với 1 người vẫn bắt buộc |
|---|---|---|
| 1 | **`uninstall.ps1`** sạch: restore audio → restore cửa sổ → bỏ ẩn taskbar → xoá display ảo → xoá firewall rule + task + cert | bạn đổi máy / cài lại Windows. Không có nó, display ảo + cable ở lại và bạn sẽ không nhớ vì sao |
| 2 | **Defender exclusion** cho `%LOCALAPPDATA%\RD\` | 3 dấu hiệu (driver display ảo + ẩn taskbar + input injection) đủ để bị gắn cờ. Exclusion 1 lần, không phải "chống phát hiện" |
| 3 | **Ghim version** VDD + GStreamer (ghi vào `LICENSES.md`) | Windows update hoặc VDD mới có thể làm hỏng capture (§21.11). Biết đang dùng bản nào = sửa được trong 5 phút |
| 4 | **`config.json.bak` trước mỗi lần đổi schema** | 1 dòng code |

### 45.5 Tổng kết chi phí — bản cá nhân
| Khoản | Chi phí |
|---|---|
| VDD, VB-CABLE, GStreamer, Rust, trình duyệt | **0** |
| Cert (tự ký LAN / Tailscale) | **0** |
| CI / build | **0** (build local) |
| Lưu code | **0** (repo private) |
| **Tổng** | **$0/năm.** Chỉ cần: dùng driver **bản phát hành**, không fork, không phát hành cho người khác |

### 45.6 Nhánh mới rẽ ra (đã cắt bớt so với v3.14)
| Nhánh | Lĩnh vực | Trạng thái |
|---|---|---|
| ~~#19 Tài liệu pháp lý (EULA, SBOM, privacy)~~ | — | **đã cắt** (§0.3.1 #2) |
| ~~#3 Đóng gói MSI + wizard + ký số~~ | — | **đã cắt** (§0.3.1 #6) — chỉ còn `install.ps1`/`uninstall.ps1` |
| ~~#6 Mô hình dữ liệu & migration sâu~~ | G | **đã cắt**: chỉ còn 2 file JSON + 1 log (§26.16) ⇒ không có DB, không migration |
| #7 UI state thực thi (skeleton/optimistic/lỗi) | D | còn — nhưng **thu nhỏ** cho 1 người |
| #12 Đo TWCC/REMB trên GStreamer | A | **chặn P0** — vẫn là việc thật duy nhất phải làm trước |
| **#20 Chế độ chạy trên máy yếu / không GPU** (chỉ MF hoặc VNC-only) | A/F | mới, từ §45.2 |
| #21 **"Máy có ở đó không"** (ngủ/reboot/IP/khoá) | G/F | ✅ **xong — §46** |
| #22 WoL + máy trung gian | F | tuỳ chọn, §46.3 |
| #23 Auto-logon + BitLocker (đi xa nhiều ngày) | F/E | quyết định của bạn, §46.4 |

---

## 46. "Máy có ở đó không?" — ngủ, reboot, đổi IP, khoá màn hình (nhánh #21 — lĩnh vực G/F)

> Đây là **lỗ hổng lớn nhất còn lại**, và nó chỉ lộ ra khi dùng thật: mọi chương từ §6 đến §45 giả định **máy chủ đang chạy, đã đăng nhập, và trả lời được**. Trên thực tế, lần nào bạn mở điện thoại ra cũng có 3 khả năng: máy **ngủ**, máy **vừa reboot** (Windows Update), hoặc **IP đã đổi**.
> Spec cũ chỉ có §11.2 dòng "Sleep → `SetThreadExecutionState`" và §11.4 "Console khoá". Một dòng cho một vấn đề chiếm **phần lớn số lần "không kết nối được"** trong đời thật. Đây là lĩnh vực **G** (bền vững) — nông nhất còn lại.

### 46.1 Năm chuyện khác nhau, và tại sao gộp chúng là sai
"Không kết nối được" có **năm** nguyên nhân rất khác nhau, cần **năm hành động khác nhau**. Hiện một thông báo chung ⇒ bạn không biết phải làm gì, và mất 5 phút thử ngẫu nhiên mỗi lần.

| # | Thực tế | Triệu chứng ở client | Bạn phải làm gì |
|---|---|---|---|
| 1 | **Máy ngủ** | TCP connect **timeout** (không phải refused) sau 2–5 s | đánh thức máy (nếu có WoL) hoặc về nhà (§46.3) |
| 2 | **App không chạy** (máy bật nhưng chưa đăng nhập / app bị tắt) | TCP **refused** (`ECONNREFUSED`, <1 s) | đăng nhập tại máy / mở app (§46.4) |
| 3 | **IP đổi** | **DNS fail** hoặc timeout (không có gì ở IP đó) | dùng tên ổn định (§46.5) |
| 4 | **Máy khoá màn hình** | kết nối **thành công**, phiên `secure_desktop`, input bị chặn | mở khoá tại máy (§46.6) |
| 5 | **Tailscale/VPN chưa bật** | `ERR_NAME_NOT_RESOLVED` hoặc timeout ở 100.64/10 | bật VPN trên điện thoại |

> **Luật:** client **phân biệt được 5 trường hợp trên** và hiện **một câu + một nút** cho mỗi trường hợp. Đây là điều §32.7 ("liền mạch khi mất mạng") hứa nhưng chưa có cơ chế, vì lúc đó mới chỉ xét "mất mạng", không xét "máy không ở đó".
> **Phân biệt `refused` vs `timeout` là toàn bộ mẹo:** `refused` = có máy, không có app. `timeout` = không ai trả lời (ngủ/off/sai IP). Trình duyệt **không** cho JS biết loại lỗi này trực tiếp → xem §46.7.

### 46.2 Giữ máy thức **chỉ khi có phiên** (và chỉ cái cần giữ)
```c
// bật khi PREPARING, tắt khi CLOSED — 2 dòng, đúng chỗ
SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED
                        | (mode == VNC ? ES_DISPLAY_REQUIRED : 0));
// tắt: SetThreadExecutionState(ES_CONTINUOUS);
```

| Cần biết | Sự thật |
|---|---|
| `ES_SYSTEM_REQUIRED` chỉ chặn **idle sleep** | nó **không** chặn: gập nắp, nút nguồn, pin yếu, Windows Update reboot. Đừng tưởng nó là "giữ máy thức" đầy đủ |
| `ES_DISPLAY_REQUIRED` chỉ cần ở **VNC mode** | HVNC capture **display ảo** ⇒ màn hình thật tắt vẫn composite. Ở VNC cần màn hình thật sáng, nếu không DWM có thể dừng vẽ |
| Nhả **ngay** khi phiên đóng | nếu quên: laptop nằm trong balo vẫn chạy full load, nóng, pin cạn. Đây là bug "app làm hỏng máy tôi" |
| Đừng sửa power settings của máy | `powercfg lidaction=0` đổi hành vi máy của bạn vĩnh viễn và cần admin ⇒ **không làm**. Chỉ **cảnh báo** (§46.2.1) |

#### 46.2.1 Cảnh báo trước khi máy tự ngủ (thay vì sửa cài đặt)
`GetSystemPowerStatus` + `powercfg /requests` cho biết máy sắp ngủ vì lý do gì. Ba cảnh báo, hiện **1 lần mỗi phiên**, không lặp:

| Điều kiện | Banner trên client |
|---|---|
| Đang chạy **pin** và < 25% | "Máy đang dùng pin 23% — nếu hết pin, phiên sẽ mất." + [Đã hiểu] |
| Đang chạy **pin** và > 15 phút | "Đang dùng pin. Cắm sạc nếu bạn cần phiên lâu." (chỉ 1 lần/phiên) |
| Sắp tới **thời điểm ngủ** theo power plan (< 5 phút) | "Máy sẽ ngủ sau ~4 phút." + **[Giữ thức tới khi tôi đóng phiên]** — nút này chỉ **gia hạn `ES_SYSTEM_REQUIRED`**, không đổi cài đặt |
> Ngược lại cũng cần: công tắc **"cho máy ngủ dù đang có phiên"** trong `Nâng cao` — cho trường hợp bạn quên đóng phiên rồi đi ra ngoài.

### 46.3 Máy đã ngủ thì **không thể** đánh thức từ trình duyệt
Sự thật không có đường vòng: máy ngủ thì **card mạng vẫn nghe** một loại packet duy nhất — **magic packet Wake-on-LAN**, gửi bằng **UDP broadcast trong LAN**. Trình duyệt **không gửi được UDP** ⇒ **không có** nút "đánh thức" trên web. Đừng hứa.

| Cách | Có thật không | Giá | Ghi chú |
|---|---|---|---|
| **(1) Đừng để nó ngủ** (§46.2) | ✅ **hiệu quả nhất** | 0 | áp dụng được cho ~90% trường hợp. Đây là câu trả lời chính |
| **(2) WoL từ máy thứ 2 trong LAN** | ✅ có, nhưng cần thiết bị luôn bật | ~0 (nếu có sẵn Pi/router/điện thoại cũ) | NIC: "Wake on Magic Packet" + BIOS; **tắt Fast Startup** (xem dưới) |
| **(3) Router có WoL** | ⚠️ tuỳ router | 0 | nhiều router gia đình không có; kiểm tra trước khi tin |
| **(4) WoL qua Internet** | ⚠️ cần port-forward UDP 9 + biết MAC + máy trung gian | 0 | không làm được từ browser ⇒ cần app/script riêng |
| **(5) Để máy chạy 24/7** | ✅ | tiền điện | máy để bàn: ~10–40 W ⇒ ~$15–50/năm. Laptop: không nên |

**Bẫy thật: Fast Startup.** Windows 10/11 mặc định bật *Fast Startup* — "Shutdown" thực chất là **hibernate**. Ở trạng thái đó **WoL không đánh thức được** (chỉ đánh thức từ Sleep). Nếu bạn định dùng WoL: tắt Fast Startup (`powercfg /h off` hoặc trong Control Panel) **và** hiểu rằng máy sẽ boot chậm hơn ~10 s.
> **Kết luận cho 1–2 người:** dùng (1). Ghi (2) vào `/help` như một tuỳ chọn nếu bạn có Pi/điện thoại cũ ở nhà. **Không** xây tính năng WoL trong app.

### 46.4 Reboot (Windows Update) — cái bẫy "chạy khi không đăng nhập"
Kịch bản ác nhất và rất thường: máy reboot lúc 3 giờ sáng để cài update → không ai đăng nhập → **tray app không chạy** → sáng ra bạn ở xa, không có gì để kết nối.

Ba "giải pháp" mọi người nghĩ tới, và tại sao hai cái đầu **sai**:

| Cách | Kết quả | Kết luận |
|---|---|---|
| Task Scheduler **"Run whether user is logged on or not"** | chạy ở **Session 0** ⇒ **không capture, không `SendInput` được** (§2.3) | ❌ **vô dụng** — đây là bẫy phổ biến nhất; app *chạy* nhưng không làm được gì |
| **Auto-logon** (`AutoAdminLogon`) | app chạy được | ⚠️ **đánh đổi thật**: mật khẩu lưu ở LSA secret, **đọc được bằng mimikatz**; máy ở nhà, có BitLocker thì rủi ro chấp nhận được — nhưng đây là quyết định **của bạn**, không phải mặc định của app |
| Chấp nhận + báo rõ | app không chạy, nhưng bạn **biết vì sao** | ✅ **mặc định của spec này** |

**Làm gì (mặc định):**
1. **Giảm số lần reboot**: đặt *Active hours* rộng, tắt "Restart as soon as possible" ⇒ update dồn vào lúc bạn ở nhà. (Windows Settings → 1 lần)
2. **Tray app ghi "lần chạy cuối"** vào `state.json`; client hiện chính xác: *"Máy đã khởi động lại lúc 03:12 và chưa đăng nhập. Cần đăng nhập tại máy."* — khác hoàn toàn với "không kết nối được".
3. **`/help` có mục "Tôi đi xa nhiều ngày"**: nói thẳng 3 lựa chọn (để máy bật + tắt auto-restart / auto-logon + BitLocker / nhờ người nhà đăng nhập). Không giấu.
4. Nếu bạn chọn auto-logon: app **không** tự bật nó (không sửa registry `Winlogon`), chỉ đưa **lệnh mẫu** trong `/help` để bạn tự chạy và tự chịu.

### 46.5 Đổi IP — client tìm máy bằng gì
| Môi trường | Cách ổn định | Ghi chú |
|---|---|---|
| **LAN** | **DHCP reservation** trong router (gán IP theo MAC) | 2 phút, 1 lần. Đây là cách duy nhất **miễn phí và chắc chắn** |
| LAN, không muốn vào router | đặt **static IP** trên máy | dễ xung đột nếu router cấp trùng dải — chọn ngoài pool DHCP |
| LAN, muốn tên | `https://rd.local` (mDNS) | ⚠️ Windows **không có** mDNS responder mặc định cho việc advertise; LLMNR chỉ giúp trong LAN và thường bị chặn ⇒ **đừng dựa vào** |
| **Ngoài LAN** | **Tailscale MagicDNS**: `https://desktop.tailnet.ts.net` | ✅ tên **không đổi** dù IP đổi, cert hợp lệ thật (`tailscale cert`) ⇒ **khuyến nghị làm đường chính** cho 1–2 người |
| Sau khi đổi | cert tự ký phải có **SAN gồm mọi IP private + hostname + Tailscale IP** | §26.6 đã ghi; nhưng nếu IP đổi **thường xuyên** ⇒ cert thành gánh nặng ⇒ **dùng Tailscale cert** thay vì tự ký |

**Quyết định:** với 1–2 người, **Tailscale là đường chính, LAN là đường phụ**. Lý do không phải "thích VPN": nó giải **3 vấn đề cùng lúc** — tên ổn định (§46.5), cert hợp lệ (§26.6), và NAT (§13.4). Nếu chỉ dùng LAN thì **bắt buộc** có DHCP reservation, nếu không bookmark của bạn sẽ chết sau mỗi lần router restart.

### 46.6 Khoá màn hình sau khi resume / hết screensaver
Với laptop ngủ–thức nhiều lần mỗi ngày, `secure_desktop` (§11.4) sẽ xuất hiện **liên tục** — và đó là trải nghiệm tệ nhất của cả hệ thống: bạn kết nối được, thấy hình, nhưng mọi cú bấm bị bỏ.

| Việc | Cách | Ghi chú |
|---|---|---|
| **Nói trước** | khi phiên sắp gặp `secure_desktop`: overlay + *"Máy đang khoá. Bấm phím bất kỳ **trên máy thật** để mở khoá."* | input **không** gửi (an toàn), và **không** cố gửi |
| **Giảm tần suất** | hướng dẫn `/help`: tắt "Require sign-in on wakeup" (`powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0`) | ⚠️ cần admin; **app không tự làm** — đổi bảo mật máy của bạn là việc của bạn |
| **Phát hiện sớm** | `WTSQuerySessionInformation(WTSConnectState)` = `WTSDisconnected` ngay sau resume ⇒ biết khoá **trước khi** bạn bấm gì | không dựa vào "input không có tác dụng" |
| **Đừng** gửi input mù | kể cả `SendInput` có thể đánh thức màn hình khoá — **không làm**: gõ mật khẩu qua stream vào màn hình khoá là đường rò rỉ | §44.8 đã cấm |

### 46.7 Cơ chế: làm sao biết là lỗi gì (browser không nói)
Trình duyệt **không** cho JS phân biệt `refused` vs `timeout`. Bốn mẹo thật, xếp theo độ tin cậy:

| # | Cách | Độ tin cậy | Ghi chú |
|---|---|---|---|
| 1 | **`fetch` + đo thời gian + `AbortController`** (`timeout=2500 ms`) | trung bình | fail **<300 ms** ⇒ gần như chắc `refused` (app không chạy, máy vẫn bật) · fail **đúng 2500 ms** ⇒ timeout (ngủ/off/sai IP) |
| 2 | **`GET /api/health` qua 2 hostname khác nhau** (IP LAN + Tailscale) | cao | cái nào trả lời ⇒ biết đang ở mạng nào, và phân biệt "máy bật nhưng app tắt" (refused) với "không tới được máy" |
| 3 | **Service worker / `navigator.onLine`** | thấp | chỉ biết client có mạng, không nói gì về máy chủ |
| 4 | **Server "last seen"** (nếu có máy thứ 2 hoặc Tailscale admin API) | cao nhưng phức tạp | **không làm** cho 1–2 người |
> Không có cách nào đạt 100% từ browser. Vì vậy: đoán **2 nhánh** (<300 ms vs timeout) là đủ, và **luôn** kèm nút "Thử lại" + 1 dòng giải thích có thể sai ("có thể máy đang ngủ"). Thà nói "có thể" còn hơn nói sai chắc chắn.

### 46.8 API & trạng thái (nhỏ, cụ thể)
```
GET /api/machine        →  { awake, logged_in, locked, uptime_s, booted_at,
                             last_seen, power:{ac,battery_pct,idle_sleep_in_s},
                             app_version, ipv4:[…], tailscale:bool }
GET /api/health         →  (đã có) version, vdd, audio, encoders, os
```
- `last_seen` được ghi **mỗi 60 s** vào `state.json` khi app chạy (một dòng) ⇒ sau reboot, client biết **máy đã từng chạy tới lúc nào**. Không có nó, bạn không phân biệt được "chưa bao giờ cài" với "vừa reboot".
- Máy ngủ ⇒ **không** endpoint nào trả lời ⇒ client dùng §46.7 để đoán. Không có "trạng thái máy" thật khi máy không ở đó — **đừng vẽ ra**.
- `GET /api/machine` chỉ trả lời khi **đã đăng nhập** (nó ở sau auth) ⇒ không rò thông tin máy cho người lạ.

### 46.9 Bảng: 5 lỗi → 5 thông báo → 5 hành động (bắt buộc trong UI)
| Lỗi | Câu (≤12 từ) | Nút |
|---|---|---|
| timeout / không phản hồi | "Máy không phản hồi. Có thể đang ngủ hoặc mất mạng." | [Thử lại] · [Xem cách đánh thức] |
| `refused` nhanh | "Máy đang bật nhưng ứng dụng chưa chạy." | [Thử lại] · [Cách bật lại app] |
| DNS không phân giải | "Không tìm thấy máy theo tên này. VPN đã bật chưa?" | [Kiểm tra VPN] |
| kết nối được nhưng `locked` | "Máy đang khoá. Cần mở khoá trên máy thật." | [Đã hiểu] (input tắt) |
| app chạy, máy vừa reboot (`booted_at` mới) | "Máy vừa khởi động lại lúc 03:12." | [Thử lại] · [Xem log] |
> Câu chữ theo §20.19: không thuật ngữ, có chủ thể, mỗi lỗi **một** hành động chính.

### 46.10 Kiểm chứng (5 test, làm được trên 1 máy)
| # | Test | Ngưỡng |
|---|---|---|
| 1 | Gập nắp / `powercfg /sleep` giữa phiên | phiên chuyển `reconnecting` **không** treo UI; thức dậy ⇒ resume hoặc `CLOSED` + nói rõ lý do, **không** đứng im |
| 2 | Tắt app rồi mở browser | phát hiện `refused` <300 ms ⇒ câu "ứng dụng chưa chạy", **không** phải "máy đang ngủ" |
| 3 | Rút mạng máy chủ (không tắt máy) | timeout ⇒ câu "không phản hồi"; phân biệt được với test 2 |
| 4 | Đổi IP máy chủ (đổi DHCP lease) | Tailscale vẫn kết nối; LAN fail với câu DNS/IP rõ ràng |
| 5 | `Win+L` giữa phiên | thấy `secure_desktop` **trước** khi bấm; input không gửi; mở khoá tại máy ⇒ tự phục hồi ≤2 s |
| 6 | Đóng phiên ⇒ kiểm `powercfg /requests` | **rỗng** (đã nhả `ES_SYSTEM_REQUIRED`) — nếu không, app làm nóng pin vô ích |

### 46.11 Nhánh mới rẽ ra
| Nhánh | Lĩnh vực | Trạng thái |
|---|---|---|
| **#22 WoL + máy trung gian** (Pi/điện thoại cũ ở nhà) | F | **tuỳ chọn**, đọc §46.3 trước. Không làm trong P1 |
| **#23 Auto-logon + BitLocker** (đi xa nhiều ngày) | F/E | **quyết định của bạn**, không phải mặc định. `/help` có lệnh mẫu |
| **#24 Máy chủ là laptop pin yếu / nhiệt** | A | chỉ ảnh hưởng preset; ghi nhận |

---

## 47. Khởi động cùng Windows, vòng đời process, trải nghiệm theo thời gian (nhánh #25 — lĩnh vực D/F)

> §46 nói *máy ngủ thì sao*. Chương này nói thứ xảy ra **trước** đó và **thường xuyên hơn nhiều**: bạn bật máy lên, và công cụ này phải **tự có mặt** — không cần bấm gì, không hỏi han, không làm máy chậm. §13.6 chỉ có 1 dòng *"tạo shortcut At log on"*, và thế **không đủ** để chạy đúng.
> Đây cũng là chỗ trải nghiệm người dùng bị đánh giá trong **10 giây đầu** — trước khi có bất kỳ tính năng nào.

### 47.1 Ba yêu cầu, và một câu để nhớ
| Yêu cầu | Nghĩa là |
|---|---|
| **Sống sót** | reboot, mất điện, Windows Update, bị kill từ Task Manager ⇒ lần sau vẫn có mặt, và **không mất cửa sổ** của bạn |
| **Không làm phiền** | không cửa sổ bật lên, không UAC mỗi lần login, không tranh CPU với app khởi động khác, không chạy 2 bản |
| **Hỏng thì nói rõ** | thiếu driver / cổng bị chiếm / config hỏng ⇒ **một câu + một nút**, không im lặng và không crash |

> Câu để nhớ: **"Cài 1 lần, từ đó không phải nghĩ tới nó nữa."** Mỗi lần bạn phải *nghĩ* tới nó (bấm mở, kiểm tra nó có chạy không, nhớ port) là một lỗi thiết kế.

### 47.2 Bốn cách tự chạy trên Windows — chỉ **một** cách đúng
| Cách | Chạy ở session nào | Capture/`SendInput` được? | Kết luận |
|---|---|---|---|
| **Task Scheduler "At log on"** (dưới user hiện tại) | user session | ✅ | ✅ **chọn** — có delay, retry, điều kiện pin, không cần admin |
| `HKCU\...\Run` | user session | ✅ | ⚠️ chạy được nhưng **không delay, không retry**; hay chạy quá sớm (§47.2.1) |
| Startup folder shortcut | user session | ✅ | ⚠️ tương đương `Run`, và bạn **dễ xoá nhầm** khi dọn startup |
| Task Scheduler **"Run whether user is logged on or not"** | **Session 0** | ❌ | ❌ **bẫy** — app chạy nhưng **không capture được** (§2.3, §46.4) |
| Service (SYSTEM) | Session 0 | ❌ | ❌ §2.3 |

**Cấu hình chính xác** (phần dễ sai nhất; `install.ps1` sinh đúng file này cho **user hiện tại, không cần admin**):
```powershell
$A = New-ScheduledTaskAction -Execute "$env:LOCALAPPDATA\RD\rd.exe" -Argument "--startup"
$T = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$T.Delay = 'PT20S'                                   # 20 giây — xem 47.2.1
$S = New-ScheduledTaskSettingsSet `
      -AllowStartIfOnBatteries `                     # ★ mặc định FALSE => app KHÔNG chạy khi dùng pin
      -DontStopIfGoingOnBatteries `                  # ★ mặc định TRUE  => app TẮT khi rút sạc
      -ExecutionTimeLimit 0 `                        # không giới hạn (mặc định 3 ngày)
      -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
      -MultipleInstances IgnoreNew                   # không 2 bản khi login nhanh 2 lần
Register-ScheduledTask -TaskName 'RD Agent' -Action $A -Trigger $T -Settings $S -Force
```
> **Hai dấu ★ là bẫy thật, không phải chi tiết vụn:** mặc định Task Scheduler là **không chạy trên pin** và **dừng khi rút sạc**. Bạn dùng laptop, rút sạc để đi họp ⇒ **app tắt** ⇒ tới cơ quan không kết nối được, và **không có thông báo nào**. Đúng loại lỗi "không biết vì sao" mà §46 cố loại bỏ.

#### 47.2.1 Vì sao delay 20 giây (không phải 0, không phải 2 phút)
| Nếu chạy quá sớm | Hậu quả |
|---|---|
| Ngay khi login | GPU driver/DWM chưa sẵn sàng ⇒ tạo display ảo **fail**; danh sách audio device còn trống ⇒ `audio_unavailable` giả |
| Trong 20 s đầu | tranh CPU/disk với 20–60 app khởi động khác ⇒ **máy khởi động chậm rõ rệt**, và bạn sẽ đổ lỗi cho app này |
| Delay 20 s | driver sẵn sàng, máy đã ổn định, app lên trong ~1 s và bạn **không thấy gì** |
| Delay > 60 s | bạn mở browser trước khi app sẵn sàng ⇒ *"không kết nối được"* dù chỉ cần chờ |

> Nếu app khởi động mà **driver vẫn chưa sẵn sàng** (máy rất chậm): đừng bỏ cuộc — **retry 3 lần, cách 10 s** riêng cho bước khởi tạo driver/audio, và **vẫn mở web server ngay** (để `/diagnostics` trả lời được). Đó là khác biệt giữa "app chết" và "app đang chờ driver".

### 47.3 Vòng đời process: một bản, và "đang chạy rồi" không phải lỗi
| Tình huống | Hành vi |
|---|---|
| Bấm icon khi app **đã chạy** | **không** mở bản thứ 2. Mang dashboard của bản đang chạy ra trước (`WM_COPYDATA` tới window ẩn, hoặc mở `https://localhost/`) |
| Copy `rd.exe` sang thư mục khác rồi chạy | mutex `Local\RD.Agent` ⇒ bản 2 hiện hộp: *"Đã có bản khác đang chạy (PID 1234, từ 3 giờ trước)."* **[Dùng bản đó]** · **[Khôi phục cửa sổ & thoát bản cũ]** |
| `Local\` hay `Global\` mutex? | **`Local\`** — 2 người (§0.3) có thể fast-switch giữa 2 user session, mỗi session cần 1 bản riêng |
| Thoát khi đang có phiên | hỏi 1 lần: *"Đang có 1 phiên. Thoát sẽ ngắt phiên và trả cửa sổ về màn hình thật."* **[Ngắt & thoát]** · **[Ở lại]** |
| Thoát bình thường | chạy **đúng thứ tự** §13.7 (audio → cửa sổ → display → task) rồi mới exit. **Không** exit trước rồi dọn sau |
| Bị kill từ Task Manager | không dọn được ⇒ `state.json` là lưới an toàn (§47.4) |
| 3 lần crash trong 5 phút | **không** restart vô hạn (Task Scheduler đã giới hạn 3) + tự ghi `crash_loop` ⇒ lần sau chỉ mở web + tray đỏ, **không** tự tạo display ảo tới khi bạn bấm "Thử lại" |
| Uninstall khi đang có phiên | **chặn**: *"Đóng phiên trước khi gỡ."* (không ngoại lệ — gỡ giữa phiên là cách chắc nhất để mắc cửa sổ) |

> **Không bao giờ** tự kill bản cũ để nhường chỗ bản mới. Bản cũ có thể đang giữ display ảo + cửa sổ của bạn; kill nó = cửa sổ mồ côi (§9.2.3).

### 47.4 Khôi phục lúc khởi động — `state.json` có **4 trạng thái**, không phải 2
§9.2.4 chỉ nói "nếu file còn → restore". Thực tế file có thể ở 4 trạng thái, và **2 trong 4 không được restore gì**:

| Trạng thái file | Nguyên nhân thường gặp | Hành vi đúng |
|---|---|---|
| **(a) không có** | lần đầu, hoặc lần trước thoát sạch | không làm gì. Khởi động bình thường |
| **(b) hợp lệ + app crash giữa phiên** | kill, panic, cúp điện | **restore đầy đủ** theo thứ tự dưới + toast 1 lần |
| **(c) hợp lệ nhưng cửa sổ/app đã đóng** | **reboot** (phổ biến nhất) | **không restore gì**, chỉ xoá entry. **Im lặng** — app tự đóng thì không có gì để cứu |
| **(d) file hỏng** (ghi dở) | mất điện đúng lúc ghi | đổi tên `state.json.corrupt-<ts>`, **giữ lại** để xem, khởi động sạch, 1 dòng trong `/diagnostics` |

**Thứ tự restore là cứng** (sai ⇒ cửa sổ bay ra ngoài màn hình):
```
① default audio device  ->  ② từng cửa sổ (SetWindowPos về origRect, bỏ maximized giả)
-> ③ tắt per-app routing  ->  ④ xoá display ảo nếu rỗng  ->  ⑤ xoá state.json
```
- ① trước: nếu restore cửa sổ trước, app có thể phát ra loa thật trong 1–2 s ⇒ đúng lúc "đang ẩn" lại có tiếng.
- ④ sau cùng: xoá display khi cửa sổ **còn** trên đó ⇒ Windows dồn cửa sổ về màn hình chính ở toạ độ **có thể ngoài màn hình** (§12.3) ⇒ mất cửa sổ.

**Nhận diện "cửa sổ còn không" — `hwnd` một mình là không đủ:** Windows **tái sử dụng** `HWND`. Nếu state ghi `0x0012` của Chrome mà sau reboot `0x0012` là cửa sổ app khác ⇒ ta sẽ move **sai cửa sổ**. Phải khớp **bộ 4**: `hwnd` + `pid` (+ process start time) + `class` + `title hash`. Không khớp đủ ⇒ coi như (c) và bỏ qua.

**`state.json` tối thiểu phải chứa** (bổ sung §9.2.4):
```jsonc
{ "schema":1, "appVersion":"...", "savedAt":<epoch>,
  "windows":[{ "hwnd":"0x...", "pid":1234, "procStart":"2026-11-07T09:12:03Z",
               "class":"Chrome_WidgetWin_1", "titleHash":"a1b2",   // chỉ hash, không lưu tiêu đề
               "origRect":{...}, "wasMax":false, "displayId":"{...}" }],
  "audio":{ "defaultBefore":"{guid}", "perApp":[...] },
  "display":{ "id":"{...}", "createdByUs":true },
  "lastSeen":<epoch> }
```
- `lastSeen` ghi **mỗi 60 s** (§46.8) ⇒ sau reboot, client nói được *"máy từng chạy tới 03:12"*.
- Ghi **nguyên tử** (`.tmp` → `fsync` → `rename`) — cùng luật với `config.json` (§26.1).
- Không lưu **tiêu đề** cửa sổ, chỉ hash: file nằm trên đĩa và không cần biết bạn đang mở gì.

### 47.5 First run — 5 trạng thái trước khi có phiên đầu tiên
Người dùng mới không đọc hướng dẫn. Thứ tự trạng thái phải **không thể đi sai**:

| # | Trạng thái | Điều kiện phát hiện | UI |
|---|---|---|---|
| 1 | **Chưa cấu hình** | `config.json` không có user | mọi route redirect về `/setup` (4 bước §24.10). **Không** có dashboard trước khi xong |
| 2 | **Xong setup, thiếu driver** | `vdd:false` | dashboard mở được + banner vàng: *"Chưa có màn hình ảo — chỉ dùng được chế độ xem toàn màn hình (VNC)."* **[Cài ngay]** (mở `winget`) · **[Dùng tiếp không có màn hình ảo]** |
| 3 | **Đủ, chưa từng dùng** | `prefs.firstRunDone=false` | **coach mark 3 bước**, chỉ 1 lần: ① chọn cửa sổ ② điều khiển ③ đóng tab là cửa sổ tự trở về. Có **[Bỏ qua]** |
| 4 | **Đang dùng** | bình thường | không coach mark, không banner |
| 5 | **Lần đầu trên điện thoại** | UA mobile + `devicePrefs` trống | gợi ý 1 lần: *"Xoay ngang để xem rộng hơn"* — không tự xoay, không chặn |

**Khoảnh khắc quyết định của cả sản phẩm:** bước 4 của `/setup` (§24.10) có **QR code**, và bạn quét bằng **điện thoại thật** ngay tại chỗ. Nếu bước này fail (cert, LAN, firewall), bạn phát hiện **trong 30 phút cài đặt** — không phải 3 tuần sau, ở nơi không có ai giúp. Vì vậy `/setup` **không được** cho "hoàn tất" khi chưa có ít nhất 1 lần tải trang thành công từ thiết bị khác.

### 47.6 Cập nhật binary khi app đang chạy (edge case gặp ngay lần thứ 2)
`cargo build` sẽ **fail** vì `rd.exe` đang bị khoá. Ba cách, chọn cách 3:

| Cách | Vấn đề |
|---|---|
| Kill app rồi build | cửa sổ có thể đang ở display ảo ⇒ **mất cửa sổ** nếu kill cứng |
| Build ra chỗ khác rồi copy đè | vẫn fail (file đang chạy) |
| ✅ **`install.ps1 -Restart`** | ① gọi `rd.exe --shutdown-clean` (**restore đủ thứ tự §13.7** rồi mới exit) ② copy file mới ③ start lại. Nếu ① fail (app treo) ⇒ **không** copy, báo rõ: *"App không tắt được. Dùng tray → Thoát trước rồi chạy lại script."* |

> Đừng làm auto-updater (§0.3.1 #6). Chỉ cần script này — và nó phải **tôn trọng** nguyên tắc: không bao giờ thay binary khi chưa dọn sạch cửa sổ.

### 47.7 Trải nghiệm theo thời gian — cái gì hỏng ở tuần 1, tháng 1, tháng 6
Công cụ loại này không hỏng lúc cài. Nó hỏng **dần**, và mỗi lần hỏng đều có dạng "trước đây vẫn được mà".

| Thời điểm | Triệu chứng | Nguyên nhân thật | Chặn bằng |
|---|---|---|---|
| **10 giây đầu** (login) | app không chạy; bạn tưởng chưa cài | Task Scheduler mặc định **không chạy trên pin** | 2 cờ ★ ở §47.2 |
| **lần dùng đầu** | "không kết nối được" trên điện thoại | cert chưa cài trust / firewall | bước QR bắt buộc (§47.5) |
| **tuần 1** | quên mật khẩu (chỉ gõ 1 lần/tháng) | 1 mật khẩu, không có email reset | gợi ý lưu vào password manager ngay ở `/setup`; `rd.exe reset-admin` (§21.5) |
| **tuần 2** | cảnh báo cert đỏ trên điện thoại | cert tự ký hết hạn **hoặc IP đổi ⇒ SAN sai** | nhắc 30/14/7 ngày (§26.6); **chuyển sang Tailscale cert** nếu IP hay đổi (§46.5) |
| **tháng 1** | video không lên, app vẫn chạy | Windows Update đổi build ⇒ VDD lỗi | `doctor` phát hiện + tự về **VNC-only**, không crash (§21.9) |
| **tháng 1** | máy tự khởi động lại lúc đêm | Windows Update | §46.4: giảm reboot + `last_seen` để nói rõ lý do |
| **tháng 2** | Defender cách ly file | bộ dấu hiệu RAT (VDD + ẩn taskbar + inject) | exclusion 1 lần (§21.11); ghi trong `/help` |
| **tháng 3** | "cái này chiếm port gì nhỉ?" | không ai nhớ | tray → **Thông tin cài đặt**: 1 trang (port, cert hết hạn, driver version, task name, thư mục) |
| **tháng 6** | quên hẳn cách gỡ | — | `uninstall.ps1` trong cùng thư mục + 1 dòng trong tray |
| **đổi máy / cài lại Windows** | phải làm lại 30 phút | không có gì mang theo | `Xuất cấu hình` (§20.13) + `install.ps1` + `LICENSES.md` ghi 3 driver cần cài |

### 47.8 Mười bốn edge case khởi động (tất cả test được trên 1 máy)
| # | Case | Kỳ vọng |
|---|---|---|
| 1 | Login lần đầu trên máy chậm (nhiều app startup) | app trễ 20 s rồi lên; driver chưa sẵn ⇒ retry 3×10 s; web server **mở ngay** |
| 2 | Logoff → login lại trong 15 s | **không** 2 bản (`MultipleInstances=IgnoreNew`) |
| 3 | Reboot khi đang có phiên | state còn ⇒ restore đủ; nếu app đã đóng thì **im lặng**, không báo lỗi |
| 4 | Mất điện đúng lúc move window | entry ghi **trước** khi move ⇒ lần sau rescue (§9.2.3) |
| 5 | Kill app từ Task Manager | lần sau restore + toast "Đã trả 2 cửa sổ về màn hình chính" |
| 6 | Crash 3 lần trong 5 phút | không restart vô hạn; tray đỏ + `crash_loop`; chỉ mở web, không tạo display |
| 7 | Rút sạc khi đang chạy | **vẫn chạy** (cờ ★) — test bằng cách rút sạc + `Get-ScheduledTaskInfo` |
| 8 | Khởi động khi không có mạng | vẫn chạy; dashboard nói "chưa có IP/Tailscale" thay vì treo |
| 9 | Port 443 bị chiếm (IIS, Skype) | thử 8443; fail ⇒ tray đỏ + câu rõ + log; **không** im lặng |
| 10 | Thiếu VDD | VNC-only, không crash, banner có nút cài |
| 11 | `config.json` hỏng | dùng mặc định + giữ `.corrupt` + banner 1 dòng |
| 12 | `state.json` hỏng | như trên, **không** restore nửa vời |
| 13 | Chạy bản thứ 2 từ thư mục khác | mutex ⇒ hộp "đã có bản khác" + 2 nút (§47.3); **không** đụng display |
| 14 | Thoát / uninstall khi đang có phiên | thoát: hỏi rồi restore; uninstall: **chặn** |

### 47.9 Kiểm chứng (7 test, ~10 phút)
| # | Test | Ngưỡng |
|---|---|---|
| 1 | Cài → reboot → login, **không bấm gì** | sau ≤30 s: `https://<host>/` trả lời; không cửa sổ nào bật lên; không UAC |
| 2 | Rút sạc, reboot | app vẫn chạy (bẫy ★) |
| 3 | Đang có phiên → `taskkill /f` | mở app lại ⇒ cửa sổ đã được trả về + toast đúng số cửa sổ |
| 4 | Đang có phiên → tắt máy bằng nút nguồn | lần sau không mất cửa sổ, không màn hình đen |
| 5 | `state.json` sửa thành chuỗi rác | app khởi động sạch, `.corrupt` được giữ, không crash |
| 6 | Chạy 2 bản | bản 2 thoát trong ≤2 s, không tạo display thứ 2 |
| 7 | `install.ps1 -Restart` khi đang có phiên | restore xong mới thay file; nếu app treo ⇒ **không** thay, báo rõ |

### 47.10 Nhánh mới rẽ ra
| Nhánh | Lĩnh vực | Trạng thái |
|---|---|---|
| ~~#26 "App thật" (shortcut, jump list, tray thay console)~~ | D | đã đủ ở §24.9 |
| **#27 Đa máy** (1 dashboard nhiều máy) | F | chỉ khi bạn có máy thứ hai — §21.14 |
| **#28 Chẩn đoán tự sửa** (`rd.exe doctor --fix`: firewall/port/driver) | F | đã có §21.9, giữ mức hiện tại |

---

## 48. Tuỳ chỉnh: 3 tầng, 4 phạm vi, và luật chống phình (nhánh #29 — lĩnh vực D)

> §20 nói *"tuỳ chỉnh phải dễ"*, §24.6 vừa rút xuống **12 mục**. Nhưng "12 mục" chỉ là con số — chưa có **mô hình** trả lời 4 câu mà mọi app loại này đều trả lời sai:
> ① Mục này thuộc về **máy nào** (server hay thiết bị đang cầm)? ② Khi 2 nơi mâu thuẫn, **ai thắng**? ③ Mục này **áp dụng ngay** hay cần phiên mới? ④ Ai quyết định một mục **được phép tồn tại** trong UI?
> Không có 4 câu trả lời này thì cài đặt sẽ phình lại 60 mục sau 3 tháng — đúng thứ §0.3 vừa cắt.

### 48.1 Ba tầng — số mục **cứng**, không phải "khoảng"
| Tầng | Số mục | Ai dùng | Mở thế nào | Nguyên tắc vào tầng |
|---|---|---|---|---|
| **T1 · Thường** | **12**, không hơn | bạn, 100% thời gian | `/settings` (1 trang) | đổi ≥ 1 lần/tháng, hiểu được **không cần đọc** |
| **T2 · Nâng cao** | **≤ 20** | khi có vấn đề cụ thể | `⚙ → Nâng cao` (1 lần bấm, không cần "tôi hiểu") | đổi 1–2 lần/**năm**, hoặc khi hỏng cần thử |
| **T3 · File** | không giới hạn | khi bạn sửa `config.json` | text editor | chỉ *có* để cứu hộ/debug; **không** có UI |
| **Không tồn tại** | — | — | — | xem §48.5 |

> **Luật cứng:** thêm 1 mục vào T1 ⇒ **phải bỏ 1 mục khác** khỏi T1 (hoặc chứng minh mục mới thay thế 2 mục cũ). Cùng luật §25 component: ngân sách, không phải ước lượng.

**T1 — 12 mục, chốt danh sách** (thay bảng §24.6; nay có cả **phạm vi** và **hiệu lực**):

| # | Mục | Giá trị | Phạm vi | Hiệu lực |
|---|---|---|---|---|
| 1 | Chất lượng | Tự động · Nét · Mượt | thiết bị | **ngay** |
| 2 | Hiển thị | Dùng thật · Vừa mắt · Chữ to · Nét | thiết bị | **ngay** |
| 3 | Tỉ lệ khung | Vừa · Đầy · 100% | thiết bị | **ngay** |
| 4 | Cách chạm (mobile) | 2 ngón cuộn · Chuột ảo | thiết bị | **ngay** |
| 5 | Con trỏ | Tự động · Cục bộ · Theo video | server | **ngay** |
| 6 | Bàn phím | Theo ý định · Thô (dùng IME của máy kia) | server | phiên sau |
| 7 | Tiếng | Hỏi mỗi phiên · Bật · Tắt | server | **ngay** |
| 8 | Âm lượng nghe | 0–100% | thiết bị | **ngay** |
| 9 | Ẩn khỏi màn hình thật | Bật · Tắt (= HVNC / VNC) | server | phiên sau |
| 10 | Ẩn cả taskbar | Bật · Tắt | server | **ngay** |
| 11 | Ngôn ngữ | Tiếng Việt · English | thiết bị | **ngay** |
| 12 | Theme | Sáng · Tối · Hệ thống | thiết bị | **ngay** |

> "Hiệu lực" là thông tin **bắt buộc hiện trong UI** cạnh mục đó (một chữ nhỏ "áp dụng từ phiên sau"). Không có nhãn này ⇒ bạn sẽ bấm, không thấy gì đổi, và cho rằng app hỏng.

**T2 — 20 mục, gom theo lý do bạn mở chúng** (không gom theo kỹ thuật):

| Nhóm | Mục | Khi nào mở |
|---|---|---|
| Muốn nét hơn / mượt hơn | bitrate trần · fps trần · keyframe · scaler · sharpening | mạng khác thường |
| Muốn ít trễ hơn | jitter buffer · cursor echo · tắt ripple | WAN, cảm giác trễ |
| Màn hình & toạ độ | resolution · DPI scale · monitor ưu tiên | đổi màn hình |
| Bàn phím | layout server · rate limit · chặn `Win+L` | gõ sai, dùng app lạ |
| Bàn giao | port · cert · STUN/TURN · Tailscale | khi không kết nối được |
| Chẩn đoán | barcode · HUD độ trễ · log level | đang tìm lỗi |
| GPU mã hoá | Tự động · **Intel QSV** · **NVIDIA** | laptop hybrid: **QSV mặc định** — cùng adapter với capture, mát hơn 10–20 W (§53.2) |

> Cách gom này quan trọng: người dùng mở cài đặt với **một triệu chứng** trong đầu ("trễ", "mờ"), không phải với một cái tên tham số. Nếu bạn phải biết "jitter buffer" là gì mới tìm được nó, đó là UI hỏng.

### 48.2 Bốn phạm vi — và ai thắng ai (bảng phải thuộc)
| Phạm vi | Lưu ở | Sống bao lâu | Ví dụ |
|---|---|---|---|
| **app** (mặc định cho mọi thứ) | hằng số trong code | mãi | preset "Tự động" |
| **server** | `config.json` (§26.1) | mãi, đi theo máy | con trỏ, ẩn taskbar, port |
| **user** | trong `config.json`, theo user | mãi, theo người | ngôn ngữ, theme |
| **device** | `localStorage` của trình duyệt | tới khi xoá dữ liệu trang | chất lượng, âm lượng, tỉ lệ khung |

**Thứ tự thắng:** `device > user > server > app`.
- Lý do `device` thắng: bạn cầm điện thoại 4G thì muốn "Mượt"; ngồi laptop cắm LAN thì muốn "Nét". Nếu server thắng, mỗi lần đổi thiết bị bạn phải vào sửa — đúng thứ §20.1 cấm.
- **Ngoại lệ có lý do:** mục thuộc **server** (con trỏ, ẩn taskbar, bàn phím) **không** cho phép ghi đè theo thiết bị. Lý do: nó thay đổi **máy thật**, không phải cách bạn nhìn máy. Nếu cho ghi đè, mở 2 tab ở 2 chế độ khác nhau sẽ đánh nhau (§42.1).
- Hiển thị: mục nào đang bị thiết bị ghi đè ⇒ có chữ nhỏ *"riêng cho thiết bị này"* + nút **"Dùng chung"** để bỏ ghi đè.

### 48.3 Ba preset thay vì thanh trượt (và khi nào mới cho số)
| Thay vì… | Cho… | Vì sao |
|---|---|---|
| bitrate 1–50 Mbps | **Tự động / Nét / Mượt** | người dùng không biết mạng mình chịu được gì; ta **đo** được (§36) |
| resolution 1280×720 … 3840×2160 | **Dùng thật / Vừa mắt / Chữ to / Nét** (§20.3) | tên theo **mục đích**, không theo con số |
| fps 15/30/60 | gộp trong Chất lượng | 3 thanh trượt cho 1 cảm giác là 3 lần đoán sai |
| jitter buffer ms | **Ít trễ ↔ Mượt** (2 nấc) | đây là đánh đổi thật, nhưng chỉ 2 nấc có nghĩa |
> **Luật:** T1 **không có** ô nhập số nào. T2 có số nhưng **luôn** kèm giá trị mặc định + khoảng an toàn + cảnh báo khi ra ngoài khoảng. Không có "ô trống để bạn tự điền" ở bất kỳ đâu.

### 48.4 Tìm cài đặt bằng từ bạn nghĩ, không bằng tên tham số
- `/settings` có **ô tìm** ngay trên cùng (không cần bấm để hiện). Gõ `"trễ"` → gợi ý *"Ít trễ (jitter buffer)"*, *"Tắt ripple"*, *"fps trần"*.
- Mỗi mục có **từ khoá đồng nghĩa** trong `settings.index`: `trễ|lag|chậm|delay`, `mờ|nét|sharp|blur`, `tiếng|âm thanh|audio|loa`, `gõ|bàn phím|keyboard|IME`, `pin|tiết kiệm|battery`. Không có synonym này thì tìm kiếm vô dụng với người không biết thuật ngữ.
- `Ctrl+K` (desktop) mở **command palette** §31 — gõ được cả **lệnh** ("chụp màn hình", "chuyển cửa sổ") và **cài đặt** trong cùng một ô. Một ô, hai loại kết quả, có nhãn phân biệt.

### 48.5 Luật "một mục có được vào UI hay không" (chống phình, kiểm tra được)
Một cài đặt chỉ được vào **T1/T2** nếu thoả **cả 4**:

| # | Điều kiện | Nếu không thoả |
|---|---|---|
| 1 | Đổi **≥ 1 lần/năm** với ≥ 20% người dùng (với ta: ≥ 1 trong 2 người) | xuống **T3 (file)**, không có UI |
| 2 | Trả lời được *"người dùng nhận ra sự khác biệt trong 2 giây?"* | gộp vào preset, **không** tách mục |
| 3 | Không phá an toàn / không làm mất dữ liệu (§20.20) | **không tồn tại** |
| 4 | Có **giá trị mặc định đúng** cho ≥ 90% trường hợp | nếu không: đó là **lỗi thiết kế**, không phải tính năng cần cài đặt |
> Điều 4 là điều quan trọng nhất: mỗi cài đặt là một **lời xin lỗi** vì ta chọn sai mặc định. Ví dụ: nếu phải có "tắt tự chuyển preset khi mạng yếu", nghĩa là tự chuyển đang làm phiền — sửa cái đó trước, đừng thêm công tắc.

**Danh sách "không tồn tại" (ghi để không ai hỏi lại)** — mở rộng §20.20:

| Không có | Lý do |
|---|---|
| Tắt mã hoá / hạ TLS / bỏ xác thực cert | không thể thoả hiệp (§41) |
| Chọn codec thủ công (H.264/VP9/AV1) | 1 codec đúng; chọn sai = không xem được |
| Tắt log | log là thứ duy nhất cứu bạn khi kẹt phím |
| "Chạy như SYSTEM / service" | §2.3 |
| Số phiên tối đa | luôn là **1** (§42.2) |
| Đổi default audio device mà không xác nhận | làm câm máy (§40) |
| Tắt thông báo tray "đang bị điều khiển" | §2.4.1 |
| Theme tuỳ chỉnh màu tự do / CSS tuỳ biến | 4 theme là đủ; tự do = vỡ layout (§49) |

### 48.6 Không bắt khởi động lại, không bắt làm lại — và cách nói khi buộc phải
| Loại thay đổi | Hiệu lực | Cách nói trong UI |
|---|---|---|
| Thuần client (theme, tỉ lệ, âm lượng) | **ngay**, 0 ms | không cần nói gì |
| Preset/chất lượng | **ngay**, ≤ 1 s (không rớt khung hình đầu) | toast nhỏ "Đang áp dụng…" |
| Cần dựng lại pipeline (resolution, scaler) | **ngay**, 1–3 s, có overlay "Đang đổi…" | không rời phiên (§6.9) |
| Cần **phiên mới** (con trỏ, ẩn/HVNC, bàn phím thô) | phiên sau | nhãn `áp dụng từ phiên sau` + nút **[Áp dụng ngay]** (tạo lại phiên, 3–5 s, hỏi 1 lần) |
| Cần **app khởi động lại** (port, cert, driver) | sau restart | nhãn + nút **[Khởi động lại app]** (chặn nếu đang có phiên — §47.3) |
> **Luật tuyệt đối:** không có thay đổi nào **âm thầm** không có hiệu lực. Hoặc nó áp dụng, hoặc UI nói rõ vì sao chưa — và **luôn** có nút để áp dụng ngay.

### 48.7 Hoàn tác, đặt lại, mang theo máy mới
- Mọi thay đổi ở T1/T2: toast có **[Hoàn tác]** 5 s (chỉ với thay đổi *gây hại được nhận ra chậm*: ẩn taskbar, đổi preset).
- Mỗi nhóm có **"Về mặc định nhóm này"**; toàn bộ có **"Về mặc định tất cả"** (hỏi 1 lần, ghi rõ mất gì).
- `Xuất`/`Nhập` = **1 file JSON** gồm cả `server` + `user` (không gồm `device` — nó thuộc về từng máy). Đây là cách "mang theo" khi đổi máy (§47.7).
- Nhập file từ **phiên bản app khác** ⇒ migrate theo `schema`, mục lạ bị **bỏ qua + báo 1 dòng**, không làm hỏng phần còn lại.

### 48.8 Cài đặt có gì **không** thuộc về cài đặt (phân biệt dễ nhầm)
| Thứ này… | Thuộc về | Không phải cài đặt vì |
|---|---|---|
| Chọn cửa sổ để điều khiển | **hành động**, không phải setting | mỗi lần dùng khác nhau |
| Phiên đang mở / trạng thái kết nối | **trạng thái** | UI hiện ở dashboard, không nằm trong `/settings` |
| Ẩn/hiện thanh công cụ trong phiên | **trạng thái tạm của phiên** | tự ẩn sau 2.5 s (§29.1), không cần lưu |
| Sắp xếp cửa sổ trong dashboard | **device pref ẩn** | nhớ ngầm, không bày ra thành mục |
> Đây là lỗi phổ biến: nhét *hành động* vào *cài đặt* ⇒ cài đặt phình, và người dùng không biết mình vừa thay đổi **vĩnh viễn** hay chỉ **lần này**.

### 48.9 Kiểm chứng (6 test)
| # | Test | Ngưỡng |
|---|---|---|
| 1 | Đếm mục T1 / T2 bằng script đọc `settings.index` | **đúng 12 / ≤20** — fail build nếu vượt |
| 2 | Đổi mỗi mục ở T1 | hoặc có hiệu lực ≤1 s, hoặc có nhãn `phiên sau`/`khởi động lại` — **0** mục im lặng |
| 3 | Đổi chất lượng trên điện thoại, mở laptop | laptop **vẫn** dùng giá trị của nó (device thắng), không bị kéo theo |
| 4 | Gõ "trễ", "mờ", "tiếng" vào ô tìm | mỗi từ trả ≥1 kết quả đúng |
| 5 | Đổi ẩn taskbar ở tab A, tab B đang mở | tab B thấy trạng thái mới ≤2 s (qua WSS), không cần F5 |
| 6 | Nhập file cấu hình của bản cũ hơn | mục lạ bị bỏ + báo 1 dòng, phần còn lại áp dụng đúng |

---

## 49. Chống vỡ giao diện: không chồng, không đè, không tràn (nhánh #30 — lĩnh vực D)

> Câu hỏi trực tiếp: *"làm sao để UI không bị quá nhiều gây ra biến dạng, đè chồng lên nhau?"*
> Spec cũ chỉ có **ngân sách chiều cao** (§29.1: top bar 48 px, banner 40 px…) — đó là *kích thước*, không phải **luật**. Không có luật thì 6 lớp phủ sẽ tự do đè lên nhau, và bạn sẽ gặp đúng cảnh: **toast che banner, banner che toolbar, toolbar che nút đóng sheet, sheet mở trên một overlay khác, và phím Esc đóng nhầm cái**.
> Chương này là bộ luật **kiểm tra được bằng script**, không phải lời khuyên thiết kế.

### 49.1 Bệnh thật của loại UI này: **5 lớp phủ chồng lên nhau, không lớp nào "sở hữu" màn hình**
Trong một phiên điều khiển, cùng lúc có thể tồn tại: **video** · **top bar** · **bottom bar** · **cursor/ripple layer** · **banner** (mất mạng) · **toast** (đã đổi chất lượng) · **sheet cài đặt** · **overlay chuyển cửa sổ** · **HUD stats** · **keyboard ảo** (mobile) · **loupe** (mobile). Đó là **11** lớp.

| Nếu không có luật | Kết quả bạn sẽ thấy |
|---|---|
| Mỗi thành phần tự đặt `z-index: 9999` | toast nằm **dưới** banner; nút "Đóng" của sheet bị banner che ⇒ **không bấm được** |
| Không có "một bề mặt tại một thời điểm" | mở sheet cài đặt khi overlay chuyển cửa sổ đang mở ⇒ 2 lớp cùng nhận click |
| Banner + toast cùng hiện ở đáy | đè lên nhau thành 1 khối chữ không đọc được |
| Mobile: keyboard ảo + bottom bar + toast | **3 thứ** ở cùng đáy màn hình, che mất vùng đang gõ |
| Cỡ chữ Lớn (200%) | top bar 48 px **cố định** ⇒ chữ tràn ra ngoài, icon đè lên tiêu đề |
| Safe area (tai thỏ iPhone) | nút đóng nằm dưới notch ⇒ không bấm được |

> **Nguyên tắc gốc:** UI không vỡ vì *nhiều thành phần*, mà vì **không có ai quyết định ai được ở trên**. Sửa bằng 2 thứ: **thang lớp (z-scale)** và **máy trạng thái bề mặt**.

### 49.2 Thang lớp — 6 tầng **cố định**, không có số tuỳ ý
```css
/* tokens.css — nguồn duy nhất. KHÔNG có z-index nào khác trong codebase. */
--z-base:     0;   /* video */
--z-content: 10;   /* cursor, ripple, HUD, loupe */
--z-chrome:  20;   /* top bar, bottom bar, banner */
--z-float:   30;   /* toast, tooltip, popover */
--z-sheet:   40;   /* bottom sheet, side panel, command palette */
--z-block:   50;   /* dialog chặn (xác nhận phá huỷ), overlay "đang chuyển…" */
--z-system:  60;   /* mất kết nối toàn màn hình, "đang tải lại" */
```

| Luật | Kiểm tra tự động |
|---|---|
| Mọi `z-index` phải là **biến token** ở trên | `grep -rE "z-index:\s*[0-9]" client/` ⇒ **0 kết quả** (fail build) |
| Không tầng nào có **≥ 2 bề mặt cùng loại** cùng hiện | xem §49.3 |
| `--z-system` chỉ dùng cho **1** thành phần, và phải **chặn toàn bộ** input | test Playwright: click vào `--z-base` khi system up ⇒ không có event |

### 49.3 Máy trạng thái bề mặt — "một lúc chỉ X"
Đây là luật chống đè **quan trọng nhất**. Không phải "cố gắng hạn chế", mà là **bất biến có test**:

| Nhóm bề mặt | Tối đa cùng lúc | Nếu yêu cầu cái thứ 2 | Ví dụ |
|---|---|---|---|
| **Dialog chặn** (`--z-block`) | **1** | cái mới **thay** cái cũ (cái cũ đóng, không xếp chồng) | xác nhận "kết thúc phiên" khi đang có dialog "xoá cấu hình" |
| **Sheet / panel** (`--z-sheet`) | **1** | **đóng cái cũ trước**, rồi mở cái mới (không mở 2) | sheet cài đặt + command palette |
| **Overlay toàn màn hình trong phiên** (chuyển cửa sổ, chẩn đoán) | **1** | như trên | — |
| **Toast** (`--z-float`) | **1** | cái mới **đẩy** cái cũ xuống (cũ tự đóng sau 1.5 s), hoặc **gộp** nếu cùng nhóm (`Đã lưu 3 thay đổi`) | đổi 3 cài đặt liên tiếp |
| **Banner** (mất mạng, thiếu driver, secure desktop) | **1** | banner mới **xếp hàng** theo mức ưu tiên: `danger > warn > info`; chỉ hiện 1, cái còn lại chờ | "mất mạng" + "đang đổi chất lượng" |
| **Popover / tooltip** | **1** | đóng cái cũ | — |
| **Keyboard ảo (mobile)** | **1**, và nó **đẩy** layout chứ không phủ lên (§30.7) | — | — |

**Esc luôn đóng bề mặt trên cùng, và chỉ một** — thứ tự: popover → toast → sheet → dialog. Test: mở sheet, mở dialog từ sheet, bấm Esc ⇒ **chỉ dialog đóng**, sheet còn. Đây là bug kinh điển và nó có test riêng (§49.7 #3).

**Mở sheet ⇒ toolbar tự ẩn**, không phải "toolbar nằm dưới sheet". Cơ chế: sheet ở `--z-sheet` và có `backdrop` bán trong suốt; toolbar ở `--z-chrome` ⇒ **nó bị backdrop che và không nhận click** (`pointer-events: none` khi sheet mở). Không có chuyện "thấy toolbar mà bấm không được".

### 49.4 Ba vùng cố định (không bao giờ chồng) và vùng "an toàn" cho lớp phủ
```
┌───────────────────────────────┐
│  TOP  (chrome, --z-chrome)    │  48 px · co giãn theo cỡ chữ · có safe-area-top
├───────────────────────────────┤
│                               │
│   STAGE  (video, --z-base)    │  ← cursor/ripple/HUD ở đây (--z-content)
│                               │
├───────────────────────────────┤
│  BOTTOM (chrome, --z-chrome)  │  40 px · tự ẩn khi fullscreen · safe-area-bottom
└───────────────────────────────┘
   TOAST  → neo ở đáy STAGE, **phía trên** BOTTOM, không đè nút
   BANNER → **đẩy** STAGE xuống (không phủ), nằm dưới TOP
```

| Luật | Vì sao |
|---|---|
| **Banner đẩy layout**, không phủ | banner phủ lên video ⇒ che đúng chỗ bạn đang làm việc; và trên mobile nó che luôn nút |
| **Toast neo trong STAGE**, không neo ở `bottom:0` | neo ở `bottom:0` thì nó đè BOTTOM bar và nút "Đóng" |
| **Chỉ 1 banner + 1 toast**; toast tự đóng 3 s, banner **không** tự đóng nếu là `danger` | banner danger tự đóng = mất cảnh báo quan trọng |
| **Không lớp phủ nào ở giữa màn hình** trừ dialog chặn | giữa màn hình là nơi mắt bạn đang nhìn |

### 49.5 Chống vỡ khi cỡ chữ Lớn, màn hình hẹp, tiếng Việt dài
Đây là 3 nguyên nhân **thật** gây "biến dạng" mà không ai nghĩ tới lúc thiết kế:

| Nguyên nhân | Cách chống |
|---|---|
| **Cỡ chữ 150–200%** (browser/OS setting) | Mọi chiều cao là `min-height` + `padding` theo `rem`, **không** `height: 48px` cố định. Bar **được phép cao lên**; STAGE nhỏ lại. Test ở 200% là **bắt buộc** trong CI ảnh chụp |
| **Tiếng Việt dài hơn tiếng Anh ~30%** | Không cắt chữ (`text-overflow: ellipsis` chỉ cho tên cửa sổ, **không** cho nút). Nút có `min-width` + cho xuống 2 dòng. §24.16 đã nói, nhưng cần **test ảnh chụp** chứ không chỉ lời |
| **Màn hình 320 px** | 1 cột; bar gộp icon; nhãn chữ ẩn dưới icon **chỉ khi** có `aria-label`/tooltip. Test ở 320×480 |
| **Tai thỏ / thanh home iPhone** | `env(safe-area-inset-*)` cho TOP và BOTTOM; toast neo trên `safe-area-bottom + 8px` |
| **Xoay ngang ↔ dọc** | Không layout nào **đổi cấu trúc** khi xoay; chỉ đổi kích thước. Xoay không được làm mất trạng thái đang mở (sheet còn mở) |
| **Video letterbox 2 bên** | Lớp phủ (cursor, toast) neo theo **STAGE**, không theo cửa sổ ⇒ không bao giờ "trôi" ra vùng đen |

### 49.6 Ngân sách số lượng — đếm được, không phải cảm tính
| Chỉ số | Ngưỡng | Cách đo |
|---|---|---|
| Bề mặt phủ **cùng lúc** trên màn hình phiên | **≤ 3** (1 chrome ẩn được + 1 banner **hoặc** toast + 1 sheet/dialog) | test đếm `[data-surface]` đang hiển thị |
| Nút hiện thường trực trên video (desktop) | **0** khi không hover (chỉ 2 bar tự ẩn) | ảnh chụp + đếm |
| Nút hiện thường trực trên video (mobile) | **0** (§30.1) | — |
| Diện tích video bị lớp phủ che (khi rảnh) | **0%** | đo bounding box |
| Diện tích video bị che khi có banner + toast | **≤ 8%** | đo |
| Số `z-index` literal trong code | **0** | grep |
| Số cài đặt trong UI T1 / T2 | **12 / ≤20** | §48.9 #1 |
| Số mục trong menu `⋯` | **≤ 8** (nhiều hơn ⇒ command palette) | đếm trong ảnh chụp |

### 49.7 Kiểm chứng — 8 test tự động (Playwright + 1 script)
| # | Test | Ngưỡng |
|---|---|---|
| 1 | **Ma trận chồng lớp**: mở mọi cặp bề mặt (banner×toast, sheet×dialog, overlay×sheet, palette×sheet) | **0** cặp cùng hiện; luôn ≤3 bề mặt |
| 2 | Banner danger + đổi chất lượng cùng lúc | toast **không** che banner; banner không tự đóng |
| 3 | Esc khi (sheet + dialog) đang mở | chỉ dialog đóng; sheet còn; Esc lần 2 đóng sheet |
| 4 | Cỡ chữ 200%, 320 px rộng, tiếng Việt | **0** phần tử tràn/đè — so ảnh chụp với baseline (`overflow` check: `scrollWidth > clientWidth` trên mọi phần tử text) |
| 5 | Mở sheet trong phiên | toolbar `pointer-events: none`; bấm vào vị trí toolbar ⇒ không có event |
| 6 | Ảnh chụp 12 tổ hợp (3 kích thước × 2 hướng × 2 theme) | diff pixel < 0.1% so baseline — **bắt được "lệch 4 px"** mà mắt bỏ qua |
| 7 | Mobile: bàn phím ảo mở | toast + bottom bar + keyboard **không** đè; video bị đẩy, không bị phủ |
| 8 | `grep -rE "z-index:\s*[0-9]" client/` | 0 kết quả |

> Test 6 quan trọng hơn vẻ ngoài: **UI vỡ dần từng 4 px**. Một lần không ai thấy. Sau 20 PR, nút "Đóng" nằm ngoài màn hình. Ảnh chụp baseline là cách duy nhất phát hiện mà không cần mở mắt mỗi lần.

### 49.8 Ba luật viết ra để không phải tranh luận lại
1. **Không có bề mặt nào "tự đặt vị trí"**: mọi lớp phủ khai báo *tầng* + *nhóm*, và máy trạng thái §49.3 quyết định nó có được hiện không.
2. **Thà bỏ một tính năng UI còn hơn thêm một lớp phủ**: nếu cần thêm thành phần thứ 4 cùng lúc trên màn hình phiên ⇒ phải **bỏ** một cái khác (cùng luật ngân sách §48.1).
3. **Không có "settings trong settings"**: cài đặt chỉ ở `/settings` và sheet trong phiên (§24.5); không có panel cài đặt thứ ba, không có wizard cài đặt giữa phiên.

---

## 50. Tính năng còn thiếu — danh sách đã rà, và quyết định từng cái (nhánh #31)

> Bạn nói *"vẫn còn thiếu mấy chỗ tính năng"*. Tôi rà lại toàn bộ theo góc nhìn **"một ngày dùng thật"** và tìm ra **8** chỗ trống. Đây là danh sách đầy đủ, mỗi cái có quyết định rõ (làm / không làm / làm sau), **không** phải danh sách "để đó".

### 50.1 Tám chỗ trống thật (và 3 chỗ trống giả)
| # | Thiếu gì | Vì sao cần với 1–2 người | Giá | Quyết định |
|---|---|---|---|---|
| 1 | **Lịch sử phiên** (ai/cửa sổ nào/lúc nào/bao lâu/lý do kết thúc) | bạn về nhà, muốn biết *"sáng nay mình đã mở gì trên máy đó"*; và khi có sự cố, đây là thứ duy nhất trả lời được | ~40 dòng + 1 file `history.jsonl` xoay 7 ngày | ✅ **P1** |
| 2 | **Lối tắt tới cửa sổ hay dùng** (ghim "Chrome ở nhà") | 4 lần/ngày bạn mở đúng 1 cửa sổ. 3 bấm → **1 bấm** | ~30 dòng (dùng `windows_recent` đã có) | ✅ **P1** |
| 3 | **Mất kết nối: giữ ảnh cuối + đồng hồ "đã mất 3 giây"** | màn hình trắng + spinner làm bạn tưởng app chết; ảnh cuối + đồng hồ cho biết **đang thử lại**, không phải đã chết | ~20 dòng | ✅ **P1** |
| 4 | **Chuyển sang app khác trên điện thoại** (tab ẩn) | bạn đang xem, mở Zalo trả lời 20 s, quay lại ⇒ phải **không** mất phiên và **không** kẹt phím | ~25 dòng (`visibilitychange` + `pagehide` đã có §6.4.7) | ✅ **P1** |
| 5 | **Âm thanh/rung báo khi phiên bắt đầu & kết thúc** (client) | biết ngay khi phiên bị ngắt, không phải nhìn màn hình | ~15 dòng | ✅ **P2** |
| 6 | **Chế độ "mạng rất yếu"** (1 fps + chỉ bàn phím) | 3G/yếu: thà đọc chữ còn hơn màn hình đứng | ~50 dòng (đã có khung §36.9) | ✅ **P2** |
| 7 | **Gửi 1 file tới máy chủ** (một chiều, ≤50 MB, có xác nhận) | dán ảnh/tài liệu vào máy ở nhà — nhu cầu thật của người dùng cá nhân | ~150 dòng + 1 endpoint | ⚠️ **quyết định của bạn** (xem 50.3) |
| 8 | **Ghi hình phiên** | không cần (bạn tự chụp màn hình được) | — | ❌ **không làm** |

**Ba "chỗ trống giả"** (đã có, chỉ khó tìm — không phải thiếu):

| Tưởng thiếu | Thật ra ở đâu |
|---|---|
| Chụp màn hình | §26.14 — nút `⋯ → Chụp màn hình` (client chụp frame, không cần server) |
| Chuyển màn hình khi server có 2 display | §6.9 `switch monitor`, `POST /sessions/{sid}/monitor` |
| Xem ai đang dùng máy | §6.8.5 `presence` + banner "Có người đang dùng máy này" |

### 50.2 Lịch sử phiên — thiết kế tối thiểu (đừng dựng lại bảng audit)
Đã cắt bảng `audit` 7 bảng ở §26.1. Nhưng **lịch sử** là thứ khác: nó là *"nhật ký của tôi"*, không phải *"audit trail của tổ chức"*.

| Trường | Ghi chú |
|---|---|
| `ts`, `sid`, `user` (1 trong 2), `app` + `titleHash`, `mode` (HVNC/VNC), `duration_s`, `end_reason`, `bytes_out` | **không** lưu nội dung, không lưu ảnh |
- Lưu **1 dòng JSON** / phiên vào `history.jsonl`, xoay vòng 7 ngày hoặc 500 dòng (cái nào tới trước).
- UI: `/history` (đọc-only) — danh sách + lọc theo ngày. **Không** có xuất CSV (§0.3.1 #4), không phân trang ảo hoá, tối đa 500 dòng.
- Dùng được cho **chẩn đoán**: khi bạn báo "hôm qua nó giật", `history.jsonl` cho biết phiên nào, mode nào, bao lâu, bitrate trung bình.

### 50.3 Gửi file — vì sao tôi để nó là **quyết định của bạn**
§41.5 cấm "đường vận chuyển dữ liệu không kiểm soát" — đúng với sản phẩm, hơi quá với 1 người dùng máy của mình.

| Nếu bật (1 chiều, client → server) | Nếu tắt |
|---|---|
| ✅ dán ảnh/tài liệu sang máy ở nhà trong 1 cú kéo | ✅ ít bề mặt tấn công hơn |
| ⚠️ cần: giới hạn 50 MB, đuôi file chặn (`exe/ps1/bat/scr/lnk`), ghi vào `%USERPROFILE%\Downloads\RD\`, **có** hộp xác nhận hiện tên + dung lượng, **không** tự mở | — |
| ⚠️ **không** làm chiều server → client (đó là "tải dữ liệu về" và không bao giờ cần) | — |
> **Khuyến nghị của tôi:** **bật**, vì clipboard ảnh chỉ đi qua được file nhỏ, và đây là nhu cầu thật. Nhưng tôi để bạn quyết — nếu bạn không thấy mình cần, tắt đi cho gọn. Đây là mục **duy nhất** trong spec mà tôi khuyên "tuỳ bạn".

### 50.4 Ba việc nhỏ nhưng đáng làm ngay vì gần như miễn phí
| Việc | Vì sao | Giá |
|---|---|---|
| **Tiêu đề tab = tên cửa sổ đang xem** (`Chrome — Tin tức · RD`) | 5 tab mở cùng lúc thì bạn biết tab nào là gì | 3 dòng |
| **Favicon đổi màu theo trạng thái** (xám = rảnh, xanh = đang phiên, đỏ = lỗi) | nhìn tab bar là biết, không phải mở tab | 5 dòng |
| **`?debug=1` hiện HUD độ trễ** (đã có ở §6.2.3 dạng `debug.show_latency_hud`) | không cần mở `/diagnostics` giữa phiên | đã có |

### 50.5 Cập nhật hàng đợi — spec **đã đóng**, chỉ còn P0
| # | Việc | Trạng thái |
|---|---|---|
| #29 | **Mô hình tuỳ chỉnh** (3 tầng, 4 phạm vi, luật chống phình) | ✅ **xong — §48** |
| #30 | **Chống vỡ UI** (thang lớp, máy trạng thái bề mặt, kiểm bằng ảnh chụp) | ✅ **xong — §49** |
| #31 | **Tính năng còn thiếu** (8 chỗ, 6 làm, 1 tuỳ bạn, 1 không) | ✅ **xong — §50** |
| — | **P0: đo thật** (p95 · TWCC · display slot · khởi động · ngủ/reboot) | ⬜ **việc duy nhất còn lại** |
> Sau v3.18, nếu bạn còn thấy thiếu, khả năng cao là (a) một trong 6 mục §50.1 mà tôi xếp P2, hoặc (b) một **giới hạn kỹ thuật** đã ghi ở §6.13/§19.3 — không phải thiếu spec. Cả hai đều đã có chỗ trong bảng, nên không cần chương mới.

---

## 51. Máy chủ thật: GTX 1050 (Pascal) — và GitHub dùng được tới đâu (nhánh #32)

> Bạn cho biết **GTX 1050** và hỏi về GitHub. Hai câu trả lời:
> **GitHub: dùng được, nhưng không phải để *chạy* — để *đọc source và trả lời câu hỏi trước khi tiêu tiền*.**
> **GTX 1050: đủ cho H.264 1080p60, và tôi tìm ra 1 cái bẫy trong source GStreamer mà spec chưa ghi — nó chỉ xuất hiện khi máy có ≥2 adapter.**

### 51.1 GitHub làm được gì / không làm được gì (đừng trông đợi sai)
| Việc | Được? | Ghi chú |
|---|---|---|
| Đọc **source** thư viện (GStreamer, VDD…) qua `api.github.com` | ✅ **đang làm** — mọi kết luận ở §51.4 lấy từ source, không phải blog | đây là giá trị thật |
| Đọc **release notes + asset** của VDD/VAD | ✅ đã xác nhận VDD **25.7.23** có *Virtual Driver Control* **đã ký**, cài/gỡ khỏi app, gồm cả driver display **và** audio đã ký | ⇒ **không cần cài bằng Device Manager thủ công nữa** (khác §45 mô tả cũ) |
| Lưu code + artifact + `docs/p0-results.md` | ✅ | repo của bạn |
| **Chạy** capture / NVENC / WebRTC để **đo p95** | ❌ | runner GitHub **không có GPU, không có desktop, không capture được** (§45.7 vẫn đúng, không thay đổi) |
| Build + lint + test đơn vị trên CI | ⚠️ được, nhưng gần như vô nghĩa cho phần khó | **đừng** dựng CI trước P0 — nó không trả lời được câu nào trong 5 câu P0 |
| Build bản release (khi đã có code) | ✅ | repo public = 2.000 phút/tháng free; private = 2.000 phút free rồi trả tiền |

> **Kết luận:** GitHub là **kính hiển vi**, không phải **máy đo**. 5 câu P0 vẫn phải chạy trên máy bạn. Nhưng nhờ đọc source, tôi **hạ được rủi ro của P0-b** và **tìm thêm một bẫy** (§51.4) — tức là P0 giờ **hẹp hơn** so với v3.18.

### 51.2 Hồ sơ GTX 1050 — đủ hay không, và đủ **cho cái gì**
| Hạng mục | GTX 1050 (GP107, Pascal) | Nghĩa với spec |
|---|---|---|
| NVENC | **thế hệ 6**, 1 đơn vị mã hoá | 1080p60 H.264 thoải mái; trần thực tế ~**1440p60** |
| Codec | H.264 ✔ · HEVC ✔ (kể cả 10-bit) · **AV1 ✘** | ta chỉ cần H.264 (browser nào cũng có, và §45.1 đã chốt NVENC) |
| HEVC **B-frame** | **không hỗ trợ** | không ảnh hưởng: chế độ low-latency của ta **không dùng B-frame** (§37) |
| Giới hạn phiên NVENC | lịch sử 2 → 3 → 5 → 8 → 12 phiên; **driver mới = 12** | ta chỉ dùng **1–2** phiên (§42) ⇒ **không phải lo** |
| VRAM | 2 GB (1050) · 4 GB (1050 Ti) — **máy bạn: 4 GB** | ban đầu tôi coi đây là ràng buộc thật; **đã đảo** ở §51.10 với 4 GB |
| NVDEC | H.264/HEVC/VP9 giải mã được | không dùng tới (client giải mã) |
| Tuổi driver | Pascal vẫn được driver mới hỗ trợ | phải **≥ 551.76** nếu muốn trần 8+ phiên, nhưng ta không cần |

> **Phán quyết:** 1050 **không phải chướng ngại** cho mục tiêu 1080p60 + p95 < 120 ms. Nó là **mức sàn hợp lý** — nếu chạy được trên 1050 thì máy mạnh hơn chạy tốt hơn. Nếu **không** chạy được trên 1050 thì vấn đề **không phải GPU**, mà là pipeline (§16.6).

### 51.3 ~~Ràng buộc thật trên 1050: **2 GB VRAM**~~ → **đã sửa ở §51.10** (máy thật là **4 GB**)
| Thành phần | VRAM ước tính | Ghi chú |
|---|---|---|
| Desktop Windows ở 1080p | ~150–250 MB | tường thuê bao theo số cửa sổ |
| **Display ảo VDD ở 1920×1200** | ~**60 MB** | 1 surface RGBA |
| **Display ảo VDD ở 3840×2160** | ~**130–260 MB** (kèm staging + cursor) | **+200 MB** so với 1200p |
| Capture texture (pool 4–6) | 30–60 MB @1200p · **150–250 MB @4K** | pool là bội số |
| NVENC session | ~64–128 MB | §39 |
| App của bạn (Chrome, VSCode…) | **biến động nhất** — Chrome 20 tab 4K = 400–900 MB | thủ phạm thật khi hết VRAM |
| **Tổng dễ chạm trần 2 GB** | khi mở **4K** + Chrome nhiều tab | ⇒ Windows bắt đầu **dồn bộ nhớ ra RAM hệ thống** ⇒ cà giật + trễ tăng vọt, **không có cảnh báo** |

**Luật cho máy này (ghi vào `config.json`, không phải lời khuyên):**

| Mục | Giá trị trên 1050 | Vì sao |
|---|---|---|
| Trần display ảo | ~~1920×1200~~ → **2560×1440** (§51.10) | 4K trên **4 GB** không còn là tự bắn chân, nhưng DWM/đường quét vẫn nặng ⇒ mặc định 1440p |
| Preset mặc định | **Balanced 1080p60 (8 Mbps)** | Sharp 12 Mbps @1440p không thêm giá trị trên 1050 |
| Cảnh báo khi VRAM trống < 300 MB | **bật** — banner vàng "máy sắp hết VRAM, hình sẽ giật" | đây là thứ **không** có ở spec cũ: hết VRAM **không** báo lỗi, chỉ giật |
| Không bao giờ | chạy *thêm* một display ảo thứ 3 khi đang có phiên | §42.6 |

> §9.4.1 (auto-detect) phải thêm bước: **đọc `DedicatedVideoMemory` từ DXGI và chọn trần resolution theo VRAM**, không chỉ theo tên GPU. Dưới 3 GB ⇒ trần 1200p; 3–6 GB ⇒ 1440p; > 6 GB ⇒ 4K.

### 51.4 **Bẫy mới phát hiện (từ source, không có trong blog nào): WGC không cho chọn adapter theo monitor**
> ⚠️ **Đính chính ở §52**: mục này nói "lệch LUID ⇒ chậm +3–8 ms". **Chưa đủ** — trên máy hybrid, DDAPI có thể **fail hẳn** (`DXGI_ERROR_UNSUPPORTED`), và display ảo có thể **không có** trong `EnumOutputs`. Đọc **§52** trước khi làm P0.
Đọc `gstd3d11screencapturesrc.cpp` (nhánh `start`), đúng nguyên văn:
```c
if (self->capture_api == GST_D3D11_SCREEN_CAPTURE_API_DXGI) {
  hr = adapter->GetDesc (&desc);                       /* adapter SỞ HỮU monitor */
  self->adapter_luid = gst_d3d11_luid_to_int64 (&desc.AdapterLuid);
  gst_d3d11_ensure_element_data_for_adapter_luid (..., self->adapter_luid, &self->device);
} else {
  gst_d3d11_ensure_element_data (..., self->adapter, &self->device);  /* WGC: adapter do BẠN chọn */
}
```
Và property: `adapter` = *"DXGI Adapter index for creating device **when WGC mode is selected**"*, mặc định `-1` (= adapter mặc định của hệ thống).

| Đường | Adapter dùng để tạo device | Hệ quả |
|---|---|---|
| `capture-api=dxgi` (mặc định) | **đúng adapter sở hữu monitor** (dò bằng `EnumAdapters1` + `EnumOutputs`) | an toàn; nhưng DDAPI cổ điển |
| `capture-api=wgc` | **adapter index bạn truyền**, mặc định `-1` | ⚠️ nếu display ảo của VDD nằm trên **adapter khác** (iGPU laptop, hoặc Microsoft Basic Render), device sẽ ở sai adapter |

**Khi nào cái bẫy này cắn thật:**

| Máy | Rủi ro |
|---|---|
| Desktop chỉ có 1050, iGPU **tắt** trong BIOS | **không** cắn (chỉ 1 adapter) |
| Desktop có iGPU (Intel) **bật** | monitor thật cắm iGPU, VDD có thể gắn NVIDIA ⇒ **2 adapter** |
| **Laptop Optimus** | chắc chắn 2 adapter — đúng loại máy hay gặp nhất |
| Sau khi cài driver GPU mới (§45 cảnh báo) | thứ tự adapter đổi ⇒ index cũ trỏ sai |

**Hệ quả kỹ thuật:** nếu device capture ở adapter A còn `nvh264enc` mở device theo LUID (`GST_NV_ENCODER_DEVICE_D3D11` + `gst_d3d11_handle_set_context_for_adapter_luid`) ở adapter B ⇒ frame phải **copy qua staging** (≈ +3–8 ms và +VRAM) hoặc **fail hẳn**. Không có thông báo rõ ràng — chỉ thấy "trễ hơn dự kiến" hoặc "`not-negotiated`".

**Luật:** P0 **bắt buộc** chạy với `capture-api=dxgi`, và **ghi lại LUID** của (a) adapter sở hữu monitor ảo, (b) adapter mà NVENC mở. **Hai LUID phải trùng.** Nếu không trùng ⇒ đó là lý do p95 cao, **không phải tại 1050**.

### 51.5 Tin tốt: P0-b hạ rủi ro — GStreamer **có** TWCC, **không có** REMB
Đọc source `gst-plugins-good/gst/rtpmanager/rtptwcc.c` + `gstrtpsession.c` + `gst-plugins-bad/ext/webrtc/gstwebrtcbin.c`:

| Có gì | Bằng chứng |
|---|---|
| **TWCC phía nhận** | `rtptwcc.c` (`rtp_twcc_manager_recv_packet`), `rtpsession` có property **`twcc-stats`** với `bitrate-sent`, `packets-sent`, `recv-packet-count`… |
| **webrtcbin quảng cáo TWCC** | `_add_supported_attributes_to_caps()` luôn set `rtcp-fb-transport-cc` |
| **REMB** | **0 hit** trong `gstwebrtcbin.c`, **0** trong `rtpmanager` ⇒ **không có** estimator kiểu REMB |
| CC (thuật toán) | **không có** — webrtcbin **không** tự điều chỉnh bitrate |
> **Nghĩa là gì:** ta **không** cần GStreamer có CC, vì **§36 chính là CC của ta** (vòng trim 500 ms đo tại pacer). Ta chỉ cần **feedback** (gói tin cho biết mất gói/trễ) — và TWCC **đã có**. Việc phải làm chỉ là **nối extmap** transport-cc vào transceiver video + đọc `twcc-stats`. Nếu không nối được ⇒ rơi về **REMB** thì phải tự sinh (không có sẵn) ⇒ **đó** mới là lúc cân nhắc Pion (§16.6).
> ⇒ **P0-b từ "có thể phải đổi stack" hạ xuống "phải nối extmap + đọc 1 property"**. Đây là tin tốt nhất trong lượt này.

### 51.6 P0 trên **máy này** — 12 bước, ~1 ngày (thay bảng P0 trừu tượng)
| # | Việc | Lệnh / cách | Kết quả cần ghi |
|---|---|---|---|
| 1 | Hồ sơ GPU | `nvidia-smi` · `Get-CimInstance Win32_VideoController \| select Name,DriverVersion,AdapterRAM` | driver version, **VRAM thật**, **danh sách adapter** |
| 2 | Cài VDD | **VDC 25.7.23** (đã ký, installer-less) → Install | có display ảo mới trong Settings |
| 3 | Đặt resolution | `vdd_settings.xml` → **1920×1200@60** (§51.3) | — |
| 4 | LUID | `nvidia-smi --query-gpu=name --format=csv` + liệt kê output của từng adapter | **LUID monitor ảo == LUID NVENC** (§51.4) |
| 5 | Capture chay | `gst-launch-1.0 d3d11screencapturesrc monitor-index=N capture-api=dxgi ! d3d11download ! videoconvert ! autovideosink` | thấy hình, **không** `not-negotiated` |
| 6 | NVENC chay | thêm `! d3d11convert ! video/x-raw(memory:D3D11Memory),format=NV12 ! nvh264enc rc-mode=cbr bitrate=8000 zerolatency=true ! h264parse ! fakesink` | `nvidia-smi` thấy encoder load |
| 7 | WebRTC | `webrtcbin` + trang test (§16) | hình trong Chrome, LAN |
| 8 | **p95** | barcode + camera điện thoại (§6.2.3) **hoặc** timestamp echo nếu 1 máy | **số p95** — câu P0-a |
| 9 | TWCC | bật extmap, đọc `twcc-stats`, giảm băng thông 2 lần | `bitrate-sent` giảm ≤ 300 ms — câu P0-b |
| 10 | Soak 4 h | `nvidia-smi --query-gpu=memory.used --loop=5` chạy song song | VRAM **không tăng dần** (rò rỉ = chết) |
| 11 | Audio | Virtual Audio **25.7.14** qua VDC → `Get-AuthenticodeSignature` trên `.sys` | **ký hay không** — nếu không ký ⇒ dùng VB-Audio (free cá nhân) |
| 12 | Khởi động | `install.ps1` → reboot → login → **không bấm gì** | ≤ 30 s có trang — câu P0-e (§47.9) |

> Ghi **số** vào `docs/p0-results.md` (repo này), không ghi cảm nhận. Một bảng 12 dòng là đủ để quyết định đi tiếp hay đổi stack.

### 51.7 Chi phí trên máy này — vẫn **$0**
| Thứ | Giá | Ghi chú |
|---|---|---|
| NVENC H.264 | $0 | driver đã có sẵn |
| VDD 25.7.23 + VDC | $0 | **đã ký** (SignPath Foundation) |
| Virtual Audio Driver | $0 | **kiểm tra chữ ký trên máy** (§51.6 #11) — nếu unsigned thì cần test-signing ⇒ **đổi sang VB-Audio** |
| Tailscale (3 user free) | $0 | HTTPS hợp lệ, `tailscale cert` |
| GStreamer | $0 | LGPL, dùng DLL động (§45.1) |
| GitHub repo public | $0 | Actions 2.000 phút/tháng (không cần cho P0) |
| **Tổng** | **$0** | không có khoản nào mới |

### 51.8 Ba việc cần **bạn** chạy (tôi không chạy được Windows ở đây)
Dán output 3 lệnh này, tôi sẽ **điền sẵn** `config.json` + bảng P0 thay vì để bạn tự suy:
```powershell
nvidia-smi
Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,@{n='VRAM_GB';e={[math]::Round($_.AdapterRAM/1GB,1)}},VideoProcessor | Format-List
Get-CimInstance Win32_DesktopMonitor | Select-Object Name,ScreenWidth,ScreenHeight
```
> Ba lệnh này trả lời ngay: (a) 1050 là **2 GB hay 4 GB**, (b) có **iGPU** hay không (⇒ §51.4 có cắn không), (c) màn hình thật đang ở **resolution nào** (⇒ chọn trần display ảo). Không cần cài gì, không cần quyền admin.

### 51.9 Cập nhật ngược vào spec (để không có 2 nguồn sự thật)
| Nơi | Đổi gì |
|---|---|
| §9.4.1 | thêm bước **đọc VRAM ⇒ chọn trần resolution** (§51.3) + bước **kiểm LUID trùng** (§51.4) |
| §16.6 | P0-b hạ mức: *"TWCC có, REMB không; chỉ cần nối extmap"* (§51.5) |
| §18 P0 | thêm *"trên GTX 1050: trần 1200p, `capture-api=dxgi`, kiểm LUID"* |
| §45 | VDD nay cài bằng **VDC** (đã ký, có cả audio) — thay quy trình Device Manager thủ công |
| §46 | thêm 1 dòng: hết VRAM **không báo lỗi**, chỉ giật ⇒ banner VRAM < 300 MB |
| §9.4.1 | **sửa nguồn đo VRAM**: DXGI `DedicatedVideoMemory`, **không** WMI `AdapterRAM` (uint32 tràn số) — §51.12 |
| §18 P0 | trần **1440p** (không phải 1200p) — §51.10 |

### 51.10 Cập nhật từ máy thật: **VRAM = 4 GB** ⇒ trần là **D3D feature level**, không phải VRAM
> Bạn xác nhận **4 GB**. Đây là **GTX 1050 Ti 4 GB** hoặc biến thể 4 GB (1050 thường chính thức 2 GB). Điều này **đổi kết luận của §51.3** — và tôi phải sửa một chỗ §51.3 viết sai (xem cuối mục).

| Kết luận cũ (§51.3, khi giả định 2 GB) | Kết luận mới (4 GB) |
|---|---|
| VRAM là **ràng buộc thật** | ❌ **sai với máy này** — 4 GB dư cho 1 phiên 1080p60 hoặc 1440p, kể cả 4K capture ~700 MB |
| Trần display ảo **1200p** | ✅ nâng lên **2560×1440** (và 4K **được phép thử**, xem cảnh báo dưới) |
| Banner VRAM < 300 MB | **giữ**, nhưng chỉ còn là lưới an toàn (Chrome nhiều tab 4K vẫn ăn 400–900 MB) |
| Chẩn đoán khi "giật" | **đổi hẳn**: trên máy này giật **không phải** do VRAM ⇒ xem 4 nguyên nhân thật ở §51.11 |

**Trần mới theo VRAM** (thay bảng "Dưới 3 GB ⇒ 1200p…"):

| VRAM khả dụng | Trần display ảo | Ghi chú |
|---|---|---|
| < 3 GB | 1920×1200 | máy yếu; 4K là tự bắn chân |
| **3–6 GB (máy bạn: 4 GB)** | **2560×1440** | mức ngọt: chữ nét ở 150%/175% |
| 6–10 GB | 4K @60 (30 nếu 4K@60 fail) | kiểm `SetDisplayConfig` thành công |
| > 10 GB | 4K @60 | — |

**Nhưng "trần" này chỉ là *policy* của ta. Windows còn một trần cứng khác:** display ảo phải mang mode mà driver chấp nhận. Nếu VDD khai `4K@60` nhưng **băng thông pixel** của mode vượt khả năng đường quét ảo (và **Pascal không có DSC**), `SetDisplayConfig` trả lỗi ⇒ phải lùi về **4K@30**. Đây là lý do bảng trên ghi "(30 nếu 4K@60 fail)" — **không phải** vì VRAM.

⚠️ **Một cảnh báo riêng cho 1050 Ti 4 GB:** rất nhiều bản 1050 Ti là **card low-profile/OEM không có đầu cấp nguồn phụ**, và một số bản OEM **bị hạ xung khi chạy tải đồ hoạ kéo dài** (giới hạn công suất ~75 W qua khe PCIe). NVENC **không** bị hạ xung (nó là khối riêng), nhưng **DWM composite lại bị**. Nếu soak 4 h mà thấy khung hình trễ tăng dần **chỉ khi Chrome đang vẽ nhiều** ⇒ nghi vấn này, cách xác nhận: log `nvidia-smi --query-gpu=clocks.gr,clocks_throttle_reasons.active --format=csv -l 5`.

### 51.11 Trên máy 4 GB, "giật" có **4 nguyên nhân khác** — và mỗi cái có dấu hiệu riêng
Đây là bảng để đọc số liệu, không phải để đoán:

| # | Nguyên nhân | Dấu hiệu phân biệt | Cách sửa | Xác suất trên máy bạn |
|---|---|---|---|---|
| 1 | **VRAM cạn** (Chrome 4K) | trễ tăng **khi mở thêm tab**; `nvidia-smi` memory.used sát trần | hạ trần display, đóng tab | **thấp** (4 GB) |
| 2 | **LUID lệch** (capture ↔ NVENC) — §51.4 | `not-negotiated`, hoặc trễ **cao đều đặn** ngay từ giây đầu; CPU% **một nhân** cao (copy staging) | `capture-api=dxgi` | **cao nếu có iGPU** |
| 3 | **Đường quét ảo / DWM quá tải** | trễ tăng theo **số cửa sổ đang vẽ**, không theo bitrate | preset/scale 1-pass (§39), hạ trần 1440p | trung bình |
| 4 | **Không phải GPU:** mạng/jitter buffer/pacing | trễ tăng theo **thời gian trong ngày** hoặc khi đổi Wi-Fi; `encode_ms` **bình thường** | §36 CC, §37 preset | **cao nhất** — đa số "giật" là cái này |

> **Quy tắc đọc số:** nếu `encode_ms p95 < 8 ms` mà glass-to-glass vẫn >120 ms ⇒ **GPU không phải thủ phạm**. Đừng mua card mới. Đây là cái bẫy tốn tiền nhất của toàn bộ dự án: 1050 Ti 4 GB **đủ**, và mọi cải thiện phải đến từ pipeline/mạng.

### 51.12 Đo VRAM trên Windows — đừng dùng `AdapterRAM` (nó sẽ báo sai)
| Cách | Trả về | Đúng? |
|---|---|---|
| `Win32_VideoController.AdapterRAM` | `uint32` ⇒ card **≥ 4 GB bị tràn số** (báo ~4 GB hoặc giá trị vô lý) | ❌ **không dùng để kết luận** |
| **`nvidia-smi --query-gpu=memory.total`** | MiB thật | ✅ **dùng cái này** |
| DXGI `DXGI_ADAPTER_DESC1.DedicatedVideoMemory` | byte thật (`SIZE_T`) | ✅ dùng trong app (§9.4.1 bước 1b) |
| Task Manager → GPU → Dedicated | MiB | ✅ để nhìn nhanh bằng mắt |

> **Hệ quả cho §9.4.1:** bước 1b **phải** đọc `DedicatedVideoMemory` từ **DXGI**, không đọc WMI. Nếu đọc WMI, máy 4 GB có thể bị xếp nhầm nhóm một cách tình cờ, nhưng máy **6 GB** sẽ bị xếp nhầm vào "2 GB" ⇒ tự hạ trần vô cớ. Đây là lỗi im lặng, không bao giờ báo.

### 51.13 Cấu hình chốt cho **máy này** (dán vào `config.json`)
```json
{
  "display": {
    "virtual_max": "2560x1440@60",
    "virtual_fallback": ["1920x1200@60", "1920x1080@60"],
    "never_4k_by_default": true
  },
  "encoder": { "order": ["nvenc", "mf"], "preset": "balanced",
               "capture_api": "dxgi", "max_bitrate_mbps": 12 },
  "guards": { "vram_low_banner_mb": 300, "luid_mismatch_fatal_log": true },
  "p0": { "measure": ["p95_g2g", "twcc_bitrate_sent", "luid_pair", "vram_peak", "encode_ms_p95"] }
}
```
> `never_4k_by_default: true` — bạn **vẫn bật 4K được** trong Nâng cao (§48 T2), nhưng mặc định không. Lý do: 4K trên 1050 Ti làm đường quét ảo + DWM nặng gấp ~2.25 lần diện tích, và lợi ích duy nhất là chữ nét hơn — đạt được rẻ hơn bằng **DPI 150% ở 1440p**.

### 51.14 Ba câu còn lại (sau khi đã biết VRAM)
| Câu | Trạng thái | Vì sao vẫn cần |
|---|---|---|
| **Có iGPU không?** | ⬜ chưa biết | quyết định **bẫy LUID** (§51.4) có cắn hay không — ảnh hưởng **trực tiếp p95**, không phải chuyện nhỏ |
| **Driver version** | ⬜ chưa biết | NVENC 6 đời cần driver đủ mới; và trần phiên (3/5/8/12) tuỳ driver |
| **Màn hình thật đang ở resolution nào** | ⬜ chưa biết | nếu bạn đang dùng 1080p thì display ảo **1440p** vẫn hợp lý (khác mode), nhưng nếu đang 1440p thì **đừng** cho client mặc định 1440p — dễ nhầm "cùng một màn hình" |

> Hai lệnh còn thiếu (không cần admin):
> ```powershell
> nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
> Get-CimInstance Win32_DesktopMonitor | Select-Object Name,ScreenWidth,ScreenHeight
> ```
> Lệnh thứ nhất cho **cả** VRAM thật, driver **và** tên card (1050 hay 1050 Ti — hai card khác nhau về số nhân CUDA nhưng **cùng NVENC**, nên không đổi kết luận). Lệnh thứ hai cho resolution thật.

---

## 52. Máy hybrid (iGPU + GTX 1050): khi nào **chậm**, khi nào **chết** (nhánh #33)

> Bạn xác nhận **có iGPU**. §51.4 chỉ nói "nếu 2 adapter thì LUID có thể lệch ⇒ chậm +3–8 ms". **Điều đó chưa đủ mạnh.** Tài liệu Microsoft nói trường hợp này có thể **fail hẳn**, và VDD lại có một cài đặt quyết định toàn bộ (mà tôi chưa đọc kỹ). Chương này thay thế §51.4 về mặt kết luận.

### 52.1 Năm sự thật, mỗi cái có nguồn
| # | Sự thật | Nguồn | Nghĩa với ta |
|---|---|---|---|
| 1 | **DDAPI (`IDXGIOutput1::DuplicateOutput`) *theo thiết kế* trả `DXGI_ERROR_UNSUPPORTED` khi chạy trên GPU rời trong hệ Microsoft Hybrid** | Microsoft KB "Error when DDA-capable app is run against GPU" + MSDN forum | ⇒ trên máy bạn, capture **phải** ở adapter sở hữu output, **không** "chọn GPU mạnh cho nhanh" |
| 2 | `DuplicateOutput` **bắt buộc** device được tạo từ **chính adapter của output** ("must be created from the adapter to which the output is connected") | docs `IDXGIOutput1::DuplicateOutput`, `E_INVALIDARG` | ⇒ 1 device cho mỗi adapter; không dùng chung |
| 3 | Trong hybrid, `EnumOutputs` trên **iGPU có thể trả 0 output** dù `DISPLAY1` **thuộc về** iGPU (mọi pixel đi qua iGPU) | SO 37349427 | ⇒ `EnumAdapters1 → EnumOutputs` có thể **không tìm ra** màn hình bạn muốn |
| 4 | Một monitor có thể **có** trong `EnumDisplayDevices` nhưng **không có** trong `EnumDisplayMonitors`/DXGI `EnumOutputs` (đã xảy ra với VDD trên ARM) | VDD issue #483 | ⇒ nhánh `dxgi` trả `E_FAIL` ⇒ **pipeline chết**, không phải chậm |
| 5 | `Microsoft Basic Render Driver` luôn tồn tại, vendor **0x1414**, **0 output**, cờ `DXGI_ADAPTER_FLAG_SOFTWARE` | DXGI overview (MS) | ⇒ vòng dò LUID **phải bỏ qua** nó, nếu không sẽ chọn nhầm "adapter rẻ nhất" |

> **Điểm mấu chốt:** với 1 adapter, sai thì **chậm**. Với 2 adapter, sai thì **không chạy** — và thông báo lỗi là `E_FAIL`/`UNSUPPORTED`/`not-negotiated`, **không nói gì về adapter**. Đây là loại lỗi làm người ta mất 2 ngày.

### 52.2 Trước khi viết thêm dòng code nào: **cắm cáp màn hình vào cổng của 1050**
Đây là cách rẻ nhất và triệt để nhất, và tôi phải nói nó **trước** mọi thứ kỹ thuật:

| Hiện trạng (suy đoán rất có khả năng, cần bạn xác nhận) | Hệ quả | Sửa |
|---|---|---|
| Cáp HDMI/DP **cắm vào mainboard** (dùng iGPU) ⇒ desktop render trên **Intel**, 1050 chỉ ngồi không | **Mọi** chế độ đều phải copy chéo adapter: capture ở iGPU → encode ở NVENC. VNC mode **luôn** ở tình trạng này | **Rút cáp, cắm vào cổng HDMI/DP của 1050** ⇒ desktop render trên 1050, iGPU về 0 dùng, **hết hybrid** |
| Cáp đã cắm vào 1050, iGPU chỉ bật trong BIOS | Windows vẫn là "hybrid system" theo nghĩa driver, nhưng output chính thuộc 1050 | VDD phải trỏ render adapter về 1050 (§52.3) |

**Sau khi cắm cáp vào 1050, kiểm 1 phát:** `Win+P` và Settings → Display → Advanced: adapter của màn hình phải là **NVIDIA**. Nếu đúng, §52.4–52.5 dưới đây trở thành **dự phòng** thay vì đường chính, và P0 đơn giản hơn nhiều.

> Nếu máy bạn là **laptop** (không cắm cáp được): bỏ qua mục này, đi thẳng §52.3.

### 52.3 VDD có cài đặt chọn GPU render — và nó quyết định tất cả
Trong `C:\VirtualDisplayDriver\vdd_settings.xml` (bản HDR 25.7.23, đọc từ repo):
```xml
<monitors><count>1</count></monitors>
<gpu>
    <friendlyname>default</friendlyname>   <!-- ĐỔI DÒNG NÀY -->
</gpu>
```

| Giá trị | Nghĩa |
|---|---|
| `default` | Windows/OS tự chọn render adapter cho display ảo — trên máy hybrid thường là **iGPU** |
| **tên GPU rời** (chuỗi khớp tên adapter, ví dụ `NVIDIA`) | ép display ảo render trên **1050** ⇒ capture + NVENC **cùng adapter** |

Và bản 25.7.23 ghi trong changelog: *"PCI-bus based GPU selection (LUID): improved multi-GPU render adapter selection by resolving an adapter **LUID from a PCI bus number** (more deterministic than name-only matching)"* ⇒ cơ chế chọn theo LUID **đã có**, đáng tin hơn so với khớp tên.

**Bốn topology và phán quyết:**

| # | Topology | Capture | Encode | Phán quyết |
|---|---|---|---|---|
| **A** | Cáp vào 1050, VDD `friendlyname=default` | 1050 | NVENC 1050 | ✅ **tốt nhất** — 1 adapter, 0 copy |
| **B** | Cáp mainboard, VDD `=NVIDIA` | 1050 (cho display ảo) | NVENC 1050 | ✅ tốt cho **HVNC**; **VNC mode** vẫn chéo adapter (màn hình thật ở iGPU) |
| **C** | Cáp mainboard, VDD `=default` (⇒ iGPU) | iGPU | NVENC 1050 | ⚠️ **chéo adapter** ⇒ xem §52.5 |
| **D** | VDD render trên adapter mà DXGI **không thấy output** | — | — | ❌ `E_FAIL` ⇒ **pipeline không khởi động** ⇒ xem §52.6 |

### 52.4 Chi phí thật của topology C (để biết "chậm" là bao nhiêu)
| Bước | Dữ liệu | Chi phí |
|---|---|---|
| DWM render display ảo trên iGPU | 1440p BGRA = **14.7 MB/frame** | — |
| Texture nằm ở device iGPU, encoder cần device NVIDIA | **không share được** `D3D11Memory` giữa 2 LUID | ⇒ `d3d11download` → system memory → upload lên 1050 |
| 2 lần copy full-frame | 14.7 MB × 2 × 60 fps = **1.76 GB/s** qua PCIe + bộ nhớ hệ thống | **≈ +2–5 ms/frame** và **1 nhân CPU** bận (không phải GPU) |
| Nguy cơ thêm | staging readback đồng bộ ⇒ **stall** nếu không dùng ring buffer ≥3 | +1 frame nếu làm ẩu |
> **Nghĩa là:** topology C **không** làm hỏng, nhưng **ăn hết ngân sách p95** một mình (mục tiêu 120 ms; 5 ms là 4% nhưng nó **cộng dồn** với jitter buffer + encode + mạng). Và nó là **nguyên nhân số 2** trong bảng §51.11 — đúng dấu hiệu "một nhân CPU cao, trễ cao đều từ giây đầu".

### 52.5 Topology C: hai cách, và tôi khuyên cách nào
| Cách | Làm gì | Ưu | Nhược |
|---|---|---|---|
| **C1 · Chuyển sang QSV** | capture iGPU → `qsvh264enc` (Quick Sync **trên cùng iGPU**) | **0 copy chéo**; không dùng 1050 nữa | chất lượng/bitrate khác NVENC (§37: QSV có bẫy `BufferSizeInKB` 8×); tải iGPU thay vì GPU rời |
| **C2 · Copy sang NVENC** | capture iGPU → staging → NVENC 1050 | giữ chất lượng NVENC | +2–5 ms, +1 nhân CPU, +PCIe |

> **Khuyến nghị:** trên máy này **đừng** chọn C bằng phần mềm. **Sửa topology** (§52.2 cắm cáp, §52.3 `friendlyname`) để về A hoặc B — rẻ hơn mọi tối ưu code. Chỉ khi không sửa được vật lý (laptop) mới chọn **C1**, và ghi rõ trong `/diagnostics` là "đang chạy QSV vì display ảo render trên iGPU".

### 52.6 Khi monitor có trong Windows nhưng **không** trong DXGI `EnumOutputs`
Đây là lỗi **chết**, không phải chậm, và GStreamer sẽ trả về đúng chuỗi này:
```c
for (adapter_idx = 0; ; adapter_idx++) {          /* EnumAdapters1 */
  for (output_idx = 0; ; output_idx++) {          /* EnumOutputs */
    if (desc.Monitor == monitor) return S_OK;
  }
}
return E_FAIL;                                    /* monitor không thuộc adapter nào */
```
**Thang leo khi gặp `E_FAIL` (thay hành vi hiện tại là bỏ cuộc):**

| Bước | Hành động | Vì sao đúng |
|---|---|---|
| 1 | Dò lại qua **`EnumDisplayDevices`** để lấy `HMONITOR` thật | Windows biết monitor mà DXGI không biết |
| 2 | Chuyển sang **WGC theo `monitor-handle`** (`gst_d3d11_winrt_capture_new(device, monitor, …)`) | WGC lấy item từ **HMONITOR**, không cần DXGI output |
| 3 | Nếu WGC cũng fail ⇒ **`unsupported_topology`** trong `/diagnostics` + gợi ý *"đổi `<gpu><friendlyname>` trong vdd_settings.xml"* | đây là lỗi cấu hình, phải nói **cách sửa**, không chỉ báo lỗi |
| 4 | **Không** tự ý chuyển sang capture màn hình **thật** | người dùng sẽ thấy desktop thật của mình bị stream ra ngoài — vi phạm §41 |

### 52.7 Vòng dò adapter — bản sửa cho §9.4.1
```
1. EnumAdapters1 → bỏ qua nếu VendorId == 0x1414 (Microsoft Basic Render) hoặc cờ SOFTWARE
2. Với mỗi adapter: EnumOutputs → ghi {adapter LUID, tên, số output, device name}
3. Monitor mục tiêu ⇒ adapter sở hữu nó. KHÔNG có ⇒ §52.6
4. Kiểm: adapter capture == adapter NVENC?  (so LUID)
     · trùng  → capture-api=dxgi, preset bình thường          [A/B]
     · lệch   → KHÔNG hạ preset vô ích; chọn 1 trong 2:
                (a) ưu tiên QSV trên adapter capture           [C1]
                (b) dxgi + staging, ghi rõ "cross_adapter=true" [C2]
5. Ghi tất cả vào /diagnostics: {"capture_luid","encode_luid","same":bool}
```
> Điều quan trọng nhất trong khối trên là **④ không được "hạ preset"**. Hạ preset **không** sửa được copy chéo adapter — nó chỉ làm hình mờ hơn mà vẫn trễ. Đây là loại "tối ưu" vô nghĩa mà §48.5 gọi là *lỗi thiết kế*, không phải tính năng.

### 52.8 P0-g (mới) — 5 phút, quyết định topology trước khi đo p95
Đo p95 trên topology C rồi kết luận "GStreamer chậm" là **kết luận sai**. Trước P0-a, chạy:

| # | Việc | Đạt khi |
|---|---|---|
| 1 | Đổ topology: tên + LUID + số output của **từng** adapter, và adapter của màn hình thật | có bảng, biết đang ở A/B/C/D |
| 2 | Cài VDD, đặt `friendlyname` theo §52.3, khởi động lại driver | display ảo xuất hiện |
| 3 | Kiểm display ảo **có** trong `EnumOutputs` (script §52.9) | không `E_FAIL` |
| 4 | Kiểm LUID capture == LUID NVENC | `same=true`, hoặc biết chắc đang ở C và chấp nhận |
| 5 | **Chỉ sau đó** mới đo p95 | số p95 có nghĩa |

### 52.9 Script đổ topology (PowerShell, không cần admin, không cần cài gì)
```powershell
Add-Type -TypeDefinition @"
using System; using SharpDX; using SharpDX.DXGI;   // nếu không có SharpDX, dùng bản C# dưới đây
"@
```
> SharpDX không có sẵn ⇒ dùng cách **không cần thư viện**: chạy `dxdiag /t %TEMP%\dx.txt` rồi đọc, **hoặc** dùng bản C# tối giản ở dưới (Copy vào `dump.ps1`, chạy `powershell -File dump.ps1`):
```csharp
// dump.ps1 — liệt kê adapter + output + LUID. Không cần admin.
$src = @'
using System; using System.Runtime.InteropServices;
public class D {
  [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid i, out IntPtr f);
  [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IF { int SetPrivateData(); int SetPrivateDataInterface(); int GetPrivateData();
                 int GetParent(); int EnumAdapters1(uint i, out IntPtr a); int IsCurrent(); }
  [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IA { int SetPrivateData(); int SetPrivateDataInterface(); int GetPrivateData(); int GetParent();
                 int EnumOutputs(uint i, out IntPtr o); int GetDesc(out D d); int CheckInterfaceSupport(); }
  [StructLayout(LayoutKind.Sequential)] public struct D { public IntPtr a; public uint b; public uint c;
    public uint d; public UIntPtr e; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string name;
    public uint vendor; public uint dev; public uint sub; public uint rev; }
  public static void Run() {
    Guid g = new Guid("770aae78-f26f-4dba-a829-253c83d1b387"); IntPtr f;
    if (CreateDXGIFactory1(ref g, out f) != 0) { Console.WriteLine("no dxgi"); return; }
    IF fac = (IF)Marshal.GetObjectForIUnknown(f);
    for (uint i = 0; ; i++) {
      IntPtr ap; if (fac.EnumAdapters1(i, out ap) != 0) break;
      IA ad = (IA)Marshal.GetObjectForIUnknown(ap); D desc; ad.GetDesc(out desc);
      Console.WriteLine(String.Format("adapter[{0}] {1}  vendor=0x{2:X} luid={3}.{4}",
          i, desc.name.Trim(), desc.vendor, desc.b, desc.c));
      for (uint j = 0; ; j++) {
        IntPtr op; if (ad.EnumOutputs(j, out op) != 0) break;
        Console.WriteLine(String.Format("   output[{0}] present", j));
      }
    }
  }
}
'@
Add-Type -TypeDefinition $src -Language CSharp
[D]::Run()
```
> Nếu script không chạy được trên máy bạn (COM interop qua PowerShell hay lỗi), **không sao** — dùng `dxdiag /t` hoặc chỉ cần trả lời 2 câu: *"cáp màn hình đang cắm vào 1050 hay vào mainboard"* và *"trong `vdd_settings.xml`, `friendlyname` là `default` hay tên GPU"*. Hai câu đó đã xác định topology A/B/C/D với độ chính xác 90%.

### 52.10 Cập nhật ngược
| Nơi | Đổi |
|---|---|
| §51.4 | thay kết luận: không chỉ "+3–8 ms" mà **có thể fail** (`UNSUPPORTED`/`E_FAIL`); trỏ §52 |
| §5.5 (recovery) | `UNSUPPORTED` ⇒ **không** chỉ re-init: kiểm topology trước (§52.6) |
| §9.4.1 | thay vòng dò bằng bản §52.7 (bỏ Basic Render, không hạ preset khi lệch LUID) |
| §21.9 (`/diagnostics`) | thêm `capture_luid` / `encode_luid` / `same` / `cross_adapter` / `vdd_render_adapter` |
| §18 P0 | thêm **P0-g** trước P0-a |
| §48 T2 | thêm 1 mục: **"GPU mã hoá"** = `Tự động · NVIDIA · Intel QSV` (vì topology C là lựa chọn **thật**, không phải lỗi) |

---

## 53. Host là **laptop**: Dell Inspiron 7467 (i5-7300HQ + HD 630 + GTX 1050 4 GB) (nhánh #34)

> §52 kết luận: *"cắm cáp màn hình vào 1050 để hết hybrid"*. **Laptop không cắm được vào đâu cả.** Nên §52 phải đảo một nửa, và thêm 5 ràng buộc mà một cái desktop không có: **nắp gập, pin, nhiệt, Wi-Fi 1x1, RAM**.

### 53.1 Ba kết luận bị đảo
| Kết luận cũ | Trên laptop |
|---|---|
| §52.2 "cắm cáp vào cổng 1050 ⇒ hết hybrid" | ❌ **không làm được**. Panel nội bộ **luôn** thuộc iGPU ⇒ hybrid là **vĩnh viễn** trên máy này. Không phải sự cố, là **điều kiện làm việc** |
| §52.5 "sửa topology rồi hãy tối ưu code" | ⚠️ chỉ còn **một** cách sửa topology: **`vdd_settings.xml` + chọn encoder** (§53.2). Không còn cách vật lý |
| §51.10 "trần display ảo 2560×1440" | ❌ hạ về **1920×1080** — panel chỉ 1080p, VDD 1440p làm app tưởng màn hình lớn hơn, DPI lệch, và capture đắt hơn 78% pixel (§53.9) |

### 53.2 Tin tốt: **iGPU HD 630 là host GPU tốt hơn GTX 1050** cho đúng bài toán này
Đây là kết luận quan trọng nhất của chương, và nó ngược với trực giác "dùng card rời cho khoẻ":

| | **HD 630 (iGPU) + QSV** | **GTX 1050 (dGPU) + NVENC** |
|---|---|---|
| Capture nguồn | ✅ panel + VDD đều thuộc iGPU ⇒ **cùng adapter** | ❌ phải kéo frame qua PCIe từ iGPU |
| Copy chéo adapter | **0** | **1.76 GB/s + 2–5 ms + 1 nhân CPU** (§52.4) |
| Nhiệt phát sinh | thấp (chia sẵn với CPU) | **+10–20 W** trong chassis 14″ |
| Quạt | thường im | **quay to, liên tục** — máy đặt ở nhà, bạn nghe qua điện thoại |
| Điện | thấp hơn ~8–15 W | cao hơn |
| Optimus | ✅ dGPU **ngủ hẳn** (D3cold) | ❌ phải đánh thức dGPU suốt phiên |
| Chất lượng H.264 @8 Mbps | khá | **tốt hơn** (NVENC 6th gen > HD 630) |
| Trần thực tế | 1080p60 thoải mái | 1080p60 thoải mái |

> **Khuyến nghị cho máy này: mặc định dùng QSV trên HD 630, để 1050 ngủ.** Đây là lần đầu spec chọn iGPU trước dGPU, và lý do rất cụ thể: **host là laptop đặt ở nhà** ⇒ nhiệt/quạt/điện là chi phí thật hằng ngày, còn chất lượng hơn 1 bậc ở 8 Mbps thì gần như không nhìn ra trên điện thoại.
> Đổi lại được: §48 T2 có mục **"GPU mã hoá"** = `Tự động · Intel QSV · NVIDIA`. Đặt `Intel QSV` cho máy này. NVENC vẫn dùng được khi bạn cần chất lượng (ví dụ đọc bảng tính nhiều chữ nhỏ).

**Topology A′ (chốt cho laptop):**
```xml
<!-- C:\VirtualDisplayDriver\vdd_settings.xml -->
<gpu><friendlyname>Intel</friendlyname></gpu>   <!-- ép display ảo render trên iGPU -->
```
⇒ capture (iGPU) → QSV (iGPU) = **1 adapter, 0 copy, dGPU ngủ**. Đây là topology **duy nhất** trên laptop vừa rẻ vừa mát.

### 53.3 Nhiệt: i5-7300HQ 45 W + GTX 1050 trong thân 14″ — và phiên remote **tệ hơn chơi game**
Lý do: chơi game là tải **từng đợt** (có màn hình chờ, có lúc rảnh). Remote desktop để mở 8 tiếng là tải **liên tục, phẳng** — nhiệt ổn định ở mức cao và **không có lúc hạ**.

| Ngưỡng | Ý nghĩa | Hành vi của app |
|---|---|---|
| CPU package < 80 °C | bình thường | không làm gì |
| 80–95 °C | turbo giảm dần | ghi log, không báo người dùng |
| **> 95 °C kéo dài 60 s** | throttle thật ⇒ `encode_ms` p95 nhảy vọt | **[GỢI Ý]**: chỉ ghi log + hiện trong HUD `debug=1`. Banner **chỉ khi** `encode_ms` p95 tăng > 2× (§54.3 #4) |
| **> 100 °C** | Tjmax, CPU tự hạ xung mạnh | giảm preset 1 bậc + banner |

**Ba việc làm được ngay, xếp theo hiệu quả/giá:**

| # | Việc | Hiệu quả |
|---|---|---|
| 1 | **QSV thay NVENC** (§53.2) | **giảm 10–20 W** — nhiều nhất, miễn phí |
| 2 | **Kê cao đáy máy 2–3 cm** (2 nắp chai, hoặc đế tản) | giảm 5–10 °C; máy này hút gió **dưới đáy** |
| 3 | **Giới hạn CPU 99%** (Power Options → Processor power management → Maximum processor state = 99%) | **tắt turbo** ⇒ giảm 10–15 °C, mất ~10% hiệu năng đơn nhân. Với remote desktop thì đánh đổi này **nên làm** — nút thắt là nhiệt, không phải CPU |

> **Không** dùng "Dell Thermal Management → Cool" như một giải pháp: nó hạ xung **mạnh hơn** mức cần, và bạn sẽ thấy chậm mà không hiểu vì sao. Dùng mục 3, có kiểm soát.

### 53.4 Optimus: dGPU ngủ ⇒ **frame đầu tiên trễ 200–800 ms** (bẫy mới)
Nếu bạn chọn **NVENC** trên laptop: khi không tải, Optimus đưa 1050 vào **D3cold** (tắt điện hoàn toàn). Lần encode đầu tiên phải đánh thức nó: driver load, clock ramp, VRAM cấp phát.

| Hiện tượng | Hệ quả | Xử lý |
|---|---|---|
| Frame đầu + 200–800 ms | client thấy "đứng hình" 0.5 s đầu, tưởng app treo | **warm-up: encode 5 frame throwaway ngay sau khi tạo pipeline**, trước khi gửi frame thật (§53.12 #4) |
| Clock ramp 300–800 MHz → boost | 1–2 s đầu bitrate không đạt | giữ bitrate ở 60% trong 2 s đầu rồi mới lên đủ |
| Nếu rút sạc | Windows hạ cả hai GPU | §53.6 |
> **Với QSV (khuyến nghị) thì bẫy này biến mất** — iGPU không bao giờ ngủ vì nó là "GPU màn hình". Đây là lợi ích thứ hai của §53.2, và là lý do P0 phải đo **riêng** độ trễ 2 giây đầu.

### 53.5 Nắp gập: mặc định của Windows là **SLEEP** — tức là giết phiên
§46.8 có dòng *"Laptop gập nắp → màn hình tắt, vẫn chạy"* — **đó là điều mong muốn, không phải mặc định**. Mặc định Dell/Windows: **gập nắp → Sleep**.

| Lựa chọn | Hệ quả | Phán quyết |
|---|---|---|
| Gập nắp → **Do nothing** | máy chạy tiếp, panel tắt, VDD không ảnh hưởng | ✅ cần thiết nếu bạn muốn gập máy |
| Gập nắp → **Sleep** (mặc định) | mất kết nối sau ~5 s; WoL từ browser không làm được (§46.3) | ❌ **đây là lý do số 1 "không kết nối được" với laptop host** |
| Gập nắp → **Shut down** | tệ nhất | ❌ |

**Nhưng với máy này, tôi khuyên: ĐỂ NẮP MỞ khi ở nhà, đặt "Do nothing".**

| Vì sao nắp mở | Vì sao đừng gập |
|---|---|
| Tản nhiệt tốt hơn (máy này thoát nhiệt ở **bản lề**) | gập nắp ⇒ khe thoát bí ⇒ §53.3 nặng hơn rõ rệt |
| Bạn nhìn thấy màn hình = biết máy đang làm gì | gập nắp + HVNC ⇒ không ai biết máy đang chạy gì |
| Không cần đổi setting nguy hiểm | "Do nothing" + quên ⇒ máy chạy trong balo, **nóng, hao pin** |

> Nếu bạn **buộc** phải gập: đặt "Do nothing" **nhưng** chỉ khi cắm sạc và đặt máy ở chỗ thoáng. App ghi vào `/diagnostics`: `lid_policy` và cảnh báo 1 lần nếu phát hiện `Do nothing` **không** cắm sạc.

### 53.6 Pin: host chạy bằng pin là cấu hình **sai**, và Windows sẽ tự phá nó
| Việc Windows tự làm khi rảnh/chạy pin | Hậu quả | Cần tắt |
|---|---|---|
| Sleep sau 15–30 phút | mất phiên | Power Options → Sleep = **Never** (khi cắm sạc) |
| Hibernate sau 3 giờ | mất phiên, khởi động lại 40 s | Hibernate = **Never** |
| **Critical battery → Hibernate** | tắt giữa phiên | hoặc để, nhưng phải **cảnh báo trước** |
| Hạ xung CPU mạnh khi rời sạc | QSV/NVENC cùng hạ theo | cắm sạc **luôn** |
| **Dell Power Manager "Battery Extender"/"Primarily AC"** | giới hạn sạc 80% ⇒ tốt cho pin, **nhưng** khi mất điện thì chỉ còn 80% | chấp nhận được, ghi vào `/diagnostics` |

**Hành vi của app trên máy này:**
- `/diagnostics` + `GET /api/machine` (§46.4) trả thêm: `on_ac`, `battery_pct`, `lid_policy`, `cpu_temp_c`, `gpu_active` (dGPU đang bật hay D3cold).
- Nếu `on_ac == false` trong phiên: **banner vàng 1 lần** *"Đang chạy pin — máy sẽ ngủ/tắt sau ~X phút"*, kèm pin % và **thời gian ước còn lại** (từ `Win32_Battery.EstimatedChargeRemaining` + công suất tiêu thụ ước).
- Nếu pin < 15% và **không** cắm sạc: **vẫn cho vào**, chỉ banner + đồng hồ ước còn bao lâu ([MỀM] — §54.3). Host ở nhà vốn cắm sạc.

### 53.7 Mạng: máy này **có cổng RJ-45** — dùng nó, đừng dùng Wi-Fi
Đây là nút thắt **lớn hơn GPU** trên laptop, và spec chưa nói gì:

| Đường | Đặc điểm | Phán quyết |
|---|---|---|
| **RJ-45 (có sẵn trên 7467)** | 1 Gbps, không power-save, jitter ~0 | ✅ **dùng cái này** khi ở nhà — cắm dây là xong |
| Wi-Fi **Intel AC 8265 (đã nâng), 2×2 867 Mbps** — **máy bạn dùng cái này** | 2 luồng ⇒ MU-MIMO, ~400–600 Mbps thực; **vẫn còn** power save | ⚠️ dùng được; 4 mục dưới là **[GỢI Ý]**, không phải điều kiện (§54.2) |
| Wi-Fi 2.4 GHz | nhiễu, 20 MHz | ❌ |

**Bốn gợi ý cho Wi-Fi [GỢI Ý — không kiểm tra, không cảnh báo, làm khi thấy giật]** (mỗi cái đều gây "giật 1 giây rồi thôi"):

| # | Ở đâu | Tắt gì |
|---|---|---|
| 1 | Device Manager → adapter → **Power Management** | ✅ bỏ *"Allow the computer to turn off this device to save power"* |
| 2 | Device Manager → adapter → **Advanced** | `Power Saving Mode` → **Highest performance** (nếu có) |
| 3 | Power Options → Wireless Adapter Settings | **Maximum Performance** (cả cắm sạc **và** dùng pin) |
| 4 | Router | bật **5 GHz**, chọn kênh 36–48; tắt "airtime fairness" nếu có |

> **Đừng** đổ lỗi "GStreamer trễ" khi đang chạy Wi-Fi 1x1 có power save. §51.11 mục 4 (mạng) là xác suất cao nhất, và trên máy này xác suất đó còn cao hơn vì card chỉ 1 luồng.

### 53.8 RAM: cấu hình gốc là **4 GB** — nếu đúng thì đây là ràng buộc thật
Spec này nhẹ (mục tiêu **< 200 MB RSS**, §43.10), nên **app** không phải vấn đề. Nhưng trên host:

| RAM | Tình hình |
|---|---|
| **4 GB** | Windows 10 idle ~2.2 GB + Chrome ~1 GB ⇒ **swap liên tục** ⇒ **chính host** giật, không phải mạng. Phải nâng cấp — 1 thanh 8 GB DDR4-2400 rất rẻ, máy có **2 slot** |
| **8 GB — máy bạn** | ✅ **dùng được**, không phải nút thắt. Đóng bớt tab nhiều RAM trên host nếu thấy swap |
| 16 GB+ | thoải mái |

**Guard [MỀM — hạ nhãn ở §54.3]:** RAM < 500 MB ⇒ **cảnh báo 1 dòng** ở picker, **vẫn cho vào**. Không từ chối, không chặn. Trên máy 8 GB gần như không xảy ra ⇒ **không nằm trong P0**.

### 53.9 Display: panel 1080p ⇒ **VDD 1080p**, không 1440p (đảo §51.10)
| Lý do | Chi tiết |
|---|---|
| Panel vật lý 14″ FHD 1920×1080 | VDD 1440p ⇒ app tưởng màn hình lớn hơn, DPI/scale lệch so với lúc bạn ngồi trước máy |
| Pixel cost | 1440p = **+78%** pixel so với 1080p ⇒ QSV phải làm nhiều hơn, capture texture lớn hơn |
| Chuyển VNC ↔ HVNC | cùng 1080p ⇒ cửa sổ không nhảy vị trí/kích thước khi đổi mode |
| Đọc chữ | trên 14″ bạn vốn đã dùng **125–150% scaling**; giữ nguyên scaling đó, đừng nới resolution |

```xml
<resolutions>
  <resolution><width>1920</width><height>1080</height><refresh_rate>60</refresh_rate></resolution>
</resolutions>
```

### 53.10 Đặc thù Dell: 3 cài đặt hay âm thầm phá phiên
| Cài đặt | Ở đâu | Vấn đề | Đặt thành |
|---|---|---|---|
| **Dell Thermal Management** | Dell Power Manager | "Cool"/"Quiet" hạ xung mạnh hơn cần | **Balanced** (hoặc Ultra Performance nếu đã làm §53.3 #3) |
| **Battery Extender / Primarily AC** | Dell Power Manager | giới hạn sạc 80% (tốt), nhưng mất điện thì ít pin hơn | giữ, chỉ cần biết |
| **Dell Update / SupportAssist chạy nền** | Services | tự cập nhật BIOS/driver **giữa phiên** ⇒ reboot (§45 cảnh báo VDD) | tắt auto-update, tự chạy khi rảnh |

### 53.11 `config.json` chốt cho **máy này**
```json
{
  "display": { "virtual_max": "1920x1080@60", "virtual_fallback": ["1600x900@60"] },
  "encoder": { "order": ["qsv", "nvenc", "mf"], "preset": "balanced",
               "capture_api": "dxgi", "max_bitrate_mbps": 10,
               "warmup_frames": 5 },
  "network": { "prefer_wired": true, "wifi_powersave_must_be_off": true },
  "guards": { "vram_low_banner_mb": 300, "ram_low_refuse_mb": 500,
              "cpu_throttle_warn_c": 95, "battery_refuse_pct": 15,
              "require_ac_for_new_session": false },
  "laptop": { "lid_policy_expect": "do_nothing_or_open", "warn_if_lid_closed": true }
}
```
> `order` đặt **qsv trước** — khác mặc định §9.4.1 (NVENC trước). Đây là **quyết định theo máy**, không phải thay đổi toàn cục.

### 53.12 P0 trên laptop — thứ tự **khác** desktop, vì có thêm 4 biến
| # | Việc | Đạt khi | Khác gì desktop |
|---|---|---|---|
| 1 | Đổ topology (§52.9) | biết panel thuộc iGPU, VDD render adapter | — |
| 2 | Cài VDD, `friendlyname=Intel`, resolution **1080p** | display ảo hiện, `EnumOutputs` thấy | — |
| 3 | **QSV** thay NVENC | `qsvh264enc` khởi tạo được; `nvidia-smi` không thấy process | **mới** |
| 4 | **Đo cold start**: tạo phiên, đo 2 giây đầu | frame đầu < 300 ms (QSV) | **mới** — Optimus §53.4 |
| 5 | p95 ở **cắm sạc** | số chính | — |
| 6 | p95 ở **pin** (để so sánh) | ghi số, **không** dùng làm chuẩn | **mới** — §53.6 |
| 7 | Soak 4 h, log nhiệt + throttle + VRAM + RAM | không throttle > 95 °C kéo dài; RAM phẳng | **mới** — §53.3 |
| 8 | Test **nắp gập** ("Do nothing") | phiên sống, panel tắt | **mới** — §53.5 |
| 9 | Test **rút dây mạng** giữa phiên (nếu dùng cáp) | ICE restart, không mất phiên | — |
| 10 | TWCC (§52.5 P0-b) | `bitrate-sent` giảm ≤ 300 ms | — |
| 11 | Khởi động lại máy → login không bấm gì | ≤ 30 s có trang | — |

### 53.13 ~~Còn hai câu~~ → **đã trả lời ở v3.23**: RAM **8 GB**, Wi-Fi **Intel AC 8265 (2×2)**. Cả hai đều **tốt hơn** giả định ⇒ 2 mối lo dưới đây đã giảm:
| Câu | Vì sao quan trọng |
|---|---|
| **RAM bao nhiêu GB?** (4 / 8 / 16 / đã nâng) | 4 GB ⇒ **host tự giật**, phải nâng cấp trước khi đo p95 (§53.8). Đây là thứ có thể làm **toàn bộ P0 vô nghĩa** |
| **Host nối mạng bằng cáp hay Wi-Fi?** | Wi-Fi 1x1 + power save ⇒ spike 20–200 ms; đo trên Wi-Fi rồi kết luận "pipeline trễ" là **sai** (§53.7) |

---

## 54. Nới lỏng: bỏ luật cứng ở nơi không cần (nhánh #35)

> Bạn nói đúng, và đây là lỗi **của tôi**, không phải ý kiến khác nhau: từ §47 đến §53 tôi biến mọi thứ thành **luật có số**. Cứu được vài lỗi thật, nhưng tạo ra 3 tác hại:
> ① **Đọc mệt** — 6.148 dòng, phần lớn là bảng ngưỡng. ② **Trái yêu cầu ban đầu** của bạn: *"không over-engineering"*, *"dễ dùng"*. ③ **Nguy hiểm hơn**: khi mọi thứ là "bắt buộc", **không còn gì là quan trọng** — §41 (bảo mật) và "nhiệt > 95 °C" trông ngang hàng nhau trên giấy.

### 54.1 Đếm thật: tôi đã tạo ra bao nhiêu luật cứng
| Chương | Luật cứng / ngưỡng có số | Test "bắt buộc" |
|---|---|---|
| §46 | ~12 | 6 |
| §47 | ~18 | 7 |
| §48 | ~14 | 6 |
| §49 | ~12 | 8 |
| §51–53 | ~22 | 6 |
| **Tổng** | **~78** | **33** |

> **78 luật cứng cho một công cụ 1–2 người dùng là sai tỉ lệ.** Bản thân §48.5 (chống phình cài đặt) đáng lẽ phải áp dụng cho **chính spec**.

### 54.2 Ba loại, và tôi đã trộn chúng
| Loại | Đặc điểm | Được phép |
|---|---|---|
| **[CỨNG]** — nguyên tắc | sai = mất dữ liệu / mất phiên / lộ máy. Hiếm | luật + test chặn merge |
| **[MỀM]** — mặc định tốt | đúng 90%, nhưng sai thì chỉ phiền | áp dụng tự động, **người dùng đổi 1 bấm**, không test chặn |
| **[GỢI Ý]** — kinh nghiệm | đúng với máy này, có thể sai với máy khác | chỉ hiện trong tooltip/`/help`, **không** áp dụng tự động, **không** báo lỗi |

**Phân loại lại những gì tôi đã viết gần đây:**

| Đã viết (§51–53) | Đúng loại | Sửa thành |
|---|---|---|
| VRAM < 300 MB → **banner** | **[MỀM]** | hiện **trong `/diagnostics`**, banner chỉ khi VRAM < 100 MB (thật sự sắp chết) |
| RAM < 500 MB → **từ chối tạo phiên** | **[MỀM]** | **cảnh báo 1 dòng** ở picker, vẫn cho vào (máy 8 GB gần như không gặp) |
| Pin < 15% → **từ chối** | **[MỀM]** | cho vào, banner + đồng hồ ước lượng |
| CPU > 95 °C → **banner** | **[GỢI Ý]** | chỉ ghi log + hiện trong HUD khi bật `debug=1` |
| `wifi_powersave_must_be_off` | **[GỢI Ý]** | `/help` có 4 bước, **không** kiểm tra, **không** cảnh báo |
| LUID lệch → **không hạ preset** | **[CỨNG]** | giữ: hạ preset không sửa được, chỉ làm hình mờ mà vẫn trễ |
| `z-index` literal = 0 | **[CỨNG]** | giữ: đây là lỗi cấu trúc, không phải sở thích |
| T1 đúng **12** mục | **[CỨNG]** | giữ (ngân sách, §48.1) |
| "Banner phải đúng 1 cái" | **[CỨNG]** | giữ: 2 banner chồng nhau là **bug**, không phải gu |
| "Đo p95 trước khi code" | **[CỨNG]** | giữ: đây là cổng quyết định 8–11 tuần |
| "Nhiệt: giới hạn CPU 99%" | **[GỢI Ý]** | tooltip trong trang chủ; không áp dụng tự động |

### 54.3 Sửa 4 chỗ cứng quá tay (áp dụng ngay)
| # | Chỗ | Trước | Sau |
|---|---|---|---|
| 1 | §53.8 RAM | `ram_low_refuse_mb: 500` (từ chối) | **cảnh báo**, không chặn. Máy bạn **8 GB** ⇒ trường hợp này gần như không xảy ra ⇒ **bỏ khỏi P0** |
| 2 | §53.6 pin | từ chối nếu < 15% | cho vào + banner. Host ở nhà **cắm sạc** ⇒ không xảy ra |
| 3 | §53.7 Wi-Fi | "phải tắt 4 thứ" | thành **4 gợi ý** trong `/help`. Card **8265 là 2×2** nên phần lớn vấn đề 1×1 đã hết |
| 4 | §53.3 nhiệt | banner > 95 °C | **log + HUD**; banner chỉ khi **throttle thật** (encode_ms p95 tăng > 2×) |

### 54.4 P0 rút từ 11 bước xuống **6 bước, 45 phút** — phần còn lại "khi gặp"
| # | Bước | Thời gian | Vì sao **không** bỏ được |
|---|---|---|---|
| 1 | Đổ topology + cài VDD 1080p (`friendlyname=Intel`) | 10′ | không có display ảo thì không có gì để đo |
| 2 | QSV chạy được + `nvidia-smi` không thấy process | 5′ | xác nhận dGPU ngủ (mục tiêu §53.2) |
| 3 | Hình hiện trong Chrome qua LAN/Wi-Fi | 5′ | toàn bộ pipeline |
| 4 | **p95 glass-to-glass** | 15′ | **cổng quyết định duy nhất** |
| 5 | TWCC `bitrate-sent` giảm khi bóp băng thông | 5′ | nếu không có, CC của ta mù |
| 6 | Reboot → login → **không bấm gì** → có trang ≤ 30 s | 5′ | nếu sai, toàn bộ ý tưởng "máy ở nhà tự chạy" sai |

| Bỏ khỏi P0 (làm **khi gặp**, không phải trước) | Vì sao |
|---|---|
| Soak 4 h · log nhiệt · cold start 2 s · đo khi chạy pin · test nắp gập · test rút dây mạng | chỉ có nghĩa **sau khi** p95 đạt; và mỗi cái là một lần chạy 10 phút **khi** có triệu chứng |
| VRAM/RAM/CPU guard | máy 4 GB VRAM + 8 GB RAM ⇒ không phải nút thắt |
| Ma trận UI 12 tổ hợp ảnh chụp (§49.7 #6) | đúng, nhưng **không phải việc của P0** — để ở P1 khi đã có UI |

> **Nguyên tắc mới (thay cho "33 test bắt buộc"):** P0 chỉ giữ những bước mà **nếu sai thì mọi thứ sau đó vô nghĩa**. Còn lại là *"biết để tra khi gặp"* — spec vẫn ghi, nhưng **không** nằm trên đường đi.

### 54.5 Ranh giới: 8 thứ **vẫn phải cứng** (đừng nới chỗ này)
Nới lỏng **không** có nghĩa là nới tất cả. Cứng ở đây vì sai một lần là mất thứ không lấy lại được:

| # | Luật | Sai thì |
|---|---|---|
| 1 | TLS bắt buộc, không có tuỳ chọn tắt | lộ mật khẩu + toàn bộ màn hình ra LAN/cà phê |
| 2 | Auth trước khi bất kỳ frame nào | ai mở URL cũng xem được máy bạn |
| 3 | `release_all` khi mất kết thúc/đóng tab | **kẹt phím** trên máy thật (gõ lung tung) |
| 4 | Restore cửa sổ/audio theo thứ tự §47.4 | cửa sổ **mất** khỏi màn hình, phải tìm tay |
| 5 | Không bao giờ kill bản cũ (§47.3) | mất phiên đang dở của người khác |
| 6 | Không lưu tiêu đề cửa sổ, chỉ hash | ghi lại lịch sử duyệt web của chính bạn |
| 7 | Một người điều khiển tại một thời điểm (§42.1) | 2 con trỏ đánh nhau, không ai dùng được |
| 8 | Toast + tray **không tắt được** khi bị điều khiển | biến máy bạn thành RAT không báo |

### 54.6 Để spec tự giữ được độ mềm (cơ chế, không phải lời hứa)
- Mỗi con số trong spec **phải** mang nhãn `[CỨNG]` / `[MỀM]` / `[GỢI Ý]`. Con số **không nhãn** = chưa quyết ⇒ không được đưa vào code.
- CI đếm: `[CỨNG]` **≤ 20** trên toàn spec. Vượt ⇒ phải cắt hoặc hạ nhãn. (Giống luật 12 mục ở §48.1 — ngân sách, không phải ước lượng.)
- Mọi `[MỀM]` **phải** có đường đổi trong UI **≤ 2 bấm** (§48), nếu không thì nó là `[CỨNG]` giả dạng.
- Test chặn merge **chỉ** cho `[CỨNG]`.

> **Câu chốt:** spec này để **một người dùng máy của mình**. Mục tiêu không phải "không có trường hợp nào xảy ra", mà là **khi có trường hợp xảy ra thì bạn hiểu và sửa được trong 2 phút** — và không phải đọc 78 bảng để làm việc đó.

---

## 55. Xem camera của máy bị điều khiển + nghe micro của máy đó (nhánh #36)

> Yêu cầu mới: *"có thể xem cam máy bị điều khiển và nghe micro nhé"*.
> Đây là chiều **ngược** với §40 (audio của máy chủ → client). §40 là **nghe âm thanh máy kia phát ra**; mục này là **nhìn/nghe cái đang ở trước máy kia**. Hai thứ khác nhau, hai pipeline khác nhau, hai loại rủi ro khác nhau.

### 55.1 Trả lời trực tiếp: **làm được**, và nó **không** phải "video call"
| Điều bạn muốn | Có | Ghi chú |
|---|---|---|
| Xem **camera** của máy chủ trong trình duyệt | ✅ | thêm 1 video track vào **cùng** `webrtcbin`, không mở kết nối thứ 2 |
| Nghe **micro** của máy chủ | ✅ | thêm 1 audio track, cùng transport |
| Nghe **tiếng máy chủ đang phát** (§40) | ✅ (đã có) | **song song** với micro, chọn được |
| Client **nói chuyện** qua loa máy chủ (intercom) | ⚠️ **cần thêm** | về kỹ thuật chỉ là chiều ngược của cùng đường audio; xem 55.7 |
| Camera **của client** gửi lên máy chủ | ❌ không làm | không mục đích, tăng rủi ro riêng tư |
| **Thấy + nghe cùng lúc** | ✅ | nhưng cần **AEC**, xem 55.5 — đây là chỗ dễ hỏng nhất |

### 55.2 Element: có sẵn trong GStreamer, không phải tự viết
| Thiết bị | Element | Ghi chú |
|---|---|---|
| Camera (webcam) | **`mfvideosrc`** (Media Foundation) — `ksvideosrc` là dự phòng | `mfvideosrc device-name="<tên>"`; chọn được camera như chọn loa |
| Micro | **`wasapi2src`** | cùng họ với `wasapi2src` đã dùng cho loopback ở §40 ⇒ **cùng code chọn thiết bị** |
| Khử vọng + khử ồn + AGC | **`webrtcdsp`** (+ `webrtcechoprobe`) | xem 55.5 |
| Đóng gói | `openh264enc`/`vp8enc`? **Không** — camera dùng **VP8/VP9** hoặc H.264 tuỳ client | nhưng **phải** là một encoder **riêng** (xem 55.3) |

### 55.3 Bốn chi phí thật, và cách chúng không phá phiên chính
| # | Chi phí | Số thật trên máy bạn | Cách tránh |
|---|---|---|---|
| 1 | **Encoder thứ 2** | camera 640×480@30 là ~1/9 pixel của 1080p ⇒ **~10–15% tải QSV**, chấp nhận được | dùng **cùng** `qsvh264enc` nhưng **instance riêng**; **không** dùng NVENC (đánh thức dGPU — §53.2) |
| 2 | **Băng thông** | 640×480@30 ≈ **0.6–1.2 Mbps**; micro Opus 24 kbps | tính vào ngân sách §36: **trừ trước** khỏi bitrate màn hình, không cộng thêm |
| 3 | **Nhiệt/điện** | +1 camera +1 mic: **~0.5–1 W** — không đáng kể | — |
| 4 | **Camera bị app khác giữ** | Teams/Zoom/Camera app **giữ độc quyền** ⇒ `mfvideosrc` mở được nhưng **khung đen** | phát hiện & báo rõ (§55.9) |

> **Luật mềm [MỀM]:** camera **mặc định tắt**, không chiếm băng thông khi không dùng. Bật là 1 bấm trong thanh dưới (§55.4). Micro **cũng mặc định tắt** — vì micro là thứ riêng tư nhất trong cả hệ thống.

### 55.4 UI: gộp vào 1 nút, không thêm thanh công cụ thứ ba
§49.4 cấm thêm vùng mới. Nên camera/mic **không** có nút riêng trên thanh dưới:

| Trạng thái | Hiển thị |
|---|---|
| Cả hai tắt (mặc định) | **1 nút** `📷` trong menu `⋯` của thanh dưới |
| Bật | video camera thành **PiP nhỏ 160×120** ở góc dưới-phải **STAGE** (trong `--z-content`, dưới toast); kéo được, nhớ vị trí theo **device** |
| Chỉ micro | không có PiP; hiện **1 icon mic nhấp nháy theo mức âm** cạnh nút `⋯` (để bạn biết nó **đang nghe**) |
| PiP đang mở + mở sheet | PiP **ẩn theo** sheet (không nổi lên trên) — §49.3 |
> PiP là **cùng** một `<video>` element nhận track thứ 2 — không phải cửa sổ mới, không phải kết nối mới.

### 55.5 Cái bẫy lớn nhất: **nghe micro + nghe tiếng máy = vòng lặp âm**
Nếu bạn bật **cả** micro máy chủ **và** loa máy chủ, và client phát ra loa ngoài: tiếng từ loa client → vào micro client → (nếu có intercom) → ra loa máy chủ → vào micro máy chủ → về client ⇒ **hú**. Kể cả **không** có intercom, vẫn có vòng **qua phòng**: micro máy chủ nghe thấy chính loa máy chủ.

| Cách chống | Chi phí | Khi nào dùng |
|---|---|---|
| **`webrtcdsp` với `echo-cancel=true` + `webrtcechoprobe`** trên nhánh micro, lấy **tín hiệu loa máy chủ làm reference** | ~2–4 ms/frame, có sẵn | ✅ **bật mặc định** khi micro bật |
| Tai nghe ở client | 0 | gợi ý 1 dòng khi người dùng bật cả hai |
| Chỉ cho **một trong hai** cùng lúc | 0 | ❌ quá cứng — thuộc loại "cấm" mà §54 vừa bỏ |
| Push-to-talk | — | tuỳ chọn cho intercom (§55.7) |

> **`webrtcechoprobe` cần reference = luồng loa của máy chủ.** Ta **đã có** luồng đó (§40 loopback) ⇒ nối vào `probe` của `webrtcdsp`. Đây là lợi thế hiếm: hệ thống khác không có sẵn reference, ta có.

### 55.6 Balloon/khung hình không đều: camera ≠ màn hình
Camera và màn hình có **hai đồng hồ khác nhau**; ghép vào cùng một `webrtcbin` mà không xử lý thì jitter buffer của track camera bị **kéo theo** nhịp màn hình ⇒ camera giật dù mạng tốt.

| Việc | Cách |
|---|---|
| Hai transceiver **riêng** | `webrtcbin` hỗ trợ nhiều transceiver; camera ở mid thứ 2 |
| Không dùng chung `rtpjitterbuffer` | mỗi track một buffer, `latency` riêng (camera **150–200 ms**, màn hình 40–80 ms) |
| Timestamp | lấy từ `mfvideosrc` (có `do-timestamp`), không tự đóng dấu ở pacer |
| Khi camera ẩn (PiP đóng) | `setDirection(recvonly→inactive)` ⇒ **ngừng encode và ngừng truyền**, không chỉ ẩn UI |

### 55.7 Intercom (client nói vào loa máy chủ) — nên làm, nhưng là **bước 2**
| | Chi tiết |
|---|---|
| Kỹ thuật | chiều ngược của cùng transceiver audio; `webrtcbin` nhận track, `wasapi2sink` phát ra loa máy chủ. **Không** cần thiết bị ảo (khác §40) |
| Rủi ro | người **ngồi trước máy** nghe thấy bạn nói mà không biết ai; và **AEC phải dùng đúng reference** nếu không hú |
| Vì vậy | **push-to-talk** (giữ phím/giữ nút) chứ không mở micro liên tục; và **luôn** có tiếng "bíp" nhỏ trước khi mở |
| Quyết định | **bước 2** (sau khi P0 xong). Không nằm trên đường đi của P0 |

### 55.8 Riêng tư — mục này **không** được nới lỏng (thuộc §54.5 loại [CỨNG])
Camera và micro là thứ khác bản chất với việc xem màn hình. Ba luật:

| # | Luật | Lý do |
|---|---|---|
| 1 | **Luôn hiện dấu hiệu đang bật** — icon trên PiP + tooltip; micro thì icon nhấp nháy theo mức âm | bạn phải biết máy đang **nghe** |
| 2 | **Tắt khi phiên kết thúc / đóng tab / mất mạng > 5 s** (không chỉ ẩn UI — **đóng thiết bị**) | không có chuyện camera chạy mà không ai xem |
| 3 | **Không lưu, không ghi, không log** nội dung; `/diagnostics` chỉ ghi `camera_on: true/false` | — |
> Trên máy có **đèn LED camera cứng** (Inspiron 7467 có) thì luật 1 và 2 được kiểm chứng bằng mắt — đó là lý do ta **không** thêm "camera ảo" hay che LED.

### 55.9 Edge case (5 cái, ghi để tra — **không** phải luật cứng)
| Tình huống | Hiện tượng | Xử lý |
|---|---|---|
| App khác đang giữ camera | khung **đen**, không lỗi | hiện "Camera đang được ứng dụng khác dùng" + nút Thử lại |
| Máy **không có** camera | `mfvideosrc` không có device | **ẩn** nút `📷` (không hiện nút chết) |
| Micro mặc định bị đổi giữa phiên | im | theo dõi `IMMNotificationClient` (đã có §40) → chuyển thiết bị, hoặc dừng có thông báo |
| Camera USB **rút** giữa phiên | `GST_STREAM_ERROR` | dừng track **đó**, không đóng phiên chính; PiP hiện "đã ngắt" |
| Băng thông cạn | màn hình ưu tiên | **hạ camera trước** (480→360→240p → tắt), không hạ màn hình — màn hình mới là thứ bạn đang điều khiển |

### 55.10 Test (4, không phải 14)
| # | Test | Đạt |
|---|---|---|
| 1 | Bật camera + micro, xem 10 phút | PiP mượt, tiếng rõ, **không hú** khi loa client mở |
| 2 | Đóng tab khi camera đang bật | LED camera **tắt** ≤ 2 s; `mfvideosrc` được release |
| 3 | Mở Teams trên máy chủ rồi bật camera trong app | báo đúng "đang được ứng dụng khác dùng" |
| 4 | Bóp băng thông xuống 1 Mbps | camera hạ 480→240 hoặc tắt, **màn hình vẫn xem được** |

---

## 56. Code + GitHub Actions: cái gì compile được ở đâu (nhánh #37)

> Bạn hỏi *"có thể viết code rồi compile bằng GitHub Action không"* — **được**, và đã có trong repo.
> Điều đáng nói không phải "có CI", mà là **ranh giới**: phần nào CI làm được thật, phần nào **không bao giờ** (và vì sao điều đó không phải vấn đề lớn như nó nghe).

### 56.1 `spike/` — 5 file, không dependency ngoài
| File | Nội dung | Spec tương ứng |
|---|---|---|
| `src/machine.rs` | adapter/VRAM/RAM/pin/nhiệt; `cross_adapter()`; trần display | §9.4.1, §51.12, §52.7, §53.9 |
| `src/pipeline.rs` | sinh chuỗi GStreamer: desktop · camera · mic, đúng tham số low-latency | §37, §55 |
| `src/policy.rs` | guard **3 mức**, mặc định **Warn**; `vram_low()` chỉ cảnh báo | §54.2, §52.5 |
| `src/main.rs` | `rd --demo`: in 3 chuỗi pipeline + mọi finding ra console | §56.3 |
| `tests/spec_conformance.rs` | **16 test** = biến spec thành assertion | nhiều chương |
| `check.sh` | chạy đúng 3 bước của CI ở máy có `cargo` — **3 s** | §56.8 |

> **Vì sao không dùng crate nào:** mỗi dependency là một lý do khiến CI fail vì lý do không liên quan đến spec. `spike` cố ý **0 dependency** ⇒ `cargo test` chạy trong 20 s và **không thể** hỏng vì crate thượng nguồn.

### 56.2 Năm test đáng chú ý nhất (vì chúng chặn đúng lỗi tôi từng mắc)
| Test | Chặn cái gì |
|---|---|
| `battery_15_percent_only_warns` | chặn tái phát **đúng lỗi §54** — tôi từng "từ chối tạo phiên ở 15% pin" |
| `capture_uses_dxgi_not_wgc` | chặn chọn `capture-api=wgc` trên máy hybrid (§52.4) |
| `every_encoder_is_zero_latency` | chặn quay lại `multipass`/`lookahead` — mỗi cái +30–130 ms (§37) |
| `room_view_does_not_capture_desktop` | chặn "Xem phòng" kéo theo capture desktop (tốn nhiệt/pin, §55.3) |
| `basic_render_never_wins_vram` | chặn chọn Microsoft Basic Render khi dò adapter (§52.1 #5) |
| `vram_low_is_a_banner_never_a_block` | chặn **tái phát chính lỗi tìm ra ở §56.7**: VRAM thấp chỉ được Warn |

> **Test này đã trả tiền lại ngay lần chạy đầu tiên** — xem §56.7: `every_encoder_is_zero_latency` đỏ vì `mfh264enc` thiếu `b-frames=0`.

### 56.3 `ci.yml` — 2 job, có artifact để tải về (⚠ xem §56.8: chưa chạy lần nào)
| Job | Runner | Làm gì |
|---|---|---|
| `test` | ubuntu | `clippy -D warnings` → `cargo test` → in 3 chuỗi pipeline ra log để **đọc bằng mắt** |
| `build-windows` | windows-latest | `cargo build --release` → **smoke-run `rd.exe --demo`** → upload artifact `rd-windows-x64` |

> **Chưa kiểm được**: `clippy` không có trong toolchain npm (§56.7), nên bước clippy chỉ chạy trên CI — tức là **hiện chưa chạy lần nào**. `cargo build` với `-D warnings` thì đã chạy và sạch.
> Bước **smoke-run** quan trọng: nếu `rd.exe` build được nhưng **panic khi chạy** (ví dụ format string sai), CI đỏ ngay — chứ không để bạn tải về rồi mới phát hiện.
> `RUSTFLAGS: -D warnings` + `clippy -D warnings` ⇒ **không có cảnh báo nào lọt**. Đây là cách duy nhất để một spike 600 dòng không mục sau 2 tuần.

### 56.4 Ranh giới: CI **không** làm được gì, và vì sao không sao
| Không làm được | Vì sao không sao |
|---|---|
| Chạy capture / NVENC / QSV thật | runner **không GPU, không desktop** (§45.7). Nhưng logic đã được test ⇒ khi chạy thật, lỗi còn lại là **lỗi môi trường**, không phải lỗi code |
| Đo p95 glass-to-glass | cần camera/điện thoại thật (§6.2.3) |
| Kiểm VDD tạo được display | cần driver đã cài |
| Kiểm khởi động sau login | cần Task Scheduler thật (§47.2) |
| Kiểm LED webcam | cần phần cứng thật (§55.8) |
> **Sửa lại sau khi chạy thật (§56.7):** câu "CI xanh = code đúng" ở trên chỉ đúng **nếu CI chạy được** — và trên repo này nó **đang không chạy** (§56.8). Từ giờ bằng chứng là **`check.sh` xanh**, CI chỉ là bản sao chạy ở nơi khác.
>
> **Kết luận thực dụng:** CI không thay được P0, nhưng nó biến *"tôi viết code rồi bạn tự biết nó có compile không"* thành *"CI xanh = code đúng, đỏ = sửa ngay"*. Đó là toàn bộ giá trị, và nó đủ.

### 56.5 Vòng làm việc từ giờ
| Bước | Ai | Thời gian |
|---|---|---|
| 1 | Tôi viết logic (pipeline, policy, config, protocol) + test | — |
| 2 | `spike/check.sh`: build `-D warnings` + 16 test + smoke-run (**hoặc** CI khi Actions bật lại) | **3 s** / ~2 phút |
| 3 | Bạn tải `rd-windows-x64` từ tab Actions | 10 s |
| 4 | Bạn chạy **P0 6 bước** (§54.4) trên laptop | 45 phút, **1 lần** |
| 5 | Bạn dán số (p95, TWCC, cold start) | — |
| 6 | Tôi chốt stack: tiếp tục Rust+GStreamer, hay đổi (§16.6) | — |
> Nghĩa là từ đây **không còn "spec trên giấy"**: mỗi lượt tôi có thể thêm một module có test, CI chứng minh nó đúng, và bạn chỉ phải làm đúng **một** việc mà máy không làm thay được — chạy trên máy thật.

### 56.6 Việc tiếp theo tôi đề nghị (chọn 1)
| # | Việc | Giá trị |
|---|---|---|
| **A** | **`security.rs`** — token/session/rate-limit theo §41, có test (không cần GPU) | phần **[CỨNG]** nhiều nhất, và test được 100% — ✅ **đã xong ở v3.28, xem §57** |
| **B** | **`config.rs`** — schema + migrate + 12 mục T1 của §48, có test round-trip | chặn được lỗi "config hỏng" (§47.4c) — **đề nghị tiếp theo** |
| **C** | **`signaling.rs`** — SDP/ICE state machine + `intent_id`/`rev` của §32 | phần dễ sinh bug race nhất |
| **D** | **Client shell** — `index.html` + JS thuần: window picker + video + 2 thanh tự ẩn (§29), chạy được với `--demo` | nhìn thấy được, không cần GPU |
> Tôi khuyên **A** trước: nó là **[CỨNG]**, test được hoàn toàn ngoài môi trường thật, và sai ở đó là hậu quả nặng nhất. **D** sau, vì nó cho bạn thứ để *nhìn*.
> **Cập nhật v3.28:** A đã xong (§57). Thứ tự mới là **B → C → D**.

### 56.7 Chạy thật trong sandbox — và nó bắt được 3 lỗi

> Không còn "tôi nghĩ nó compile được". Dưới đây là những gì đã chạy, và những gì nó phát hiện.

**Cài Rust khi mạng bị chặn.** `static.rust-lang.org` và `objects.githubusercontent.com` đều không truy cập được trong sandbox (`curl` exit 35/000) ⇒ `rustup-init` không tải được. Lối vòng: `registry.npmjs.org` **thì** vào được, và trên đó có gói `@rust-sandbox/rust-1-95-x86_64-linux` — **rustc + cargo + rust-std 1.95.0, 116 MB**, không cần mạng ngoài.
```sh
npm install -g @rust-sandbox/rust-1-95-x86_64-linux
export PATH="$HOME/.local/rust/bin:$PATH"   # rustc 1.95.0 (59807616e 2026-04-14)
```
> Ghi lại vì đây là mẹo dùng lại được: **bất kỳ máy nào bị chặn static.rust-lang.org đều cài Rust bằng npm được.**

**Kết quả (`./spike/check.sh`):**
| Bước | Kết quả |
|---|---|
| `cargo build` với `RUSTFLAGS=-D warnings` | **sạch**, 0.7 s |
| `cargo test` | **16/16 pass** |
| `cargo run -- --demo` | in đúng 3 chuỗi, `may start session: true`, guards `(none)` |
| `cargo clippy` | **không có trong toolchain** ⇒ chưa chạy lần nào (chỉ CI, và CI đang tắt — §56.8) |

**3 lỗi thật, không phải lỗi tưởng tượng:**
| # | Lỗi | Nếu không chạy test thì hậu quả |
|---|---|---|
| 1 | `every_encoder_is_zero_latency` **ĐỎ**: nhánh `mfh264enc` thiếu `b-frames=0` | phát hiện muộn ở P0, khi màn hình đã chạy bằng fallback ⇒ **+30–60 ms** mà không ai biết vì sao. Đã thêm `b-frames=0` + ghi chú *phải xác nhận property bằng `gst-inspect-1.0 mfh264enc`* ở P0 bước 2 |
| 2 | 2 warning `dead_code` (`Encoder::MediaFoundation`, `Thresholds::vram_*`) | CI `-D warnings` sẽ **đỏ ngay commit đầu** ⇒ sửa: `main.rs` dùng `rd_spike_lib` thay vì `mod` (bin và test compile **cùng một bản code**), và `vram_*` được dùng thật |
| 3 | `Thresholds.vram_block_mb` **tồn tại** | đây là **vi phạm §54.2 của chính tôi**: VRAM thấp thì hết frame, không mất dữ liệu ⇒ **không bao giờ được Block**. Đã xoá field, thay bằng `vram_low()` chỉ trả `Warn`, banner **300 MB** đúng §53, kèm test `vram_low_is_a_banner_never_a_block` |

> **Bài học rẻ nhất của cả spec này:** lỗi #3 là lỗi *thiết kế*, và nó chỉ lộ ra khi mọi con số phải được **dùng** ở đâu đó. Assertion rẻ hơn review, và **rẻ hơn tranh luận**.

### 56.8 GitHub Actions: account bị **khoá vì billing** — không phải lỗi `ci.yml`

> Câu hỏi *"compile bằng GitHub Action"* hoá ra có **hai** vế: *file CI có đúng không* (**có**) và *Actions trên repo này có chạy không* (**không, hiện tại**).

**Bằng chứng:**
| Kiểm tra | Kết quả |
|---|---|
| Run `42445510438` (commit v3.24) | `conclusion: startup_failure`, **0 s**, **0 job**, `path: "BuildFailed"`, `name: ""` |
| `GET /repos/.../actions/workflows` | `{"total_count": 0}` — GitHub **chưa đăng ký** workflow nào |
| Push thêm `hello.yml` **7 dòng** (`run: echo hello`) | **cũng `startup_failure` 0 s** ⇒ loại trừ YAML/`ci.yml` |
| `ci.yml` parse bằng PyYAML | hợp lệ — 3 key `on/env/jobs`, 2 job; ASCII thuần, không tab, không CRLF |
| `GET /repos/.../actions/permissions` | **403** `Resource not accessible by integration` ⇒ tôi **không tự bật được** |

> Kết luận **ban đầu** (sai): "Actions bị tắt ở mức repository". Đúng phần *nằm ngoài file*, sai phần *nguyên nhân*.

#### 56.8.1 Nguyên nhân thật (§56.9 kể lại thí nghiệm)

> **`The job was not started because your account is locked due to a billing issue.`**
> — annotation của GitHub, đọc được ngay khi một workflow **6 dòng** chạy được.

| Điều tôi tưởng | Điều thật |
|---|---|
| Actions bị tắt trong `Settings → Actions` | Actions **bật bình thường**; **account** bị khoá vì billing |
| Repo private ⇒ cần thêm thanh toán ⇒ **public là xong** | **Public không giúp gì** khi lock ở mức account — lock chặn cả phút miễn phí |
| `startup_failure` = file workflow hỏng | `startup_failure` cũng là **cùng lỗi billing** này, chỉ hiển thị ở tầng trước khi có job |

> **Việc phải làm: xử lý billing ở account** (thêm phương thức thanh toán / trả số dư / mở ticket với GitHub Support để gỡ lock). Sau đó **không cần sửa gì trong repo** — `ci.yml` đã sẵn sàng, chỉ chờ account mở khoá.

### 56.9 Thí nghiệm đã tìm ra nó (cách làm đúng, để lần sau khỏi đoán)

| Bước | Làm gì | Học được |
|---|---|---|
| 1 | `gh run rerun 42450086894` | **"cannot be rerun; its workflow file may be broken"** — GitHub *cũng* nghi file, nên tôi suýt tin |
| 2 | Thay `ci.yml` bằng **6 dòng**: `on: [push, workflow_dispatch]` + `run: echo` | workflow **đăng ký được** (`gh run list` hiện tên `ci`) ⇒ **file cũ không phải thủ phạm** |
| 3 | `gh run view <id>` đọc **ANNOTATIONS** | thấy nguyên văn câu billing ⇒ hết đoán |
| 4 | Khôi phục `ci.yml` đầy đủ | không mất gì |

> **Bài học phương pháp (đáng nhớ hơn cả CI):** `startup_failure` + `path: BuildFailed` **không** có nghĩa là file sai — nó là *"chưa tới được bước đọc file"*. Ba lần tôi suy luận từ **triệu chứng** đều sai; chỉ **thay bằng file tối giản rồi đọc annotation** mới ra sự thật. Khi một hệ thống trả lỗi chung chung, **giảm biến số** nhanh hơn **suy luận**.

**Bật lại (30 s, chỉ bạn làm được):**
1. Repo → **Settings → Actions → General**.
2. *Actions permissions*: chọn **Allow all actions and reusable workflows** → **Save**.
3. Nếu repo **private**: xuống **Billing & plans** xem còn minutes (repo cá nhân free thường có 2 000 phút/tháng; Rust build ~2 phút/lần).
4. Vào tab **Actions**, chọn `ci` → **Run workflow** (đã có `workflow_dispatch`).

**Trong lúc chờ, cổng kiểm tra không bị chặn:** `./spike/check.sh` làm đúng 3 bước của job `test` (build `-D warnings` → test → smoke-run) và chạy **3 s ở máy có `cargo`**. Job `build-windows` thì chỉ CI làm được (máy bạn là Windows nhưng cần Rust; nếu muốn, `rustup` trên Windows tải từ `static.rust-lang.org` được — mạng nhà bạn không bị chặn như sandbox).
> Nói thẳng: **§56 không còn là "CI sẽ chứng minh"**. Bằng chứng hiện có là `check.sh` xanh; CI là bản sao để chạy ở nơi khác *khi bạn bật nó*.

### 56.10 Actions đã chạy xanh sau khi cập nhật billing (2026-11-08)

Người dùng vừa thêm phương thức thanh toán và yêu cầu thử lại. Trigger `workflow_dispatch` trên nhánh `arena/4117a3fc-arenaaiworkspace-1`.

| Run | Kết quả | Bằng chứng |
|---|---|---|
| `42451633095` | **success** | `test (ubuntu)` xanh 8 s; `build rd.exe (windows)` xanh 35 s; artifact `rd-windows-x64` được tạo |
| `42451848287` | **success** | `test (ubuntu)` xanh 18 s: **clippy**, **test**, `print pipelines` đều xanh; `build rd.exe (windows)` xanh 34 s: **build**, **smoke-run**, upload artifact đều xanh |

Run `42451848287` chạy trên commit `8047ed27adec07bea73fa23decb8026bd07e4d4b`. GitHub API xác nhận artifact `rd-windows-x64` tồn tại, 65,563 bytes, chưa hết hạn. Sandbox không tải được ZIP artifact (kết nối tới blob storage trả EOF); tuy vậy workflow log xác nhận build Windows, smoke-run và upload đều thành công. Không tuyên bố đã kiểm tra nhị phân tải về.

**Kết luận cập nhật:** billing đã được xử lý đủ để Actions cấp runner. Bằng chứng compile thật hiện có: CI chạy `clippy -D warnings` + test trên Ubuntu và build + smoke-run `rd.exe` trên Windows thành công. Không cần thay đổi workflow. Còn cảnh báo không chặn build: action `checkout@v4` nhắm Node.js 20 nhưng runner ép Node.js 24; `ubuntu-latest` sẽ chuyển sang Ubuntu 26.


### 56.11 Ngoài lề: `[CỨNG]` đang **23/20** — ngân sách §54.6 đã bị vượt 3

> §54.6 đặt luật: "CI đếm `[CỨNG]` **≤ 20** trên toàn spec". Đếm bằng `grep -o '\[CỨNG\]'` (2026-11-08): **23** — tức là **đã vượt 3** so với ngân sách. (§54.1 đếm 78 "luật cứng" theo *bảng*, không theo *nhãn*; con số 23 là con số §54.6 thực sự định nghĩa.)
>
> **Đây là vi phạm, không phải con số đẹp.** 3 chỗ phải hạ nhãn — đề nghị cụ thể, chưa làm vì cần bạn chọn: (a) "banner phải đúng 1 cái" (§49) → `[MỀM]`, vì 2 banner chồng là xấu chứ không mất dữ liệu; (b) "T1 đúng 12 mục" (§48.1) → `[MỀM]`, vì 13 mục không làm hỏng gì; (c) "không lưu tiêu đề cửa sổ" → **giữ `[CỨNG]`** (đây là quyền riêng tư, đúng loại), nên chỗ thứ ba phải là "restore đúng thứ tự §47.4" → tách làm 2 luật con thay vì 1 luật chung.
>
> Sau khi hạ 3 nhãn: **20/20**, không còn slot trống — nghĩa là từ đây mỗi `[CỨNG]` mới **phải** đổi lấy một cái cũ. Đó là ý của ngân sách, và cũng là lý do §57 **không** thêm luật cứng nào (§57 dùng hết 0 slot: cả 7 file đều hiện thực luật đã có nhãn từ §41/§54.5).
>
> §57 dùng hết **0** slot mới: cả 7 file `security/` đều là hiện thực của luật **đã** được đánh dấu `[CỨNG]` từ §41 và §54.5. Một chương mới không tự động đẻ ra luật cứng mới — đó là điểm của ngân sách.


### 57.9 CI bắt 3 lint mà sandbox không thể bắt — và cách đọc chúng

> Sandbox không có `clippy` (toolchain npm chỉ có rustc + cargo), nên `check.sh` **không thể** thay CI ở bước này. Lần push đầu tiên của §57 đỏ đúng ở `clippy`. Log job **không tải được** (blob storage trả EOF — đúng như §56.10 đã ghi), nên đã đổi bước CI để lỗi hiện thành **annotation**:

```yaml
- name: clippy
  run: |
    set +e
    cargo clippy --all-targets --message-format=json -- -D warnings > /tmp/clippy.json
    status=$?
    set -e
    jq -r 'select(.reason=="compiler-message") | .message
           | select(.level=="error")
           | "\(.spans[0].file_name):\(.spans[0].line_start): \(.message)"' /tmp/clippy.json \
      | sort -u | head -40 | while IFS= read -r line; do echo "::error::clippy: $line"; done
    exit $status
```

Ba lint thật, sửa trong một commit:

| Lint | Chỗ | Sửa |
|---|---|---|
| `chunks_exact` với chunk size hằng (clippy khuyên `as_chunks`) | `crypto.rs` nén SHA-256 | vòng `while` theo chỉ số — **không** phụ thuộc phiên bản toolchain, và ở đây còn ngắn hơn |
| doc comment treo lơ lửng trước `impl` | `window.rs` | chuyển vào doc của `enum WindowError` (nơi nó thực sự nói về điều gì) |
| `drain(..).collect()` | `input.rs` `release_all` | `std::mem::take` — **cùng một hành vi**, không cấp phát thêm |

> **Bài học, lần thứ ba trong repo này (§56.7, §56.9, §57.9):** thứ duy nhất tìm ra lỗi là **chạy cái gì đó**. Và khi log không đọc được, **đổi cách phát lỗi** (annotation) rẻ hơn nhiều so với đoán.
>
> Từ giờ bước `clippy` trong CI **không bao giờ** im lặng: mỗi lỗi là một annotation có `file:line`, đọc được bằng `gh api .../check-runs/<job>/annotations` — kể cả khi ZIP log bị chặn.


---

## 57. Tầng bảo mật **thành code có test** — `security.rs` (nhánh #38)

> §41 là chương **đúng nhất** của spec này: nó lật giả định nền (client không đáng tin), nó đẻ ra 5 quyết định kiến trúc, và nó có 14 kiểm chứng. Nhưng đến v3.27, cả 14 kiểm chứng đó **vẫn là chữ**. Chương này là lần đầu tiên chúng chạy.
>
> Kết quả ngắn: **100 test** (74 unit + 26 conformance), 0 dependency thêm, 10/14 kiểm chứng §41.10 tự động, và **4 chỗ spec tự mâu thuẫn được sửa** — trong đó 3 chỗ chỉ lộ ra khi phải viết code, không phải khi đọc lại.

### 57.1 Có gì trong `spike/src/security/` (7 file, 0 dependency)

| File | Luật **[CỨNG]** mà nó giữ | Spec | Test |
|---|---|---|---|
| `crypto.rs` | SHA-256 · HMAC-SHA256 · so sánh **hằng thời gian** · entropy | §41.6 | 5 |
| `auth.rs` | lockout 5/15′ · user lạ tốn **đúng một** KDF · policy mật khẩu 12 ký tự | §41.6, §5.8 | 11 |
| `token.rs` | access 15′ · refresh 7 ngày rotate · **reuse ⇒ chết cả chuỗi** · revoke-all chết **ngay** · `alg:none` bị từ chối | §41.6, §32.3 | 19 |
| `gate.rs` | **không TLS thì không bind ra LAN** · `X-Frame-Options: DENY` · không nhận token trong URL · mutation cần custom header · `/windows` 30/phút | §41.5 D4, §54.5 #1–2, T6, T18 | 12 |
| `window.rs` | client **không bao giờ** gửi `hwnd`; `wid` phải nằm trong snapshot agent vừa trả, TTL **3 s** | §41.4 **T1**, §41.5 **D1** | 6 |
| `input.rs` | clamp `u16` · chặn `Win+L` + SAS · `release_all` idempotent + **nhảy hàng** · watchdog **3 s** | §44.2, §44.8, §6.5.4 | 12 |
| `refresh.rs` | dọn tài nguyên **sau 5 s** (F5 không phá display) · display ảo **không** bị dọn | §42.13, §9.2.2 | 6 |

> **Vì sao 7 file chứ không 1:** mỗi file là **một** ranh giới lỗi. `window.rs` sai thì lộ cửa sổ; `input.rs` sai thì kẹt phím; `gate.rs` sai thì mất cả máy. Gộp lại thì một test đỏ không cho biết đang mất cái nào.

### 57.2 Bốn thứ chỉ lộ ra khi **chạy**, không lộ khi **đọc**

| # | Phát hiện | Nếu không viết test thì hậu quả |
|---|---|---|
| 1 | **Thứ tự kiểm `alg` ↔ chữ ký sai**: token `alg:none` + chữ ký rỗng trả `Malformed` thay vì `WrongAlg` | log bảo "token hỏng" trong khi thực tế là **một cuộc tấn công downgrade**. Vẫn bị chặn, nhưng **không nhìn thấy**. Đổi 2 dòng để mã lỗi nói đúng sự thật |
| 2 | `Session`/`Rotated` có `#[derive(Debug)]` ⇒ `{:?}` in **nguyên access + refresh token** | §41.10 #12 ("grep log ⇒ 0 token") **đỏ ngay** ở dòng log đầu tiên. Đã thay bằng `Debug` viết tay in `<redacted N chars>`, kèm test |
| 3 | `RevokedReason` không `Copy` ⇒ chỗ đọc `family.revoked` **move** ra khỏi reference | nếu chỉ sửa cho compile được bằng `.clone()`, mỗi lần kiểm token là một cấp phát — và kiểm token chạy **mỗi request**. Sửa bằng `Copy` |
| 4 | `Lockout` không có `Default`, `RateLimiter` không `Clone` | test đầu tiên không viết được ⇒ dấu hiệu API **không dùng được** ở chỗ khác. Thêm `Default`/`Clone` là sửa API, không phải sửa test |

> **Bài học lặp lại của §56.7:** cả 4 lỗi đều thuộc loại *"đọc thì thấy đúng"*. Assertion **rẻ hơn tranh luận**, và rẻ hơn review.

### 57.3 Mười kiểm chứng §41.10 giờ là test

| # | §41.10 nói | Test thật | File |
|---|---|---|---|
| 1 | `wid` lạ ⇒ 403 | `c1_wid_outside_the_returned_list_is_403` | conformance |
| 2 | `sid` người khác ⇒ 403 | `c2_someone_elses_sid_is_refused_on_every_route` | conformance |
| 3 | XSS qua tên cửa sổ | `the UI never injects server data through innerHTML` (+ **sửa một XSS thật**, §57.5) | `server.test.js` |
| 4 | CSRF thiếu custom header ⇒ 403 | `c4_post_without_the_custom_header_is_refused` | conformance |
| 5 | Clickjacking bị chặn | `c5_clickjacking_headers_are_present` + `responses_carry_clickjacking_headers` | conformance + app |
| 6 | Refresh reuse ⇒ revoke chuỗi | `c6_refresh_reuse_revokes_the_whole_chain` | conformance |
| 7 | Media chỉ TLS/DTLS | **không test được ở đây** — cần Wireshark + pipeline thật (§56.4) | — |
| 8 | Cert sai ⇒ hard fail | một nửa: `c8_tls_cannot_be_switched_off…` (không có đường tắt TLS). Phần "cert sai" thuộc OS/browser | conformance |
| 9 | `/windows` 100 req/s ⇒ 429 | `c9_windows_metadata_is_rate_limited_to_thirty_per_minute` (**30/phút** theo T18, xem §57.6 #2) | conformance |
| 10 | Fuzz REST/WSS/DC không panic | `garbage_never_panics` + `garbage_refresh_tokens_are_unknown_not_a_crash` (10 dạng input hỏng). **Chưa phải 1 triệu input** — đó vẫn là việc của P1 | token |
| 11 | Toạ độ ±2³¹ ⇒ clamp | `c11_coordinates_cannot_leave_the_screen_and_win_lock_is_blocked` — mạnh hơn clamp: toạ độ là `u16` ở **kiểu dữ liệu** | conformance |
| 12 | Log redaction | `c12_nothing_in_a_debug_rendering_leaks_a_token` + `debug_output_never_contains_a_token` | conformance + token |
| 13 | `config.json` hỏng ⇒ mặc định | **chưa** — thuộc `config.rs` (§56.6 **B**) | — |
| 14 | Bị Defender gắn cờ | **không test được** ngoài máy thật | — |

> **10/14 → 4 còn hở, và cả 4 đều đúng loại "chỉ máy thật trả lời được"** (#7 Wireshark, #13 `config.rs` chưa viết, #8/#14 thuộc OS). Không có kiểm chứng nào bị bỏ vì *khó viết test*.

### 57.4 Bốn chỗ code **cố ý** khác spec (và điều kiện quay lại)

> Đây là `security::DEVIATIONS` — danh sách này nằm **trong code** để không ai phải đoán, và `rd --demo` in nó ra mỗi lần chạy.

| # | Spec ghi | Code làm | Vì sao | Quay lại khi |
|---|---|---|---|---|
| **D-1** | JWT **RS256** | **HS256**, khoá ≥ 32 byte | RS256 cần crate RSA/ring ⇒ 2–6 dependency, đúng thứ §56.1 cắt. Cả hai đầu token đều ở **cùng một máy của bạn** ⇒ khoá đối xứng không mất tính chất nào | có client thứ ba không được giữ khoá ký |
| **D-2** | **argon2id** (m=64 MB, t=3, p=1) | **PBKDF2-HMAC-SHA256**, 210 000 vòng | argon2 cần crate + build C. PBKDF2 210k ≈ 100–200 ms trên i5-7300HQ — đủ chậm cho 1 người dùng, đúng NIST SP 800-132 | hash bị lộ (P7) hoặc có user thứ hai — record **đã lưu** `iterations` + `salt` nên migrate được tại chỗ |
| **D-3** | refresh **7 ngày** (vài chỗ ghi 30) | 7 ngày, **một** hằng số | hai con số trong spec là lỗi chép; 7 khớp §9.11 `refresh_days: 7` | — (đã sửa spec, không sửa code) |
| **D-4** | threat model giả định nhiều user/role | 1 user `owner`; **mọi** kiểm tra `sid.owner == sub` vẫn đầy đủ | §0.3.1 #4 cắt multi-user, nhưng phần kiểm quyền là thứ khiến "1 mật khẩu" vẫn an toàn khi **bất kỳ ai trong LAN** mở được URL (§41.3) | có user thứ hai — `role` đã có sẵn trong claims, không phải đổi schema |

> **Ranh giới của "0 dependency":** tự viết SHA-256/HMAC là **đúng** ở đây vì chúng là primitive có vector chuẩn (FIPS 180-4, RFC 4231, RFC 6070) và test đối chiếu vector — sai là đỏ ngay. Nếu ngày nào cần TLS, chữ ký số, hay constant-time crypto thật thì **phải** dùng crate đã kiểm định; dòng này để không ai tự viết tiếp.

### 57.5 Một **XSS thật** tìm thấy trong mock khi áp T5

> Test #3 của §41.10 bắt được lỗi trong **chính repo này**, không phải lỗi giả định.

| Trước | Sau |
|---|---|
| `$('#diagnosticsList').innerHTML = checks.map(item => \`…${item.title}…${item.output}…\`)` | `renderDiagnostics(checks)` — `createElement` + `textContent`, không một chuỗi HTML nào |
| Output là `Get-PnpDevice`, `Get-CimInstance`, `nvidia-smi`, **tên Wi-Fi**, tên app từ máy thật | như trên, nhưng đi qua `textContent` ⇒ `<img onerror=…>` trong tên thiết bị chỉ là **chữ** |

**Vì sao nó nguy hiểm hơn vẻ ngoài:** trang này là origin sẽ giữ **cookie refresh `HttpOnly`** (§41.6). XSS trong origin đó không đọc được cookie, nhưng nó **gọi API bằng cookie của bạn** — tức là tạo phiên, xem màn hình, điều khiển chuột. Đúng chuỗi T5 → A2.

**Test chặn tái phát** (`mock-server/server.test.js`): markup tĩnh thì `innerHTML` được phép; **mọi** object đến từ server (`item`, `check`, `result`, `report`, `device`, `session`, `window`) thì không bao giờ được nội suy. Grep 1 dòng, chạy 0.2 s.

Cùng lượt đó: **cả hai mock server** (Node và `lantern-mock.exe`) trước đây **không có** `X-Frame-Options`/CSP. Đã thêm, kèm test đọc header thật từ response — vì một mock thiếu header sẽ dạy sai người đọc, và sản phẩm thật bám theo mock.

### 57.6 Hai chỗ spec **tự mâu thuẫn** (đã sửa nhờ viết code)

| # | Mâu thuẫn | Sửa |
|---|---|---|
| 1 | §5.8 ghi "login **5/phút/IP**"; §41.6 ghi "**5 lần / 15 phút / (IP+user)**" | **Không mâu thuẫn** — hai **phạm vi** khác nhau: luật IP chặn dò **nhanh** (spray nhiều username), luật (IP+user) chặn dò **chậm**. Code giữ **cả hai**; §57.1 ghi rõ thay vì để người đọc tự đoán cái nào thắng |
| 2 | §41.10 #9 ghi "100 req/s `/windows` ⇒ 429"; §41.4 **T18** ghi "**30/phút**" | Đây là **hai đại lượng khác nhau**: 100/s là **tần suất tức thời** phải chịu được (burst), 30/phút là **ngân sách** của endpoint metadata. Code hiện thực **30/phút** (con số chặt hơn, và là con số có lý do: T18 nói về giám sát ngầm). 100/s phải được hiểu là "server không sập dưới burst", thuộc test tải P1 |
| 3 | §41.6 "refresh 7 ngày" vs. các chỗ ghi 30 ngày | 7 ngày — xem D-3 |
| 4 | §57.1 `input.rs` cần `block_win_l` từ config, nhưng §48 chưa có `config.rs` | Tham số **truyền vào hàm**, không đọc global. Khi `config.rs` (§56.6 **B**) ra đời thì nó chỉ việc truyền giá trị |

### 57.7 Trạng thái test (2026-11-08, sandbox)

| Bộ | Số test | Kết quả |
|---|---|---|
| `spike` unit + doc (`cargo test`) | **74** | xanh |
| `spike` conformance (`tests/spec_conformance.rs`) | **26** (16 cũ + 10 §41.10) | xanh |
| `lantern-mock.exe` (`app/`) | **8** | xanh |
| mock backend (`npm test`) | **2** | xanh |
| `cargo build` với `RUSTFLAGS=-D warnings` | — | **sạch** |
| `cargo clippy -D warnings` | — | **xanh trên CI** (run `42464776111`) — sandbox không có clippy, và CI đã bắt **3 lint thật** (§57.9) |
| `./spike/check.sh` | — | **all green**, ~1.5 s |
| CI đầy đủ | 2 job | run `42464776111`: `test (ubuntu)` **success** · `build rd.exe (windows)` **success**; artifact `rd-windows-x64` 87 461 B, `lantern-mock-windows-x64` 208 878 B |

> **Điều test này KHÔNG chứng minh:** nó không chứng minh app an toàn. Nó chứng minh **14 luật [CỨNG] đã được viết ra và không ai xoá được mà không thấy test đỏ**. Phần còn lại — TLS thật, cert, DTLS-SRTP, driver — vẫn phải làm và vẫn có thể sai.

### 57.8 Việc tiếp theo (cập nhật §56.6)

| # | Việc | Trạng thái |
|---|---|---|
| **A** | `security.rs` | ✅ **xong ở v3.28** (§57) |
| **B** | `config.rs` — schema + migrate + 12 mục T1 của §48 + round-trip test | **đề nghị tiếp theo**: giờ là chỗ duy nhất còn `unwrap` tiềm ẩn khi khởi động, và nó mở đường cho §41.10 #13 |
| **C** | `signaling.rs` — SDP/ICE state machine + `intent_id`/`rev` §32 | sau B |
| **D** | Client shell thật (không mock) — window picker + video + 2 thanh tự ẩn §29 | sau C |

> Tôi vẫn giữ thứ tự **B → C → D**. Lý do đổi so với §56.6: **A xong**; và `config.rs` giờ là thứ chặn nhiều việc nhất — không có nó thì mọi module sau phải nhận 30 tham số bằng tay, và đó là cách một spec 7 000 dòng biến thành một hàm 40 đối số.

---

## 58. Cái **dùng được ngay hôm nay**: MJPEG trong trình duyệt (nhánh #39)

> Câu bạn nói: *"mình muốn dùng thật trên máy, hóng quá"*. Đây là câu trả lời đúng nhất tôi có thể đưa ra **hôm nay**, không phải sau khi làm xong WebRTC.
>
> Nguyên tắc: **đi đường ngắn nhất tới "nhìn thấy máy thật trên máy thật"**, rồi mới nói rõ nó thiếu gì. Không hứa, không để bạn chờ một tính năng lớn rồi mới được nhìn thấy gì.

### 58.1 Vì sao MJPEG, không phải WebRTC trước

| | MJPEG (đã có ở v3.29) | WebRTC (chưa) |
|---|---|---|
| Dòng JS ở client | **0** (`<img src>` tự chạy) | ~600 (peer connection, SDP, ICE, DC) |
| Dependency mới | **0** | `webrtcbin` + DTLS + ICE stack |
| Dùng đúng đường capture của spec | ✅ cùng `d3d11screencapturesrc capture-api=dxgi` (§52.4) | ✅ |
| Kiểm được **ngay** trên laptop | ✅ | cần P0 xong trước |
| Độ trễ | ~150–300 ms | mục tiêu ≤ 80 ms LAN |
| Âm thanh | ❌ | ✅ |
| Điều khiển | ❌ | ✅ |

> **Điểm quan trọng:** MJPEG và WebRTC **dùng chung một chặng capture**. Nếu MJPEG hiện được hình thì `d3d11screencapturesrc` + adapter đúng đã chạy — tức là **một nửa P0 đã xong**, và phần còn lại chỉ là đổi chặng vận chuyển. Nếu MJPEG **không** hiện hình, làm WebRTC bây giờ cũng sẽ không hiện — sẽ khó tìm lỗi hơn nhiều.

### 58.2 Cấu hình cụ thể (và vì sao từng số)

```
d3d11screencapturesrc monitor-index=N capture-api=dxgi
  ! video/x-raw,framerate=15/1          ← chặn TRƯỚC d3d11download (bớt 50% frame đọc)
  ! d3d11download ! videoconvert        ← khỏi D3D11 memory, sang CPU
  ! video/x-raw,format=I420,width=1280,height=720
  ! jpegenc quality=70                  ← 70 = điểm "chữ còn đọc được"
  ! multipartmux boundary=lanternframe
  ! fdsink fd=1                         ← ra stdout; exe bơm vào socket
```

| Lựa chọn | Vì sao | Nếu làm khác |
|---|---|---|
| `framerate` đặt **trước** `d3d11download` | bỏ frame ở GPU, rẻ hơn nhiều | đặt sau ⇒ GPU vẫn đọc 60 fps rồi CPU mới bỏ — đúng lỗi tốn nhiệt §53.3 |
| 1280×720, không 1080p | JPEG 1080p15 tốn ~3× CPU mà nhìn không khác | 1080p ⇒ quạt chạy, hình vẫn thế |
| `jpegenc quality=70` | dưới 60 chữ nhoè, trên 80 tốn CPU vô ích | 90 ⇒ +40% CPU, không thấy khác |
| `capture-api=dxgi` | cùng đường §52.4, chọn được adapter trên máy hybrid | WGC không chọn được adapter (§52.4) |
| `fdsink fd=1` | không file tạm, không pipe shell, dừng là dừng | ghi file rồi đọc ⇒ trễ + đầy đĩa |
| Không `nvh264enc` | giữ dGPU ngủ (§53.2) | NVENC ⇒ dGPU thức, nóng, pin |

### 58.3 Ba thứ **phải** đúng, nếu không sẽ là lỗi im lặng

| # | Thứ | Nếu sai |
|---|---|---|
| 1 | `boundary` trong `Content-Type` **giống tuyệt đối** boundary trong pipeline | trình duyệt nhận byte, không vẽ gì, **không báo lỗi**. Test `the_content_type_boundary_matches_the_pipeline_exactly` giữ chỗ này |
| 2 | Header gửi **sau** frame đầu tiên | pipeline chết ngay ⇒ client treo vô hạn ở trạng thái "đang tải". Code chờ ≤ 64 KB đầu rồi mới trả 200; lỗi ⇒ `503` + stderr của GStreamer |
| 3 | Đóng tab ⇒ **kill** `gst-launch-1.0` | capture chạy mồ côi: nóng máy, tắt app vẫn còn tiến trình. **Luật này khó hơn vẻ ngoài của nó — xem §58.7–§58.9; bản đầu viết sai và đã để lại tiến trình mồ côi thật** |

> Cả ba đều là loại *"không thấy bằng mắt khi đúng, rất khó thấy tại sao khi sai"*. (1) và (2) có test từ đầu; (3) phải chạy thật bằng socket mới lộ ra **ba** lỗi riêng biệt — đó là toàn bộ nội dung §58.7–§58.9.

### 58.4 Trung thực về **cái không có**

Bản này **chỉ có hình**. Không tiếng, không điều khiển, không WebRTC, không đăng nhập, chỉ loopback (chưa TLS trong binary ⇒ §54.5 #1 cấm bind LAN). Chi tiết + cách xử lý từng cái: [`docs/run-on-windows.md`](run-on-windows.md).

**Vì sao vẫn đáng làm ngay:** nó trả lời đúng một câu hỏi mà mọi thứ khác phụ thuộc vào — *"máy này có capture được màn hình và gửi tới trình duyệt không?"* Trả lời "có" ⇒ P0 bước 3 đã xong. Trả lời "không" ⇒ ta biết phải sửa gì **trước khi** xây WebRTC lên trên.

### 58.5 Test (không cần GPU, không cần Windows)

| Test | Giữ cái gì |
|---|---|
| `the_pipeline_uses_dxgi_and_ends_in_a_pipe` | không rơi về WGC, không `fakesink`, không NVENC |
| `framerate_is_capped_before_download` | thứ tự `framerate` < `d3d11download` |
| `monitor_index_from_the_query_string_is_clamped_not_trusted` | `?monitor=99` ⇒ 8, không phải lỗi 500 |
| `the_content_type_boundary_matches_the_pipeline_exactly` | lỗi im lặng #1 |
| `the_stream_response_has_no_content_length_and_keeps_the_security_headers` | stream vô hạn + vẫn có `X-Frame-Options` |
| `the_live_page_never_renders_untrusted_input` | chỉ hai số đã clamp vào HTML |
| `live_status_is_honest_about_the_sandbox` | trên Linux phải nói "chỉ Windows", **không** giả vờ sẵn sàng |
| `--check` trong CI | route live tồn tại trong binary, không chỉ trong docs |

> **`probe_live_status()` là chỗ đáng chú ý:** nó biến "nút bấm được nhưng lỗi" thành "nút mờ + nói lý do cụ thể". Một app nói *"Chưa có GStreamer trong PATH"* tốt hơn một app hiện khung đen, và tốt hơn nhiều lần một app không có nút đó.

Bản v3.30 thêm **bốn test HTTP thật** — dựng server trên cổng ngẫu nhiên, đóng vai trình duyệt bằng `TcpStream`, và dùng một `gst-launch-1.0` giả (`LANTERN_GST`) để điều khiển pipeline. Chúng **không** mock `stream_live()`: request đi qua đúng `handle()`, đúng socket, đúng `ChildGuard`.

| Test | Giữ cái gì | Lỗi nó bắt được |
|---|---|---|
| `http_stream_kills_the_pipeline_when_the_tab_closes` | đóng tab ⇒ PID trong pidfile chết ≤ 3 s | §58.7 + §58.8 |
| `http_stream_returns_504_and_cleans_up_when_no_frame_arrives` | `504` < 6 s, giữ stderr, không để lại tiến trình | §58.9 |
| `http_stream_sends_multipart_headers_before_body` | 200 + đúng `Content-Type` + **không** `Content-Length` | hợp đồng với trình duyệt |
| `peer_closed_also_catches_an_rst_from_a_closed_tab` | RST tính là "đã đóng" | §58.8 |
| `stderr_is_read_only_after_the_child_is_gone` | đọc stderr sau kill, < 2 s | §58.9 |

> **Đếm tiến trình bằng PID, không bằng tên.** `ps | grep gst` trên CI có thể dính tiến trình lạ; script giả tự `echo $$ > pid` nên test chỉ hỏi đúng tiến trình của nó sống hay chết.

> **`probe_live_status()` là chỗ đáng chú ý:** nó biến "nút bấm được nhưng lỗi" thành "nút mờ + nói lý do cụ thể". Một app nói *"Chưa có GStreamer trong PATH"* tốt hơn một app hiện khung đen, và tốt hơn nhiều lần một app không có nút đó.

### 58.6 Ba lỗi chỉ hiện ra khi chạy thật

Đoạn code trên **qua hết unit test** mà vẫn sai ba lần. Cả ba đều vô hình trong test thường vì chúng chỉ xảy ra khi có một **tiến trình bên ngoài** và một **socket thật**. Ghi lại nguyên văn vì đây là dạng lỗi sẽ quay lại: nó không nằm ở logic của ta, nó nằm ở *hợp đồng với hệ điều hành*.

| # | Triệu chứng quan sát được | Nguyên nhân thật | Sửa |
|---|---|---|---|
| 1 | Đóng tab, `gst-launch-1.0` **vẫn chạy** | Chỉ kill khi `write_all` trả lỗi. Pipeline **im lặng** thì không có lần ghi nào ⇒ không có lỗi nào | Poll 250 ms + `peek` + `ChildGuard` (§58.7) |
| 2 | Sau khi sửa (1), vẫn còn 1 tiến trình | Trình duyệt đóng khi còn byte chưa đọc ⇒ OS gửi **RST**, không phải FIN; `peek` trả `Err`, mà code chỉ nhận `Ok(0)` | `Err` khác timeout ⇒ coi là đã đóng (§58.8) |
| 3 | Nhánh lỗi `504` **treo > 15 s** | Đọc `stderr` của tiến trình **còn sống** ⇒ `read_to_string` chờ tới khi nó thoát (có thể mãi mãi) | Kill + `wait` **trước**, rồi mới đọc stderr (§58.9) |

> Bài học chung, viết ra để lần sau không mất thêm một vòng: **một tiến trình con + một socket = ba trạng thái, không phải một.** "Đã đóng", "còn sống", và "không nói gì" là ba chuyện khác nhau; code nào chỉ xử lý hai trong ba thì sẽ để lại capture mồ côi hoặc spinner vô hạn.

### 58.7 Lỗi 1 — kill chỉ khi ghi lỗi là **không đủ**

Bản đầu của vòng lặp:

```rust
loop {
    match rx.recv() {
        Ok(chunk) => if stream.write_all(&chunk).is_err() { break; },  // "client đóng tab"
        Err(_) => break,
    }
}
```

Nó đúng **chỉ khi** pipeline liên tục đẩy frame. Nhưng `d3d11screencapturesrc` có thể im lặng rất lâu — màn hình tĩnh, DPMS tắt, dGPU ngủ (§53.4), hoặc người dùng chọn monitor không tồn tại. Khi đó:

1. Không có chunk nào ⇒ không có `write_all` ⇒ **không có lỗi**.
2. Client đã đóng từ lâu, nhưng ta không biết vì ta chỉ *ghi*, không bao giờ *hỏi*.
3. Tiến trình capture sống tới khi tắt app. Trên laptop: quạt chạy, pin tụt, và người dùng kết luận "app này hỏng".

Cách sửa gồm ba phần, thiếu phần nào cũng hỏng:

| Phần | Vì sao cần |
|---|---|
| `recv_timeout(POLL)` thay `recv()` | để vòng lặp **thức dậy** kể cả khi pipeline không nói gì |
| `peer_closed()` bằng `peek` | hỏi thẳng socket "đầu bên kia còn đó không", **không** lấy mất dữ liệu |
| `ChildGuard` (Drop ⇒ `kill` + `wait`) | mọi đường ra — kể cả `return` sớm ở nhánh `504` — đều dọn tiến trình |

`ChildGuard` là phần dễ bỏ qua nhất và cũng là phần quan trọng nhất: nó biến việc dọn dẹp từ *"nhớ gọi ở mọi nhánh"* thành *"không thể quên"*.

### 58.8 Lỗi 2 — FIN và RST là hai kiểu đóng khác nhau

Sau khi sửa §58.7, bài test bằng socket thật **vẫn** thấy tiến trình còn sống. Đoạn mã khi đó:

```rust
matches!(stream.peek(&mut probe), Ok(0))   // "chỉ Ok(0) là đã đóng"
```

Đó là định nghĩa của **FIN** — đóng bình thường, hết dữ liệu. Nhưng trình duyệt đóng tab **khi trong buffer còn frame chưa vẽ** thì hệ điều hành gửi **RST**: kết nối bị huỷ, không phải kết thúc. `peek` trả `Err(ConnectionReset)`, và biểu thức trên trả `false` ⇒ "client còn sống" ⇒ pipeline chạy mãi.

Bảng đúng phải là bốn dòng, không phải một:

| `peek` trả | Nghĩa | Kết luận |
|---|---|---|
| `Ok(0)` | FIN — đóng bình thường | **đã đóng** |
| `Ok(n>0)` | có byte đến (đường này client không gửi gì) | còn sống |
| `Err(kind)` khác `WouldBlock`/`TimedOut` | **RST**, `ECONNRESET`, … | **đã đóng** |
| `Err(WouldBlock \| TimedOut)` | 200 ms không có gì | còn sống |

> **Vì sao unit test không bắt được:** test cũ đóng socket **sạch** (`drop` sau khi hai bên đã trao đổi hết) ⇒ luôn ra FIN. Chỉ khi phía server còn dữ liệu chưa gửi xong mà client bỏ đi thì mới ra RST — đúng thứ xảy ra với MJPEG 15 fps. Test mới `peer_closed_also_catches_an_rst_from_a_closed_tab` dựng đúng tình huống đó: server ghi 4 KB mà client không đọc, rồi client đóng.

### 58.9 Lỗi 3 — đọc `stderr` của tiến trình đang chạy là **chờ nó chết**

Nhánh "pipeline không trả frame" cần lời giải thích của GStreamer, nên nó đọc `stderr`:

```rust
let text = BufReader::new(stderr).read_to_string(&mut text);  // ❌ chờ EOF
```

`read_to_string` đọc **tới EOF**, mà EOF chỉ đến khi tiến trình đóng `stderr` — tức là khi nó **thoát**. Với `gst-launch-1.0` bị treo (chờ frame mãi, hoặc lỗi DXGI giữ pipeline sống), người dùng thấy: bấm nút → spinner → **không có gì**, mãi mãi. Đo được: `curl` bỏ cuộc ở 15 s, server chưa gửi byte nào.

Cách sửa: **kill trước, đọc sau.**

```rust
fn take_stderr_after_kill(&mut self) -> String {
    let _ = self.0.kill();
    let _ = self.0.wait();          // chắc chắn đã chết trước khi đọc
    let mut text = String::new();
    if let Some(stderr) = self.0.stderr.take() {
        let _ = BufReader::new(stderr).read_to_string(&mut text);   // giờ EOF đến ngay
    }
    text
}
```

Đo lại: `504` trong **8.0 s** (đúng bằng `FIRST_FRAME_TIMEOUT`), body là thông báo lỗi thật của GStreamer, và không còn tiến trình nào sót lại.

> **Một chi tiết nhỏ nhưng là cái bẫy:** kill ngay lập tức có thể đến *trước khi* GStreamer kịp ghi lỗi ra stderr — test `stderr_is_read_only_after_the_child_is_gone` đỏ vì đúng lý do đó (nhận về chuỗi rỗng). Trong luồng thật điều này không xảy ra vì ta đã chờ 8 s trước khi kill; test phải mô phỏng đúng thứ tự (chờ 150 ms) thay vì đòi hỏi một hành vi mà code không hứa.

### 58.10 Bảng "đã kiểm bằng gì"

Sòng phẳng về mức độ tin cậy của từng phần — vì "test xanh" không có nghĩa "chạy được trên laptop của bạn":

| Phần | Kiểm bằng | Tin được đến đâu |
|---|---|---|
| Tham số pipeline (DXGI, thứ tự, fps) | unit test so chuỗi | **cao** — đúng chuỗi sẽ chạy trên Windows |
| Header/status/`boundary` | test HTTP thật (socket) | **cao** — đúng byte trình duyệt nhận |
| Đóng tab ⇒ kill pipeline | test HTTP thật + PID | **cao** — đúng cơ chế, không phụ thuộc GStreamer |
| `504` khi không có frame | test HTTP thật + `gst` giả | **cao** cho phần bọc; **trung bình** cho nội dung lỗi (tuỳ GStreamer) |
| Hình ảnh thật từ DXGI | **chưa ai kiểm** trong sandbox | **0** — cần máy Windows của bạn |
| Chất lượng/độ trễ MJPEG thật | **chưa ai kiểm** | **0** — §6.2.3 không áp dụng cho MJPEG, xem `docs/run-on-windows.md` |
| Âm thanh, chuột/bàn phím, TLS, LAN | **không có trong bản này** | — |

> Dòng thứ năm là dòng quan trọng nhất. Toàn bộ §58 tồn tại để **giảm** phần "chưa ai kiểm" đó xuống còn đúng một lần bấm nút trên máy bạn — không phải để tuyên bố nó đã xong.
