# Rà soát tự thả bom và sát thương lên người ném

Source Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`: `ExplosionBarn.damageObject` chuyển damage cho Player; `Player.damage` miễn damage từ đồng đội khác nhưng không miễn cho chính người ném. Frag có bán kính nổ trực tiếp tối đa 12 world units. `Projectile.explode` có thể tạo nhiều bom con từ `splitType` và `numSplit` (ví dụ MIRV), ngoài vụ nổ đầu.

## Thay đổi

Chỉ áp dụng cho tự thả thử nghiệm, không đổi Preview/Assist/Lock hoặc bắt đầu Fire:

- Cần biết explosion definition, bán kính nổ và scale người ném; thiếu hoặc bất thường thì không tự thả.
- Với cùng hướng/lực và ba mốc bất định fuse hiện có, so khoảng cách giữa endpoint và vị trí người ném ngoại suy vận tốc đều. Không tự thả nếu nằm trong bán kính nổ tối đa + bán kính người ném + 0,5 wu biên dự phòng.
- Không tự thả throwable có split, vì mô hình hiện tại chưa tính đường đi và sát thương bom con.
- Input thủ công vẫn được giữ. Người chơi vẫn có thể tự thả hoặc chuyển quyền như trước.

**Quan trọng:** không tự thả không có nghĩa là ngòi dừng. Nếu người chơi tiếp tục giữ, bom vẫn có thể nổ trên tay. Kiểm tra này không bảo đảm an toàn: vận tốc có thể đổi, mạng/terrain/va chạm sai, shrapnel có thể đi xa hơn bán kính nổ trực tiếp, trạng thái server không được xác nhận. Chỉ là guard bảo thủ theo mô hình, có thể bỏ qua cơ hội hợp lệ; không hứa trúng hay an toàn tuyệt đối.

## Kiểm thử

`npm run check`: 265 test đạt, gồm tình huống gần người ném không tự thả nhưng vẫn thả tay được và tình huống xa vẫn tự thả. Fixture mới chạy chính source `Player.damage`, `ExplosionBarn.damageObject`, `Projectile.explode` và định nghĩa frag/MIRV, với cộng tác viên giả lập; xác minh self vs ally và split, không chạy server hay gameplay live. Kiểm tra nguồn còn lại: client 4 biến thể, grenade 320 + 20 preview, stair 11.520, ray 8.640, loot và 568 cấu hình súng đều đạt. Chưa kiểm thử live.
