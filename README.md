# Tabspace

Thiết kế: [docs/tabspace-design.md](docs/tabspace-design.md). Bản thử nghiệm Chrome extension nằm trong `extension/`; hướng dẫn cài đặt và giới hạn tại [extension/HUONG-DAN.md](extension/HUONG-DAN.md).

Đóng gói: `cd extension && zip -r ../tabspace-extension.zip .`.

### Âm báo thử nghiệm (0.84)
Trong **Cài đặt & sao lưu → Âm báo**, có thể bật riêng âm kết quả đóng tự động thành công hoặc bị chặn/không rõ, chọn hai âm có sẵn hoặc file âm cục bộ (tối đa 1 MB, 5 giây), chỉnh âm lượng và nghe thử. Mặc định tắt. Chỉ cố phát khi trang quản lý đang mở và chứng kiến lượt chuyển trạng thái; không mở trang phát âm, không phát bù, không phát cho lời nhắc preset. Chrome có thể chặn phát tự động ngay cả khi nghe thử được. Giờ yên lặng, tùy chọn toàn màn hình và tạm dừng tự động hóa có hiệu lực; âm bị bỏ qua, không phát dồn. Âm tùy chỉnh và thiết lập âm không có trong bản sao lưu; lưu cục bộ và có thể xóa trong cài đặt.
