# Đường phản ứng khi mục tiêu đổi hướng

## Đối chiếu luồng hiện tại

- `installSender` bọc receiver: ghi thời điểm nhận trước xử lý native, sau đó `observeUpdate` đọc vị trí mạng từ đối tượng đã được native cập nhật. Chỉ snapshot chứa vị trí mới cấp mẫu cho `SnapshotTracker`; không tạo mẫu đứng yên từ frame render.
- `SnapshotTracker.observe` tính vận tốc đoạn mới, phát hiện đổi hướng/dừng/bắt đầu bằng ngưỡng và đặt lại lịch sử fit ngắn khi đủ bằng chứng. `boundedOscillation` độc lập giữ lịch sử vùng A–D, vô hiệu hóa midpoint khi mẫu vượt vùng trước đó thêm 0,06 đơn vị. Nếu đi từ giữa vùng ra, cần thời gian quan sát thêm trước khi có bằng chứng vượt vùng.
- World update làm cache aim vô hiệu. `pre()` tính lại cho frame sau, có thể yêu cầu scheduler gửi; nếu native sender chạy giữa snapshot và `pre`, sender tính lại thay vì dùng cache cũ. Receiver không tự gửi, cũng không ép gửi ngay. Do đó thời gian đến sender phụ thuộc lịch frame và native scheduler; không thể suy ra ms live từ code tĩnh.
- Human-like Lock có smooth riêng; sau phát hiện, góc đầu ra vẫn có thể cần nhiều frame để tiến tới góc mới. Tắt Human-like là lựa chọn riêng đã có, không mặc định tắt và không ảnh hưởng Assist.
- Ở source `08346fb6...` client `game.ts`, native so sánh khác biệt input (góc hơn 0,1 độ) hoặc timeout trước khi gửi. Mạng, server tick, vòng lặp browser và các điều kiện triển khai live vẫn ảnh hưởng kết quả.

## Mô phỏng phát hiện

Chạy `node scripts/benchmark-aim-reaction.mjs`. 60 phase cho mỗi tình huống; snapshot 33 Hz đều, lượng tử 16 bit trên 1024 đơn vị; không jitter/backlog. Thời gian đầu là từ sự kiện trên server giả lập đến snapshot đầu có timestamp sau sự kiện được nhận, gồm downlink. Thời gian sau là từ snapshot đó đến khi vận tốc đổi dấu/dừng theo ngưỡng hoặc midpoint tắt; đây chỉ là proxy phân loại, không đo góc ngắm hay gửi input. Mẫu tại sự kiện có thể chứa quãng di chuyển cả trước và sau sự kiện. Mọi case dưới đây có lịch sử baseline hợp lệ.

| Tình huống | Downlink | Sự kiện → snapshot đầu trung vị/p95 | Snapshot đầu → phân loại trung vị/p95 |
|---|---:|---:|---:|
| Đảo chiều | 30 ms | 45,2 / 58,8 ms | 30,3 / 30,3 ms |
| Dừng | 30 ms | 45,2 / 58,8 ms | 30,3 / 30,3 ms |
| Thoát A–D cùng trục từ giữa vùng | 30 ms | 45,2 / 58,8 ms | 60,6 / 60,6 ms |
| Thoát A–D vuông góc | 30 ms | 45,2 / 58,8 ms | 0 / 30,3 ms |

Tất cả mẫu kịch bản này phân loại trước 800 ms. Kết quả chỉ áp dụng quỹ đạo cụ thể, không phải giới hạn hay cam kết live; không bao gồm CPU receiver, frame, điều khiển góc, scheduler, uplink, bay đạn, va chạm hay jitter. Ở 80/150 ms downlink, phần đầu tăng tương ứng nhưng phần sau trong mô hình giữ nguyên vì cadence đều.

## Kết luận và việc tiếp theo

Đã có phản ứng dựa trên dữ liệu chứ không cần đoán trước đổi hướng. Thử giảm ngưỡng vượt vùng hoặc phản ứng theo vận tốc ngắn có thể phát hiện thoát sớm hơn, nhưng dễ hiểu nhầm một nhịp A–D bình thường; cần so sánh nhiều pha, nhiễu, A–D liên tục và độ trễ khi rời vùng. Không tự hứa bỏ hoàn toàn đánh đổi. Chưa có thay đổi runtime, chưa đo latency thực hay chứng minh được thay đổi nào an toàn hơn. Việc tiếp theo là thử ứng viên trong benchmark và đo đầu ra controller/sender, kèm kiểm tra Wallcheck và Assist, trước khi cân nhắc tích hợp.
