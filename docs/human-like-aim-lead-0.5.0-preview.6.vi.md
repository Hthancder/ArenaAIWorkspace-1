# 0.5.0-preview.6 — Human-like aim toggle và lead rõ ràng

Ngày: 2026-11-12  
Phạm vi: Aim — Mode & activation / Prediction. **Chưa xác nhận gameplay live trên máy người dùng.**

## Người dùng báo

- Aim Lock tạo cảm giác “không hoạt động”, dù native forward/correction đã chạy.
- Đạn hướng về vị trí cũ khi địch di chuyển; shotgun văng pellet và không trúng.
- Human-like aim, nếu có, không được làm chậm hoặc cản bám mục tiêu mặc định.
- “Đạn bám” không đồng nghĩa trúng: phải aim theo vị trí tương lai và contract vũ khí thật.

## Thay đổi

- `Human-like aim (Lock)` là toggle **riêng**, mặc định **off**.
  - Off: Lock không bị giới hạn theo kiểu mô phỏng chuyển động người; aim đi thẳng vào điểm giải được.
  - On: Lock dùng `Lock responsiveness`/`smooth` như lớp điều khiển mượt hơn.
  - Toggle này không thay đổi `Assist strength`, `Direct native mouse input`, Fire hoặc Movement.
- Nâng `Lead adjustment` tối đa từ 150% lên **200%**; mặc định vẫn 100% (không đoán thêm cho mọi người).
- Hint prediction giải thích rằng Assist strength là lực kéo; 100% là gần Lock. Lead là vị trí tương lai theo tốc độ đạn/snapshot, không phải “đánh dấu kẻ địch”.
- Diagnostics `aimControls` thêm `latencyCompensation`, `leadAdjustment`, `humanLikeAim`.
- Legacy `Smooth Lock`/saved `smoothEnabled=true` không còn âm thầm làm chậm aim sau migration; cần chọn lại `Human-like aim`.

## Vì sao không hứa “vũ khí nào cũng trúng”

Aim Lock/Lock có thể khóa đúng tâm điểm lead nếu contract vũ khí, snapshot và aim route hợp lệ. **Không thể bảo đảm trúng mọi súng hoặc mọi khoảng cách:**

- shotgun/pellet spread, recoil và random jitter không thể được “biết trước”;
- target đổi hướng đột ngột có thể vượt prediction horizon;
- packet stale/jitter, wallcheck/layer hoặc weapon profile thiếu sẽ làm direct/prediction nhường input có chủ đích;
- lead cao hơn không loại bỏ spread hoặc đổi chuyển động của địch.

Script không disable spread, không đổi damage/cooldown server, không biết trước movement tương lai.

## Kiểm chứng

- `npm run check`: **148/148 PASS** (sau migration/menu regression updates).
- Source runner với pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`: **4/4 PASS** (xem log cuối).
- Migration fixture: legacy `smoothEnabled:true` không còn bật `humanLikeAim`; explicit `humanLikeAim:true` được giữ.
- Menu fixture: `smooth` chỉ hiện/cho phép chỉnh khi Lock + Human-like aim bật.

## Cách thử đúng

1. Cài `userscripts/duality-reborn.user.js` **0.5.0-preview.6**, xóa script cũ, reload page-world.
2. Main:
   - Mode = **Aim Lock**.
   - Activation = Fire.
   - **Human-like aim = OFF**.
   - Direct native mouse input = ON.
   - Prediction = ON.
   - Lead adjustment = 100% (thử 110–150% chỉ nếu địch vẫn chạy ngang và bạn thấy under-lead).
3. Giữ Fire với enemy trong FOV; quan sát súng/crosshair. Nếu dùng Aim Assist, tăng **Assist strength** (100% là mức kéo mạnh gần Lock).
4. Shotgun: bắn gần hơn, aim tâm hitbox; không có switch nào đảm bảo pellet spread ngẫu nhiên trúng.
5. Nếu vẫn lệch cùng một phía khi target chạy ngang, gửi diagnostics JSON và mô tả súng/range. Không gửi packet hoặc token.

**Không có live confirmation hoặc hitrate guarantee.**
