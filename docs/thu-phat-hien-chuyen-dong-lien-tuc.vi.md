# Thử phát hiện chuyển động liên tục trong vùng A–D

## Ứng viên và cách tái hiện

Dùng bốn snapshot gần nhất: nếu cả ba đoạn liên tiếp theo cùng một hướng, và khoảng dời trong bốn mẫu vượt 55%, 80%, hoặc 100% bề rộng vùng đã quan sát (có sàn 0,2), tạm ngừng midpoint, kể cả khi vẫn còn trong vùng. Không cần dự đoán đổi hướng tương lai. Đây là giả thuyết, không phải mã được đưa vào sản phẩm.

`node scripts/make-aim-experiments.mjs` tạo các bản sao trong `.cache/aim-candidates`, không sửa `src`. Ví dụ:

```sh
node scripts/make-aim-experiments.mjs
node scripts/benchmark-aim-reaction.mjs
AIM_MODULE="file://$PWD/.cache/aim-candidates/aim-0.55.mjs" node scripts/benchmark-aim-reaction.mjs
node scripts/benchmark-micro-strafe.mjs --human
AIM_MODULE="file://$PWD/.cache/aim-candidates/aim-0.55.mjs" node scripts/benchmark-micro-strafe.mjs --human
```

Thay `0.55` bằng `0.8` hoặc `1` để thử các ngưỡng khác. `benchmark-midpoint-stability.mjs` cũng nhận `AIM_MODULE`. Test này dùng các trường hợp đã biết, không phải dữ liệu độc lập; không chứng minh giải pháp tối ưu.

## Kết quả

- Reaction giả lập: 55% rút trung vị phát hiện thoát cùng trục sau snapshot đầu từ 60,6 xuống 30,3 ms, p95 vẫn 60,6 ms. 80% và 100% không cải thiện trường hợp này. Không có nghĩa input được gửi sớm hơn tương ứng.
- Micro-strafe + Human-like: ở A–D width 1,2 và radius 0,75, trung vị/p95 sai số current 0,437/2,365, 55% 0,795/2,474, 80% 0,671/2,350. Tỷ lệ sai số vuông góc vượt bán kính giả định lần lượt 28,51%, 51,67%, 46,92%; đây không phải hit rate. 100% cho kết quả giống current ở toàn bộ kịch bản script này.
- Thoát cùng trục width 1,2, radius 0,75, chỉ giai đoạn thoát: current 4,505/7,919; 55% 4,445/8,017; 80% 4,199/7,697. Thử nghiệm 80% cải thiện kịch bản này nhưng làm A–D thường xấu đi như trên.
- Bộ kiểm tra midpoint tuần hoàn đều không cho thấy thay đổi ở 55%; bộ micro-strafe có quỹ đạo và jitter khác đã phát hiện sự suy giảm rõ rệt. Một benchmark riêng lẻ là không đủ để duyệt.

Kết luận: không đưa các ứng viên vào runtime. Không có bằng chứng đạt thuật toán tốt nhất; còn thiếu trace thực, mô hình va chạm và đo thời gian thực từ receiver qua controller tới gói native. Không thể bảo đảm mọi kiểu di chuyển hoặc không có trade-off. Test `npm run check`: 191/191; integration source ghim: bốn biến thể qua, không phải test live.
