# Smooth với mục tiêu di chuyển liên tục

Chạy `node scripts/benchmark-micro-strafe.mjs --human --smooth=0` (lặp với 20 và 50). Mô hình dùng snapshot 33 Hz, cadence đều và jitter/backlog, 30/60/144 Hz, ba hạt giống, đạn 66/100/182, prediction Lock, AimController responsive và smooth như chỉ định. `smooth=0` là góc trực tiếp. Các trường hợp và dữ liệu đã được dùng phát triển, không phải kiểm định độc lập. Error là khoảng cách vuông góc proxy tại thời gian bay mô hình ước lượng, không phải hit rate; không mô phỏng server, spread, va chạm, native scheduler hoặc live.

| Tình huống | Smooth | Median / p95 (đơn vị thế giới) | Ngoài bán kính giả định |
|---|---:|---:|---:|
| A–D width 1,2, radius 0,75 | 0 | 0,371 / 9,228 | 19,85% |
| | 20 | 0,422 / 3,358 | 27,26% |
| | 50 | 0,437 / 2,365 | 28,51% |
| A–D width 3, radius 1 | 0 | 0,929 / 10,679 | 46,49% |
| | 20 | 0,934 / 6,811 | 47,19% |
| | 50 | 0,922 / 4,902 | 46,07% |
| Thoát A–D cùng trục width 1,2, radius 0,75: riêng giai đoạn thoát | 0 | 5,517 / 10,066 | — |
| | 20 | 4,739 / 8,742 | — |
| | 50 | 4,505 / 7,919 | — |

Smooth thấp hơn không thắng nhất quán: trực tiếp giảm trung vị với A–D nhỏ nhưng đuôi lớn hơn, và trong ví dụ thoát cùng trục có proxy xấu hơn. So sánh một bước nhảy vị trí trong `do-phan-ung-den-input.vi.md` cho thấy hội tụ chậm hơn, nhưng không thể suy ra đơn giản rằng giảm smooth luôn cải thiện aim với predictor đang đổi theo thời gian. Không thay mặc định hoặc runtime theo kết quả này. Nếu thử thay đổi tự động cần benchmark thêm chuyển hướng, jitter, Human-like, đường gửi thật, và tập dữ liệu mới không dùng để tuning.
