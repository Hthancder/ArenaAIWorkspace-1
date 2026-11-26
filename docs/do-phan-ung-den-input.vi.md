# Đo phản ứng từ snapshot tới input trong fixture source

Chạy `node scripts/check-upstream.mjs .cache/survev` với checkout Survev ghim `3edee7e8bd07fda8a63905aab4c45b595b684a80`. Fixture trích các phương thức client và serializer thực từ source, dùng collaborators giả và đồng hồ ảo; không mở trận hay kết nối mạng.

## Cập nhật ở frame kế tiếp

Mục tiêu đứng yên dịch từ `(12,20)` đến `(12,20.7)` trong fixture; prediction tắt, Human-like tắt, Lock và Wallcheck bật. Snapshot đến ở 10%, 50% hoặc 90% khoảng giữa hai frame. Receiver không tự gửi, test không ép timeout; `pre()` và native input frame kế tiếp đưa hướng mới qua serializer. Cả 30/60/144 Hz, bốn biến thể unminified/minified và hai chế độ loot đều qua.

Khoảng chờ có chủ ý từ receive đến frame tiếp theo, theo đồng hồ ảo: 30 Hz 3,33–30 ms; 60 Hz 1,67–15 ms; 144 Hz 0,69–6,25 ms. Đây là **lịch giả lập do test đặt**, không đo thời gian CPU, độ trễ trình duyệt hay độ trễ game live. Kết quả không chứng minh input luôn gửi ngay sau mọi snapshot: native chỉ gửi theo diff/timeout và tùy luồng thực tế.

## Human-like trên dây đã serialize

Cùng một thay đổi vị trí, sau một giây warm-up, snapshot đến ở giữa frame. Đo đến khi góc trên gói InputMsg đạt 90% góc mục tiêu mới, với `smoothProfile=responsive`, prediction tắt và các điều kiện còn lại như trên. Không có network, tick server, spread hay người chơi thật. `smooth=0` đi thẳng tới góc, không làm mượt, dù cờ Human-like vẫn bật.

| Smooth | 30 Hz | 60 Hz | 144 Hz |
|---|---:|---:|---:|
| 0 | 16,7 ms | 8,3 ms | 3,5 ms |
| 20 | 183,3 ms | 175,0 ms | 170,1 ms |
| 50 | 283,3 ms | 275,0 ms | khoảng 281,3 ms |

Đây là **thời gian hội tụ 90% trong tình huống nhân tạo**, không phải thời gian phát hiện đổi hướng, hit rate, đo thực tế hoặc thời gian mọi trường hợp. Smoothing không có mức trễ cố định: góc, vận tốc góc trước đó, nhịp khung hình, profile và mục tiêu thay đổi liên tục đều ảnh hưởng. Output được làm mượt là một yếu tố có thể đáng kể sau khi dữ liệu đã đến; đánh đổi là độ mượt. Người dùng có thể điều chỉnh Smooth hoặc tắt Human-like trong Lock nếu muốn phản ứng trực tiếp hơn. Không thay đổi mặc định, Assist hay thuật toán trong lượt này.

Cần các kịch bản chuyển động liên tục, góc và tốc độ khác nhau, biến thiên frame, prediction, wallcheck, controller và dữ liệu live trước khi đề xuất thay đổi tự động; không suy diễn các số này thành ping hoặc hiệu quả gameplay.
