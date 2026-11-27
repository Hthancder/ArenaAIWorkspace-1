# Rà soát thả bom và Wallcheck hướng thực

## Quyền Fire sau tự thả bom

Gate chống nấu lại sau tự thả trước đây tiếp tục xóa `shootStart` và `shootHold` cả khi input có lệnh đổi súng thủ công, đã sang vũ khí khác hoặc input không còn đủ điều kiện an toàn. Source pin xử lý Fire và equip trong cùng `Player.handleInput`; việc xóa Fire có thể ảnh hưởng vũ khí người chơi vừa chọn.

Khi có đổi trang bị thủ công, slot không còn là throwable hoặc input không sẵn sàng, gate chuyển sang manual cho phần còn lại của lần giữ. Fire/equip được giữ nguyên và auto không tự giành lại trong cùng lần giữ; nhả Fire reset gate. Khi vẫn cầm grenade bình thường sau auto-release, gate vẫn suppress để tránh nấu lại. Người chơi chủ động đổi trang bị/nắm quyền có thể tiếp tục tự nấu hoặc ném; không có bảo đảm server ACK.

## Wallcheck hướng đã làm mượt

Trước đây khi hướng thực khác hướng giải, ray được kéo dài qua toàn bộ mục tiêu dự đoán cộng bán kính, kể cả khi ray thực giao hitbox trước đó. Tường nằm sau điểm giao có thể khiến aim bị chặn nhầm. Nay tính giao điểm của chính ray thực với vòng tròn mục tiêu và cắt tại điểm đầu, hoặc điểm ra nếu nòng nằm bên trong; nếu không giao thì vẫn kiểm tra toàn segment bảo thủ. Phép này dùng vị trí/hitbox dự đoán, không chứng minh viên đạn thật sẽ trúng; không mô phỏng pan, spread hay chuyển động tương lai.

## Kiểm tra

264 test đạt; so sánh 8.640 trường hợp hình học với `coldet.intersectSegmentCircle` từ source Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`. Cũng đạt fixture client bốn biến thể, 11.520 hướng cầu thang, loot, grenade 320 + 20 preview và 568 cấu hình súng. Benchmark geometry tổng hợp Node 4000 vật thể median 0,818 ms, p95 1,033 ms/solve, không phải FPS live. Chưa kiểm tra gameplay live; source pin có thể khác bản đang chạy.
