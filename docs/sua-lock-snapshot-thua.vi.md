# Lock và snapshot đứng yên

Một lỗi có thể tái hiện trong fixture: sau 150 ms, predictor từ chối track cũ là `uncertain`, nhưng tracker súng chỉ hết hạn sau khoảng 250 ms. Fallback đứng yên trước đây chỉ chạy khi track đã hết hạn. Với các update hoàn chỉnh cách nhau 100 ms và mục tiêu không đổi vị trí, Lock do đó có thể mất rồi bắt lại, kể cả Human-like đã tắt. Đây là một cơ chế giật có thật trong fixture, không phải bằng chứng duy nhất gây ra hiện tượng ở trận live.

Fallback nay áp dụng ngay khi track quá 150 ms nếu chuỗi update nguồn hoàn chỉnh, liên tục, mục tiêu còn hiện diện, mẫu mới và ổn định. Hai mẫu đủ để bắt đầu suy luận; chuỗi thiếu, bị ngắt hoặc có dấu hiệu di chuyển không được giả định đứng yên. Suy luận vẫn được đánh dấu approximate; Strict không dùng nó. Wallcheck, kiểm tra người chắn, tầng, activation và Assist không bị bỏ qua. Source được ghim đánh dấu partial dirty khi vị trí player đổi và player partial có pos; không chứng minh mọi server live luôn hành xử như vậy.

Test fixture chạy 180 frame, người bắn di chuyển, giữ Fire, ghi chuột native và gửi input; teammate đứng yên được bỏ qua trong update hoàn chỉnh mỗi 100 ms. Các test khác kiểm tra strict, dừng stream và cập nhật chuyển động. Fixture không mô phỏng đầy đủ server, interpolation, network, spread hay gameplay thật; cần kiểm tra live trước khi khẳng định hết giật.

Đã bỏ hai thử nghiệm khỏi menu và runtime: Lock tức thời khi Fire và bù di chuyển bản thân. Cấu hình lưu cũ của hai mục này bị bỏ qua khi nạp; Human-like, Assist, prediction, Wallcheck, tùy chọn đồng đội và grenade vẫn giữ. Các benchmark cũ chỉ là tài liệu lịch sử, không mô tả runtime hiện tại.
