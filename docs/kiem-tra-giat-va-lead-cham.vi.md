# Kiểm tra giật và lead mục tiêu chậm

## Công việc runtime

Đã giảm xử lý lặp khi tái khám phá mapping: membership của player pool được lập một lần thay vì lọc pool cho từng object; source-field adapter chỉ dùng cache nếu danh sách phương thức và net key không thay đổi. Tracker suy luận riêng đối với player đã ổn định và không có delta bỏ bớt lần fit sát nhau dưới 50 ms; delta vị trí thật vẫn xử lý ngay. Đây là những đường có khả năng tốn CPU, không chứng minh chúng gây giật trong trận cụ thể.

`node scripts/benchmark-stationary-updates.mjs`: thử tổng hợp 64 player đứng yên, 10.000 tick cách 33 ms, trên Node trong sandbox. Một lần chạy riêng baseline 1.172,8 ms / 640.000 kiểm tra, bản gated 491,5 ms, số phép fit 640.000 → 320.064; mẫu cuối có tuổi 33 ms thay vì 0. Khi chạy song song tác vụ khác kết quả 2.010,2 → 1.000,7 ms. Đây là microbenchmark của tracker, **không phải FPS game**, không tính draw, DOM, game hay network. Player di chuyển mới không bị throttle; test kiểm tra delta thật được dùng ngay.

Diagnostics `runtimePerformance` có p95 và max của tối đa 256 mẫu mới nhất, peak cả phiên, cho `inputFrame`, `visualFrame`, `snapshotHook`, `discovery`, `xrayScan`; mỗi số chỉ đo thời gian thực thi code script tại hook đó, không đo GPU, game, RTT, GC bên ngoài hook hay frame rate thực. P95 có thể bị pha loãng sau khi mở menu; peak cả phiên không cho biết thời điểm. `featureMs` cũ chỉ là một lần post, không đại diện cho cả frame.

## Súng bắn từng viên, mục tiêu chậm

`node scripts/benchmark-slow-target.mjs` so sánh 3 hướng thay lead trên quỹ đạo tổng hợp thẳng 1/2/4 đơn vị mỗi giây, đảo chiều chậm, stop/start và chạy nhanh; 30/60/144 Hz, snapshot 33 Hz, down/up 30/80/150 ms, tốc độ đạn 66/100/182. Không mô phỏng random spread, server cooldown/buffering, chính xác RTT từng chiều hoặc live gameplay; đây là sai số góc quy đổi khoảng cách, không phải tỉ lệ trúng.

Cắt nửa lead giảm p95 reverse2 từ 3,582 xuống 2,586 đơn vị nhưng làm straight2 từ 0,399 lên 1,331, và straight4 từ 0,785 lên 2,578. Giảm lead theo độ bất định cũng làm trường hợp thẳng xấu đi, ví dụ straight2 p95 0,399 → 0,562. Vì vậy **không áp dụng** các phương án này cho runtime; không thể kết luận khắc phục hụt súng từng viên. Source server có thể buffer `shootStart` single khi cooldown còn dưới 0,1 giây, nhưng client không có xác nhận chính xác cooldown server để cộng thời gian giả vào mọi viên bắn.

Để chẩn đoán trận thật, cần `runtimePerformance`, `aimEvidence.lastEngagedFailure`, `lastPrediction`, `aimControls`, tên súng và trường hợp mục tiêu đi chậm thẳng hay A–D; ghi lại trong cùng trận sau khi tái hiện. RTT chỉ là ước lượng ACK cục bộ, không phải latency một chiều chính xác.
