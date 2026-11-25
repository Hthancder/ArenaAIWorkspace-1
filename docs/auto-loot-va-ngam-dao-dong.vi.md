# Vứt đồ và mục tiêu dao động nhỏ

Đối chiếu mã nguồn Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff`: client gửi `DropItem` (protocol 1028, message 12, `item`/`weapIdx`); server xử lý việc nhặt/vứt. Server đã có `mobileDropTicker = 3` khi `dropLoot` chạy; không phải mọi nguyên nhân vứt đều được client nhìn thấy.

## Auto Loot

Chế độ Nearby tạm ngừng input Loot tự động 3,5 giây từ mỗi `DropItem` hợp lệ được gửi trong protocol đã xác minh. Vứt tiếp kéo dài thời gian; pulse đã chuẩn bị trong cùng frame bị hủy; thao tác nhặt thủ công không bị chặn. Thời gian nghỉ được xóa khi giải phóng match. Nếu server không chấp nhận lệnh vứt thì vẫn có thể nghỉ vì client không có xác nhận thành công ở đây. Lệnh Loot đã gửi trước đó không thể thu hồi, và chỉ nhận biết các lệnh vứt đi qua sender đã map; thao tác vứt do server hoặc giao thức không tương thích không được bảo đảm phát hiện.

Chế độ Mobile chạy trên server, không thể bị userscript tạm dừng giữa trận; server có cooldown riêng 3 giây ở `dropLoot`, nhưng không hứa bao phủ mọi trường hợp. Như trước, server tự chọn loot gần nhất và có thể chọn khác với client khi có nhiều món hoặc trễ mạng.

## Aim Lock và dao động

Với Prediction bật trong Lock, tracker giữ tối đa 32 snapshot trong 900 ms. Chỉ khi có ít nhất tám mẫu trong ít nhất 550 ms, khoảng cách mẫu không vượt 150 ms, có ít nhất hai lần đảo hướng có ý nghĩa và toàn bộ vùng dao động nhỏ hơn 1,3 lần bán kính mục tiêu (tối đa 2 world unit), solver thử ngắm giữa vùng quan sát thay vì ngoại suy vận tốc tức thời. Nếu mẫu cuối cho thấy tốc độ vượt 5 wu/s, hoặc snapshot cũ hơn 150 ms, giả thuyết này bị bỏ. Không thay đổi Assist; tắt Prediction để bỏ cả cơ chế này. Đường đạn, wallcheck, muzzle và giới hạn tầm vẫn được kiểm tra.

Không dùng quy tắc “con trỏ đang trên mục tiêu thì luôn bỏ lead”: mục tiêu có thể đang chạy và viên đạn cần thời gian bay. Mẫu quá ít hoặc chuyển động thay đổi vẫn dùng solver cũ; người chơi có thể đột ngột rời vùng và giả thuyết không biết được tương lai. Tâm vùng là ước lượng, không bảo đảm trúng, không loại được tản đạn/lag, và có thể lệch so với ý muốn khi người chơi nhắm một điểm khác trên cơ thể.

## Benchmark tổng hợp

Cùng script `node scripts/benchmark-aim.mjs`, so sánh trước/sau trên bộ seed mô phỏng đã dùng trong lúc phát triển (không phải kiểm thử độc lập/live), sai lệch vị trí tương lai, đơn vị wu:

| Chuyển động | Trung vị trước → sau | p95 trước → sau |
|---|---:|---:|
| Dao động nhỏ điều hòa | 1,465 → 0,286 | 2,936 → 2,515 |
| Dao động rồi chạy nhanh | 3,634 → 3,749 | 12,449 → 11,632 |
| Chạy thẳng | 0,388 → 0,388 | 3,139 → 3,139 |
| Đường cong | 2,573 → 2,573 | 6,646 → 6,646 |

Ở trường hợp dao động rồi chạy nhanh, trung vị xấu đi dù p95 tốt hơn; không che trade-off này. Bộ mô phỏng chỉ có một số quỹ đạo, tốc độ đạn, thời gian mạng; không mô phỏng spread hoặc đo tỷ lệ trúng, FPS hay trạng thái triển khai live. Các thuật toán cần được kiểm tra thêm trong game.
