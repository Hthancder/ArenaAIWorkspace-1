# Rà soát Auto Switch

Duality Client 4.1 có nhánh coi ammo từ 0 tăng lên khi đang giữ Fire (hoặc `shotDetected`) là điều kiện đổi súng. Reborn trước đó cũng coi 0 → dương khi giữ Fire là phát bắn. Nhưng source Survev `WeaponManager.fireWeapon` giảm ammo khi bắn, còn reload làm tăng ammo: chỉ giữ Fire trong lúc reload từ rỗng không chứng minh đã bắn. Vì vậy nhánh này có thể yêu cầu đổi súng ngay sau reload dù chưa thấy phát bắn.

Auto Switch nay chỉ nhận diện ammo giảm trên cùng slot và cùng loại súng. Đổi lấy độ an toàn: nếu reload và bắn gộp trong cùng snapshot, ammo cuối vẫn cao hơn trước, có thể bỏ lỡ lần đổi đó. Không suy đoán server đã bắn, không bypass cooldown, không sửa input Fire. Native equip thủ công vẫn được ưu tiên. Test unit mô phỏng reload từ rỗng rồi bắn trong cả hai chế độ; đây không phải xác nhận hành vi live.
