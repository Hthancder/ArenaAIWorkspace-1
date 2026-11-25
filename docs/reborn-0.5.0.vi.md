# Báo cáo triển khai 0.5.0-preview.1 — 2026-11-12

## Phạm vi giao

Triển khai theo [SPEC](implementation-spec-aim-esp.vi.md), không chỉ đổi tên menu. Đây là **preview source-verified, không phải nghiệm thu toàn bộ SPEC hoặc live gameplay**. P0/P1/P2/P4 có code và tests; P3 còn điều kiện chất lượng/đo lường chưa đạt đủ. P5 đóng theo final check/package/push thực tế.

Original reference giữ nguyên. Không cần chạy npm để dùng file cài [`userscripts/duality-reborn.user.js`](../userscripts/duality-reborn.user.js).

## Source → implementation → evidence

Pin: [survev/survev@3edee7e8bd07fda8a63905aab4c45b595b684a80](https://github.com/survev/survev/tree/3edee7e8bd07fda8a63905aab4c45b595b684a80), protocol1028. Các line numbers dưới đây tham chiếu pin, không phải live deployment.

| Source thực | Code mới | Bằng chứng |
|---|---|---|
| client game.ts471–564,733–770: native input direction/normalize/diff/timeout/send/prevInput | `features.mjs` sender coordinator + scheduler, `aim-adapters.mjs` | Source runner thực thi statement slices native; moving target/fixed cursor; original prevInput không bị clone sửa; disable restore |
| shared inputMsg.ts + net.ts/bitBuffer.ts: 10-bit mỗi thành phần x/y | Source runner dùng actual InputMsg và BitStream, normalize hướng sau decode | Assert wire direction/Fire/movement, không chỉ assert helper hoặc mouse mutation |
| game.ts410–447: camera/zoom cập nhật sau playerBarn | Recompute world solve tại sender, tách input từ render projection | Native source-frame đổi zoom giữa pre và input; wire vẫn đúng world angle |
| game.ts1056–1149 + player.ts502–552: ACK và full/partial objects apply | RX hook sau native receiver; net field AST discovery; `SnapshotTracker`, `NetworkTiming` | Receiver chạy source thường/renamed; offline only-updated-position IDs, delete/reuse/layer/gaps, no render samples |
| weaponManager.ts738–949; bullet.ts190–205,228–265; perkDefs.ts128–158 | `weaponProfile`, solver/muzzle clipping, range variance−jitter margin, toMouseHit inverse | Unit nominal/perk/dual-approx, intercept physical residual, clipping eligible obstacle heights/floors; không đoán aimDelay/fireDelay |
| server player.ts2273–2289; client structure.ts114–136; server structure.ts75–98 | `aim-geometry.mjs`: real client stair collision/downDir → cardinal layer | Stair direction tests. Không đòi client có downOri/upOri: các field đó chỉ server có |
| player.ts59–79,849–857: TextStyle fill cyan, native name và visibility | `native-names.mjs` | Blue/red fill thay trực tiếp, unknown native; latest visibility/ownership/recycle cleanup; không đổi text hoặc dựng TextStyle mỗi tick |
| Input enum shared gameConfig.ts57–94 | Manual equip11–20, Stow27, Swap28; không xem scope21/22 là weapon change | Final-input combination tests, manual equip trong pending switch/melee |
| Native cooldown/Fire and smoke/minimap semantics đã có ở0.4.0 | Giữ RepeatFire, WeaponSwitch, SmokeBarn/Map adapters | Source smoke update, native server WeaponManager melee cooldown, minimap methods tiếp tục pass |

Runtime chỉ parse syntax/data flow tại discovery, không eval upstream source hoặc tạo Proxy gọi thử game methods. Source runner riêng mới transpile/evaluate method slices trong VM inert cho kiểm thử.

## Input/feature consistency

- Native InputMsg là intent. Outgoing clone giữ prototype và arrays/vectors riêng; không thay movement/Fire/equip ngoài authority tương ứng.
- Aim không giữ/delay Fire để chờ Lock. Assist0 nhường hoàn toàn; Lock lưu controller angle theo thời gian; off/release/lost target yêu cầu native restore ngay cả stationary cursor.
- Actual equipped profile, không profile từ requested slot. Melee authority hủy pending Switch; một equip trong message, native capacity giữ nguyên. Chờ melee confirmation thay vì gửi EquipMelee mỗi frame. Manual equip không bị tự giành lại trong cùng Fire hold.
- Semi pulse không trở thành physical activation của Aim/Switch. Loot command không mất bởi aim/equip; scope inputs không bị nhầm thành weapon change.
- Mobile và Melee chỉ một movement authority. Release không coast; native input không bị sửa.
- Gameplay dùng source layer; layer spoof là preview. Stair direction có tính ở nominal shot; không hứa mô phỏng mọi stair transition giữa input và server tick.
- Canvas lỗi được cô lập khỏi names/zoom/input. Config changes không clear overrides unrelated. Blur/typing/menu/emote/dead/downed/spectator/hidden pause automation, không nuốt native Fire.

## ESP/menu

Không còn upper-left squad HUD hoặc Canvas name labels/legend/tag boxes. Legacy flags bị migrate off. Native name colors cố định blue/red; unknown giữ native; không nhân red tint lên cyan. Lines hoạt động riêng và default off, dot default off.

Main/Visuals/Misc/Keybinds/Help giữ nguyên, nhóm details; Assist và Lock chỉ hiện controls đúng mode; prediction advanced đóng mặc định, setting phụ theo parent. Range input không rerender toàn panel/mất focus. Off vẫn chọn được khi contract chưa có; missing contract khóa các mode can thiệp. Details open-state giữ khi đổi mode/capability.

## Kiểm thử đã chạy

```sh
npm run check
npm run check:upstream -- /home/user/survev-reference
node scripts/benchmark-aim.mjs --write
git diff --check
git diff --quiet HEAD -- references/duality-client.reference.js
```

- **122/122 offline tests pass**, không skipped. Các tests cũ assert mouse mutation/label tags đã được chuyển thành assertion semantics mới, không giữ assertion sai hoặc xóa coverage đơn thuần.
- **4/4 expanded source-method scenarios pass:** unminified và minify+rename `m_*`, mỗi kiểu có mobile/nearby loot. Mỗi scenario chạy receiver, native scheduling và wire roundtrip, Lock/Assist/camera/restore, smoke, melee cooldown và minimap.
- Build readable, syntax check pass. Reference diff rỗng.

Source harness không chạy toàn bộ Game.update/render/network/server physics. Nó dùng actual source input statements, input class/bitstream/receiver và các methods đã liệt kê, với collaborator fixtures và socket inert. **Không gọi đây là full live E2E.** Normalize sau decode theo server semantics, không khởi động server hoặc anti-cheat.

## Benchmark — kết quả không chỉ zigzag

[Report đầy đủ](aim-benchmark.vi.md), reproducible bằng `npm run benchmark:aim`.

Diagnostic/calibration seeds:7301/99173/441019. Sau sửa confidence, frozen solver được chấm trên **held-out1847/82031/517991**; không thêm maneuver classifier/acceleration hoặc tune lại theo holdout.

12 nhóm gồm đứng yên, thẳng/chéo, tới–xa, bắt đầu/dừng, cong,90°/180°, đổi tốc độ, zigzag không đều, mixed và wall-stop/sliding. Render30/60/144Hz; snapshots33Hz regular và jitter/gap/backlog **đúng thứ tự WebSocket**. Quantization16-bit/1024. Baselines no-predict, legacy render-tracker và simple CV. Mỗi model/category12540 frames; fallback không bị loại khỏi điểm.

Một số số liệu (world units):

| Nhóm | Legacy median / p95 | Snapshot median / p95 |
|---|---:|---:|
| Straight |1.455 /9.219 |0.388 /3.139 |
| Diagonal |1.665 /10.456 |0.402 /5.594 |
| Curve |2.964 /7.770 |2.573 /6.646 |
| Speed-change |4.736 /14.533 |4.502 /12.800 |
| Mixed |3.403 /11.428 |3.285 /11.389 |
| Start-stop |4.965 /8.685 |**6.050** /8.317 |
| Reverse180 |4.731 /16.448 |**4.835 /17.043** |

Không giấu regression: start-stop median kém khoảng1.085wu; reverse180 median/p95, approach-retreat p95 và turn90 p95 vẫn kém. Tương lai đổi hướng trong thời gian bay vốn không thể suy ra chắc chắn, nhưng điều đó **không** đủ để đánh dấu nghiệm thu hết tiêu chí chất lượng. Không tối ưu riêng zigzag; zigzag median gần như ngang legacy, p95 có cải thiện.

Fit residual và slope uncertainty có đơn vị riêng. Confidence thấp giảm **flight lead**, solve lại TOF thực; trạng thái `reduced-lead-uncertainty` và `aimApproximate` phản ánh điều đó. Stale>150ms nhường native, không cắt TOF hay âm thầm vẫn gọi là exact prediction.

## Phần còn mở — không tự đánh dấu xong

1. **P3 quality:** cần đánh giá/giảm regression start-stop và đảo hướng trên dataset calibration khác rồi chấm holdout mới. Không thêm shortcut đoán zigzag.
2. Recovery trong report hiện là **proxy**, không phải first sustained reacquisition; selection churn/stale decisions đa mục tiêu chưa có benchmark riêng. Sticky/membership/lifecycle có assertion, nhưng không thay thế các metric đó.
3. CPU trong report chỉ đo solver Node (p95 vài microsecond trong run này), không phải browser feature-frame cost/FPS hoặc so baseline toàn engine. Chưa có measured game-frame benchmark.
4. Weapon random spread/recoil/shotgun jitter và empowered45 là bất định. Dual next-hand không có pre-shot source state chắc chắn nên dùng central approximation có flag; không bịa next-shot metadata. Range dùng conservative jitter margin; toMouseHit vẫn chịu native clamp64 và random range adjustment.
5. Native muzzle/stair methods chưa được trích chạy toàn server collision suite; hiện unit geometry đối chiếu source, source receiver/input wire tests và lifecycle combinations. Không hứa mọi corner/stair/pan/destructible/ricochet giống server.
6. Traffic scheduler so nominal angle0.1° và length0.5 theo source; BitStream quantization được roundtrip-test, chưa benchmark packet-rate toàn trận thực tế.
7. Chưa test live. Những hạn chế trên là phạm vi bằng chứng, không lý do trì hoãn sửa source-backed bugs đã triển khai.
