# Tabspace 0.5 — bản thử nghiệm

## Cài vào Chrome
1. Giải nén file ZIP vào một thư mục cố định. Đừng xóa thư mục sau khi cài.
2. Truy cập `chrome://extensions`, bật **Chế độ dành cho nhà phát triển**.
3. Chọn **Tải tiện ích đã giải nén** và chọn thư mục chứa `manifest.json`.
4. Ghim Tabspace trên thanh công cụ; nhấn icon để mở popup, chọn **Mở không gian quản lý**. Có thể chỉnh phím tắt tại `chrome://extensions/shortcuts`.

## Kiểm thử
- Chọn các tab đang mở, dùng **Lưu đã chọn** để lưu bản sao hoặc **Lưu & đóng đã chọn** để lưu trước rồi đóng. Tạo/chỉnh nhóm, mở từng tab hoặc cả nhóm, thêm tag cho tab đã lưu, tìm kiếm.
- Nút **Nghỉ** cho tab nền (không ghim, không phát âm thanh) vào trạng thái discard sau xác nhận. Chrome có thể từ chối; trang sẽ tải lại khi mở và trạng thái chưa lưu có thể mất.
- Trong **Thùng rác**, khôi phục hoặc xóa vĩnh viễn nhóm, tab đã lưu và phiên đã xóa từ phiên bản này. Không tự xóa theo thời gian và không được đưa vào file sao lưu; hãy khôi phục dữ liệu cần giữ trước khi xuất. Nếu nhóm gốc bị xóa, khôi phục nhóm trước khi khôi phục tab.
- Trong **Lịch sử dọn**, xem kết quả các lượt lưu & đóng mới và mở lại các tab xác nhận đã đóng. Nhật ký lưu cục bộ, không được xuất trong JSON. Trạng thái không rõ cần kiểm tra thủ công; không thực hiện cùng lúc trên hai cửa sổ Tabspace.
- Trong **Preset dọn tab**, tạo preset với tên miền và nhóm đích, sau đó xem trước và chọn tab để lưu & đóng. Tab đang xem, ghim, phát âm thanh hoặc ẩn danh được bỏ qua. Không phân biệt tài khoản theo URL; Chrome không cho biết chắc tab có dữ liệu chưa lưu.
- Trong **Phiên đã lưu**, lưu thủ công các tab web trong cửa sổ thường; chọn từng tab để mở lại trong cửa sổ mới. Bản lưu không chứa nội dung form, lịch sử điều hướng hoặc nhóm Chrome; các trang có thể tải ngay.
- Trong **Cài đặt & sao lưu**, xuất JSON; nhập để gộp hoặc thay thế. File chứa URL và dữ liệu nhạy cảm. Sao lưu ra ngoài Chrome profile.

## Giới hạn quan trọng
Đây là bản thử nghiệm đầu tiên, không phải bản hoàn chỉnh theo tài liệu thiết kế. Chưa có preset tự động, lịch, tự động đóng, workspace, snapshot tự động, âm thanh tùy chỉnh, thông báo nền, đồng bộ hoặc bảo vệ tùy chỉnh. Xóa vĩnh viễn trong thùng rác không thể hoàn tác. Chỉ lưu URL http/https; Chrome có thể không cho mở hoặc thao tác một số tab. Lưu & đóng không bảo toàn nội dung chưa lưu hay trạng thái trang; chỉ dùng với trang bạn biết an toàn. Việc nhập thay thế sẽ xóa dữ liệu đang lưu. Không dùng extension làm bản sao lưu duy nhất.
