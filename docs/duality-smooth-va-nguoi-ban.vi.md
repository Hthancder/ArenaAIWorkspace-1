# Người bắn đang di chuyển và smooth theo Duality

Lần thử được báo: Human-like **đã tắt**, đồng đội đứng yên trong FOV, người bắn chạy quanh và thấy Lock chậm về rìa. Do đó smooth không phải lời giải cho lần thử này. Theo source ghim, runtime hiện bắt đầu từ snapshot vị trí người bắn đã nhận; server tạo đầu đạn từ vị trí người bắn khi xử lý bắn, trong khi client có thể render vị trí nội suy khác. Khi người bắn chạy, các vị trí này không nhất thiết trùng nhau, dù địch đứng yên.

## Bù di chuyển bản thân (thử nghiệm)

Trong **Main → Aim — Prediction**, bật `Bù di chuyển bản thân (thử nghiệm)` để thử. Mặc định tắt vì có regression trong benchmark và chưa xác minh live. Nó chỉ thử trong Lock súng, khi bật prediction và Wallcheck, Strict prediction tắt, contract source được nhận diện, có ít nhất ba mẫu vị trí bản thân gần đây, RTT mới và không cao, hướng input desktop hiện tại khớp vận tốc quan sát, và không có vật cản gần đường ngoại suy. Ngoại suy tối đa 200 ms; khi dừng, đổi hướng, thiếu dữ liệu/RTT, đang dùng touch hoặc ở gần vật cản, về nghiệm gốc. Các kiểm tra đường đạn, người chắn, layer và Fire vẫn hoạt động; không dự đoán tương lai có thể đổi hướng hay bảo đảm hit. Không áp dụng grenade/Assist. Có thể không kích hoạt nhiều lần trong thực tế vì điều kiện bảo thủ.

`lastPrediction.ownMotionMs` báo số ms ngoại suy đã dùng (null là fallback); `ownSnapshotAgeMs`, `ownEstimatedSpeed`, `rttMs` hỗ trợ chẩn đoán. `visualCrossTrack` là khoảng vuông góc từ hướng output đến tâm **render** tính từ vị trí render của người bắn; có thể chứa ảnh hưởng offset nòng/độ lệch render và không phải vị trí va chạm hoặc bằng chứng trúng. Nếu không phát hiện được visual position, giá trị null. Không lưu tọa độ hay danh tính.

### Benchmark tổng hợp

`scripts/benchmark-self-motion.mjs` quét 5 chuyển động người bắn × 6 mục tiêu, FPS 30/60/144, 3 tốc độ đạn, phase và delay hai chiều, jitter/gap. Trường hợp `orbit/still`: sai số vuông góc proxy median/p95 baseline 1.584/2.694, nghiệm bù có điều kiện 0.079/2.694 world unit; bù được 68.652 trên 88.410 mẫu, phần còn lại fallback. Nó không đo hit: không có game live, server tick, spread, wall, ACK, collision thật hoặc input thực; hướng input trong fixture giả định lý tưởng từ đạo hàm quỹ đạo. Ở `straight/reverse`, tỷ lệ proxy >1 tăng 87,7% → 89,9%; `stop/straight` p95 1,927 → 1,948. Vì có đánh đổi và RTT hai chiều có thể bất đối xứng, **không bật mặc định và không khẳng định cải thiện mọi kiểu di chuyển**.

## Smooth tham khảo Duality

Phân tích tĩnh `docs/duality_client.js` 4.1: chọn điểm trên màn hình, nội suy vị trí với cubic ease-out `1 - (1-t)^3`, duration cơ sở 45 ms cộng phần phụ thuộc góc, khoảng cách pixel và slider, retarget từ điểm hiện tại. Nó cũng có cơ chế giữ/phát lại Fire khi đang chuyển động. Không chạy mã Duality.

Thêm profile **Duality-inspired (cubic)** chỉ khi Human-like bật. Dùng cubic theo pixel, retarget, duration và ngưỡng gần tương tự, nhưng xử lý hướng gần đối diện bằng đường góc để tránh singularity qua giữa màn hình. Không chép cơ chế chặn/phát lại Fire; prediction, input an toàn và Wallcheck vẫn là của dự án. Đây là phỏng theo, không phải bản sao đầy đủ hoặc tuyên bố tốt hơn Duality; khi Human-like tắt thì profile không hoạt động và không ảnh hưởng tình huống đã báo.
