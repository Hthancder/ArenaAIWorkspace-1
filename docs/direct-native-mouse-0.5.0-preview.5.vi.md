# 0.5.0-preview.5 — direct native mouse input

Ngày: 2026-11-12  
Phạm vi: desktop/local player path đã được audit trong source pin `survev@3edee7e8bd07fda8a63905aab4c45b595b684a80`, protocol **1028**. **Chưa xác nhận gameplay live trên máy người dùng.**

## Vấn đề

Aim correction trước đây nằm ở sender InputMsg: packet đi đúng hướng, nhưng các đoạn native cùng frame vẫn đọc `input.mousePos` gốc. Với desktop/local rotation, gun/player presentation có thể tiếp tục bám cursor thật, tạo cảm giác “aimbot không tác động” hoặc lệch giữa packet và hướng súng.

## Thay đổi

- Direct native mouse input **mặc định bật**, có control `Aim — Mode & activation → Direct native mouse input` để tắt.
- Trong `pre`, sau khi chọn target/solution, script ghi tạm **cùng aim plan** vào native `input.mousePos` cho đúng frame hiện tại. Game `update`, native input construction và local `Player.updateRotation` cùng thấy correction thay vì packet sửa riêng.
- FOV, sticky và candidate selection vẫn đọc intent vật lý đã được giữ riêng. `Assist` không bị feed lại output đã sửa như thể đó là intent người dùng; `Lock` chỉ advance một lần mỗi frame.
- Bán kính vật lý từ tâm màn hình được giữ nguyên; chỉ hướng và, khi weapon `toMouseHit`, khoảng cách native được đổi. Sau zoom native thay đổi, sender vẫn là lớp giải quyết cuối và có thể recompute world direction.
- Restore trước native `input.flush()`, ở `post()`, menu/blur/hidden, config change, release/match teardown và Stop. Chỉ ghi lại coordinate mà frame còn sở hữu; writer khác chạy sau không bị clobber.
- Không tạo DOM mouse event, Pointer Lock, warp OS cursor, chặn selection, hay global/browser mouse interception. Native network path vẫn là đường gửi duy nhất; không phát packet riêng/fake user gesture.
- Nếu thiếu `flush` contract hoặc descriptor `mousePos.x/y` không hỗ trợ, direct route fail đóng (`skippedFrames`, no partial mutation). Sender correction hiện có vẫn được phép chạy để tránh mất toàn bộ aim.

Diagnostics mới: `mouseInput = { enabled, flushReady, active, appliedFrames, skippedFrames }`. Đây chỉ là trạng thái local aggregate, không chứa packet, vị trí, hướng, ID hoặc tên người chơi.

## Anti-ban — giới hạn rõ ràng

Bản này **không phải anti-ban và không tuyên bố tránh được hệ thống chống gian lận/ban**. Không có kỹ thuật “tầng sâu” nào trong bản này conceal, disable, bypass hay sửa đổi anti-cheat của game; cũng không có bảo đảm an toàn khi dùng trên máy chủ công cộng.

Những gì được làm để giảm rủi ro thao tác và không phá trải nghiệm:

- scoped frame transaction thay vì global input interception;
- raw physical intent được phục hồi trước native flush/end-frame;
- không synthetic DOM event hoặc cursor thật bị dịch chuyển;
- không ép/cooldown/Fire/movement, không packet ngoài native sender;
- fallback fail-closed và cleanup theo ownership;
- diagnostics chỉ aggregate, bounded, không export dữ liệu người chơi/packet.

Đây là giảm bề mặt can thiệp/lỗi có thể quan sát ở phía client, không phải làm aimbot “giống người”, không phải randomization giả tạo và không phải bằng chứng hệ thống chống gian lận không phát hiện được.

## Kiểm chứng

- `npm run check`: **148/148 PASS**.
- `npm run check:upstream -- .cache/survev`: **4/4 source scenarios PASS**.
- Source scenario chạy trực tiếp source `updateRotation`, native desktop mouse expressions, BitStream roundtrip, stationary cursor moving target, flush restore và enable/disable.
- Unit/integration tests bao phủ physical intent separation, radius preservation, `toMouseHit` bound, newer writers, input-vector replacement, unsupported descriptors, opt-out, diagnostics, and single Lock advance per frame/sender cache.

## Cách thử

1. Cài `userscripts/duality-reborn.user.js` **0.5.0-preview.5**, disable/remove script cũ, reload page-world, Right Shift mở menu.
2. Aim Mode Lock, Activation Fire; giữ Fire với enemy trong FOV và quan sát body/gun/crosshair, không chỉ packet diagnostics.
3. Diagnostics nên hiển thị `mouseInput.flushReady=true`, `active=false` sau frame và `appliedFrames > 0`; `aimEvidence.lastLiveAttempt.state='input-applied'`.
4. Tắt `Direct native mouse input` nếu muốn so sánh hành vi sender-only cũ.
5. Gửi diagnostics JSON nếu vẫn thất bại; không chụp packet/token. **Chưa có live confirmation.**
