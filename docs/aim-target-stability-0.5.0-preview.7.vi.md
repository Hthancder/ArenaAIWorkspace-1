# 0.5.0-preview.7 — ổn định mục tiêu và aim tự nhiên

Ngày: 2026-11-12  
Phạm vi: target acquisition, Lock movement and player-perceived aim stability. **Chưa xác nhận gameplay live trên máy người dùng.**

## Vấn đề người dùng báo

- Lock/Assist giật sang một trong hai địch trong FOV, rồi giật ngược lại.
- Khi ngắm xa/lệch khỏi địch, Lock kéo nhân vật quay đột ngột.
- Cảm giác aim chính xác hơn khi đứng yên; ở xa khó trúng hơn.
- Aim chịu ảnh hưởng bởi hướng/tốc độ người chơi, hướng/tốc độ địch, khoảng cách và hướng đạn.

## Thay đổi

### Target hysteresis / anti-flicker

- Mục tiêu hiện tại được nới FOV chiếm dụng từ `1.15x` lên `1.25x`.
- Score lựa chọn mới dùng **distance × 0.65 cho mục tiêu hiện tại**, không phải nearest-neighbor tuyệt đối mỗi frame.
- Một địch mới vẫn thắng nếu rõ ràng gần chớn ngắm hơn; mục tiêu hiện tại không đổi chỉ vì chênh lệch vài pixel/1 frame.
- `Sticky` vẫn có thể tắt để quay lại nearest-candidate tuyệt đối.

### Human-like aim — tự nhiên hơn nhưng vẫn có toggle

- Default `Human-like aim (Lock)` là **ON**. Các bản install mới/migration không âm thầm giữ preview.6 hay legacy `Smooth Lock=false` như mặc định combat-critical.
- Lock có giới hạn **angular rate 8.5 rad/s** khi human-like bật; không còn bước quay lớn ngay frame đầu như chỉ exponential smoothing.
- Không thêm trễ vô hạn, không random sai hướng; đây là motion-quality ramp/toggle, không phải chống phát hiện.
- Tắt `Human-like aim` để Lock tức thì. Assist strength vẫn là lực kéo của Aim Assist; không bị angular cap.
- `Human-like amount` chỉ hiện khi Lock.

### Prediction/lead

- Giữ prediction qua snapshot/weapon profile/trajectory; `Lead adjustment` max 200%.
- Không cộng vận tốc người bắn vào vận tốc đạn (bullet không “thừa hưởng” velocity trong source semantics). Không thể xóa move-spread của vũ khí bằng aim.
- Đạn ở xa cần nhiều flight time hơn; prediction đích đến là điểm tương lai tại thời điểm đạn chạm, không phải bám tâm hiện tại. Prediction vẫn phụ thuộc snapshot/age/velocity đo được.
- Không tuyên bố mọi súng/mọi khoảng cách đều tất trúng, đặc biệt shotgun pellet spread.

## Giới hạn quan trọng

- Đứng yên dễ trúng hơn chủ yếu vì weapon move-spread/recoil và client/server weapon behavior; script không được xoá spread hoặc làm server ưu tiên hit.
- Ở xa, miss window lớn hơn do flight time, latency, snapshot age và uncertainty; prediction chỉ ước lượng trong những gì snapshot cung cấp.
- Human-like ramp làm gun/player xoay không giật nhưng vẫn có độ trễ quay. Nếu muốn phản ứng nhanh nhất, tắt toggle (không mô phỏng người).
- Aim không chặn hoặc can thiệp anti-cheat; không có guarantee no-ban.

## Kiểm chứng

- `npm test`: **148/148 PASS** sau code changes (chính xác: xem log cuối).
- Lock convergence/assist/tracker/registry/mouse integration tests giữ nguyên.
- Sau version build và source runner cần chạy: `npm run check` và `npm run check:upstream -- .cache/survev`. **Chưa live-test.**

## Cách thử

1. Cài preview.7, disable/remove preview.6/cũ, reload page-world.
2. Main → Mode Lock, Activation Fire.
3. Human-like aim Test:
   - **ON**: hai địch trong FOV không đổi qua lại liên tục; acquisition quay mượt.
   - **OFF**: Lock phản hồi tức thì nhưng có thể giật/quay nhanh khi enemy vào FOV.
4. Nếu muốn bám đúng mục tiêu xa/lệch ngắm mà không tự ý kéo: giảm `FOV radius`, không tắt Lock, hoặc dùng Assist strength thấp.
5. Nếu vẫn under-lead ở ngang, tăng Lead adjustment 110–150%; nếu over-lead, giảm về 90–100.
6. Shotgun ở xa không thể tất trúng pellet; đứng gần/aim tâm hitbox mới đáng tin.

**Không có live confirmation/hitrate guarantee.** Gửi diagnostics JSON nếu còn hiện tượng đổi target/lệch lead, kèm súng, range, trạng thái di chuyển và con đường target.
