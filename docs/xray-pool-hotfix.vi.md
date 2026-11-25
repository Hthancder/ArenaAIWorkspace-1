# X-Ray: đối chiếu pool object

Đối chiếu mã nguồn công khai Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff` (HEAD của nhánh master khi kiểm tra). `client/src/map.ts` chứa pool obstacle và building; mỗi `Pool` giữ danh sách object, obstacle có `type`, `sprite` và `isBush`, còn building có `imgs` chứa các record `sprite`/`isCeiling`. Các định nghĩa dùng `createBush` cho `bush_*` và `brush_*`, `createTree` cho `tree_*`, và có `table_*`, `stairs_*`. Không tìm thấy căn cứ để đổi tên hàng loạt hay làm mờ mọi loại object.

Lỗi quét trước đây cắt mỗi mảng ở 2048 phần tử và có thể hết ngân sách ở metadata trước khi đến pool. Nay ưu tiên danh sách pool có cấu trúc object phù hợp, duyệt qua phần tử sau 2048, bỏ qua object không active trong lượt ưu tiên, và nhận `isBush` trên obstacle khi thiếu registry. Vẫn giới hạn ngân sách 12000 object mỗi lần quét để tránh treo frame; điều này không đảm bảo mọi object được xử lý trên các map quá lớn. Việc khám phá vẫn có thể không khớp bản game triển khai nếu cấu trúc thay đổi.

Ceiling vẫn chỉ áp dụng cho record `isCeiling`, không ẩn floor. Khi pool tái sử dụng obstacle hoặc building bị vô hiệu/thay danh sách ảnh, override cũ được nhả; sau tắt X-Ray trả lại giá trị game. Loại mới xuất hiện sau lần quét có thể cần chờ lần quét tiếp theo (~500 ms). Các thay đổi là phía hiển thị, không làm lộ object chưa được server gửi và không thay đổi va chạm.

Kiểm thử bổ sung dùng pool theo cấu trúc source, cây/bụi sau phần tử 2048, floor/ceiling, thay loại và tái sử dụng building. Chưa xác nhận trên bản live. Script kiểm tra tích hợp trong repo cố định ở commit `3edee7e8...`, không khẳng định đã kiểm thử tích hợp tự động với commit mới nhất.
