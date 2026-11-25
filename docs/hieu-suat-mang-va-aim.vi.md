# Hiệu suất, mạng và ưu tiên aim

Đối chiếu Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff`, không phải xác minh trên bản live. Game tạo PIXI Application ưu tiên WebGL và fallback Canvas khi khởi tạo thất bại (`client/src/main.ts`); player đã nội suy vị trí theo khoảng cập nhật (`client/src/objects/player.ts` và `client/src/game.ts`). Userscript không thể ép một trình duyệt dùng GPU cụ thể hay bảo đảm WebGL được tăng tốc phần cứng. Không chuyển thuật toán aim sang GPU: lượng phép tính nhỏ và trao đổi CPU/GPU có thể tăng độ trễ; chưa có benchmark chứng minh lợi ích.

## Đã thay đổi

- Trong ticker, xử lý aim và yêu cầu native gửi aim trước Auto Loot; vẫn giữ các phụ thuộc layer và chuyển vũ khí. Aim được gọi ở callback ưu tiên cao hơn callback visual của script. Điều này không thể ưu tiên nó hơn mọi công việc game/trình duyệt hoặc bảo đảm deadline.
- Chỉ quét obstacle và registry cấu trúc khi có đối tượng tiềm năng cần kiểm tra. Không bỏ wallcheck, muzzle check hoặc giảm số candidate được kiểm tra. Bộ lọc FOV/team chạy trước kiểm tra layer, nên số đếm lý do loại trong diagnostics có thể khác khi một mục tiêu vi phạm nhiều điều kiện.
- Snapshot không chứa vị trí không còn quét toàn bộ danh sách người chơi. Xóa object vẫn được xử lý, và tracker vẫn cập nhật khi có vị trí mới.
- Đánh dấu thời gian nhận ngay trước native update, nhưng vẫn chỉ lấy trạng thái sau khi game xử lý xong. Do đó thời gian xử lý native không bị cộng nhầm vào RTT/tuổi snapshot. RTT/2 vẫn chỉ là ước tính, không xác định được độ trễ từng chiều; không cam kết cải thiện độ chính xác trong mọi điều kiện.

## Giới hạn mạng

Không thay đổi tần suất snapshot server, thuật toán nội suy game, codec, băng thông hoặc các gói dữ liệu. Không xếp hàng, bỏ gói hoặc làm giả vị trí để che lag: những cách này có thể làm tăng độ trễ, mất đồng bộ hoặc giảm độ chính xác. Các tối ưu client này không làm giảm ping, mất gói, jitter mạng hay đảm bảo hết giật; khi snapshot cũ, predictor vẫn áp dụng giới hạn tin cậy hiện có. Chưa đo FPS, băng thông, ping hay tỷ lệ trúng thực tế trước/sau trên máy người dùng.

Nếu còn giật khi mạng yếu, thử kết nối ổn định hơn (ưu tiên dây hoặc Wi-Fi tốt), đóng tải nền, chọn máy chủ gần nếu game cho phép; kiểm tra ping, packet loss và FPS để phân biệt mạng với render. Trên trình duyệt hỗ trợ, có thể kiểm tra cài đặt tăng tốc phần cứng và trạng thái WebGL, nhưng không có bảo đảm trình duyệt chọn đúng GPU hoặc cải thiện mạng.
