# Kiểm tra Wallcheck tại sender trong cùng frame

Plan có thể được tính trước khi input native được gửi. Trước đây nếu cursor và activation không đổi, sender dùng lại plan đó: một vật chắn mới hoặc registry biến mất sau lần tính có thể không được kiểm tra lại trước gói tin.

Với plan gun/melee đang hoạt động và Wallcheck bật, sender nay tính lại điều kiện chọn mục tiêu và hình học từ dữ liệu hiện có. Hướng điều khiển đã tính của frame được giữ nguyên, không chạy smoothing lần hai; nếu mục tiêu đầu tiên thay đổi thì nhường input thay vì nhảy sang mục tiêu khác. Đường mục tiêu và đường thực tế đã smooth đều được kiểm tra. Grenade aim với plan có điều chỉnh cũng tính lại tại sender, kể cả khi không bật tự thả. Nếu plan null từ đầu thì tiếp tục dùng null, không tự kích hoạt aim. Fire vật lý không bị chặn.

Giá phải trả là thêm một lần solve/scan cho gói sử dụng plan gun/melee có Wallcheck hoặc grenade; không quét trước activation cho gun. Benchmark geometry giả lập với 4000 object đo một solve median 0,795 ms, p95 0,974 ms trên sandbox lượt này, không phải đo thời gian tăng thêm trong browser hay FPS game. Test mô phỏng vật chắn và registry đổi giữa pre-frame và sender, xác nhận giữ hướng smooth và Fire, và hồi phục frame sau. Không thể kiểm tra trạng thái server chưa replicate hoặc sự thay đổi sau khi gói gửi; chưa kiểm chứng live.
