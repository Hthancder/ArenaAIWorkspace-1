# Ping, FPS và giới hạn dự đoán

## Đã thay đổi

Với **Lock**, Auto prediction và Latency compensation bật, khi có ít nhất 650 ms / 12 snapshot gần như chuyển động thẳng, khoảng trống mẫu không quá 100 ms và độ lệch khỏi đường thẳng ≤0.12 wu, solver cộng thêm một ước lượng bằng RTT/2 vào thời gian dự đoán (tổng vẫn bị chặn ở 100 ms). Ý tưởng: timestamp được ghi tại lúc nhận snapshot, nên tuổi tính từ timestamp đó chưa tính thời gian snapshot đi từ server tới client; đầu vào cũng cần thời gian đi ngược lại. ACK RTT gồm cả scheduling và không đo được thời gian từng chiều, nên đây là **ước lượng**, không phải timestamp server. Không áp dụng bổ sung khi dữ liệu thiếu/cũ, chưa đủ thẳng, đang ở giả thuyết dao động, hoặc tắt Latency compensation. Assist vẫn dùng cách tính cũ. Mục tiêu vẫn có thể đổi hướng ngay sau thời gian thẳng và gây sai số; đây không phải bảo đảm chính xác hơn trong mọi tình huống.

Các yếu tố đã xét: vị trí snapshot, tuổi, vận tốc/độ bất định và trạng thái dao động, RTT ước tính, tốc độ/tầm/nòng và các perk có nhánh xác định, scale hitbox, layer và chướng ngại được replicate. Nhánh ngẫu nhiên `bonus_45`, dual hand, spread, jitter shotgun và độ dài đạn điều chỉnh ngẫu nhiên vẫn không thể biết chắc trước phát; cooldown, recoilTicker, thời điểm server thực sự bắn và chuyển động của mục tiêu sau snapshot không được biết chính xác. FPS ảnh hưởng thời điểm xử lý và mẫu đầu vào: tuổi snapshot đã tính thời gian thực, không cộng một số ước lượng FPS tùy ý có thể đếm trùng; không đo hay tuyên bố cải thiện FPS thực tế. Source: Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff`, `client/src/game.ts` (seq/ACK), `server/src/game/weaponManager.ts`, `objects/bullet.ts`, `objects/player.ts`. Giao thức server live có thể khác.

## Thử nghiệm và đánh đổi

`node scripts/benchmark-latency.mjs` là baseline cùng thuật toán nhưng không cộng bù snapshot; thêm `--adaptive` để bật phần mới. Chuyển động thẳng/đảo chiều/cong giả lập, snapshot 33 Hz, vị trí lượng tử 16 bit trên 1024 wu, render 30/60/144 Hz, ba phase và ba tốc độ đạn 66/100/182. Độ trễ mỗi chiều cố định, ước lượng RTT chính xác và không có scheduler ACK, jitter hay packet loss trong benchmark này. Mỗi hàng 16.839 phép tính. Sai số là khoảng cách vuông góc từ tia tới tâm tương lai, không mô phỏng va chạm đầy đủ hoặc là tỷ lệ trúng. Bộ mẫu dùng để phát triển, không độc lập.

| Chuyển động; trễ xuống/lên | Trung vị trước → sau (wu) | p95 trước → sau (wu) |
|---|---:|---:|
| Thẳng; 30/30 ms | 0.233 → 0.012 | 0.343 → 0.074 |
| Thẳng; 80/80 ms | 0.618 → 0.463 | 0.894 → 0.673 |
| Thẳng; 150/150 ms | 1.553 → 1.553 | 2.227 → 2.227 |
| Đảo chiều; 80/80 ms | 10.532 → 10.532 | 32.422 → 32.646 |
| Cong; 30/30 ms | 1.457 → 1.457 | 6.555 → 6.555 |

Ở ping cao, mức chặn 100 ms cố ý hạn chế ngoại suy nên không bù đủ. Benchmark chuyển động đa dạng `scripts/benchmark-aim.mjs` cũng cho thấy thẳng trung vị 0.388 → 0.151 wu, nhưng tiếp cận/rút lui 3.659 → 3.786 wu và p95 20.300 → 20.532 wu; dừng ở tường 5.230 → 5.268 wu, p95 13.158 → 13.199 wu. Có hồi quy, nhất là khi tương lai khác lịch sử; phần cải thiện thẳng không thể xóa bỏ sự bất định. Benchmark A–D không thay đổi các chỉ số đã báo cáo trong `on-dinh-a-d-hitbox.vi.md` trên cùng bộ mẫu. Không khẳng định kết quả trên mọi súng hay mọi điều kiện mạng thực.

Đã thử nâng trần ngoại suy lên 250 ms: ở trễ giả lập 250/250 ms, thẳng trung vị 3.136 → 1.929 wu, nhưng đảo chiều 16.291 → 19.085 wu và p95 28.308 → 30.464 wu; không áp dụng trần này. Không có cách phía client bảo đảm luôn trúng: hai đối thủ với cùng lịch sử có thể chọn hai hướng khác nhau sau lúc bắn, và server còn có độ tản ngẫu nhiên. Cần thử thực tế trước khi kết luận bất kỳ mức cải thiện nào.
