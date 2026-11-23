# Chain kỹ thuật phối hợp các tính năng có sẵn

Tài liệu này mô tả các **chain** mới ngoài `Deauth + Clone + Verify`. Mỗi chain chỉ **điều phối** những API `Start/Stop/IsRunning/GetStateJson/Export` đã có sẵn; không tự phát sóng hay copy lại logic member.

> Nguyên tắc: một tính năng — một chỗ vào (Feature Guide / menu cũ giữ nguyên). Chain chỉ xuất hiện ở `WiFi → Chains`, `seclab chain …` và `/seclab/action` (chain_start/stop/auto) và `/seclab/status.chain`.

---

## Tổng quan 7 chain

| ID | Tên hiển thị | Phối hợp | Mục đích |
|---|---|---|---|
| `recon-capture` | Recon → Capture | Probe Radar + 2.4 GHz Analyzer → PMKID / CSA | Chọn mục tiêu tốt nhất từ `/wifi_airtime.json` (bestCh + hidden decloaked) rồi bắn PMKID/CSA. |
| `napt-lan` | NAPT → LAN | NAPT Router → LAN Auditor (deep) + HTTP Inspector (3128) + Responder+ | Khi NAPT đã lên, quét LAN/IoT đầy đủ và giám sát HTTP/Cred. |
| `portal-lan` | Portal → NAPT → LAN | Evil Portal → NAPT handoff → LAN Guard + HTTP Inspector | Khách vào portal xong vẫn bị Guard/Inspector theo dõi. |
| `guard-audit` | Guard → Audit | LAN Guard (ARP/DHCP alert) → LAN Auditor (deep) + export | Khi Guard thấy ARP_CHANGE/DHCP_MISMATCH, tự động audit sâu và ghi `/chain_guard_audit.log`. |
| `ble-pipeline` | BLE Guard → Audit → Clone | BLE Privacy Guard (`/ble_guard.log`) → Pairing Audit → GATT Explorer/Clone | Lấy candidate từ Guard log (hits→RSSI) rồi audit pairing, xong mở GATT clone. |
| `usb-verify` | USB Generate → Verify | Smart BadUSB Generate → Arm LED Link → Run Payload → Verify/Export | Tạo payload theo OS profile, chờ LED Link decode → xem `/led_link/export.json`. |
| `sonar-evidence` | Sonar → Evidence | Sonar Guard (`/sonar_state.json`, `/BruceMIC/guard_*.wav`) → Bundle | Gom log + số clip WAV thành `/chain_sonar_evidence.json`. |

Mỗi chain là dãy `ChainStep {tool, action}` (`chain_logic.h:chainSteps()`). Trạng thái tổng hợp ở `/chain_state.json` và `/chain.log` (csv: `uptimeSec,chain,step,ok,detail`).

---

## Recon → Capture — chọn mục tiêu

1. **Observe**: Probe Radar ghi `/probe_radar.json` (PNL, MAC rotations, OS hint); Analyzer ghi `/wifi_airtime.json` (load/peak/retry/RSSI/cleanScore, `bestCh/bestScore`, `hidden[]` decloaked).
2. **Pick**: `chainParseHiddenTargets()` đọc `hidden[]` (bssid/ch/rssi/decloaked/ssid) và `chainScoreTarget()` tính `128−rssi + cleanScore + (decloaked?50:0)`. `chainPickBestTarget()` chọn điểm cao nhất.
3. **Capture**: `pmkidStart(bssid, ssid, channel)` hoặc `csaStart(..., newCh=csaChannel, bursts=csaBursts)`. Trên menu cho chọn Portal → PMKID hay CSA, trên CLI/WebUI mặc định PMKID.

Không có snapshot → báo “chạy Analyzer trước”. Logic thuần trong `chain_logic.h` nên test được trên host mà không cần radio.

## NAPT → LAN — tự động sau NAPT

- **Trigger**: NAPT Router `start` thành công (STA đã lên hoặc AP-only). Watcher (task `chainWatch`, 2s) thấy `naptIsRunning()` và flag `chainNaptLanAuto==ON` thì gọi `lanAuditStart(true)`, `naptHttpInspectorStart(0)`, `responderPlusStart()`.
- **Stop**: chỉ dừng LAN members, giữ NAPT để không rớt client. Có toggle `seclab set chainNaptLanAuto on|off` và `seclab chain auto napt-lan on|off`.

## Portal → NAPT → LAN — tương tự

- Khi `portalNaptIsRunning()` và `chainPortalLanAuto==ON`, watcher tự arm `lanGuardStart()` + HTTP Inspector. Cần STA hoặc đã có NAPT; nếu thiếu, chain báo precondition.

## Guard → Audit — alert → deep audit

- Guard chạy nền, đếm `arpChanges + dhcpMismatch` (fallback `rogueDhcp`). `chainGuardAlertCount()` đọc `/lan_guard_state.json`-style JSON.
- Watcher lưu `s_lastGuardAlerts`; khi count tăng, `fireGuardAudit()` gọi `lanAuditStart(true)` + `lanAuditExport()` và ghi `chainGuardAuditSummary()` (“guard alerts=… | lan devices=… findings=…”).
- Có thể để Guard chạy riêng; chain chỉ là “khi Guard kêu thì audit”.

## BLE Guard → Audit → Clone

1. BLE Privacy Guard (passive scan, classify Tile/SmartTag 0xFEED/0xFD5A/0xFCF1) ghi `/ble_guard.log` dạng `Kind | MAC | addrType | RSSI | sweeps | age`.
2. `chainParseBleGuardCandidates()` parse, sort hits↓ rồi RSSI↓; pick top candidate.
3. `blePairingAuditStartAsync(mac, addrType)` (tôn trọng `blePairAuditJustWorks`).
4. GATT Explorer/Clone (`ble_gatt_cloner_setup()`) là bước menu-blocking (interactive).

Menu BLE vẫn giữ nguyên; chain chỉ thêm shortcut “Guard scan xong → audit luôn”.

## USB Generate → Verify

- Generate tạo Ducky Script + payload theo `SmartBadUsbGetOsProfile()` và `badUsbPermissionCheck`.
- Arm LED Link (`smartBadUsbStartLedLink`) bật receiver Output Reports; Run Payload cắm USB vào host.
- Verify kiểm tra `smartBadUsbGetLedLinkStateJson()` có `phase:DONE` và export `/led_link/export.json`. Các bước đều là API cũ, chain chỉ xếp thứ tự và log.

## Sonar → Evidence

- Sonar Guard (full-duplex I2S 48kHz) ghi `guard_*.wav` + `/sonar_state.json` + `/sonar_guard.log` (menu-blocking).
- Chain ở chế độ headless chỉ **bundle**: đọc hai snapshot, đếm số wav trong `/BruceMIC/`, ghi `/chain_sonar_evidence.json`.

---

## Tự động hoá (watcher) và cài đặt

- Ba flag mới trong `SecLabPlusSettings`: `chainNaptLanAuto`, `chainPortalLanAuto`, `chainGuardAuditAuto` (mặc định OFF, lưu trong `bruce.conf: seclabPlus`).
- `chainWatcherEnsure()` tạo task 4 KiB khi có flag ON; không tạo ở LITE. Các flag cũ (`portalNaptHandoff`, `lanGuardAutoArm`, `httpInspectorAutoStart`, …) vẫn dùng riêng cho member.
- CLI: `seclab chain list|status|start <id>|stop <id>|auto <which> [on|off]` và `seclab set chainNaptLanAuto|chainPortalLanAuto|chainGuardAuditAuto`.
- WebUI: `/seclab/status` thêm `chain:{active,lastChain,uptimeSec,lastErr,auto:{…},chains:[{id,title,running}]}` và `plus.chain*Auto`; `/seclab/action` thêm `chain_start|chain_stop|chain_auto`.

## Precondition và an toàn

- `chainCheckPreconditions()` kiểm tra `radioHasMemForWifi/Ble`, `USB_as_HID+CONFIG_TINYUSB_HID_ENABLED`, `HAS_MICROPHONE`. Thiếu thì trả `ChainBlock` có `chainBlockReason()` hiển thị cho user (“Low DMA RAM…”, “USB HID not enabled…”).
- Mọi bước tôn trọng exclusive radio: `cleanlyStopWebUiForWiFiFeature()`, `radioFreeBleForWifi()` đã nằm trong member Start.
- Evidence chỉ là **observation**; Chain Guide trong Feature Guide nói rõ “observations are not proof of an attack”.

## Test

- `tests/chain/run.sh [patched-Bruce-path]` — host test cho `chain_logic.h` (ASan+UBSan): scoring, JSON readers, airtime hidden[], BLE guard sort, guard count/summary, preconditions/watcher, fuzz random bytes.
- Đã chạy: `tests/chain/run.sh /tmp/Bruce` và `…/firmware/Bruce` đều pass. Các test cũ (lan-guard, radio-observation, …) không bị ảnh hưởng.

## File thay đổi

- `src/modules/wifi/chain_logic.h` (mới, Arduino-free) + `src/modules/wifi/chain_orchestrator.h/.cpp` (điều phối, menu, watcher, headless start).
- `src/core/config.h/.cpp` (3 flag chain auto), `src/core/menu_items/WifiMenu.h/.cpp` (+ `Chains` menu), `src/core/serial_commands/seclab_commands.cpp` (chain CLI), `src/core/wifi/webInterface.cpp` (chain status/action).
- `firmware/dsolution-183-2mic-bruce.patch` đã regenerate gồm toàn bộ trên.
