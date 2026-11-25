# Wallcheck và chỉ báo mục tiêu

## Wallcheck

Đối chiếu mã nguồn Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff`, đặc biệt `server/src/game/objects/bullet.ts`, `weaponManager.ts` và `shared/utils/collider.ts`. Đường đạn server xét obstacle chưa chết, cùng layer, đủ độ cao; obstacle `collidable` dừng đạn. Player khác cũng có thể chặn đường đạn. Obstacle không collidable không tự dừng viên đạn chính; vật phản xạ có thể tạo đạn phản xạ riêng.

Khi Wallcheck bật, script kiểm tra đường từ nòng tới **mép hitbox** mục tiêu dự đoán, thay vì kéo đường tới tâm và nhầm vật nằm sau mép hitbox thành vật chặn. Kiểm tra các obstacle client biết, player khác nằm trên đường bắn và cả hướng thực sau Assist/làm mượt nếu khác hướng dự đoán. Obstacle đã chết, khác layer hoặc thấp hơn chiều cao đạn đã xác minh được bỏ qua; collider không hỗ trợ/thiếu hoặc dữ liệu không đủ được xử lý bảo thủ. Khi một đường bị chắn, script nhả điều khiển ngắm và không tự chuyển sang candidate tiếp theo ở lần tính đó. Sticky bật sẽ giữ ưu tiên mục tiêu bị chắn trong lúc còn hợp lệ/trong FOV để thử lại khi thông đường. Fire và di chuyển của người chơi không bị chặn. Tắt Wallcheck sẽ bỏ các kiểm tra này.

**Giới hạn:** chỉ dùng object được server replicate và collider/trạng thái client hiện có; không biết chính xác tương lai, mọi chướng ngại chưa được gửi, pan/hiệu ứng đặc biệt, lệch hướng ngẫu nhiên hay mọi va chạm server. Player chắn đường được xét tại vị trí đã biết, không tiên tri vị trí khi đạn tới. Không khẳng định đường thông thì chắc chắn bắn trúng. Không đủ contract registry hoặc quá nhiều collider liên quan thì không tự aim. Đường kiểm tra là một đường trung tâm, không phải mọi pellet shotgun hay toàn bộ độ tản.

## Chỉ báo

Trong **Main → Aim — Hỗ trợ ngắm**, bật **Hiển thị mục tiêu đang ngắm** và chọn **Vòng tròn / Tâm ngắm / Góc khung / Hình thoi**. Chỉ báo mặc định tắt, nằm quanh vị trí player được chọn theo tọa độ render; nó khác tùy chọn **Predicted point** thể hiện điểm dự đoán. Chỉ báo không đổi aim, không vẽ khi không còn mục tiêu hợp lệ/bị Wallcheck nhả, và tự ẩn khi tính năng tắt. Nó có thể lệch nhẹ khi render/interpolation hoặc snapshot thay đổi, và chỉ hiển thị entity client biết. Không kết luận mục tiêu đã bị trúng.

Kiểm thử bổ sung gồm vật chắn, sau mép hitbox, biến mất, layer/chiều cao, collider thiếu, player chắn, đường ngắm sau smoothing, sticky, bật/tắt và bốn kiểu chỉ báo. Các fixture/source-method công khai không thay thế xác minh trận live.
