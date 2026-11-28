# Kiểm thử thoát A–D và mô hình tick

Tiếp tục kiểm tra phiên bản midpoint `6cd9321`, chưa thay runtime. `scripts/benchmark-wide-escape.mjs` đo lúc gate midpoint tắt sau khi mục tiêu đổi hành vi, quét pha chuyển động và pha snapshot (33 Hz), không dự đoán input tương lai. Với 60 pha đủ điều kiện mỗi trường hợp, thời gian từ **snapshot đầu tiên sau sự kiện** đến khi gate tắt, trung vị/p95: thoát cùng trục 151,5/363,6 ms; thoát ngang 0/30,3 ms; dừng 30,3/30,3 ms; thoát cùng trục chậm 242,4/515,2 ms. Snapshot đầu tiên nhận được sau sự kiện trung vị/p95 lần lượt là 45,2/58,8 ms với downlink 30 ms, 95,2/108,8 ms với 80 ms, và 165,2/178,8 ms với 150 ms. Đây là proxy gate, không phải thời gian ngắm đúng, không có sender, smoothing hay server thật.

Đã thử guard thu hẹp biên và guard pivot. Biên 0,15 có thể phản ứng sớm hơn trong một số pha nhưng làm giảm chất lượng A–D rộng/chéo; pivot thử nghiệm không thay kết quả đáng kể. Không đưa vào runtime khi chưa có cân bằng tốt hơn.

## Collision bổ sung

Bot duel hiện có `--tick-collision`: Fire được làm tròn lên tick giả định 100 Hz; mỗi đoạn đạn được kiểm tra với vị trí mục tiêu ở thời điểm tick. Tần số mặc định 100 game/33 network được đối chiếu config source Survev pinned; predicate đoạn–vòng tròn được so 12.000 ca với `coldet.intersectSegmentCircle` từ source pinned, gồm cả đoạn zero và điểm bắt đầu bên trong. Đây **không phải** replay server: quỹ đạo player, pha tick, grid, clipping range, xử lý va chạm và networking vẫn giản lược; không suy ra tần số server live.

Holdout quick có 269.568 phát tương quan mỗi model, gồm cả mục tiêu thu hẹp A–D rồi thoát, ba khoảng cách, ba tốc độ đạn, người bắn và mục tiêu di chuyển, boost và slowdown. Tỷ lệ chạm mô phỏng:

| Nhóm | Trước midpoint | Hiện tại | Guard biên 0,15 thử nghiệm |
|---|---:|---:|---:|
| Tổng | 54,4% | 56,4% | 56,2% |
| A–D rộng | 40,7% | 49,5% | 48,5% |
| A–D chéo | 51,2% | 62,3% | 60,8% |
| Thoát A–D | 63,5% | 62,2% | 62,6% |
| Thu hẹp rồi thoát | 57,0% | 60,1% | 59,6% |

Mô hình continuous hiện tại tổng 56,3%, A–D rộng 48,7%, thoát 61,2%; không so trực tiếp như phép đo độc lập vì cả input và phát bắn có tương quan, cũng khác lượng tử thời điểm Fire. Cả hai mô hình là giả lập, không có vật cản, recoil, spread, replay server hoặc đo gameplay live. Kết quả xác nhận cần tiếp tục cải thiện thoát A–D mà không mất lợi ích đang có, chứ không chứng minh chính xác live.

Chạy: `node scripts/benchmark-wide-escape.mjs`, `BOT_MODELS=current node scripts/benchmark-bot-duel.mjs --quick --holdout --tick-collision`, `node scripts/check-bot-duel-source.mjs .cache/survev`, `node scripts/check-bot-tick-source.mjs .cache/survev`. Source fixture yêu cầu checkout pinned như các kiểm thử upstream khác.

## Theo từng giai đoạn sau đổi hành vi

**Đính chính:** mốc của `ad-shrink-escape` trong benchmark ở commit `9b0372d` là 3,0 nhưng lúc đó mục tiêu vẫn đi cùng hướng với chu kỳ nhỏ; khác biệt xảy ra khi bỏ lần đảo tiếp theo tại 3,12. Đã sửa mốc và thêm test. Các mốc `ad-escape`, `ad-escape-stop` và `ad-escape-return` tại 2,4 vẫn đúng: mục tiêu bỏ lượt đảo ở mốc này. Số tổng theo loại mục tiêu trước đây không thay đổi.

Bổ sung `ad-delayed-escape`: mục tiêu còn đảo tại 2,4 như A–D bình thường, rồi bỏ lượt đảo tại 2,88. Phân nhóm theo thời gian server giả lập kể từ lúc input đầu tiên khác nhịp trước, không cung cấp mốc này cho bộ dự đoán. Holdout quick tick mới có 314.496 phát tương quan/model. So sánh trước midpoint → hiện tại:

| Nhóm | Trước | Hiện tại |
|---|---:|---:|
| Thoát A–D 0–200 ms | 42,5% | 33,2% |
| Thoát A–D 200–500 ms | 57,2% | 57,2% |
| Thoát rồi dừng 0–200 ms | 25,2% | 21,5% |
| Thoát rồi quay lại 0–200 ms | 27,2% | 27,3% |
| Thoát trễ 0–200 ms | 22,3% | 11,7% |
| Thoát trễ 200–500 ms | 67,2% | 67,2% |
| Thu hẹp rồi thoát 0–200 ms, mốc đã sửa | 27,4% | 27,4% |
| A–D rộng toàn giai đoạn | 40,7% | 49,5% |

Cửa sổ 0–200 ms và 200–500 ms của mẫu thoát trễ gồm 864 và 1.152 phát. Các phát cùng quỹ đạo tương quan, có thể bay qua lần đổi hướng tiếp theo; thuật toán lấy mẫu di chuyển theo bước 1/120 giây, nên thời gian thay đổi thực trong quỹ đạo có thể trễ một bước. Điều này không đo thời gian phản ứng client thực. Kết quả bộc lộ trade-off trong các mẫu cụ thể, không đại diện mọi hành vi người chơi.

Thử lưu dấu vượt biên trong sáu snapshot gần nhất với biên 0,06/0,2/0,4 wu và pha midpoint với lead 20/40/60%. Ở tập trước khi thêm `ad-delayed-escape`, biên 0,4 cho A–D rộng 48,3%; blend 20% cho A–D rộng 47,2%, A–D chéo 59,3% (hiện tại 49,5%/62,3%). Guard biên 0,15 cho thoát trễ 0–200 ms 20,5%, nhưng vẫn giảm A–D rộng/chéo. Thử rút ngắn lịch sử thẳng còn 250/350/450 ms để cấp bù snapshot sớm hơn; 250 ms không cải thiện 0–200 ms thoát trễ và một số nhóm khác giảm. Không ship các ứng viên khi chưa giải quyết được điểm yếu mà không đánh đổi đáng kể.
