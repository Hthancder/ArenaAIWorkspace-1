# Rà soát khôi phục minimap

Duality can thiệp đánh dấu minimap qua hook toàn cục; Reborn giữ hook cục bộ và vẽ lại qua renderer native. Bản trước ghi nhận cấu hình đã vẽ **trước** khi `renderMap` thành công. Nếu renderer tạm lỗi, các lần đồng bộ sau thấy cùng cấu hình và không thử lại; khi tắt, việc khôi phục cũng có thể bị bỏ qua sau lỗi.

Nay chỉ chốt cấu hình sau khi redraw thành công, giữ trạng thái cần khôi phục nếu render bật bị lỗi giữa chừng, và thử lại sau ít nhất 2 giây; đổi cấu hình không phải đợi timeout cũ. Không bảo đảm khôi phục nếu renderer vẫn lỗi khi dispose/rời trận. Test dùng renderer giả ném lỗi trước khi hồi phục, không chứng minh lỗi này xảy ra trên game live.
