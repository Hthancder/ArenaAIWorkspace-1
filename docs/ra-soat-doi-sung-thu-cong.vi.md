# Nhường điều khiển khi đổi vũ khí thủ công

Source Survev `Player.handleInput` nhận hướng chuột, di chuyển, Fire và danh sách equip từ cùng gói. Trước đây khi người chơi bấm đổi vũ khí, pending Auto Switch bị hủy nhưng sender vẫn có thể dùng plan gun/melee tính trước đó. Đặc biệt khi Wallcheck tắt, plan melee được cache có thể tiếp tục chèn hướng chạy về mục tiêu ngay trong gói equip thủ công.

Nay gói equip/swap thủ công hủy plan, hướng melee, equip tự động và mouse ownership trước khi tạo gói; hướng và Fire thật được giữ. Chế độ Mobile Movement nếu bật vẫn áp dụng di chuyển từ phím người chơi, không chạy theo melee. Các lệnh scope không bị phân loại là equip, Auto Switch của script vẫn theo cơ chế riêng. Không trì hoãn hay phát lại Fire.

Test mô phỏng gun/melee với Wallcheck bật/tắt, movement, và native InputMsg serialize qua bốn biến thể source. Không mô phỏng server nhận gói trong mạng hoặc khẳng định đây là toàn bộ nguyên nhân giật live; khi tiếp tục giữ Fire, tính năng có thể lập plan mới theo trạng thái được client quan sát ở frame sau.
