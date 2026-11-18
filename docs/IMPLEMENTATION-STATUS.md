# SiriX — tiến độ thực hiện thiết kế v1.2

Tài liệu thiết kế là mục tiêu, không phải danh sách tính năng đã hoàn tất.
Không đổi phiên bản gói sang 1.2 cho đến khi các hạng mục bắt buộc được thực hiện và kiểm thử.

## Đã thực hiện trong mã (vẫn cần kiểm thử trên thiết bị)

- Sửa ghi log sau khi xóa hoặc xoay vòng, và làm mới màn hình xem log.
- Các hook chỉ được cài khi class/selector có mặt; một quyết định trả lời được áp dụng cho các lệnh AddViews/SayIt cùng lượt, kèm giới hạn thời gian và ưu tiên tác vụ hệ thống khi đã nhận diện.
- Chế độ kích hoạt `auto` / `prefix`; trong `prefix`, chỉ `@ai` có nội dung được gửi tới AI, còn `@siri` hoặc câu không có tiền tố giữ Siri gốc. Nhận diện chính xác `@ai` phụ thuộc transcript Apple, nên Type-to-Siri là cách thử đáng tin cậy hơn.
- Tùy chọn hiển thị bản Siri gốc khi lệnh AddViews có văn bản; bản gốc không được đưa vào lời đọc.
- Trò chuyện thử trong Settings với provider đang chọn, không dùng tool và không lưu lịch sử lâu dài.
- Kiểm tra kết nối chạy nền, dùng đúng provider của trang cấu hình; retry HTTP 429/5xx tối đa hai lần mỗi vòng trên luồng nền.

## Chưa hoàn tất so với thiết kế

- STT thay Apple, ghi mic, dịch transcript và thử STT.
- TTS tùy chỉnh, chọn giọng/nguồn, tự nhận ngôn ngữ, và chống Siri đọc chồng.
- Deferred push/notification cho đáp án trễ; lưu lịch sử bền, giao diện lịch sử, ẩn danh, thống kê.
- Model dự phòng khi lỗi/hết giờ, hủy request theo generation, phát hiện offline sớm.
- Xuất/nhập cấu hình, kiểm tra cập nhật, công cụ `current_app`, các trang cấu hình tương ứng.
- Hiển thị stream theo từng chữ và mốc timeout theo token đầu; hiện SSE chỉ tích lũy và hiển thị khi hoàn tất.

STT, TTS và deferred push phụ thuộc API riêng, quyền mic và audio session của Siri. Không đưa các công tắc chưa hoạt động vào Settings hoặc cam kết hành vi an toàn cho đến khi có kiểm thử trên thiết bị iOS jailbreak. Log có thể chứa câu hỏi và URL; hiện chưa có chế độ ẩn danh.
