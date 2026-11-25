# Ổn định A–D và hitbox nhỏ

Lock + Auto prediction có tùy chọn **Ổn định dao động A–D (Lock)**, mặc định bật; có thể tắt khi không phù hợp. Assist không dùng cơ chế này. Bộ dự đoán chỉ giả định mục tiêu dao động quanh giữa vùng sau ít nhất 550 ms lịch sử hợp lệ, hai lần đổi chiều và đường kính không quá `min(3.5 × bán kính, 3.5)` world unit (thay đổi mới và đánh đổi được đo trong `aim-giua-vung-ad.vi.md`). Không còn loại giả thuyết chỉ vì vận tốc tức thời lớn: A–D nhanh cũng có thể là dao động. Nếu điểm mới vượt vùng quan sát trước hơn 0.06 wu trên một trục, giả thuyết bị bỏ ngay ở snapshot đó; khoảng trống >150 ms, dữ liệu cũ hay vùng quá rộng cũng vô hiệu hóa nó. Trước khi có snapshot vượt vùng, không thể biết đối phương đã quyết định chạy; nhiễu hoặc vùng đang trôi vẫn có thể gây kích hoạt sai. Tắt tùy chọn nếu thấy bám chậm khi mục tiêu thoát.

## Đối chiếu nguồn

Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff`: `server/src/game/objects/player.ts` tính `rad = GameConfig.player.radius * scale`, `recalculateScale()` cập nhật collider theo perk, last breath và fat modifier; `shared/gameConfig.ts` đặt bán kính cơ bản 1. Scale mạng được mã hóa 8 bit trong khoảng 0.75–2 (`shared/net/net.ts`, `objectSerializeFns.ts`); client `player.ts` cũng dùng scale mạng nhân bán kính. Skin trông nhỏ không chứng minh collider nhỏ; client chỉ có scale đã lượng tử hóa, không đảm bảo hình học máy chủ đúng tuyệt đối ở mọi thời điểm. Các bán kính 0.35/0.5 dưới đây là stress test giả định, không phải giá trị tối thiểu của nguồn này.

## Benchmark tổng hợp (không phải hit rate)

Chạy `node scripts/benchmark-micro-strafe.mjs`. Snapshot giả lập 33 Hz, lượng tử hóa vị trí 16 bit trên 1024 wu, trễ 35 ms, trường hợp có jitter và gap, render 30/60/144 Hz, 3 seed và tốc độ đạn 66/100/182; mục tiêu chạy hình tam giác tốc độ 12 wu/s, có kịch bản thoát theo hai hướng và trôi chậm. Mỗi hàng 37.620 phép tính. Thước đo là khoảng cách vuông góc từ tia ngắm dự đoán đến tâm tương lai giả lập, không mô phỏng toàn bộ đường đạn, va chạm, spread, vật cản, bắn thật hay hành vi người chơi. So sánh cùng seed đã dùng để thiết kế, không phải tập kiểm định độc lập.

Các con số dưới đây là phép so sánh lịch sử của lần triển khai trước, không phải bảng so sánh cho giới hạn 3.5 mới.

| Kịch bản | Trung vị trước → sau (wu) | p95 trước → sau (wu) | Ngoài bán kính trước → sau |
|---|---:|---:|---:|
| A–D, radius 0.75 | 6.595 → 0.371 | 11.696 → 9.228 | 95.99% → 19.85% |
| A–D, radius 0.35 (stress) | 4.731 → 0.167 | 12.039 → 7.938 | 76.98% → 17.58% |
| Thoát ngang, radius 0.75 | 5.698 → 0.584 | 14.052 → 11.580 | 85.25% → 34.17% |
| Thoát dọc trục A–D, radius 0.75 | 5.962 → 3.457 | 13.934 → 11.191 | 95.19% → 64.90% |
| Vùng trôi, radius 0.75 | 6.619 → 0.601 | 11.718 → 10.265 | 96.01% → 41.18% |

Kết quả gộp cả thời gian trước khi thoát, không riêng giai đoạn thoát; không suy ra phản ứng tức thời. Trong `scripts/benchmark-aim.mjs`, chuyển động thẳng và cong không đổi về trung vị/p95; kịch bản dao động rồi thoát có trung vị **3.749 → 3.893 wu** (xấu hơn), p95 **11.632 → 11.591 wu**. Đây là trade-off thực, không đảm bảo tránh mọi hồi quy. Chưa kiểm chứng trong gameplay thật; không thể dự đoán input tương lai hoặc spread ngẫu nhiên của server.
