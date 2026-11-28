# Rà soát codebase

Phạm vi: module runtime `src`, đường input/sender/activation, lifecycle, cấu hình, aim, grenade, loot, ESP; rà tĩnh các rule biến không dùng, nhánh không tới được, key trùng và biểu thức bất thường. Đối chiếu fixture integration và source Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`. Đây không phải kiểm chứng toàn bộ trạng thái game hoặc server live.

## Đã sửa

- Migration cấu hình chỉ giữ `lines` và `showDot` cho version 2, nhưng bản hiện tại lưu version 3. Reload một cấu hình v3 đã bật hai mục này lại tắt chúng. Giữ giá trị hợp lệ của v2/v3, vẫn đặt mặc định an toàn cho cấu hình cũ hơn.
- Khi tab ẩn mà không nhận blur/keyup, cờ phím aim và trạng thái smoothing còn tồn tại; khi quay lại chế độ aim bằng phím có thể tiếp tục aim dù người chơi đã nhả phím. Xóa cờ, reset controller và trả ownership chuột khi tab ẩn; người dùng cần nhấn lại phím.
- Bỏ các import không dùng trong runtime, một hàm đọc tên riêng không được gọi, biến renderer không dùng và destructuring không dùng trong script đối chiếu. Không xóa các API hỗ trợ còn được test chỉ vì hiện không được menu dùng.

## Xác minh và giới hạn

- `npm run check`: 296 tests, gồm regression reload và chuyển tab không blur/keyup; build và kiểm tra cú pháp userscript.
- `scripts/check-upstream.mjs` với source pin: pass bốn tổ hợp unminified/minified và hai chế độ loot; thêm kiểm tra source grenade, gun, loot, muzzle, stair, target layer và wall ray đều pass. Các kiểm tra này là fixture/mô phỏng, không xác nhận deployment live, hit rate, hoặc mọi tổ hợp tính năng.
- Rule rà tĩnh runtime/scripts không tìm thấy lỗi trong nhóm rule đã chọn sau dọn dẹp. Các mô-đun có code tương đồng hoặc API chỉ phục vụ test chưa được gộp/xóa bừa vì hành vi và contract có thể khác nhau.
