# Tabspace 0.8 — bản thử nghiệm

## Cài vào Chrome
1. Giải nén file ZIP vào một thư mục cố định. Đừng xóa thư mục sau khi cài.
2. Truy cập `chrome://extensions`, bật **Chế độ dành cho nhà phát triển**.
3. Chọn **Tải tiện ích đã giải nén** và chọn thư mục chứa `manifest.json`.
4. Ghim Tabspace trên thanh công cụ; nhấn icon để mở popup, chọn **Mở không gian quản lý**. Có thể chỉnh phím tắt tại `chrome://extensions/shortcuts`.

## Kiểm thử
- Chọn **Tìm tất cả** để tìm đồng thời tab đang mở, nhóm, tab đã lưu, phiên và preset. Chọn **Tag** để xem số nhóm và tab gắn mỗi tag. Tab không tự kế thừa tag của nhóm; nội dung trang không được tìm kiếm.
- Chọn các tab đang mở, dùng **Lưu đã chọn** để lưu bản sao hoặc **Lưu & đóng đã chọn** để lưu trước rồi đóng. Tạo/chỉnh nhóm, mở từng tab hoặc cả nhóm, thêm tag cho nhóm và tab, ghi chú cho tab, chuyển bản lưu giữa các nhóm và tìm kiếm theo tag/ghi chú.
- Nút **Nghỉ** cho tab nền (không ghim, không phát âm thanh) vào trạng thái discard sau xác nhận. Chrome có thể từ chối; trang sẽ tải lại khi mở và trạng thái chưa lưu có thể mất.
- Trong **Thùng rác**, khôi phục hoặc xóa vĩnh viễn nhóm, tab đã lưu và phiên đã xóa từ phiên bản này. Không tự xóa theo thời gian; dữ liệu có trong file sao lưu. Nếu nhóm gốc bị xóa, khôi phục nhóm trước khi khôi phục tab.
- Trong **Lịch sử dọn**, xem kết quả các lượt lưu & đóng mới và mở lại các tab xác nhận đã đóng. Nhật ký được xuất trong JSON; lịch sử nhập lại có thể trỏ tới các trang đã mở trên thiết bị khác. Trạng thái không rõ cần kiểm tra thủ công; không thực hiện cùng lúc trên hai cửa sổ Tabspace.
- Trong **Preset dọn tab**, tạo preset với tên miền và nhóm đích, sau đó xem trước và chọn tab để lưu & đóng. Tab đang xem, ghim, phát âm thanh hoặc ẩn danh được bỏ qua. Không phân biệt tài khoản theo URL; Chrome không cho biết chắc tab có dữ liệu chưa lưu.
- Trong **Phiên đã lưu**, lưu thủ công các tab web trong cửa sổ thường; chọn từng tab để mở lại trong cửa sổ mới. Bản lưu không chứa nội dung form, lịch sử điều hướng hoặc nhóm Chrome; các trang có thể tải ngay.
- Trong **Cài đặt & sao lưu**, xuất JSON; nhập để gộp hoặc thay thế. File chứa nhóm, phiên, preset, thùng rác, lịch sử và có thể chứa URL hoặc dữ liệu nhạy cảm. Chế độ thay thế giữ lịch sử và thùng rác cũ rồi thêm từ file. Sao lưu ra ngoài Chrome profile.

## Giới hạn quan trọng
Đây là bản thử nghiệm đầu tiên, không phải bản hoàn chỉnh theo tài liệu thiết kế. Chưa có preset tự động, lịch, tự động đóng, workspace, snapshot tự động, âm thanh tùy chỉnh, thông báo nền, đồng bộ hoặc bảo vệ tùy chỉnh. Xóa vĩnh viễn trong thùng rác không thể hoàn tác. Chỉ lưu URL http/https; Chrome có thể không cho mở hoặc thao tác một số tab. Lưu & đóng không bảo toàn nội dung chưa lưu hay trạng thái trang; chỉ dùng với trang bạn biết an toàn. Việc nhập thay thế sẽ xóa dữ liệu đang lưu. Không dùng extension làm bản sao lưu duy nhất.
