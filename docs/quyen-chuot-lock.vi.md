# Quyền điều khiển chuột khi Lock

Theo source Survev được ghim, hướng súng trên màn hình đọc `input.mousePos` trong `Player.updateRotation`, còn `InputMsg` được tạo sau đó từ cùng vector. Nếu chỉ sửa gói khi gửi thì hai hướng có thể khác nhau; con trỏ vật lý CSS/OS cũng không thể được userscript dịch chuyển thật.

Bản này không chọn mục tiêu, dự đoán hay kiểm tra vật cản trước activation của aim súng. FOV vẫn là điều kiện chọn lúc kích hoạt, còn snapshot được tiếp tục thu để prediction có dữ liệu. Không tự bắn. Grenade Preview/Assist/Lock và activation riêng vẫn giữ.

Lock súng yêu cầu nắm quyền vector chuột native bằng accessor: khi không thể chiếm ổn định, trả quyền cho game và không gửi hướng Lock riêng. Cấu hình cũ tắt direct mouse được chuyển về bật và tùy chọn sender-only đã bỏ khỏi menu. Khi Fire bắt đầu giữa pre-frame và sender, sender cũng cài ownership thay vì chỉ sửa gói; khi object chuột bị thay hoặc descriptor bị đổi, không tái sử dụng plan cũ mà chưa xác nhận ownership. Cursor đúng giữa màn hình được cấp vector nhỏ nhưng khác 0 vì source mặc định (1,0) nếu độ dài bằng 0. Nhả Fire/điều kiện activation, blur, blocker hoặc dispose vẫn trả chuột theo hành vi an toàn hiện có; Assist không ép giữ ownership.

Các test gồm activation giữa frame, cursor trung tâm, descriptor không configurable, thay object chuột, di chuột khi giữ Fire, Wallcheck và chuyển Assist. Fixture dựa trên source kiểm tra rotation, native input, sender/serialize và flush qua 90 frame trong bốn biến thể build. Không có test này chứng minh kết quả trên server live, mọi client khác hay mọi tương tác với script khác. Với Fire bắt đầu sau khi game đã render rotation của frame hiện tại, không thể sửa ngược frame đã vẽ; không thể hứa loại bỏ mọi giật hoặc thay đổi vị trí con trỏ OS.
