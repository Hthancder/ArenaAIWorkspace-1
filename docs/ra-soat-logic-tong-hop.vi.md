# Rà soát logic tổng hợp

Đối chiếu Duality và source Survev tại commit `3edee7e8bd07fda8a63905aab4c45b595b684a80`, kiểm tra các đường aim, input, vũ khí, lựu đạn, loot và Wallcheck. Hai thay đổi có thể kiểm chứng trong đợt này:

- ACK dùng để ước lượng RTT chỉ còn hiệu lực 1,5 giây; sau đó bù truyền đi về 0 thay vì tiếp tục dùng ping cũ. ACK mới sau khoảng gián đoạn bắt đầu ước lượng mới thay vì trộn với EWMA cũ. Đây là fallback không biết latency, không phải đo ping thực; dự đoán vẫn có thể sai khi mạng gián đoạn.
- Khi số structure/stair vượt ngân sách quét hoặc stair có collision không hợp lệ, không coi lớp bắn như bình thường. Aim bỏ ứng viên khi không xác định được lớp, thay vì bỏ qua stair có thể nằm ngoài phần đã quét. Input vật lý không bị chặn; giới hạn này có thể làm aim bỏ mục tiêu trong cảnh bất thường.

Không đổi thêm menu hay sao chép mù logic Duality. Benchmark tổng hợp cho thấy dự đoán vẫn có hồi quy trong các pha dừng, đảo chiều và A–D; không thể suy ra hitrate thật. Source fixture và benchmark không xác nhận phiên bản server đang chạy, FPS, RTT mạng thật hoặc lỗi giật đã hết khi chơi. Tự thả bom vẫn là ước lượng có giới hạn và không có xác nhận server.
