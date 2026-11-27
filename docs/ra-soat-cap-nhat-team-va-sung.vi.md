# Hủy plan khi server cập nhật team hoặc súng

Source Survev `Game.m_processGameUpdate` xử lý `playerInfos` và `deletedPlayerIds` rồi dựng lại `teamInfo` ngay cả khi `fullObjects`, `partObjects`, `delObjIds` đều rỗng. Nó cũng cập nhật active player và local weapon từ `activePlayerIdDirty` / `activePlayerData.weapsDirty`. Trước đây cache aim chỉ bị hủy theo các mảng world object: với Wallcheck tắt, plan đã chọn địch có thể được dùng lại khi thông tin team vừa đổi hoặc xóa trước sender; đổi vũ khí cũng có thể để lại plan của vũ khí trước.

Nay các cập nhật team, active player và vũ khí cũng hủy plan; cập nhật active player buộc discovery ngay thay vì đợi throttle một giây. Receiver không tự gửi input. Sender tính lại theo trạng thái mới; quan hệ không rõ vẫn không được chọn, Fire vật lý giữ nguyên. Update chỉ điều khiển thông thường không gây quét hay hủy plan.

Regression gồm cập nhật team/loại thông tin/vũ khí không kèm world object và đổi active player. Fixture source thực thi `m_processGameUpdate`, `deletePlayerInfo`, `recomputeTeamData` và serializer thật qua 4 biến thể; không phải test live. Chỉ xử lý thông tin mà client nhận được, không khẳng định đã giải quyết mọi nguyên nhân giật hay bắn đồng đội.
