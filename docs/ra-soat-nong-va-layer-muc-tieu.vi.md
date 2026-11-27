# Rà soát nòng súng và layer mục tiêu

Đối chiếu source Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`:

- `Bullet.checkForCollisions` cho phép va chạm player trên stair layer (bit 2) ngay cả khi parity tầng khác; melee dùng `sameLayer` với layer vật lý của người đánh, không dùng aimLayer của đạn. Bộ lọc và kiểm tra cuối nay phân biệt hai trường hợp này. Không đổi lựa chọn team hoặc FOV; chưa mô phỏng toàn bộ hình học/animation melee.
- `WeaponManager.fireWeapon` dùng bán kính gốc `GameConfig.player.radius = 1` để kiểm tra gunPos trong vật cản khi bắn khác layer, không dùng `player.rad` đã nhân scale. Dùng đúng bán kính và so khoảng cách bình phương theo source.
- Nếu gunPos ở trong collider tròn, source lấy giao điểm đi ra; pháp tuyến hướng ra không cắt nòng. Đồng thời mặt phẳng bị dịch 0,01 wu trước khi so với chiều dài nòng, nên cả vật cản rất gần ngay ngoài nòng cũng có thể cắt. Đã sửa cả hai trường hợp.
- `testCircleAabb` trong source không coi tiếp xúc ngoài đúng điểm là giao nhau; sửa phân loại stair tại biên, vẫn xét tâm nằm trong hộp.

Kiểm tra: 267 test, 1.152 so sánh nòng viên trung tâm với nhánh `fireWeapon` và collider gốc ở nhiều hướng, scale và layer; 32 tổ hợp predicate layer đạn/melee; 11.520 hướng cầu thang và 32 biên circle/AABB. Fixture client 4 biến thể, ray 8.640, grenade, loot, và 568 cấu hình súng cũng đạt. Mô hình nòng vẫn không đầy đủ cho nhiều collider gần nhau, dual/offhand, shotgun jitter hoặc source khác; benchmark Node geometry 4000 vật thể median 0,917 ms, p95 1,339 ms/solve không phải FPS trình duyệt. Chưa xác minh trong trận live.
