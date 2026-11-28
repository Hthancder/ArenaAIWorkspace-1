# Hiệu chỉnh nhận biết mục tiêu dừng

Bản trước chỉ dùng suy luận đứng yên khi snapshot thật đã quá 150 ms. Source Survev pinned đánh dấu player partial-dirty khi vị trí hoặc hướng đổi, và client server gửi partial khi dirty. Trong stream đầy đủ, liên tục, player vẫn hiển thị nhưng vắng khỏi update có thể đang đứng yên. Chờ hết 150 ms có thể tiếp tục lead theo vận tốc cũ sau khi địch đã dừng.

Sau khi đã nhận một vị trí thật, bản mới cho phép dùng track phụ đứng yên sớm hơn nếu: update đã qua kiểm tra protocol/đủ danh sách/chu kỳ; track phụ còn mới và có ít nhất hai mẫu cùng vị trí, vận tốc gần 0; mẫu phụ mới hơn vị trí thật, cùng layer và cùng vị trí đã nhận. Đây vẫn là **suy luận**, được đánh dấu `approximate` / `inferred-stationary`. Vị trí thật mới được ưu tiên ngay; ngắt stream, xóa player hoặc update không đủ vẫn xóa bằng chứng. `Strict prediction` không dùng suy luận, không chặn Fire. Nút **Nhận biết dừng sớm** mặc định bật và tắt được; tắt nó giữ hành vi chờ quá 150 ms như trước, không tắt fallback đứng yên cũ. Tắt Auto prediction cũng vô hiệu cả hai. Không làm nóng target trước activation, không thêm dự đoán input tương lai. Đây không bảo đảm player còn dừng khi đạn đến; có thể bất lợi nếu địch lập tức khởi động lại, nguồn live khác hoặc trạng thái replication bị thiếu.

## Mô phỏng sử dụng source

Đã sửa benchmark source trước đó: không còn phát position giả cho mọi player trong mọi snapshot. Adapter kiểm tra source pinned có nhánh dirty position/direction và partial, mô phỏng tích lũy dirty giữa hai lần gửi, các snapshot thiếu vị trí và track đứng yên phụ. Vẫn là xấp xỉ: không chạy đầy đủ Player/update message, culling và toàn bộ nguyên nhân dirty; input, lịch mạng, vật cản và world vẫn giả. Fallback native được chấm như ngắm trực tiếp vị trí gần nhất, không biết chuột thật. Benchmark chạy cùng helper `inferredStationary` của runtime nhưng không chạy `features.mjs`, sender, smooth hay full Wallcheck. Model vẫn bắn vào tường để kiểm tra đạn; số va tường không đại diện cách Wallcheck runtime xử lý.

15 cặp chuyển động, nguồn player/đạn/grid/weapon, MP5/AK-47/M870, hai khoảng cách, có/không tường, boost, 30/60/144 FPS, bốn cặp latency, ba seed khác nhau cho từng tập. Mỗi model 86.400 phát tương quan/tập; seed "holdout" mới chỉ là ba seed tổng hợp, không phải validation live. So sánh baseline → dừng sớm:

| Nhóm | Phát triển | Seed kiểm tra |
|---|---:|---:|
| Tổng | 19,1% → 19,6% | 19,8% → 20,4% |
| Target dừng/chạy (2 kiểu người bắn) | 11,8% → 15,1% | 8,8% → 13,2% |
| Target không đều, người bắn dừng/chạy | 12,6% → 13,2% | 9,3% → 9,9% |
| Target chạy thẳng | 40,9% → 40,9% | 47,1% → 47,1% |
| Target quay góc | 21,2% → 21,2% | 25,7% → 25,7% |
| Target không đều rồi thoát | 28,0% → 28,4% | 24,9% → 24,4% |
| Không tường | 27,7% → 28,5% | 27,8% → 29,0% |

Trong tập kiểm tra, target dừng/chạy không tường 13,4→21,3%; có tường 4,2→5,0% và tỉ lệ phát có pellet/đạn va tường 58,3→70,0%. Do **không chạy Wallcheck đầy đủ**, không coi mức tăng va tường là hành vi runtime: đây là rủi ro cần kiểm tra game. Nhóm súng trong tập kiểm tra MP5 20,1→20,6%, AK-47 19,8→20,5%, M870 19,0→19,8%; shotgun tính trúng nếu ít nhất một pellet chạm. Kết quả có spread/recoil theo source và phụ thuộc kiểu bắn giả; không chứng minh tỷ lệ trúng live.

Đã thử chiếu vị trí người bắn 25/50/75/100% theo RTT/ý định di chuyển. Một số nhóm tăng mạnh nhưng có hồi quy ở target dừng/chạy, không đều và khi gần tường; còn phụ thuộc input, ACK và collision thực. Chưa bật projection trong runtime. Kết quả cũ `kiem-thu-doi-khang-source.vi.md` được giữ làm lịch sử nhưng không so trực tiếp vì trước đây gửi đủ vị trí ở mọi snapshot và ít cặp hơn.

Lệnh sau khi có checkout pinned sạch: `SOURCE_MODELS=current,fast-stop node scripts/benchmark-source-duel.mjs --holdout`. `--quick` dùng ít FPS/mạng hơn; `SOURCE_MODELS` còn cho phép thử projection, chỉ trong benchmark. Tài liệu `kiem-thu-doi-khang-source.vi.md` mô tả setup source và giới hạn còn lại.
