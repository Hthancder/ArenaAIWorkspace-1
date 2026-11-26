# Grenade Aim — bản thử nghiệm

Trong **Main → Grenade Aim (thử nghiệm)** chọn một chế độ độc lập, mặc định Off:

- **Preview:** chỉ vẽ đường và vùng nổ danh định, không sửa input.
- **Assist:** kéo hướng và lực ném về nghiệm; dùng `Lực Assist bom (%)` riêng.
- **Lock:** đặt hướng và lực theo nghiệm danh định.

Assist/Lock có thể chọn **Giữ Fire** hoặc **Cầm bom**. Chế độ giữ Fire tiếp tục dùng fuse ước lượng cho gói nhả đang chờ gửi, sau đó trả quyền input. Chế độ cầm bom giả định ném ngay với fuse đầy khi chưa giữ. Người chơi tự giữ và nhả; tính năng không tạo Fire hay tự ném. Grenade timer tùy chọn độc lập.

## Giới hạn quan trọng

Mọi kết quả là **ước lượng, chưa xác nhận server**; không dùng timer hoặc chỉ báo làm thời điểm giữ/nhả an toàn, không bảo đảm trúng hay tránh tự nổ. Thời gian fuse khi giữ dựa trên cạnh Fire chuyển cho sender, không phải xác nhận cook server. Mạng, tick, dự đoán mục tiêu, bề mặt, collider, góc/lực lượng tử và server live có thể khác. Đường nét đứt và chữ `ước lượng / chưa xác nhận` không chứng minh đường đi hay vụ nổ.

Mô hình hiện chỉ nhận throwable cookable, không va chạm nổ, không playerCollision, không heavyType, không force-max, không fuseVariance và aimDistance bằng 0; thực tế chủ yếu frag và MIRV nếu định nghĩa capture hợp lệ. Smoke, bom va chạm, vật biến hình và fuse đặc biệt không hỗ trợ. `amped_explosives`, thiếu perk, thiếu snapshot vận tốc mới (bao gồm người ném), thiếu contract map/terrain, target, vật cản, fuse hoặc loại bom thì không điều khiển. Danh sách vật thể chỉ gồm dữ liệu client đã nhận.

Mô hình dùng trọng lực/drag mặt đất phẳng theo source và dự đoán mục tiêu theo vận tốc hiện tại; không đoán tương lai đổi hướng. Kiểm tra đường đi 2D bảo thủ, coi vật cản trên đường là chặn, không tính nảy hoặc ném vượt vật thấp; surface được lấy từ `getGroundSurface` client tại các điểm rời rạc, không bảo đảm trùng `isOnWater` server, có thể bỏ sót vùng nước mỏng hoặc dữ liệu chưa nhân bản. Target có thể không có nghiệm hay nằm ngoài FOV. Thiếu thông tin thì trả input gốc; diagnostic **Help → Refresh diagnostics → grenadeAim.state** giải thích trạng thái. Snapshot đứng yên có thể không được server cập nhật thường xuyên, khiến điều kiện vận tốc mới không đạt và tính năng không hoạt động.

## Kiểm thử và nguồn

`node scripts/check-grenade-upstream.mjs .cache/survev` so sánh 320 quỹ đạo phẳng với `WeaponManager.throwThrowable` và `Projectile.update` của source `3edee7e8...`, với collaborators giả. `scripts/check-upstream.mjs` kiểm tra Lock đi tới InputMsg serialize (ground adapter và snapshots giả), các chế độ minified, và độ lượng tử hóa input. Unit test bao gồm mode, tính quỹ đạo, không sửa Fire, nhả, equip, thiếu terrain và kiểm tra đường. Không có kiểm thử live, không xác nhận các điều kiện game mới nhất hoặc mọi terrain/đối tượng/perk.
