# Aimbot: hạn chế lead thừa khi A–D rộng

## Thay đổi

Khi `Ổn định dao động A–D (Lock)` đang bật và lịch sử snapshot thực sự cho thấy ít nhất hai lần đổi chiều trong một vùng hữu hạn, bộ giải đã có nhánh nhắm trung điểm cho dao động nhỏ. Nhánh mới mở rộng có điều kiện sang đường kính trên 3,5 đến tối đa `min(6 × bán kính mục tiêu, 6)` world units, chỉ nếu đường đi quan sát đủ dài, snapshot còn mới, mục tiêu chưa rời vùng và thời gian bay danh nghĩa lớn hơn 65% thời gian đi qua vùng theo tốc độ quan sát. Không dự đoán lần đổi hướng kế tiếp. Bỏ qua nhánh này khi đang dùng Assist hoặc tắt ổn định A–D; Strict prediction sẽ bỏ qua nghiệm gần đúng này. Không thay đổi Fire hay chuẩn bị aim trước activation.

Đây là **đánh đổi**, không phải cam kết bắn trúng: trung điểm có thể nằm ngoài hitbox khi biên độ rộng, và người chơi có thể thoát vùng trước khi snapshot tới. Có thể tắt ổn định A–D nếu gặp lead lệch trong lối chơi của bạn. `wide-bounded-oscillation` được đánh dấu approximate trong diagnostics. Các guard cũ về layer, Wallcheck, muzzle và độ mới snapshot vẫn áp dụng.

## Bot giả: trước `b21b23c` và sau thay đổi

Đối chiếu dùng `scripts/benchmark-bot-duel.mjs` sau khi thêm các mẫu A–D rồi dừng, thoát ngang và vừa A–D vừa trôi. Chạy 34 cặp hành vi người bắn/mục tiêu, 1.703.808 phát mô phỏng cho mỗi phiên bản; 12/35/70 wu; boost và giảm tốc bắn độc lập cho hai phía, 30/60/144 FPS và bốn cặp latency. Đường đạn được quét với hitbox tròn chuyển động. Bảng là hit proxy của **mô hình**, không phải hitrate gameplay:

| Mục tiêu | Trước | Sau | Sai lệch trung bình trước → sau (wu) |
|---|---:|---:|---:|
| A–D rộng | 30,4% | 33,5% | 2,858 → 2,265 |
| Di chuyển bất quy tắc | 28,8% | 31,9% | 2,392 → 1,828 |
| A–D đổi nhịp | 19,0% | 19,8% | 3,373 → 2,954 |
| A–D rồi chạy thoát | 60,7% | 60,8% | 1,176 → 1,099 |
| Đứng yên | 75,4% | 75,4% | 0,129 → 0,129 |
| Chạy thẳng | 77,0% | 77,0% | 0,144 → 0,144 |

Một bộ phase/nhịp/jitter khác (`--quick --holdout`, 254.592 phát mỗi phiên bản, đã được xem sau khi chạy) cho A–D rộng 40,1% → 48,7%, nhưng A–D rồi chạy thoát **giảm 62,5% → 61,2%**. Không che giấu regression này: chưa thể biết mục tiêu sẽ thoát trước khi quan sát được nó. Bộ 14 họ chuyển động tổng hợp và bài phản ứng cũng được chạy; snapshot, vận tốc, controller, source và mạng live có thể khác mô hình.

## Tái lập và giới hạn

- `npm run benchmark:bot`, hoặc `node scripts/benchmark-bot-duel.mjs --quick --holdout`. Có thể giới hạn `BOT_MODELS=current`; để so sánh bản cũ dùng `AIM_MODULE` trỏ tới một bản module cũ có đường import hợp lệ.
- Bot dùng các input được thiết kế thủ công, không phải người thật; các lần bắn tương quan, không phải số trận độc lập. Không có recoil, spread, tường, giải va chạm, tracking/serialization chính xác của server hay FPS trình duyệt. Xem `docs/kiem-thu-bot-doi-khang.vi.md` để biết chi tiết mô hình.
- Unit và integration kiểm tra toggle, Assist, Strict, thời gian bay ngắn, target rời vùng, lịch sử thiếu/gap và Fire không bị thay đổi. Chưa kiểm thử live, chưa xác nhận jitter hoặc hitrate đã tốt hơn.
