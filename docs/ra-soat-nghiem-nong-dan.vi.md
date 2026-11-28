# Rà soát nghiệm nòng đạn và thời gian bay

## Thay đổi

Bộ giải trước đây lặp dự đoán rồi hiệu chỉnh góc nòng cuối cùng, nhưng không tính lại thời gian bay từ **nòng cuối cùng**. Với mục tiêu gần, súng có lệch ngang hoặc nòng bị clip, hướng/nòng/thời gian/điểm dự đoán có thể không khớp nhau. Bộ giải nay tính lại giao điểm và kiểm tra sai số tâm của mô hình; nếu cần, hiệu chỉnh góc tối đa 9 bước và kiểm tra lại tầm bắn. Không thêm setting, không thay chính sách chọn mục tiêu hoặc smoothing.

Khi không hội tụ, giữ nghiệm cũ để không tự tắt aim ở cự ly gần (đặc biệt khi nòng ở trong hitbox), nhưng đánh dấu `unresolved-muzzle-solution` và `approximate`. Strict prediction sẽ từ chối nghiệm đó; Fire thủ công vẫn nguyên. Đây **không** phải lời giải va chạm trong hitbox: trường hợp không hội tụ vẫn có thể sai lớn, đặc biệt cạnh vật cản. Clip thay đổi giữa các góc, thứ tự vật cản, input động, spread và va chạm game thật chưa được chứng minh bằng kiểm tra này.

## Kiểm thử tổng hợp

Chạy `node scripts/benchmark-muzzle-consistency.mjs`, 60.000 tổ hợp xác định có/không một vật tròn, vị trí 1–50 wu, tốc độ, lệch nòng và chuyển động giả lập; đây là kiểm tra nhất quán nội bộ chứ không phải hitrate. So sánh bản trước `e566c42` với bản sửa trên cùng dữ liệu:

- Không vật cản, khoảng 4–10 wu: số nghiệm lệch tâm mô hình >0,02 wu giảm từ 1.327/3.674 xuống 0; 10–50 wu giảm từ 48/24.489 xuống 0.
- Có vật tròn: 4–10 wu giảm từ 1.121 xuống 8/3.674; 10–50 wu giảm từ 64 xuống 17/24.489. Các trường hợp còn lại không hội tụ và được đánh dấu gần đúng.
- Cự ly 1–4 wu: không vật cản còn 937/1.837 không hội tụ; có vật tròn còn 804/1.837. Các trường hợp này giữ nghiệm cũ, không chứng minh bắn trúng; trong fixture vật tròn sai lệch lớn nhất của nghiệm giữ lại là 23,78 wu trên toàn bộ khoảng cách.

Benchmark 14 họ chuyển động với các seed đã dùng trong phát triển không cho thấy thay đổi ở những dòng sai số đã kiểm tra ở khoảng cách xa; nó không thay thế kiểm thử độc lập. Những đánh đổi stop/đảo chiều của predictor vẫn tồn tại. Chưa đo hiệu quả, FPS hoặc độ giật trong game live.
