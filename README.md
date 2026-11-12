# Duality Client Reborn — compatibility preview

Bản userscript viết lại từ mục tiêu của mẫu người dùng cung cấp, với menu nhẹ và discovery có kiểm chứng. **Đây là bản thử nghiệm đã test offline, chưa xác nhận hoạt động trên build live của survev.io.** Không bảo đảm tương thích mọi update hoặc tránh phát hiện. Việc dùng trên máy chủ công cộng có thể vi phạm điều khoản của game.

Bản hiện tại: **0.3.0 — team-aware ESP / readable preview**. ESP có phân biệt ENEMY / ALLY / SQUAD / UNKNOWN, filter, màu tùy chỉnh, label, distance/weapon, marker và off-screen arrows; aim dùng chung logic team. Giữ fixes Join/aim/native pickup của 0.2.0. **Chưa xác nhận live và chưa gọi là “reborn hoàn toàn”.** Kết quả: 79 tests offline + 4 kịch bản method-level từ source public. [Chi tiết ESP 0.3.0, phạm vi còn mở và checklist](docs/reborn-0.3.0.vi.md).

## File để cài

**[`userscripts/duality-reborn.user.js`](userscripts/duality-reborn.user.js)** — artifact độc lập, **không minify**, giữ tên hàm và các section module; đã bundle parser; không cần cài npm trên máy người dùng và không tải thư viện/font/ảnh từ CDN.

1. Tắt các bản Duality/Neko/userscript cũ để tránh xung đột hook.
2. Tạo script mới trong Tampermonkey/Violentmonkey, dán toàn bộ file `.user.js`, lưu.
3. Script phải chạy ở **page/main world**, tại **document-start**. Metadata có `@sandbox raw` và `@inject-into page`; mức hỗ trợ tùy manager/trình duyệt. Không chạy như đoạn console muộn sau khi trang đã load.
4. Reload `https://survev.io/`. Mở menu bằng **Right Shift**. Các tính năng gameplay mặc định **tắt**.
5. Chờ trạng thái capture/mapping. Checkbox bị khóa nghĩa là chưa đủ contract trên build đó, không phải tính năng đã hoạt động.
6. Nếu có menu nhưng tính năng không chạy: vào trận → **Help → Copy diagnostics**, gửi JSON diagnostics. Các trường `captureState`, `checks`, `missingContracts`, `lastWarning` phân biệt capture/mapping/protocol; diagnostics không chứa token Join, tên/vị trí người chơi hoặc game object.
7. Nếu **không có menu**: mở Console, tìm thông báo `[Duality Reborn 0.3.0] Script đã chạy` và gửi dòng lỗi màu đỏ đầu tiên nếu có. Cho biết trình duyệt và userscript manager. Không có thông báo này chưa đủ để kết luận lỗi game: có thể script chưa được inject, bị chặn hoặc lỗi trước bootstrap. Không gửi cookie/token hay dump toàn bộ game state.

**Retry capture** chỉ thử lại bắt Application trong 15 giây. Nếu đã lỡ thời điểm khởi tạo item DB/Join, cần reload. **Stop / cleanup** gỡ hook của bản này, trả property về giá trị game ghi gần nhất và bỏ menu/overlay. Muốn bật lại sau Stop: reload.

## ESP phân biệt địch–ta (0.3.0)

**Visuals → ESP / Teams → Enabled**. Mặc định địch **đỏ**, đồng minh/cùng squad **xanh**, chưa rõ team **xám**. Khác squad nhưng cùng phe vẫn là ALLY, không phải địch. Membership thiếu/xung đột luôn UNKNOWN và không trở thành mục tiêu aim.

- **Teams:** lọc enemy/ally/unknown/downed, cùng layer, max range theo world units.
- **Display:** lines, marker, role/status labels, tên, distance, weapon, off-screen arrows opt-in, current enemy target highlight và legend/counts.
- **Colors:** màu riêng cho enemy/ally/unknown/target; font size, opacity và line width có giới hạn.
- Label dùng Canvas2D và text game đã đặt, không đổi TextStyle mỗi frame. Tránh text trùng bằng native-name override có restore. Filter áp dụng overlay, không xóa UI đồng đội vốn thuộc game.
- Không dựng HP/armor/ammo giả. Off-screen arrows chỉ dùng active entities client đã nhận. Đường/marker là ký hiệu, không phải hitbox hay collision visibility.
- DPR cap 2×, tối đa 30 Hz / 256 entities và cache 256 measurements; chưa có FPS benchmark.

## Test lại hai tính năng chính (0.2.0)

- **Auto Loot:** Misc → Auto Loot → Enabled → **Nearby supplies (now)**. Dùng ngay trong trận khi đủ contract/protocol; chỉ ammo/heal/boost/throwable. Không tự đổi súng/gear. Có backoff nếu loot không đổi, không giả xác nhận inventory tăng. Cấu hình cũ thiếu pickup mode sẽ dùng nearby mode.
- **Mobile loot / doors:** chọn mode này nếu muốn hành vi Join cũ; phải bật **trước khi Join trận mới**. Đã sửa desktop Join có `isMobile === undefined` khiến bản trước bỏ qua cả protocol và mobile flag. Chuyển/tắt giữa trận không hoàn tác server-mobile state đã gửi.
- **Aimbot:** Enabled, giữ nút/phím Fire và đưa con trỏ gần đối thủ trong FOV. Phép chiếu input nay tách khỏi ESP để không lệch theo camera interpolation/shake. Trạng thái `Aim` và `Loot` hiển thị riêng; nếu chưa tác động, gửi Help → Copy diagnostics thay vì chỉ screenshot checkbox.
- `wallcheck-unavailable` nghĩa là bạn đang yêu cầu wallcheck nhưng registry/collider contract chưa đủ. Script không âm thầm bỏ qua wallcheck. Nearby loot cũng không chạy khi thiếu item DB hoặc chưa thấy Join khớp protocol.

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
| ESP / labels / player lines | Team-aware 0.3.0 | Địch/ally/squad/unknown, filter, tùy chỉnh màu; downed/layer/distance/weapon, markers/legend và arrows opt-in. Chỉ active entities đã nhận; vị trí render nếu nhận diện được, fallback mạng; không giả HP hoặc đổi TextStyle liên tục. |
| Ceiling / tree / bush opacity / smoke | Đã viết lại | Scan có budget, property override có restore; không dark-tint smoke trực tiếp vào field private. |
| Zoom | Có giới hạn 1–3× | Dò local zoom bằng semantic anchor; đổi phạm vi camera không tạo enemy state mới. |
| Own flashlight | Range/spread preview | Dùng base defs, chưa tính movement/recoil/perk modifiers; không phải raycast/ricochet chính xác hoặc flashlight đối thủ. |
| Grenade nominal radius | Preview | Chỉ active projectile, cùng layer, defs/registry + protocol khớp; không nhận nhầm loot. Không có fuse/landing prediction/occlusion/shrapnel; không phải ranh giới an toàn. |
| Auto Loot | Hai mode | Nearby supplies phát native Loot trong trận, chỉ stackable supplies, có backoff; mobile loot/doors cần Join mới. Cả hai vẫn chịu điều kiện server, không có pickup acknowledgement. |
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

`pretest` build lại artifact trước khi chạy tests. Test offline (79 cases) gồm JS semantics, semantic discovery, mutation qua minify/rename, timeout/cleanup, message clone, pool lifecycle, input flush, menu/jsdom và bootstrap end-to-end với **fixture giả**. Không có end-to-end test với browser game live, anti-cheat hay benchmark FPS.

- `src/core.mjs`: safe descriptor traversal, AST roles, bootstrap, math, cleanup.
- `src/features.mjs`: feature runtime, capability gates, lifecycle, input và visual overrides.
- `src/esp.mjs`: ESP frame model, relation/color/filter/labels, bounded Canvas2D renderer và DPR handling.
- `src/menu.mjs`: DOM menu, config validation/storage và keybinds.
- `src/main.mjs`: userscript lifecycle/controller.
- `scripts/build.mjs`: metadata và bundle.
- `tests/`: offline regression tests.
- `scripts/check-upstream.mjs`: kiểm tra method-level từ checkout source public riêng; chạy `npm run check:upstream -- /path/to/survev-checkout`, HEAD phải đúng source pin. Chạy 4 kịch bản (2 kiểu transform × 2 loot mode), không phải full game hoặc Codefend/live E2E.
- `docs/reborn-0.3.0.vi.md`: ESP/team semantics, tests và phạm vi còn mở.
- `docs/reborn-0.2.0.vi.md`: bằng chứng lỗi Join/input, native pickup và checklist live.
- `docs/survev-technique-review.vi.md`: phân tích ba mẫu ban đầu.

Parser Acorn dùng MIT license; thông báo license được nhúng vào artifact `.user.js` khi build.
