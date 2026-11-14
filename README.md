# Tabspace

Thiết kế: [docs/tabspace-design.md](docs/tabspace-design.md). Bản thử nghiệm Chrome extension nằm trong `extension/`; hướng dẫn cài đặt và giới hạn tại [extension/HUONG-DAN.md](extension/HUONG-DAN.md).

Đóng gói: `cd extension && zip -r ../tabspace-extension.zip .`.

### Âm báo thử nghiệm (0.84)
Trong **Cài đặt & sao lưu → Âm báo**, có thể bật riêng âm kết quả đóng tự động thành công hoặc bị chặn/không rõ, chọn hai âm có sẵn hoặc file âm cục bộ (tối đa 1 MB, 5 giây), chỉnh âm lượng và nghe thử. Mặc định tắt. Chỉ cố phát khi trang quản lý đang mở và chứng kiến lượt chuyển trạng thái; không mở trang phát âm, không phát bù, không phát cho lời nhắc preset. Chrome có thể chặn phát tự động ngay cả khi nghe thử được. Giờ yên lặng, tùy chọn toàn màn hình và tạm dừng tự động hóa có hiệu lực; âm bị bỏ qua, không phát dồn. Âm tùy chỉnh và thiết lập âm không có trong bản sao lưu; lưu cục bộ và có thể xóa trong cài đặt.

### Thông báo trên website thử nghiệm (0.85)
Tại **Cài đặt & sao lưu → Thông báo trên website**, có thể bật riêng lời nhắc mới và kết quả đóng tự động, rồi thêm từng website và cho phép Chrome truy cập. Mặc định tắt; Chrome có thể cấp quyền đọc/thay đổi dữ liệu trên mọi đường dẫn và cổng của tên miền đã chọn. Tabspace chỉ cố hiển thị đúng giao thức, tên miền và cổng đã chọn, trên tab thường đang hoạt động trong cửa sổ Chrome đang tập trung. Thông báo chỉ có câu chữ chung, website có thể quan sát, tự biến mất sau 10 giây, có nút đóng, không thực hiện thao tác đóng tab. Không bảo đảm hoạt động trên mọi trang, trang hạn chế hoặc toàn màn hình. Trong giờ yên lặng, toàn màn hình, tạm dừng tự động, hoặc khi quá gần thông báo trước, thông báo bị bỏ qua và không phát bù; các kênh OS và âm báo vẫn độc lập. Bỏ website/tắt tính năng không thu hồi quyền Chrome: quản lý quyền trong chi tiết extension. Thiết lập không xuất/nhập sao lưu.
