# Benchmark sự kiện ngắm

Chạy `node scripts/benchmark-aim-events.mjs`. Đây là mô phỏng quyết định ngắm, không phải tỷ lệ trúng thực tế. Không thay đổi thuật toán hay userscript.

## Thiết lập

Bảy quỹ đạo tổng hợp: vừa bắt mục tiêu chạy thẳng (không có lịch sử trước sự kiện), đảo 180°, dừng, thoát A–D theo hai hướng, chạy thẳng và A–D liên tục. So sánh `current` (predictShot với Lock stabilization và bù snapshot), giảm lead còn một nửa, tắt midpoint và ngắm thẳng vị trí đã nhận. Các biến thể này là thí nghiệm, không phải bật/tắt được đề xuất trong menu. So sánh không chạy code Duality.

Snapshot đều 33 Hz, lượng tử 16 bit/1024; độ trễ lên/xuống bằng nhau 30 hoặc 80 ms; FPS 30/60/144, ba phase, tốc độ đạn 66/100/182. Cửa sổ tính từ thời điểm sự kiện thật, không phải lúc client quan sát được; acquisition chỉ tính từ khi packet đầu tiên đã đến. Tổng hợp mẫu theo frame nên FPS cao có nhiều trọng số hơn. Sai số là khoảng cách vuông góc từ đường ngắm tới vị trí mục tiêu tại thời điểm bay do mô hình từng phương án tính; fallback dùng khoảng cách tới vị trí đã nhận. Chỉ báo `outside-radius` dùng bán kính giả định 1, không phải tỷ lệ trượt trong game.

Không mô phỏng controller Human-like, spread, jitter, va chạm, input thực, bất đối xứng mạng, backlog hay server; quỹ đạo và phase hữu hạn, không phải kiểm định độc lập. Đặc biệt thoát A–D side ở đây đi gần theo hướng nhìn nên sai số vuông góc rất thấp không chứng minh tracking tốt. Các phương án có thể ước lượng thời gian bay khác nhau, nên số liệu là proxy chứ không phải so sánh va chạm chính xác. Để thực sự kiểm chứng cần thêm mô phỏng va chạm theo thời gian và trace thực.

## Kết quả lần chạy

Trung vị / p95, đơn vị thế giới (các con số có thể tái hiện):

| Kịch bản và thời gian sau sự kiện | Current | Thử nghiệm đối chứng |
|---|---:|---:|
| Bắt mục tiêu 0–150 ms | 0.886 / 12.869 | lead 0.5: 4.983 / 12.869 |
| Đảo hướng 0–150 ms | 9.594 / 24.573 | lead 0.5: 7.615 / 19.155 |
| Đảo hướng 150–400 ms | 0.426 / 1.002 | lead 0.5: 3.990 / 6.413 |
| Thoát A–D cùng trục 0–150 ms | 8.760 / 13.097 | tắt midpoint: 3.543 / 6.842 |
| A–D liên tục 0–150 ms | 0.459 / 1.422 | tắt midpoint: 5.428 / 5.817 |
| Chạy thẳng 0–150 ms | 0.081 / 0.773 | lead 0.5: 3.608 / 6.180 |

Giai đoạn đầu sau đảo/thoát bị chi phối bởi thông tin chưa đến client và quãng bay dự đoán; giảm lead toàn cục hay tắt midpoint giúp một kịch bản nhưng làm xấu rõ rệt kịch bản khác. Không đủ cơ sở đưa các thay đổi đó vào sản phẩm. Các kết quả trên không chứng minh chiến lược khác không thể tốt hơn.

## Đề xuất tiếp theo

1. Mở rộng mô hình va chạm theo thời gian, trọng số theo thời gian thay vì số frame, và các phase/biên độ/hướng cùng packet jitter, backlog, tái bắt mục tiêu.
2. Thử chỉ giảm niềm tin midpoint **sau bằng chứng rời vùng**, đo riêng độ trễ phát hiện và sự đánh đổi A–D thật so với thoát. Không giả định biết sự kiện trước khi packet đến.
3. Khi có thể, lấy trace ẩn danh và kiểm thử live để kiểm tra thời điểm nhận snapshot, cấu hình ping/perk và điều khiển Human-like. Không kết luận hiệu quả live từ mô phỏng.
