# SiriX — tiến độ thực hiện thiết kế v1.2

> **1.1.1 — refactor Settings & logic.** Giao diện cài đặt được làm lại theo một tầng
> dùng chung (`Prefs/SXUISupport`), logic prefs có kiểm tra hợp lệ, và một số lỗi
> trong pipeline được vá. Chi tiết ở mục cuối tài liệu.

Tài liệu thiết kế là mục tiêu, không phải danh sách tính năng đã hoàn tất.
Không đổi phiên bản gói sang 1.2 cho đến khi các hạng mục bắt buộc được thực hiện và kiểm thử.

## Đã thực hiện trong mã (vẫn cần kiểm thử trên thiết bị)

- Sửa ghi log sau khi xóa hoặc xoay vòng, và làm mới màn hình xem log.
- Các hook chỉ được cài khi class/selector có mặt; một quyết định trả lời được áp dụng cho các lệnh AddViews/SayIt cùng lượt, kèm giới hạn thời gian và ưu tiên tác vụ hệ thống khi đã nhận diện.
- Chế độ kích hoạt `auto` / `prefix`; trong `prefix`, chỉ `@ai` có nội dung được gửi tới AI, còn `@siri` hoặc câu không có tiền tố giữ Siri gốc. Nhận diện chính xác `@ai` phụ thuộc transcript Apple, nên Type-to-Siri là cách thử đáng tin cậy hơn.
- Tùy chọn hiển thị bản Siri gốc khi lệnh AddViews có văn bản; bản gốc không được đưa vào lời đọc.
- Trò chuyện thử trong Settings với provider đang chọn, không dùng tool và không lưu lịch sử lâu dài.
- Kiểm tra kết nối chạy nền, dùng đúng provider của trang cấu hình; retry HTTP 429/5xx tối đa hai lần mỗi vòng trên luồng nền.
- Lịch sử lưu trên thiết bị có giới hạn, xem chi tiết/sao chép/xóa từng mục hoặc toàn bộ; lượt ở chế độ không lưu chỉ ở bộ nhớ. Không phải chế độ ẩn danh mạng hoặc log.
- Thống kê thay/giữ/lỗi/hết giờ và thời gian trung bình có trọng số; có thể xóa riêng. Lưu/đọc kho làm trên hàng đợi nền, dùng lock liên tiến trình và epoch để tránh đáp án cũ phục hồi dữ liệu sau khi xóa.

## Chưa hoàn tất so với thiết kế

- STT thay Apple, ghi mic, dịch transcript và thử STT.
- TTS tùy chỉnh, chọn giọng/nguồn, tự nhận ngôn ngữ, và chống Siri đọc chồng.
- Deferred push/notification cho đáp án trễ; chế độ ẩn danh toàn diện (chặn dữ liệu nhạy cảm trong mọi log và không gửi mạng) chưa có.
- Model dự phòng khi lỗi/hết giờ, hủy request theo generation, phát hiện offline sớm.
- Xuất/nhập cấu hình, kiểm tra cập nhật, công cụ `current_app`, các trang cấu hình tương ứng.
- Hiển thị stream theo từng chữ và mốc timeout theo token đầu; hiện SSE chỉ tích lũy và hiển thị khi hoàn tất.

STT, TTS và deferred push phụ thuộc API riêng, quyền mic và audio session của Siri. Không đưa các công tắc chưa hoạt động vào Settings hoặc cam kết hành vi an toàn cho đến khi có kiểm thử trên thiết bị iOS jailbreak. Log có thể chứa câu hỏi, URL hoặc dữ liệu khác. Không lưu lịch sử không đồng nghĩa với ẩn danh khi dùng mạng hoặc log.

## 1.1.1 — Refactor Settings & logic (đã làm trong mã, cần thử trên thiết bị)

### Giao diện

- **Một tầng UI dùng chung** (`Prefs/SXUISupport`): màu theo trạng thái, pill trạng thái,
  empty state, alert/confirm, định dạng ngày tương đối, đếm số. Không màn hình nào tự vẽ kiểu riêng.
- **Root**: header có pill trạng thái sống (“Sẵn sàng / Thiếu khóa API / Đã tắt”) + 4 dòng
  tổng quan đọc ngay (trạng thái, nhà cung cấp + model, cách trả lời, lịch sử). IA chia lại
  thành 10 nhóm có footer giải thích; thêm “Khôi phục cài đặt mặc định” (xác nhận trước),
  respring có xác nhận. Mọi thay đổi debounce 0,25 s rồi mới reload + phát notify.
- **Cấu hình nhà cung cấp**: khóa được che dạng `sk-…abcd`, nút dán khóa từ bộ nhớ tạm
  (tự lấy dòng đầu, chặn chuỗi quá ngắn), hiển thị endpoint đã chuẩn hóa và cảnh báo khi
  URL sai, **kết quả kiểm tra kết nối hiện ngay trong trang** (không còn hộp thoại chặn),
  lưu lại lần kiểm tra gần nhất và tự xoá khi đổi cấu hình.
- **Chọn model**: trang mới `SXModelPickerController` liệt kê model gợi ý theo nhà cung cấp,
  đánh dấu model đang dùng; vẫn giữ ô nhập tay cho endpoint tự host.
- **Trò chuyện thử**: khung chat bong bóng thật (tự co giãn, trái/phải theo vai), trạng thái
  “Đang trả lời…”, bong bóng lỗi màu riêng, mốc thời gian, chạm giữ để sao chép, xoá hội thoại.
- **Lịch sử**: nhóm theo ngày, tìm kiếm, vuốt để xoá, empty state, trang chi tiết có chia sẻ.
- **Thống kê**: header tỉ lệ thay + thanh tiến trình, các dòng số liệu theo nhóm, kéo để làm mới.
- **Log**: lọc theo mức (Tất cả / Vấn đề / Lỗi), tìm kiếm, đếm dòng, chỉ sao chép phần đang xem,
  tự bám cuối khi đang ở cuối.
- **Prompt**: thêm bộ mẫu (Ngắn gọn / Giải thích kỹ / Lập trình) chèn vào ô soạn, có xác nhận
  khi đang sửa dở.

### Logic

- `SXPrefs`: thêm ghi giá trị tổng quát, `resetAll` (xoá cả key lạ trong domain), chuẩn hoá/
  kiểm tra endpoint, che khóa, đọc key phụ, và các chuỗi tóm tắt dùng cho UI.
- `SXIntercept`: chỉ thay **một** view chính (ưu tiên `…Utterance`), không đè nội dung lên mọi
  view có chữ; quyết định chỉ dùng lại trong **cùng `dialogIdentifier`** và rút cửa sổ 30 s → 20 s.
- `SXLLM`: sửa role `functionResponse` của Gemini (`tool` → `user`, lỗi 400 trước đây);
  trả lại ngân sách retry sau mỗi request thành công; báo lỗi hết giờ rõ ràng thay vì “HTTP 0”;
  **không âm thầm rơi về api.openai.com** khi endpoint người dùng nhập không hợp lệ; UA dùng `SX_VERSION`.
- `SXTools` (`fetch_url`): chặn redirect, chặn host nội bộ/loopback/link-local, cắt body ở 2 MB.
- Thêm `scripts/check-prefs.sh` (lint plist ↔ controller ↔ selector, cân bằng ngoặc) chạy trên
  Linux và trong CI, trước job build.

### Vẫn còn thiếu (như trước 1.1.1)

STT/TTS thay Apple, deferred push cho đáp án trễ, model dự phòng, huỷ request theo generation,
xuất/nhập cấu hình, và hiển thị stream theo từng chữ trong bubble.
