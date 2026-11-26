# Lock khi người bắn di chuyển quanh mục tiêu

Người dùng báo đồng đội đứng yên trong FOV, còn mình chạy vòng quanh và giữ bắn: tâm Lock chậm, lệch ra rìa. Ngay cả khi cả hai vị trí được biết chính xác, **hướng từ người bắn tới mục tiêu vẫn liên tục xoay**; Human-like SmoothDamp có độ trễ theo hướng đang xoay. Độ trễ vị trí người bắn, tick, độ lệch giữa vị trí render và snapshot, độ trễ mạng, và spread cũng có thể góp phần; không thể suy ra tỉ lệ trúng từ một giả lập.

## Tùy chọn mới

Main → Aim — Mode & activation → **Lock tức thời khi giữ Fire**. Mặc định tắt; khi bật, Lock bỏ smooth chỉ trong lúc đang giữ Fire, còn prediction, Wallcheck, lựa chọn mục tiêu và Fire vẫn theo logic hiện tại. Nếu activation là phím, khi không Fire vẫn dùng Human-like như trước; thả Fire khôi phục smooth. Assist không bị thay đổi. Khi activation là Fire, lựa chọn này đồng nghĩa Lock trực tiếp trong phần lớn thời gian kích hoạt. Đây là lựa chọn chủ động giữa mượt và phản ứng nhanh, không thể vừa giữ quỹ đạo smooth như cũ vừa đảm bảo không có trễ do smooth.

Tắt Human-like cũng làm Lock trực tiếp, nhưng tắt nó cho toàn bộ thời gian activation. Cả hai không bù vị trí server của người bắn hoặc khử spread. Các ước lượng origin từng thử có cải thiện và regression khác nhau; chưa bật bù tùy tiện vì có thể làm trường hợp khác xấu. Không cần tắt Wallcheck hoặc prediction để thử lựa chọn mới.

## Kiểm tra controller

`node scripts/benchmark-orbit-controller.mjs` dùng vị trí lý tưởng biết chính xác, 30/60/144Hz, 3 phase, bỏ các mẫu đầu và cho các tần số trọng số ngang nhau. Đo khoảng cách vuông góc từ tia do controller trả ra đến hướng mục tiêu lý tưởng, **không phải hit rate**; không có muzzle, prediction, mạng, tick, vật cản hoặc spread. Responsive smooth 50 / smooth 0 median/p95 (world units):

| Tình huống tổng hợp | Smooth 50 | Smooth 0 |
|---|---:|---:|
| Người bắn vòng tròn, mục tiêu đứng | 1.088 / 1.126 | 0 / 0 |
| Người bắn đi thẳng, mục tiêu đứng | 0.883 / 1.104 | 0 / 0 |
| Người bắn dừng/đi, mục tiêu đứng | 0.199 / 1.065 | 0 / 0 |
| Người bắn vòng tròn, mục tiêu chuyển động | 0.998 / 1.360 | 0 / 0 |
| Người bắn đứng, mục tiêu đảo hướng | 2.268 / 2.526 | 0 / 0 |

Smooth 0 trong benchmark chỉ có nghĩa controller không thêm trễ so với nghiệm lý tưởng đã cho sẵn; không chứng minh nghiệm runtime hay thực tế là chính xác. Thử bù góc dựa tốc độ đổi hướng trong mô hình thử nghiệm làm một số đoạn dừng xấu hơn nên không tích hợp.

`lastPrediction.controllerErrorDeg` ghi chênh lệch góc giữa output controller và nghiệm predictor tại cùng thời điểm; `aimControls.smooth`, `humanLikeAim`, `lockInstantFire` cho biết cài đặt. Số này gần 0 không chứng minh ngắm đúng giữa hitbox hiển thị, đạn đi đúng server, hay trúng.
