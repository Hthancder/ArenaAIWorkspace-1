# Dùng snapshot mới khi chuẩn bị gửi aim

## Vấn đề và thay đổi

Trước đây pre-frame có thể cache nghiệm aim. Nếu update thế giới được native xử lý sau pre-frame nhưng trước sender, sender vẫn có thể tái sử dụng nghiệm cũ. Nay `observeUpdate` hủy cache khi update chứa full object, partial object hoặc object bị xóa (bao gồm cả đổi layer, trạng thái chết và collider, không chỉ vị trí). Lần gửi input **đã được native lên lịch** tiếp theo sẽ tính lại từ dữ liệu đã xử lý, áp dụng lại Wallcheck và bộ dự đoán. Update chỉ chứa control/ACK không hủy cache. Không tính aim hay gửi thêm gói ngay trong receiver, không tăng tần suất snapshot của server; nếu không có lần gửi cho đến frame sau thì không có đường tắt nào được cam kết. Reset trận cũng hủy cache cũ.

Điều này sửa trường hợp tái dùng dữ liệu cũ, không tăng tốc phép giải hay khẳng định giảm ping. Sender có thể phải tính lại thêm một lần nếu thực sự có update giữa các bước; chưa đo chi phí hay độ trễ trong trình duyệt thật. Việc tính lại không đổi quy tắc nhận diện A–D: Lock với tùy chọn ổn định vẫn cần lịch sử, hai lần đảo chiều, giới hạn đường kính và không có gap lớn; khi ổn định thì ngắm giữa vùng, không đuổi vận tốc mới nhất. Chưa đủ lịch sử hoặc vừa thoát vùng thì predictor bình thường tiếp tục dùng snapshot; không được coi mọi lần đổi hướng là dấu hiệu A–D. Assist không bật bộ ổn định này. Human-like smoothing vẫn có thể làm chậm hướng thực gửi; có thể giảm/tắt để so sánh.

## Kiểm thử và giới hạn

- Kiểm thử fixture cố ý xếp thứ tự pre-frame → snapshot địch đổi vị trí → sender trong cùng frame. Bản cũ gửi `{x:1,y:0}`; bản mới gửi hướng mới có thành phần y >0.2. Đây là kiểm thử xác định một interleaving, không phải phép đo độ trễ/hitrate thực.
- Kiểm thử A–D lặp cho thấy sau snapshot cùng frame, nghiệm vẫn là `bounded-oscillation` và nhắm gần giữa; một kiểm thử obstacle đổi trạng thái xác nhận Wallcheck được tính lại, không chặn Fire thủ công. Update control-only không phát sinh gói; reset/thiếu snapshot contract và xóa object được kiểm thử.
- `scripts/check-upstream.mjs` tái hiện interleaving bằng native source `3edee7e8bd07fda8a63905aab4c45b595b684a80`, cả bản minify/đổi tên và unminified. Fixture ép scheduler để kiểm tra hướng serialize; code sản phẩm không ép gói trong receiver. Không có server hay gameplay thật.
- Bộ benchmark solver không mô phỏng interleaving sender, nên kết quả không chứng minh thay đổi này nhanh hơn: ví dụ `benchmark-aim.mjs` thẳng trung vị/p95 0.151/3.139 wu, zigzag 7.098/17.087; `benchmark-micro-strafe.mjs --human` A–D rộng 3 wu 0.922/4.902 wu, còn khi địch thoát cùng trục, riêng giai đoạn thoát trung vị/p95 4.569/9.275 wu. Đây là số tổng hợp trên bộ đã dùng phát triển, không phải tỷ lệ trúng live.

Đạn vẫn mất thời gian bay; CPU không thể biết thao tác địch chưa xảy ra, cải thiện mạng hay khử spread ngẫu nhiên. A–D đủ nhanh có thể bị alias do tần số snapshot, và những snapshot tới muộn không thể khôi phục hành động chưa quan sát được. Tùy game và mạng, lỗi mà người dùng thấy có thể do smoothing, cập nhật muộn, lựa chọn mục tiêu, A–D hoặc spread; không kết luận riêng interleaving này là nguyên nhân trong trận thật.
