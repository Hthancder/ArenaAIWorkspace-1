# Wallcheck khi registry không đọc được

Mapping phát hiện bảng object theo contract source, nhưng bảng đó có thể bị thay hoặc biến mất trước lần rà tiếp theo. Trước đây `geometryObjects` trả mảng rỗng cả khi bảng không hợp lệ hoặc scan ném lỗi; Wallcheck có thể hiểu nhầm đó là không có vật chắn. Đường ngắm bom cũng dùng một phép đọc trả rỗng khi scan thất bại.

Nay snapshot ghi trạng thái hợp lệ: bảng mất, dạng mảng, lỗi liệt kê hay entry accessor/biến mất đều không được coi là đường trống. Gun/melee với Wallcheck bật trả quyền ngắm; grenade aim từ chối nghiệm, kể cả khi tự thả đang chờ. Không gọi getter và không chặn Fire thủ công. Khi bảng đọc lại được, điều khiển có thể tiếp tục theo gate bình thường. Quét vẫn chỉ thực hiện khi có ứng viên, không thêm quét trước activation cho gun.

Test dùng bảng giả biến mất, proxy lỗi và hồi phục; grenade test kiểm tra mất bảng và hồi phục. Một số gói có thể dùng lại plan đã tính trong cùng frame; thay đổi ngay sau lần tính đó có thể chỉ được thấy ở lần solve tiếp theo. Snapshot đọc được vẫn không chứng minh server đã replicate mọi vật hoặc không thay đổi trong mạng, và chưa phải kiểm chứng live.
