# Reborn 0.2.0 — sửa luồng Auto Loot và aim/input

Ngày: 2026-11-12. Người dùng báo 0.1.2 có menu nhưng **Auto Loot và Aimbot không hoạt động**. Báo lỗi live này được giữ là chưa giải quyết xác nhận; chưa nhận diagnostics/build capture từ máy người dùng. Không coi số test đạt là bằng chứng đã “reborn hoàn toàn”.

## 1. Lỗi đã tái hiện bằng method source

Repo public được fetch/clone lại, vẫn ở `3edee7e8bd07fda8a63905aab4c45b595b684a80`.

### Desktop Join có thể có isMobile = undefined

[Game.tryJoinGame](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/game.ts#L160-L172) gán `device.mobile || window.mobile`. Trên desktop với `device.mobile === false`, khi không có `window.mobile`, giá trị là `undefined`, dù JoinMsg ban đầu khởi tạo field là false.

Bản cũ bắt buộc `typeof isMobile === 'boolean'` nên **bỏ qua toàn bộ Join**, bao gồm protocol và yêu cầu mobile loot. Harness chạy đúng method `tryJoinGame` từ source đã fail với `null !== 1028` trước khi sửa. Đây là lỗi bản Reborn tái hiện được với source public, chưa phải chứng minh nguyên nhân duy nhất của báo lỗi live.

Bản mới cho phép boolean hoặc undefined trong contract Join, vẫn kiểm tra các field/method còn lại; chỉ thay mobile flag khi protocol khớp và người dùng chọn mobile mode. Giữ prototype serializer, không sửa Join gốc. Sau khi thấy Join, mapping được refresh ở frame tiếp theo thay vì đợi throttle 1 giây. Diagnostics phân biệt **pending-next-join**, **mobile-join-forwarded**, **off-next-join**, **unsupported-protocol**. Forwarded chỉ nghĩa là đã chuyển qua native sender, không phải server acknowledgement hoặc xác nhận nhặt item.

### Input aim không dùng cùng origin với render

[Game.update — facing/input](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/game.ts#L470-L489) đổi mouse screen sang delta quanh **tâm viewport**, rồi cộng vị trí mạng của active player. [Camera render projection](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/camera.ts#L22-L27) lại trừ vị trí camera, có thể đã nội suy/shake và khác vị trí player.

Bản mới có `aimPoint(camera, target, playerPosition)` riêng; ESP tiếp tục dùng projection render. Test cố tình lệch camera center, rồi chạy chính các biểu thức aim được trích từ `Game.update` để kiểm tra hướng nhận được. Bản mới cũng fallback physical Fire nếu thiếu binds contract, thay vì chuyển từ fallback hoạt động sang undefined khi vừa quan sát được protocol. Khi binds đã nhận diện được, vẫn tôn trọng trạng thái phím người dùng đã bind.

## 2. Auto Loot dùng ngay trong trận

Mobile Join không thể bật hiệu lực server ngay giữa trận. Vì vậy 0.2.0 bổ sung **Nearby supplies (now)** và đặt làm pickup mode mặc định. Checkbox Auto Loot vẫn mặc định tắt. Cấu hình cũ thiếu `lootMode` sẽ dùng nearby mode; người dùng có thể chọn mobile mode nếu muốn giữ hành vi Join cũ.

Source liên quan:

- [LootBarn tìm closestLoot](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/loot.ts#L163-L195), [getter](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/loot.ts#L244-L246).
- [Native checkInputs chứa Input.Loot](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/game.ts#L565-L590).
- [Server xử lý Input.Loot](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/objects/player.ts#L3487-L3495), [server chọn loot](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/objects/player.ts#L3568-L3598).

Implementation:

- Nhận diện AST của `getClosestLoot()` trả về duy nhất một own field; chỉ đọc field, không gọi thử method để dò state.
- Revalidate entity active/type Loot, vị trí hữu hạn, cùng layer, owner và bán kính client. Chỉ chọn ammo/heal/boost/throwable. Bỏ qua súng, melee, outfit, armor, scope và perk; không tự thay inventory quan trọng.
- Phát native `isBindPressed(Input.Loot)` cho frame đã chọn; để game tự dựng InputMsg, phát hiện diff và serialize. Không gửi gói độc lập, không synthesize Interact/Use, không giả click chuột.
- Backoff 350 ms → 700 ms → 1400 ms → tối đa 2000 ms cho cùng entity/id/count chưa đổi. Count/id đổi thì reset. Không giả xác nhận capacity hay pickup thành công từ input đã phát.
- Pause khi hidden/dead/downed/spectating; chỉ bật sau Join protocol 1028 và đủ contracts. Hook giữ cùng pulse cho nhiều consumer trong một frame; restore khi bind instance đổi hoặc dispose.

**Giới hạn:** dùng closestLoot của client từ frame trước, đã kiểm lại vị trí/range. Server tự chọn lại loot và kiểm capacity/quyền nhặt; không có cam kết target-ID hay pickup acknowledgement. Nếu loot gần nhất là súng/gear bị bỏ qua, không tự chọn item thứ hai. Không hỗ trợ đầy đủ touch controls; khoảng cách desktop được dùng bảo thủ. Không bật server-mobile bằng nearby mode, nhưng nếu trận đã Join mobile trước đó thì chuyển mode giữa trận không hoàn tác được server state.

## 3. Không còn im lặng khi aim không tác động

Diagnostics có `stats.aimState` và counter lý do loại ứng viên: teammate, unknownTeam, otherLayer, dead/downed, outsideFov, wall… Không đưa player ID/name, vị trí hay message/token vào các counter này. UI hiển thị Aim/Loot state 1 Hz. `wallcheck-unavailable` vẫn chặn aim nếu người dùng yêu cầu wallcheck; không lén tắt wallcheck để tạo cảm giác tính năng hoạt động.

Help có **Copy diagnostics**, với textarea chọn sẵn để Ctrl+C nếu clipboard bị chặn. File cài tiếp tục **không minify**, không có CDN/font/ảnh/UI effects mới.

## 4. Kiểm tra đã chạy và cách tái hiện

```sh
npm run check
# 59/59 offline tests, build artifact và syntax check

npm run check:upstream -- /path/to/survev-checkout
# checkout phải có HEAD đúng commit pin ở trên
```

Harness `scripts/check-upstream.mjs` không vendor source Survev vào artifact/repo. Nó đọc/transpile file từ checkout riêng, trích các method cần kiểm tra, chạy với collaborator/socket/renderer giả. Chạy 4 kịch bản: unminified và minify + đổi tên m_* bằng esbuild, mỗi dạng kiểm tra cả mobile và nearby mode.

Nó dùng method thật `tryJoinGame`, `JoinMsg.serialize`, `InputMsg`, player/camera/binds/getClosestLoot và biểu thức input lấy từ `Game.update`. Không chạy toàn bộ `Game.update`, toàn bộ Codefend pipeline, renderer, networking hay physics/server. Do đó **đây là kiểm tra method-level với source public, không phải full game integration hoặc live E2E**. Không benchmark FPS, không thử anti-cheat, không cam kết tương thích mọi update.

## 5. Checklist test lại trên máy người dùng

1. Chỉ bật một bản script, kiểm tra version **0.2.0**; reload trang và vào trận mới để quan sát được Join.
2. Auto Loot → Enabled + **Nearby supplies (now)**. Đến gần ammo/heal/boost/throwable, quan sát inventory thực tế. `loot-input-ready` chỉ nói input đã sẵn sàng; không chứng minh nhặt thành công.
3. Nếu muốn mobile behavior: chọn **Mobile loot / doors**, bật trước khi Join trận mới. Bật/tắt/chuyển mode giữa trận không sửa được mobile mode đã gửi cho server.
4. Aim → Enabled, giữ phím/nút Fire, đưa con trỏ gần đối thủ trong FOV. Có thể tắt prediction/smooth để tách lỗi baseline; nếu bật wallcheck mà thiếu contract, trạng thái sẽ báo rõ, không tự bypass.
5. Nếu vẫn lỗi: **Help → Copy diagnostics** sau khi vào trận, gửi JSON cùng hiện tượng. Cần dữ liệu live này trước khi xác nhận đã xử lý báo lỗi hoặc port tiếp toàn bộ phần còn thiếu.
