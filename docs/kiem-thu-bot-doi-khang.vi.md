# Bot giả kiểm thử lead và di chuyển

## Chạy lại

- `npm run benchmark:bot`: bot ngắm, bot mục tiêu và đạn mô phỏng; in các nhóm kết quả. `node scripts/benchmark-bot-duel.mjs --details` in từng tổ hợp.
- `BOT_EXPERIMENT=./experiments/weave-axis.mjs node scripts/benchmark-bot-duel.mjs`: thêm giả thuyết A–D nghiên cứu, **chỉ dùng trong benchmark**, không tải vào userscript.
- `node scripts/check-bot-duel-source.mjs .cache/survev`: đối chiếu hằng số/nhánh với source pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`.

## Mô hình

Hai bot có lịch input độc lập: đứng yên, chạy thẳng, A–D nhanh và rộng, đổi nhịp A–D, A–D rồi thoát, A–D chéo, zigzag, dừng/chạy, đổi hướng 90 độ và chạy vòng. Lấy 28 cặp hành vi; khoảng cách ban đầu 12/35/70 world units; mỗi bên độc lập có/không boost và có/không slowdown khi bắn. Source pin quy định tốc độ cơ bản 12, cộng 1,85 khi boost ≥50, nhân 0,5 trong nhánh shot slowdown; bot chỉ mô phỏng các hằng số này, không áp dụng đủ bonus/phạt súng, vật phẩm, nước và perk.

Snapshot giả 33 Hz lượng tử hóa, jitter và nghẽn định kỳ, giữ thứ tự gói; down/up lần lượt 30/30, 80/80, 30/120 và 120/30 ms, khung 30/60/144 Hz. Lệnh di chuyển của người bắn có trễ uplink; predictor chỉ đọc snapshot đã tới và input hiện tại. Vị trí thật ở thời điểm server giả nhận Fire và đường đi tương lai chỉ được bộ chấm dùng. Đạn di chuyển tuyến tính và quét va chạm hình tròn đang chuyển động, không chỉ kiểm điểm cuối. Mỗi biến thể chấm **1.403.136 lần bắn mô phỏng**, không phải 1.403.136 trận độc lập; các mẫu tương quan và các kịch bản/phase đã được xem trong phát triển.

`current` dùng predictor runtime hiện tại; `direct` là đường thẳng đến snapshot cũ, **không** phải kỹ năng người thật. `guarded` và `stable-own` thử ngoại suy vị trí người bắn với guard, chưa được tích hợp. `oracle-origin` sử dụng vị trí tương lai thật của người bắn, chỉ là đối chứng không khả thi. `experimental` đoán chu kỳ trên trục Y, thiên vị mẫu nên không tích hợp.

## Kết quả cần chú ý

Đây là tỷ lệ va chạm của **mô hình giả**, tuyệt đối không suy ra hitrate thật:

| Nhóm | current | so sánh / nhận xét |
|---|---:|---|
| Mục tiêu A–D rộng | 30,4% | direct 28,5%, sai lệch trung bình current 2,858 wu so với direct 1,095 wu |
| Mục tiêu A–D đổi nhịp | 19,0% | direct 25,7%, sai lệch trung bình 3,373 so với 1,353 wu |
| Mục tiêu A–D nhanh | 67,5% | giả thuyết chu kỳ trục Y 66,4%, dù A–D rộng tăng lên 52,9% |
| Người bắn chạy thẳng | 45,8% | guarded 71,7%, stable-own 57,3%; cho thấy vị trí bắn cũ có thể quan trọng |
| Người bắn A–D nhanh | 47,1% | guarded 47,2%, sai lệch trung bình tăng từ 1,416 lên 1,475 wu |
| Mục tiêu đổi hướng 90° | 34,6% | stable-own 35,8%, nhưng sai lệch trung bình tăng từ 1,948 lên 2,035 wu |

Kết quả giải thích một số khả năng lead lệch, **không xác định nguyên nhân lỗi live**. Vì giả thuyết chu kỳ bị ràng vào trục, đoán trước hành vi và có regression, còn phép chiếu origin dựa vào input/RTT và cũng có regression, chưa bật chúng trong runtime chỉ vì điểm trung bình tốt hơn. Cần tiếp tục kiểm tra cửa sổ lúc thoát nhịp, hướng tùy ý, các tình huống bất đối xứng và bằng dữ liệu game trước khi chọn phương án.

## Giới hạn

Không có người chơi thật hoặc bản ghi input thật: đây là hành vi giả lập, không khẳng định bao phủ mọi tình huống. Không mô phỏng tick/logic đầy đủ của server, rate thực tế, tự động gửi input, ACK đo thật, interpolation, smoothing, chọn mục tiêu, recoil, spread, vật cản, va chạm người chơi/vật thể, terrain, ammo/cooldown hay thay đổi tốc độ khi súng thực sự bắn. Snapshot vị trí được gửi đều kể cả đứng yên, khác cơ chế gửi thay đổi và suy luận đứng yên của runtime. Tốc độ đạn/range chỉ là các mẫu giả 66/100/182 và 250, không đại diện toàn bộ súng hay range thật. Không dùng kết quả để hứa trúng hoặc xác nhận jitter đã hết.
