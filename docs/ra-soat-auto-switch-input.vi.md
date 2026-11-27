# Rà soát Auto Switch và quyền input

Đối chiếu luồng input client và xử lý vũ khí server trong bản Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80`: equip và Fire có thể cùng xuất hiện trong một gói, còn ammo phản ánh trạng thái được cập nhật sau đó. Không coi biến động ammo là xác nhận đồng bộ cho từng lần bắn.

- Khi người chơi tự equip/swap trong lúc giữ Fire, Auto Switch nhường quyền đến khi kết thúc lần giữ đó; trạng thái chuyển tự động đang chờ được xóa.
- Khi Fire được thả, xóa baseline ammo và chuyển đổi đang chờ. Lần giữ mới lấy mẫu đầu làm baseline thay vì so sánh với lần giữ cũ.
- Nếu Fire thả giữa lần tính frame và lúc gửi gói, hủy equip tự động đã lên lịch; input gốc vẫn được gửi.
- Equip thủ công khi Fire không được giữ chỉ hủy kế hoạch của chính gói đó, không chiếm quyền của lần giữ kế tiếp. Frame và sender đều quan sát nhả Fire ngay cả khi input bị chặn, để kết thúc quyền của lần giữ cũ; chỉ việc bị chặn khi vẫn giữ Fire không kết thúc quyền này.

Các test bao gồm tự equip rồi ammo giảm trong cùng lần giữ, kích hoạt lại sau khi thả, ammo cập nhật trước mẫu đầu của lần giữ mới, và thả giữa frame với sender. Đây là biện pháp bảo thủ, không phải ghép ACK bắn: ammo cập nhật trễ *sau* mẫu đầu của lần giữ mới vẫn có thể bị nhầm là phát mới; nếu phát thật xảy ra trước mẫu đầu, nó có thể không được nhận diện. Chưa kiểm thử gameplay live hoặc xác nhận sửa hiện tượng giật mà người dùng đã báo.
