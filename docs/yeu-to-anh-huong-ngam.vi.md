# Kiểm tra các yếu tố ảnh hưởng chung tới aim

Không dựa vào một loại súng hay một chuyển động để đánh giá toàn bộ. Kết quả dưới đây là fixture/benchmark, không phải xác nhận server live, FPS hay tỉ lệ trúng trong trận.

## 1. Vũ khí và perk từ source

`node scripts/check-gun-profiles-upstream.mjs .cache/survev` trích định nghĩa và `Bullet.init` từ source ghim, so sánh profile runtime với source trong world giả không va chạm. **568/568 tổ hợp**: 71 súng cơ sở × 8 tổ hợp perk 9mm/high velocity/bonus assault, dùng jitter tầm bắn tối thiểu. Tốc độ danh định và tầm bảo thủ trùng fixture; không kiểm tra skin, `.45` empowered ngẫu nhiên, `toMouseHit` clipping, random spread, projectile phụ, tường, ping hoặc gameplay live. Kết quả này không chứng minh mọi vũ khí trúng đúng.

## 2. Vị trí người bắn và độ trễ

Source `WeaponManager.fireWeapon` tạo `gunPos` từ **vị trí người bắn tại server lúc bắn**, cộng offset súng. Runtime hiện dùng `sourcePos` mới nhất làm origin, không ngoại suy vị trí người bắn đến lúc server xử lý. Đây là một yếu tố có thể ảnh hưởng nhiều loại súng và cả địch đứng yên, nhất là khi chính người chơi di chuyển; chưa chứng minh đó là nguyên nhân live.

`scripts/benchmark-self-motion.mjs`: thí nghiệm **chưa tích hợp runtime**, so sánh origin cũ với ứng viên ngoại suy ngắn bằng tracker người bắn. Quét người bắn đứng, chạy, đảo chiều, start/stop × mục tiêu đứng, chậm, thẳng, đảo chiều, sidestep, start/stop; ping một chiều đối xứng/bất đối xứng 30–150 ms, FPS 30/60/144, đạn 66/100/182 và hai kiểu cadence (đều/jitter-gap). Chấm sai số vuông góc giữa tia và mục tiêu tương lai, world không vật cản và không spread. Native fallback dùng proxy ngắm thẳng vị trí cuối khi solver từ chối; **không phải input thực, hit rate hay phép đo live**.

| Người bắn / mục tiêu | Gốc cũ: median / p95 | Ngoại suy thử: median / p95 | Gốc cũ / thử: proxy sai số >1 |
|---|---:|---:|---:|
| still/still | 0.000 / 0.000 | 0.000 / 0.000 | 0.0% / 0.0% |
| still/slow | 0.154 / 0.475 | 0.154 / 0.475 | 1.0% / 1.0% |
| still/straight | 0.653 / 1.982 | 0.653 / 1.982 | 29.9% / 29.9% |
| still/reverse | 9.567 / 30.347 | 9.567 / 30.347 | 89.9% / 89.9% |
| still/sidestep | 1.194 / 9.668 | 1.194 / 9.668 | 56.0% / 56.0% |
| still/stop | 3.254 / 8.231 | 3.254 / 8.231 | 76.1% / 76.1% |
| straight/still | 1.412 / 2.474 | 0.546 / 1.564 | 80.5% / 21.0% |
| straight/slow | 1.314 / 2.162 | 0.403 / 1.203 | 79.5% / 20.1% |
| straight/straight | 0.695 / 1.320 | 0.183 / 1.033 | 14.9% / 5.4% |
| straight/reverse | 10.355 / 29.051 | 10.316 / 28.869 | 87.7% / 88.3% |
| straight/sidestep | 1.640 / 10.102 | 1.092 / 9.849 | 75.1% / 52.8% |
| straight/stop | 2.859 / 9.057 | 3.023 / 8.439 | 79.5% / 73.2% |
| reverse/still | 2.304 / 4.013 | 0.988 / 3.000 | 81.7% / 43.4% |
| reverse/slow | 2.246 / 4.285 | 0.885 / 3.104 | 81.4% / 42.5% |
| reverse/straight | 1.605 / 5.219 | 0.731 / 4.137 | 74.5% / 43.6% |
| reverse/reverse | 11.622 / 31.549 | 10.402 / 30.256 | 82.3% / 80.5% |
| reverse/sidestep | 2.505 / 10.646 | 1.413 / 10.168 | 84.6% / 66.4% |
| reverse/stop | 3.796 / 8.577 | 3.157 / 7.871 | 89.3% / 78.0% |
| stop/still | 0.516 / 2.943 | 0.156 / 1.926 | 37.0% / 15.2% |
| stop/slow | 0.476 / 2.637 | 0.338 / 1.596 | 36.1% / 15.8% |
| stop/straight | 0.779 / 1.927 | 0.536 / 2.051 | 36.3% / 24.5% |
| stop/reverse | 10.771 / 30.003 | 10.443 / 29.265 | 87.4% / 86.1% |
| stop/sidestep | 1.182 / 10.053 | 1.139 / 9.848 | 63.6% / 57.6% |
| stop/stop | 3.593 / 8.711 | 3.159 / 8.163 | 78.3% / 73.8% |

Ứng viên giảm sai số trong nhiều tình huống người bắn di chuyển, nhưng không đồng đều: `straight/reverse` proxy >1 tăng 87,7% → 88,3%, `stop/straight` p95 tăng 1,927 → 2,051. Fixture chưa có collision/tường, perk, server tick, cooldown, độ trễ thay đổi, gia tốc thật hay gameplay. Vì vậy chưa thay runtime: cần so sánh thêm hitbox/đường đạn và fail-closed cho muzzle dự đoán, latency khó ước lượng, tối ưu không làm nhóm khác xấu đáng kể.

## 3. Chẩn đoán lần bắn

`lastPrediction` giờ ghi thêm `ownSnapshotAgeMs` và `ownEstimatedSpeed` dưới dạng số ẩn danh; đây là dữ liệu quan sát client, không phải vận tốc server xác nhận. Mục tiêu là phân biệt lỗi có liên quan vị trí người bắn với vấn đề lead mục tiêu hoặc mạng. Nó không thay đổi hướng ngắm. Các hạn chế và kiểm thử đạn theo tick tại `docs/gioi-han-du-doan-theo-source.vi.md`; độ giật tại `docs/kiem-tra-giat-va-lead-cham.vi.md`.
