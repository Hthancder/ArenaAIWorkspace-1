# Chuẩn bị nghiệm ngắm trước Fire

Khi Aimbot Assist hoặc Lock đang bật, trước khi điều kiện kích hoạt được thỏa mãn script vẫn chọn mục tiêu trong FOV, kiểm tra quan hệ/layer, tính nghiệm theo cấu hình prediction và kiểm tra đường bắn. Việc này chỉ là chuẩn bị: **không chỉnh chuột, không gửi gói bắn và không tự bắn**. Điều kiện kích hoạt Fire/phím vẫn giữ nguyên, controller Human-like không được chạy trước và sẽ không tự hướng nòng trước khi kích hoạt.

Khi Fire hoặc phím kích hoạt đổi trạng thái trong cùng một frame, sender bỏ kế hoạch cũ và tính lại theo dữ liệu hiện tại; không dùng nghiệm chuẩn bị cũ nếu target, tường hoặc input đã đổi. Việc tính trước không chứng minh giảm độ trễ bắn hay tăng hit rate: các phép tính vẫn được kiểm tra lại khi kích hoạt, snapshot/mạng và thời gian làm mượt vẫn ảnh hưởng. Xử lý thêm khi chưa bắn có chi phí CPU; không quét nếu aimbot tắt. Diagnostics `aimPreparation` cho biết `ready` hoặc lý do không có nghiệm; không chứa danh tính hay vị trí.

Kiểm thử bao gồm không sửa Fire/chuột khi chờ, chặn tường ngay khi kích hoạt, chuyển Fire trong cùng frame và không dùng correction cũ khi nhả. Fixtures không thay thế đo hiệu năng hoặc test live.
