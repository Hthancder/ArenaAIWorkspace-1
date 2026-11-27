# Auto Loot: đối chiếu và giảm thử lại

## Nguồn tham khảo

- [Survev, commit 08346fb6](https://github.com/survev/survev/tree/08346fb6ea74c5a8b961a153d2d7d0411e31c8ff): `client/src/objects/loot.ts` xác định `closestLoot`; `client/src/game.ts` đưa input Loot vào gói; `server/src/game/objects/player.ts` tự chọn loot gần nhất và kiểm tra nhặt. `pickupLoot` có cooldown 0,1 giây và kiểm tra trạng thái, inventory, loại đồ. Server-mobile tự động nhặt và mở cửa, còn ảnh hưởng scope zoom.
- [Survev-Krityhack, commit 6b3d4b1](https://github.com/Drino955/Survev-Krityhack/blob/6b3d4b11c117fb286198d123a66c10e3edb084b3/src/plugins/autoLoot.js): plugin đặt `isMobile`/`useTouch` thành true qua property hook. Đây là cơ chế khác với Nearby; không sao chép mã, không thay đổi tên người chơi hay ép touch controls. Chế độ Mobile sẵn có của Reborn chỉ sửa Join khi được chọn và có các tác dụng phụ server nêu trong menu.
- `references/duality-client.reference.js` có cách sửa `isMobile` trong Join; cũng không sao chép code từ bản này. Repository duality_client tìm được qua tìm kiếm nhưng clone không thành công, nên không khẳng định đã đọc phiên bản online hiện hành của nó.

## Thay đổi Nearby

- Đặt khoảng cách tối thiểu 120 ms giữa các lần lên lịch yêu cầu Loot, có dự phòng so với cooldown server 100 ms. Từng object có backoff riêng 350/700/1400/2000 ms khi không thay đổi, kể cả khi `closestLoot` tạm mất hoặc luân phiên giữa các item. Tối đa 128 record, hết hạn sau 10 giây, xóa khi rời match; ID/type/count mới của object được tái sử dụng reset retry của object đó.
- Khi game đọc bind, kiểm lại candidate, ID, type, count, vị trí/radius, layer, quyền sở hữu và loại supply. Nếu thay đổi từ lúc lên lịch, không phát input giả cũ. Không chặn input nhặt do người chơi thật gửi. Không lặp `Interact` hoặc `Use`, không quét toàn bộ loot mỗi frame, không sửa Join trong Nearby.
- Một mô phỏng xác định: hai candidate không đổi luân phiên mỗi 160 ms trong 10 giây ở bước 16 ms; cách lưu một candidate cũ lên lịch 63 lần, backoff mới 14 lần. Đây chỉ là số yêu cầu *được lên lịch* trong mô phỏng, không phải đo băng thông, FPS, tỷ lệ nhặt thành công hay độ trễ trong trận live. Khoảng cách tối thiểu có thể làm chậm nhặt liên tiếp khoảng 120 ms.

## Giới hạn quan trọng

Bản mới thêm guard các vật cạnh tranh đã replicate; chi tiết và đánh đổi xem `docs/ra-soat-loot-gan-nhat.vi.md`. Guard không thay đổi các giới hạn server dưới đây.

Input Loot **không chứa ID mục tiêu**. Bán kính chọn loot của server desktop khác bán kính client, và vị trí/loot có thể thay đổi trong khi gói đang truyền. Dù client chỉ phát lệnh khi thấy ammo/heal/boost/throwable, server có thể chọn item khác, kể cả súng/gear. Không cam kết tuyệt đối chỉ nhặt supply; khi có nhiều vật nằm sát nhau, nên cân nhắc tắt Nearby. Khi vật gần nhất phía client không phải supply, Nearby không chọn vật thứ hai. Mobile vẫn dùng chính sách server, có thể nhặt súng/gear và mở cửa, và chỉ thay đổi khi Join mới.

Không có xác nhận nhặt thật hay dung lượng inventory được suy ra từ mỗi lần phát; server là nguồn quyết định. Không thay đổi giao thức hoặc tốc độ mạng, không cam kết giảm ping, hết giật hay cải thiện FPS. Kiểm thử tự động là fixture và source-method pinned, chưa phải kiểm thử live.
