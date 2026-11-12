# 0.5.0-preview.4 — phân biệt registry qua native snapshot receiver

## Bằng chứng từ diagnostics người dùng

Preview.3 capture/protocol/sender/scheduler đều hợp lệ nhưng `objectRegistry=false`, `registry.state=ambiguous-native-id-table`. Người dùng chọn Lock, activation Fire, Wallcheck bật. History lúc đang điều khiển có `wallcheck-unavailable`, chuyển lại `waiting-activation` khi nhả Fire. `forwardedInputs=320`, `correctedGameplayInputs=0`, `schedulerRequests=0`, `lastCorrection=null`.

Đây là bằng chứng một blocker cụ thể trong lượt thử, không phải chỉ hình súng chưa xoay hoặc snapshot mở menu. Chưa chứng minh blocker này là lỗi duy nhất; chưa biết bảng cạnh tranh cụ thể trong phiên live vì không xuất game references/source vào JSON.

## Vì sao preview.3 chưa đủ

Cặp get-by-ID/delete-by-ID không phải đặc trưng độc quyền của world objects. Preview.3 fail closed khi có nhiều owner/table cùng mẫu. Fixtures cũ chỉ có một native candidate và một shape-only decoy, nên không kiểm tra được tình huống người dùng vừa gặp. Cũng chưa deduplicate hai game fields tham chiếu cùng owner.

## Sửa

1. Deduplicate các owner bằng object identity, không đếm alias hai lần.
2. Vẫn chứng minh native get/delete dùng chung table và cùng tham số ID.
3. Tìm actual snapshot receiver qua public message contracts `fullObjects`, `partObjects`, `delObjIds`, `activePlayerData`.
4. Truy call `this.owner.deleteMethod(msg.delObjIds[i])`: owner và deleteMethod phải khớp native candidate. Không lấy call dùng `deletedPlayerIds` (player metadata).
5. Một candidate được receiver xác nhận thì chọn `snapshot-id-table`; nhiều candidate receiver thì vẫn fail closed. Không chọn theo thứ tự key, tên obfuscated, bảng lớn nhất hoặc tự tắt Wallcheck. Không có anchor thì giữ fallback cũ và trạng thái ambiguity rõ ràng.
6. Hook receiver của chính script trước đây che AST gốc. `patchMethod` lưu liên kết wrapper→original trong WeakMap riêng; semantic AST inspection dùng original chỉ với wrapper do module này tạo. Không tin public `.original`, không thay Function.toString, không gọi method để dò. Cleanup/ownership vẫn giữ nguyên.
7. Diagnostics thêm `registry.nativeCandidates` và `receiverCandidates` để xác nhận có chọn đúng nhánh. Không xuất table references, IDs, tọa độ, packet hay token.

Không đổi Fire, movement, cooldown, prediction/controller hoặc xoay súng để che input failure. Không bypass wall collision.

## Kiểm chứng

- `npm run check`: **140/140 PASS**, build readable và syntax check.
- `npm run check:upstream -- .cache/survev`: **4/4 PASS**, pinned source 3edee7e8bd07fda8a63905aab4c45b595b684a80, thường và minify/mangle × mobile/nearby.
- Fixture source bổ sung native get/delete decoy thứ hai và alias của Creator. Actual Game.m_processGameUpdate liên kết đúng registry qua delObjIds, sau khi receiver đã được hook. Có actual PlayerBarn.deletePlayerInfo, không chỉ chọn lọc getter.
- Kịch bản source giữ Wallcheck bật, xác nhận `snapshot-id-table`, nativeCandidates=2/receiverCandidates=1; vật cản vẫn chặn, bỏ vật cản thì Lock correction đi qua actual InputMsg serializer/BitStream.
- Regression mới: phân biệt delObjIds/deletedPlayerIds, alias identity, minify/rename, hai anchor thật vẫn từ chối, method giả thiếu snapshot contract không được dùng, owned wrapper/remap/cleanup và public `.original` giả không được tin.
- Reference gốc không đổi; không sửa benchmark vì solver/controller không đổi.

Đây là kiểm chứng offline/source-method, **không phải live gameplay E2E, server ACK hoặc proof of hit**.

## Kiểm tra trên máy người dùng

Cài thay script cũ bằng `userscripts/duality-reborn.user.js` version **0.5.0-preview.4**, reload. Giữ Lock/Fire/Wallcheck và thử với enemy trong FOV. Diagnostics mong đợi `registry.state=snapshot-id-table`, `checks.objectRegistry=true`, `capabilities.wallcheck=true`. Khi thực sự cần đổi hướng, `aimEvidence.lastCorrection`/`correctedGameplayInputs` phản ánh native sender correction; không phải server xác nhận.

Nếu còn lỗi, Copy diagnostics sau lượt thử (có thể sau chết). Không cần tự tắt Wallcheck hoặc gửi toàn bộ game object. Nếu registry vẫn ambiguous, candidate counts sẽ phân biệt lỗi duplicate/reference với nhiều native snapshot anchors; nếu đã resolve, live evidence sẽ chỉ ra blocker tiếp theo thay vì suy từ menu-open.
