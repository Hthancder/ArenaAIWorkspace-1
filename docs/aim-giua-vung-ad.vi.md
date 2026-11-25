# Aim giữa vùng A–D rộng hơn

## Thay đổi

Lock + Auto prediction + **Ổn định dao động A–D** vốn đã nhắm giữa vùng khi có ít nhất 550 ms lịch sử, ít nhất hai lần đổi chiều và không có gap lớn. Trước đây giới hạn đường kính là `min(2.5 × radius, 2)` wu; nay là `min(3.5 × radius, 3.5)` wu. Vì vậy vùng A–D rộng hơn có thể được ổn định thay vì bám theo vận tốc tức thời và dẫn ngắm quá xa. Nếu snapshot mới vượt vùng cũ hơn 0.06 wu, giả thuyết bị bỏ ở snapshot đó; không biết đối thủ chạy ra trước khi dữ liệu đến. Track cũ, gap >150 ms, không đủ đảo chiều hoặc vùng vượt giới hạn vẫn không được ổn định. Assist không đổi, tùy chọn ổn định vẫn tắt/bật được.

Điểm giữa không thể bảo đảm trúng: nếu chiều rộng lớn hơn hai lần bán kính collider, một phần vùng nằm ngoài tia giữa ngay cả khi không có spread. Đường kính ở đây là hộp bao 2D, không phải nhận biết ý định người chơi, và vị trí thực giữa các snapshot có thể vượt vùng quan sát. Skin trông nhỏ không chứng minh hitbox nhỏ. Không dự đoán được thao tác tương lai, jitter mạng hay đạn tản ngẫu nhiên. Bắn vào giữa không ngăn được địch né hoặc rời vùng.

Nếu thấy bám chậm, kiểm tra **Lock**, **Auto prediction** và **Ổn định dao động A–D** đều bật; thử giảm Human-like amount hoặc tắt Human-like để so sánh vì smoothing có chủ ý làm chậm hướng ngắm. Nếu địch thoát khỏi vùng mà tâm bị giữ quá lâu, thử tắt ổn định. Wallcheck vẫn có thể chặn ngắm qua vật cản. Các gợi ý này không bảo đảm trúng; chưa xác minh trong game live.

## Kiểm thử tổng hợp

`node scripts/benchmark-micro-strafe.mjs` so sánh hướng solver trực tiếp; `--human` thêm AimController responsive, smooth 50, mỗi frame. Mục tiêu giả lập 12 wu/s, snapshot 33 Hz, 35 ms mỗi chiều, quantization 16-bit/1024, jitter/gap trong một nửa kịch bản, render 30/60/144 Hz, 3 seed, đạn 66/100/182. Mỗi hàng 37.620 phép tính. Sai lệch là khoảng cách vuông góc từ tia đến tâm tương lai, không phải hit rate; fallback được tính như ngắm thẳng vào snapshot gần nhất. So sánh với bản ngay trước thay đổi trên cùng seed được dùng phát triển, không phải xác thực độc lập; không mô phỏng spread, tất cả va chạm hay human input thật. Mô phỏng `--human` dùng hướng trực tiếp vào snapshot làm native và thời gian bay theo solver, không mô phỏng toàn bộ input loop.

| Kịch bản (radius 1, rộng 3 wu) | Trung vị trước → sau (wu) | p95 trước → sau (wu) | Ngoài radius trước → sau |
|---|---:|---:|---:|
| Đảo A–D, solver trực tiếp | 7.081 → 0.929 | 11.875 → 10.679 | 97.19% → 46.49% |
| Đảo A–D, Human-like giả lập | 2.732 → 0.922 | 7.285 → 4.902 | 82.82% → 46.07% |
| Thoát dọc trục, Human-like, cả kịch bản | 2.857 → 2.236 | 10.550 → 8.391 | 81.16% → 70.51% |

**Đánh đổi khi thoát:** chỉ xét các frame mà quyết định bắn xảy ra trong khoảng thoát 0.6 giây (7.614 mẫu), thoát dọc trục + Human-like có trung vị **2.605 → 4.569 wu**, p95 **7.904 → 9.275 wu**. Trực tiếp: trung vị **3.922 → 5.794 wu**, p95 **10.129 → 10.129 wu**. Nhắm giữa giúp phần dao động nhưng có thể tăng sai số khi địch đột ngột chạy khỏi vùng; không giấu hồi quy này. Với thoát ngang + Human-like, trung vị **1.501 → 1.039 wu**, p95 **7.095 → 2.696 wu**. Bài benchmark 14 nhóm `scripts/benchmark-aim.mjs` cho thẳng/cong trung vị và p95 không đổi; kịch bản dao động rồi thoát trung vị 3.893 → 3.913 wu, p95 11.591 không đổi. Các kịch bản khác không đại diện cho mọi trận.

Đã thử rút lịch sử tối thiểu 550 → 400 ms; có trường hợp rộng 3 wu dùng Human-like xấu hơn (trung vị 0.922 → 0.936, p95 4.902 → 5.088), nên giữ 550 ms. Không kết luận rằng cơ chế sẽ bắt được mọi nhịp A–D, đặc biệt khi tần số đổi hướng cao so với tần số snapshot hoặc có lag.
