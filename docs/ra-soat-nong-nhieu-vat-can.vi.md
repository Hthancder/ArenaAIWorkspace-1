# Nòng súng gần nhiều vật cản

Đối chiếu nhánh `WeaponManager.fireWeapon` và collider của source Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`:

- Sau mỗi va chạm, server dịch endpoint theo pháp tuyến rồi dùng endpoint mới cho vật cản tiếp theo. Trước đây mô hình luôn kiểm tra tất cả vật cản trên tia ban đầu và chọn theo khoảng cách thô. Một fixture nhiều collider tròn cho thấy sai khác tới 1,686 wu trong một mẫu. Nay mô hình lần lượt cập nhật endpoint, độ dài và mặt phẳng clipping theo thứ tự registry đang quan sát.
- Khi gunPos nằm trong AABB cùng layer, phép giao nguồn có pháp tuyến không ổn định và một số mẫu trả điểm xuất phát rất xa phía sau. Thay vì tự tin bịa muzzle, aim nhường điều khiển và giữ Fire thủ công; có thể bỏ qua mục tiêu hợp lệ trong cảnh này. Nếu source bỏ qua vật cản do bắn khác layer, không áp dụng guard nhầm.

Kiểm thử: 270 test; 1.152 mẫu nòng một collider tròn và 3.000 mẫu ba collider tròn, so với nhánh source với cùng thứ tự (sai số tối đa ~4,5e-16 wu trong bộ mẫu). Với 3.000 mẫu hai AABB: 572 mẫu gunPos trong hộp được guard; 2 mẫu trong số đó có kết quả source cách gốc hơn 3,5 wu; 2.428 mẫu ngoài hộp có sai lệch tối đa ~0,00969 wu trong bộ mẫu. Đây là kiểm thử tổng hợp, không chứng minh thứ tự registry client trùng thứ tự grid server, cũng không mô phỏng toàn bộ shotgun, dual/offhand hay gameplay.

Các fixture source client 4 biến thể, layer, cầu thang, ray, grenade, loot và 568 cấu hình súng đều đạt. Benchmark Node geometry 4.000 vật thể median 0,735 ms, p95 0,972 ms/solve chỉ đo scan tổng hợp, không đo đầy đủ muzzle hay FPS thực. Chưa kiểm thử live.
