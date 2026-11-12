# Tabspace 0.1 — bản thử nghiệm

## Cài vào Chrome
1. Giải nén file ZIP vào một thư mục cố định. Đừng xóa thư mục sau khi cài.
2. Truy cập `chrome://extensions`, bật **Chế độ dành cho nhà phát triển**.
3. Chọn **Tải tiện ích đã giải nén** và chọn thư mục chứa `manifest.json`.
4. Ghim Tabspace trên thanh công cụ; nhấn icon để mở popup, chọn **Mở không gian quản lý**. Có thể chỉnh phím tắt tại `chrome://extensions/shortcuts`.

## Kiểm thử
- Chọn các tab đang mở, dùng **Lưu đã chọn** để lưu bản sao hoặc **Lưu & đóng đã chọn** để lưu trước rồi đóng. Tạo/chỉnh nhóm, mở từng tab hoặc cả nhóm, thêm tag cho tab đã lưu, tìm kiếm.
- Nút **Nghỉ** cho tab nền (không ghim, không phát âm thanh) vào trạng thái discard sau xác nhận. Chrome có thể từ chối; trang sẽ tải lại khi mở và trạng thái chưa lưu có thể mất.
- Trong **Cài đặt & sao lưu**, xuất JSON; nhập để gộp hoặc thay thế. File chứa URL và dữ liệu nhạy cảm. Sao lưu ra ngoài Chrome profile.

## Giới hạn quan trọng
Đây là bản thử nghiệm đầu tiên, không phải bản hoàn chỉnh theo tài liệu thiết kế. Chưa có preset, lịch, tự động đóng, workspace, phiên/snapshot, thùng rác, hoàn tác, âm thanh tùy chỉnh, thông báo nền, đồng bộ hoặc bảo vệ tùy chỉnh. Xóa bản lưu/nhóm là vĩnh viễn sau xác nhận. Chỉ lưu URL http/https; Chrome có thể không cho mở hoặc thao tác một số tab. Lưu & đóng không bảo toàn nội dung chưa lưu hay trạng thái trang; chỉ dùng với trang bạn biết an toàn. Việc nhập thay thế sẽ xóa dữ liệu đang lưu. Không dùng extension làm bản sao lưu duy nhất.
