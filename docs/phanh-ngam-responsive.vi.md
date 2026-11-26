# Phanh hướng ngắm ở Lock Responsive

## Thay đổi

Khi Human-like bật, Lock dùng profile `responsive`, và hướng đích đã tính nằm ngược chiều vận tốc góc hiện tại, giảm thời gian SmoothDamp xuống 70% trong thời điểm phanh. Chỉ sử dụng hướng đích đã quan sát/tính ra và vận tốc controller hiện tại; không dự đoán địch sẽ đổi hướng. Không snap, vẫn qua SmoothDamp và giới hạn tốc độ như trước. Khi không phanh, smooth không đổi. Assist, profile natural/precise, Human-like tắt hoặc smooth 0 không đổi. Không thay logic giữa A–D, wallcheck, lead hay Fire; không thêm setting.

## So sánh tổng hợp

Đối chứng là `src/aim.mjs` tại `31020c6`. `scripts/benchmark-controller-motion.mjs` đánh giá predictor + responsive controller ở 30/60/144 Hz (trọng số thời gian bằng nhau), snapshot 33 Hz đều, downlink/uplink 30 hoặc 80 ms, 3 phase, đạn 66/100/182. Error là sai lệch so với mặt phẳng x=60, không bao gồm hitbox vật lý, vật cản, spread, va chạm, sender, recoil, hay server. Các con số là đơn vị thế giới, không phải tỷ lệ trúng.

| Tình huống | Trước median/p95 | Sau median/p95 |
|---|---:|---:|
| Đứng yên | 0 / 0 | 0 / 0 |
| Chạy thẳng | 1,734 / 2,429 | 1,734 / 2,429 |
| Đảo chiều | 6,797 / 20,468 | 6,649 / 20,216 |
| Đảo chiều nhanh | 11,508 / 35,371 | 11,235 / 35,097 |
| Dừng–chạy | 4,523 / 8,356 | 4,511 / 8,363 |
| A–D nhỏ | 0,300 / 0,570 | 0,300 / 0,570 |
| A–D rộng | 1,432 / 3,480 | 1,310 / 3,348 |

Tỷ lệ proxy vượt bán kính 1 ở đảo nhanh tăng nhẹ 96,53% → 96,57%; dừng–chạy p95 tăng nhẹ. Trong benchmark micro-strafe với Human-like, A–D nhỏ radius 0,35 p95 1,260 → 1,283; A–D width 1,2 radius 0,75 p95 2,365 → 2,169; thoát cùng trục radius 0,75 giai đoạn thoát median/p95 4,505/7,919 → 4,477/7,857. Có đánh đổi và các sai số vẫn lớn, không phải cải thiện toàn diện. Các benchmark là dữ liệu tổng hợp đã được xem trong phát triển, không phải tập độc lập hay gameplay live.

Tái hiện (checkout gốc là commit nêu trên):

```sh
mkdir -p .cache/controller-baseline
git show 31020c6:src/aim.mjs > .cache/controller-baseline/aim.mjs
git show 31020c6:src/core.mjs > .cache/controller-baseline/core.mjs
AIM_MODULE="file://$PWD/.cache/controller-baseline/aim.mjs" node scripts/benchmark-controller-motion.mjs
node scripts/benchmark-controller-motion.mjs
AIM_MODULE="file://$PWD/.cache/controller-baseline/aim.mjs" node scripts/benchmark-micro-strafe.mjs --human
node scripts/benchmark-micro-strafe.mjs --human
```

192 test và bốn biến thể fixture upstream ghim đã qua; chưa kiểm tra trong trận. Không có bảo đảm trúng, không vượt độ trễ snapshot hay dự đoán được thay đổi tương lai.
