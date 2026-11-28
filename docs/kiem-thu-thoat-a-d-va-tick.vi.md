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

## Theo từng giai đoạn sau thoát

Bổ sung hai kiểu mục tiêu thoát 300 ms rồi dừng hoặc quay lại; phân nhóm phát bắn theo thời gian server giả lập kể từ sự kiện (0–200, 200–500, 500–1.000 ms). Holdout quick tick có 299.520 phát tương quan/model, khác tập 269.568 phát ở trên nên không so tổng trực tiếp với bảng cũ. Kết quả trước midpoint → hiện tại:

| Giai đoạn | Trước | Hiện tại |
|---|---:|---:|
| Thoát cùng trục 0–200 ms | 42,5% | 33,2% |
| Thoát cùng trục 200–500 ms | 57,2% | 57,2% |
| Thoát rồi dừng 0–200 ms | 25,2% | 21,5% |
| Thoát rồi quay lại 0–200 ms | 27,2% | 27,3% |
| Thoát rồi quay lại 200–500 ms | 31,4% | 31,4% |
| A–D rộng toàn giai đoạn | 40,7% | 49,5% |

Mỗi ô 0–200 ms chứa 864 phát, 200–500 ms chứa 1.152 phát; các phát cùng quỹ đạo tương quan và có thể bay qua lần đổi hướng tiếp theo. Chúng không cho biết thời gian phản ứng của client thực. Kết quả làm rõ trade-off đầu thời điểm thoát, bị che khuất khi chỉ xem số tổng.

Thử thêm lưu dấu vượt biên trong sáu snapshot gần nhất với biên 0,06/0,2/0,4 wu và pha midpoint với lead 20/40/60%. Biên 0,4 cho A–D rộng 48,3%, 0–200 ms thoát vẫn 33,2%; blend 20% cho A–D rộng 47,2%, A–D chéo 59,3% (hiện tại 49,5%/62,3%) trong khi thoát 0–200 ms vẫn 33,2%. Các biên nhỏ hơn hoặc blend lớn hơn làm hại A–D rõ hơn. Không ship các ứng viên vì chưa giải quyết được trường hợp quan trọng mà không đánh đổi đáng kể. Các ca stop/return là mẫu tổng hợp mới, không đại diện mọi hành vi người chơi.
