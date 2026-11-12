# Duality Client Reborn — compatibility preview

Bản userscript viết lại từ mục tiêu của mẫu người dùng cung cấp, với menu nhẹ và discovery có kiểm chứng. **Đây là bản thử nghiệm đã test offline, chưa xác nhận hoạt động trên build live của survev.io.** Không bảo đảm tương thích mọi update hoặc tránh phát hiện. Việc dùng trên máy chủ công cộng có thể vi phạm điều khoản của game.

Bản hiện tại: **0.1.2 — readable debug**. Người dùng đã báo bản trước không hoạt động trên live; lỗi live **chưa được tái hiện hoặc xác định nguyên nhân**. 47 tests offline chỉ kiểm tra các trường hợp mô phỏng, không xác nhận game live. Xem [đợt đối chiếu source lần 2](docs/survev-source-pass-2.vi.md) để biết nguồn tham khảo.

## File để cài

**[`userscripts/duality-reborn.user.js`](userscripts/duality-reborn.user.js)** — artifact độc lập, **không minify**, giữ tên hàm và các section module; đã bundle parser; không cần cài npm trên máy người dùng và không tải thư viện/font/ảnh từ CDN.

1. Tắt các bản Duality/Neko/userscript cũ để tránh xung đột hook.
2. Tạo script mới trong Tampermonkey/Violentmonkey, dán toàn bộ file `.user.js`, lưu.
3. Script phải chạy ở **page/main world**, tại **document-start**. Metadata có `@sandbox raw` và `@inject-into page`; mức hỗ trợ tùy manager/trình duyệt. Không chạy như đoạn console muộn sau khi trang đã load.
4. Reload `https://survev.io/`. Mở menu bằng **Right Shift**. Các tính năng gameplay mặc định **tắt**.
5. Chờ trạng thái capture/mapping. Checkbox bị khóa nghĩa là chưa đủ contract trên build đó, không phải tính năng đã hoạt động.
6. Nếu có menu nhưng tính năng không chạy: vào trận → **Help → Refresh diagnostics**, gửi JSON diagnostics. Các trường `captureState`, `checks`, `missingContracts`, `lastWarning` phân biệt capture/mapping/protocol; diagnostics không chứa token Join, tên/vị trí người chơi hoặc game object.
7. Nếu **không có menu**: mở Console, tìm thông báo `[Duality Reborn 0.1.2] Script đã chạy` và gửi dòng lỗi màu đỏ đầu tiên nếu có. Cho biết trình duyệt và userscript manager. Không có thông báo này chưa đủ để kết luận lỗi game: có thể script chưa được inject, bị chặn hoặc lỗi trước bootstrap. Không gửi cookie/token hay dump toàn bộ game state.

**Retry capture** chỉ thử lại bắt Application trong 15 giây. Nếu đã lỡ thời điểm khởi tạo item DB/Join, cần reload. **Stop / cleanup** gỡ hook của bản này, trả property về giá trị game ghi gần nhất và bỏ menu/overlay. Muốn bật lại sau Stop: reload.

## Sửa riêng trong 0.1.2

- Bỏ `minify: true` khỏi build, bật giữ tên hàm. File cài có format và section source rõ ràng; vẫn bundle Acorn nên file dài, không phải mã obfuscate.
- Sửa lỗi **Retry capture làm mất canvas**: engine không còn xóa canvas do menu sở hữu; Stop vẫn gỡ menu/overlay.
- Hủy callback Application đang chờ microtask khi Retry/Stop để tránh khởi tạo engine cũ sau khi đã hủy.
- Có boot log và diagnostics trạng thái capture/checklist contract. Đây là công cụ xác định lỗi, **không phải bản sửa tương thích live đã được xác nhận**.

## Đã thay đổi

- Bỏ iframe loader và phụ thuộc `window.ou/sr/sl/pr`.
- Bỏ anti-debug đệ quy, tắt console/Error, freeze window, fake `toString`, font spoof, redirect/version gate bên ngoài và cookie giả `__cf_ray`.
- Giữ bố cục sidebar và tab **Main / Visuals / Misc / Keybinds / Help**, nhưng viết bằng DOM thuần; bỏ blur, animation, glow, logo/font ngoài và render framework.
- Capture Application và item DB có timeout, reentrancy guard và ownership-aware cleanup. Có **hai hook global tạm thời**: `.call` để bắt Application và `Object.keys` để bắt DB; không tuyên bố hoàn toàn không hook global hay zero overhead.
- Dùng **AST/source semantics + runtime contracts**, không dùng số lượng field, thứ tự `Object.keys` hay riêng `function.length` để đoán vai trò camera/player/sender.
- Không `eval` source game hay gọi thử constructor/method game lên Proxy giả để dò property. Parser Acorn chỉ đọc cú pháp; chỉ các API đã được nhận diện và feature opt-in mới được gọi/sửa khi chạy.
- Tách lifecycle app/game/pool/active-player, reread array khi compact, reset tracking khi entity ID bị tái sử dụng.
- Input aim phục hồi **trước native `flush()`**, không phá snapshot bàn phím/chuột. Semi-auto không đảo current/old mouse state.
- Sửa message ở boundary serializer **của instance game**, không bit-flip raw WebSocket. Những enum-dependent features chỉ bật sau khi quan sát Join **protocol 1028**, khớp snapshot source đã khảo sát.
- UI cập nhật trạng thái 1 Hz, discovery tối đa 1 Hz sau bootstrap, scan map effect có budget ở 2 Hz, overlay tối đa 30 Hz. Đây là giới hạn tần suất, **không phải số đo FPS hoặc bảo đảm không lag**.

## Tình trạng tính năng

Tất cả dòng “đã viết lại” dưới đây là trạng thái implementation/fixture tests, **không phải xác nhận live**.

| Nhóm | Tình trạng | Điều kiện / khác biệt |
|---|---|---|
| Aimbot, smooth, FOV, sticky, aim dot | Đã viết lại | Player/camera/input-flush/team/spectator contract; giữ nút bắn. Unknown team bị bỏ qua. |
| Prediction | Đã viết lại | Cần item DB; constant-velocity intercept, time-aware EMA; dùng base bullet speed, chưa tính perk modifiers hoặc toàn bộ netcode/physics. |
| Wallcheck | Bảo thủ | Segment circle/AABB cùng layer; bỏ obstacle thấp hơn bullet height khi protocol khớp. Chưa mô phỏng muzzle/aimLayer trên cầu thang, xuyên phá/ricochet. |
| Melee Lock | Bản cơ bản | Aim trong 5.5 world units + mobile direction; cần protocol xác nhận và DB. Không có Auto Melee switch. |
| Semi Auto | Đã viết lại | Held single-fire, theo fireDelay; không tuyên bố vượt cooldown server. |
| Auto Switch | Bản cơ bản hai súng | Quan sát ammo giảm, chuyển sang slot súng khác nếu còn đạn. Không có one-gun swap/reset trick. |
| Player lines / visible nametags | Đã viết lại | Chỉ player active client đã nhận; không có toàn bộ state ngoài vùng replication. Đường ESP dùng vị trí render nội suy nếu nhận diện được, fallback vị trí mạng; không thay nametag style liên tục. |
| Ceiling / tree / bush opacity / smoke | Đã viết lại | Scan có budget, property override có restore; không dark-tint smoke trực tiếp vào field private. |
| Zoom | Có giới hạn 1–3× | Dò local zoom bằng semantic anchor; đổi phạm vi camera không tạo enemy state mới. |
| Own flashlight | Range/spread preview | Dùng base defs, chưa tính movement/recoil/perk modifiers; không phải raycast/ricochet chính xác hoặc flashlight đối thủ. |
| Grenade nominal radius | Preview | Chỉ active projectile, cùng layer, defs/registry + protocol khớp; không nhận nhầm loot. Không có fuse/landing prediction/occlusion/shrapnel; không phải ranh giới an toàn. |
| Auto Loot | Mobile Join mode | Trận tiếp theo; loot theo điều kiện server, có cả mở cửa; còn ảnh hưởng scope/mobile behavior. Chỉ protocol xác nhận, không phải field autoLoot riêng. |
| Mobile Movement | Đã viết lại | Vector chuẩn hóa, touchMoveLen số 255, không boolean. |
| Layer Spoofer / Map Highlights | **Chưa port** | Ghi rõ trong menu; không fake trạng thái thành công. |
| Grenade trajectory / ricochet / other flashlights | **Chưa port** | Cần đối chiếu physics và collision build live, không giữ approximation sai từ bản cũ. |

## Các giới hạn tương thích quan trọng

Source tham khảo: [`survev/survev@3edee7e8bd07fda8a63905aab4c45b595b684a80`](https://github.com/survev/survev/tree/3edee7e8bd07fda8a63905aab4c45b595b684a80), protocol **1028**. Môi trường phát triển chỉ truy cập được các host được cấp phép, không truy cập trực tiếp bundle/game live trên survev.io.

Semantic discovery chịu được một số đổi tên property, field bổ sung và thay thứ tự khai báo (có mutation test), nhưng vẫn phụ thuộc public anchors như `selectIdlePose`, `canInteract`, `getMeleeCollider`, `getAimMovement`, `serializeMsg` và dạng phương trình camera đã nhận diện. Nếu game inline/xóa anchor, dùng computed access opaque hoặc đổi logic, tính năng liên quan sẽ bị khóa. **AST không phải cơ chế bất biến qua mọi phiên bản.**

Camera/world overlay ưu tiên vị trí render nội suy cho đường ESP khi nhận diện được contract; fallback về vị trí mạng nếu thiếu contract. Không bảo đảm khớp pixel với mọi render variant; tracking vẫn dùng vị trí mạng. Item capture chỉ diễn ra lúc khởi tạo registry; script chạy quá muộn có thể không có DB. Các tính năng phụ thuộc enum sẽ không tự nới protocol gate khi thấy phiên bản lạ.

Không có network telemetry, auto-update URL, phiên bản/license gate hay remote payload. Bản gốc được giữ riêng ở `references/duality-client.reference.js`, **không import vào build**; bản đó chứa lỗi cú pháp như nội dung được lưu và không được thực thi trong tests.

## Phát triển / kiểm tra

Node.js 22:

```sh
npm ci
npm run check
```

`pretest` build lại artifact trước khi chạy tests. Test gồm JS semantics, semantic discovery, mutation qua minify/rename, timeout/cleanup, message clone, pool lifecycle, input flush, menu/jsdom và bootstrap end-to-end với **fixture giả**. Không có end-to-end test với browser game live, anti-cheat hay benchmark FPS.

- `src/core.mjs`: safe descriptor traversal, AST roles, bootstrap, math, cleanup.
- `src/features.mjs`: feature runtime, capability gates, lifecycle, input và visual overrides.
- `src/menu.mjs`: DOM menu, config validation/storage và keybinds.
- `src/main.mjs`: userscript lifecycle/controller.
- `scripts/build.mjs`: metadata và bundle.
- `tests/`: offline regression tests.
- `docs/survev-technique-review.vi.md`: phân tích ba mẫu ban đầu.

Parser Acorn dùng MIT license; thông báo license được nhúng vào artifact `.user.js` khi build.
