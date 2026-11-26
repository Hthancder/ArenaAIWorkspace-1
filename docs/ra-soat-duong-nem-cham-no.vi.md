# Rà soát preview vật ném nổ khi chạm

Đối chiếu Duality và source Survev cho thấy preview cũ giả định mọi vật ném bay song song hướng ngắm và tiếp tục lăn khi chạm đất. Với snowball và các loại `aimDistance > 0`, server tạo hướng từ vị trí bàn tay tới điểm phía trước người chơi; vật `explodeOnImpact` dừng/nổ khi chạm đất.

Preview đã tính hướng theo `aimDistance`, giới hạn độ cao theo source và dừng tại điểm chạm đất nếu nổ khi chạm. Nếu điểm cuối không đúng nhịp lấy mẫu, thêm điểm đó vào đường vẽ. Đây chỉ sửa hình dự đoán, không sửa input hay auto throw. Preview vẫn giả định không vật cản, không nước, không vận tốc người ném/perk và không biết fuse còn lại; đường nét đứt không chứng minh va chạm hoặc kết quả live.

`scripts/check-grenade-upstream.mjs` nay so sánh thêm 20 tình huống snowball từ `WeaponManager.throwThrowable` và `Projectile.update` tại 60 Hz, người ném đứng yên, không vật cản/nước. Không thay thế test thực tế.
