# Giảm chi phí aimbot

Trong mỗi lần giải aim súng có ứng viên, code cũ tạo hai snapshot descriptor của toàn bộ registry: một lần tìm cầu thang và một lần tìm vật cản. Wallcheck sau đó lọc tất cả vật cản theo trạng thái/tầng rồi mới loại vật ở xa đường đạn. Hai lượt này có thể tốn CPU và tạo rác khi registry lớn, kể cả trong giai đoạn chuẩn bị trước activation.

Bản này chỉ lấy một snapshot mới cho mỗi lần giải, đồng thời phân loại cầu thang và vật cản; Wallcheck loại hình ở xa trước khi kiểm tra trạng thái/tầng. Không giữ danh sách qua các lần giải hay snapshot, không giảm tần số aim và không bỏ kiểm tra muzzle, layer, player blocker hoặc Wallcheck. Hình không hỗ trợ vẫn vào narrow phase để fail closed. Test so sánh tập kết quả cũ/mới, accessor không bị gọi, registry thay đổi, cùng source fixture blocker.

Đo riêng bằng `node scripts/benchmark-aim-geometry.mjs`: trên registry giả lập 4.000 đối tượng, một lượt không chạy song song đo median cũ 2,949 ms, mới 1,076 ms; p95 lần đo đó 5,040 và 1,906 ms. Con số phụ thuộc máy và chỉ đo bước scan/lọc trong Node, không phải FPS, network hay thời gian trọn frame trong game. Chưa xác định đây là toàn bộ nguyên nhân lag trên máy người dùng.

Diagnostics `runtimePerformance.aimFrame` và `aimSender` ghi thời gian giải aim ở frame và sender (tính cả thời gian khi không cần giải), bên cạnh `inputFrame`, `snapshotHook`, `discovery` và `visualFrame`. Các số là thời gian script cục bộ, không phải GPU, FPS hay ping. Nếu bản mới vẫn lag, thử tái hiện rồi dùng Help → Copy diagnostics để phân biệt nhánh tốn thời gian; dữ liệu không chứng minh server đã nhận input hoặc bắn trúng.
