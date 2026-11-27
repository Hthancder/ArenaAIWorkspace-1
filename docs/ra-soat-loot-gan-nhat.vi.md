# Auto Loot Nearby và vật gần nhất của server

Đối chiếu source Survev tại `3edee7e8`: client desktop chọn `closestLoot` trong bán kính `loot.rad`; server xử lý input Loot không có ID, tự chọn vật gần nhất trong bán kính `player.rad + loot.rad`. Ví dụ supply cách 1,5 và súng cách 0,8, bán kính supply 2 và súng 0,2: client chọn supply, server với bán kính người 1 chọn súng. `scripts/check-loot-upstream.mjs` thực thi `Player.getClosestLoot` source để tái hiện, dùng grid giả.

Nearby nay yêu cầu registry object có contract get/delete, candidate còn nằm trong registry và không thấy vật có cùng layer/quyền sở hữu ở khoảng cách gần hơn hoặc bằng. Xét mọi loại loot, không chỉ súng; quá nhiều object, entry không đọc được hoặc loot thiếu dữ liệu thì dừng. Kiểm tra lúc chuẩn bị pulse và lúc game đọc bind, không chặn bind vật lý. Backoff vẫn giới hạn tần suất kiểm tra khi có conflict; có thể nhặt chậm hơn sau khi vật cản biến mất. Không thay đổi Mobile mode.

Đây là guard bảo thủ dựa trên object đã replicate: có thể bỏ qua supply hợp lệ, không biết object chưa được gửi hoặc đã thay đổi trong lúc gói đang đi, và **không bảo đảm tuyệt đối** server chọn đúng item. Scan registry tối đa 8192 entries mỗi lần thử hoặc đọc pulse, không quét mỗi frame khi backoff. Chưa đo FPS browser, chưa test live.
