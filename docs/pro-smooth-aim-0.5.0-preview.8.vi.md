# 0.5.0-preview.8 — Aim profile: critically damped SmoothDamp

Ngày: 2026-11-12  
Phạm vi: Aim — Mode & activation, Lock smoothing. **Chưa xác nhận gameplay live trên máy người dùng và đây không phải anti-ban.**

## Người dùng yêu cầu

Thêm smooth tốt, “như mình bắn thật”, mượt/pro, tham khảo Survev và các game/implementation khác.

Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80` không có thuật toán “human aim” chiến đấu tích hợp để copy; source chỉ dùng smoothing cho UI/visual interpolation (ví dụ smoothstep/UI fade) và nhập trực tiếp cho weapon/mouse path. Bản này vì vậy dùng thuật toán game-feel phổ biến, không claim là code Survev hay một luật anti-detection.

## Thuật toán được chọn

**Critically damped angular SmoothDamp** (“Game Programming Gems-style”), thay vì chỉ `angle += delta * (1-exp(-dt/tau))`:

- ease-in ở đầu và ease-out/decelerate ở cuối;
- không overshoot khi initial angular velocity = 0;
- frame-rate independent;
- giữ angular velocity xuyên frame, nên chuyển mục tiêu trơn;
- shortest-arc angle, reset velocity khi target/mode bị mất hoặc stale >250ms;
- bounded dt (gốc tối đa 50ms/frame) để tránh nhảy sau frame drop;
- profile thiên hướng **experience/comfort**, không random, không giả micro-noise, không nhằm lừa anti-cheat.

Nguồn kỹ thuật tham khảo: Unity `Mathf.SmoothDamp` mô tả spring-damper không overshoot [1](https://docs.unity.com/en-us/engine/6000.5/script-reference/unityengine/mathf/smoothdamp); công thức exponential-approx SmoothDamp và game-feel logic [2](https://graemepottsfolio.wordpress.com/tag/damped-spring/), [3](https://theorangeduck.com/page/spring-roll-call). Survev source pin được audit trực tiếp; không trích xuất random “human mouse” từ page bên thứ ba.

## Profiles

| Profile | smoothTime scale | angular rate | Ý nghĩa |
|---|---:|---:|---|
| `Responsive / Pro` (default) | 0.78× | 12 rad/s | Gọn, sắc nhưng vẫn ease-in/out; nên thử trước |
| `Natural` | 1.00× | 8.5 rad/s | Cân bằng mượt/độ nét |
| `Precise / Cinematic` | 1.32× | 6.25 rad/s | Chậm và nhìn điện ảnh hơn |

`Human-like amount` [0–100] điều khiển thời lượng ease; 0 vẫn chỉ có hiệu lực khi human-like bật. Tắt **Human-like aim** để Lock tức thì—không dùng spring. Assist strength không bị angular cap.

## Khác biệt so với preview.7

- preview.7: exponential gain + fixed 8.5 rad/s cap; bắt đầu quay nhanh ngay frame đầu (dù không teleport).
- preview.8: second-order critically damped spring; initial acceleration từ 0, decelerate tự nhiên ở cuối, responsive hơn và ít cảm giác “giật” hơn khi phải xoay 90–180°.
- Không phát sinh noise/overshoot/bouncy khi trường hợp bình thường.

## Kiểm chứng

- `npm run check`: **149/149 PASS** sau implementation và fixture.
- Source runner sau version bump: cần chạy trên pinned source; kết quả sẽ được giữ trong log delivery (source scenarios không live test).
- Test mới kiểm tra:
  - profile Responsive hội tụ nhanh hơn Natural, Natural nhanh hơn Precise;
  - SmoothDamp finite/converged tại 30/60/144Hz;
  - shortest-arc shortest and zero velocity settle;
  - existing Lock/Assist/tracker/mouse/record tests vẫn giữ nguyên.

## Cách thử

1. Cài `userscripts/duality-reborn.user.js` **0.5.0-preview.8**, bỏ preview cũ, reload page-world.
2. Main → Mode Lock, Activation Fire; `Human-like aim ON`.
3. `Aim profile = Responsive / Pro`; `Human-like amount = 35–50` ban đầu.
4. Nếu muốn mượt hơn, chọn Natural / amount 55–70; Precise chỉ khi muốn cinematic rõ rệt.
5. Giữ Sticky ON; giảm FOV nếu Lock vẫn tự kéo khi ngắm xa.
6. Tắt Human-like nếu muốn Lock tức thì không ramp.

## Giới hạn

- Không “pro aim” bằng prediction/weapon spread; spring chỉ sửa đường đi quay.
- Người/weapon/server random không bị script xóa; shotgun pellet ở xa vẫn miss.
- Không đánh lừa anti-cheat hoặc ngụy trang thao tác; không claim account safety.
- Không live-tested hoặc benchmark hitrate.
