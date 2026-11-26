# Rà soát preview theo Duality

Duality lưu riêng `toMouseLen` từ input, không tính lực ném từ độ lớn vector hướng đã chuẩn hóa. Runtime cũ dùng `lastAimSent` (vector đơn vị) cho hướng và lấy độ dài vector đó chia zoom làm khoảng cách; vì vậy sau một lần aim preview bom có thể ngắn bất thường, hoặc giữ hướng súng cũ sau khi chuyển vũ khí.

Preview nay tách hướng khỏi khoảng cách: không có correction hiện tại thì dùng chuột vật lý/zoom; với plan hiện tại dùng hướng plan, và chỉ dùng khoảng cách plan khi nó có `toMouseHit`. Nếu sender đã tính lại trong cùng frame, kết quả sender được ưu tiên; đổi config/match bỏ dữ liệu cũ. Hướng center trùng với fallback native `(1,0)`. Không thay Fire, solver grenade, thời điểm nhả, wallcheck hoặc server input; vẫn là preview ước lượng, không mô phỏng đủ va chạm/địa hình/network.

Test bao gồm chuột thường, hướng vector đơn vị, khoảng cách plan, sender thắng plan trong cùng frame, bỏ plan sau đổi config và tái hiện chuyển từ hướng Lock cũ sang preview bom. Source fixture/physics vẫn có giới hạn và chưa kiểm chứng game live.
