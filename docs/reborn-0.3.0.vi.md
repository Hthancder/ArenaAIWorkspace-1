# Reborn 0.3.0 — ESP phân biệt địch/ta và thống nhất team logic

Ngày: 2026-11-12. Tiếp tục yêu cầu hoàn thiện Reborn, ưu tiên ESP. Đây là bản **implementation + offline/source-method checks**, không phải xác nhận đã phục hồi toàn bộ tính năng trên survev.io live.

## Những gì đã triển khai

### Team và squad không còn bị trộn

Source [PlayerBarn.recomputeTeamData](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/player.ts#L2827-L2869) tạo `teamInfo` theo teamId, `groupInfo` theo groupId. 0.3.0 xây hai membership index riêng cho mỗi lượt xử lý, dùng chung quy tắc phân loại cho ESP và aim:

| Nhãn | Điều kiện | Màu mặc định |
|---|---|---|
| SQUAD | Cùng team và có bằng chứng cùng group | Xanh `#56b6ff` |
| ALLY | Cùng team, khác group hoặc chưa rõ group | Xanh `#56b6ff` |
| ENEMY | Cả hai có team rõ ràng, khác team | Đỏ `#ff6262` |
| UNKNOWN | Thiếu hoặc xung đột team membership của bản thân/đối tượng | Xám `#b9bfc9` |

Khác squad **không** có nghĩa là địch trong faction mode. Group trùng cũng không ghi đè bằng chứng khác team. Membership trùng ở nhiều team là unknown; team 0 vẫn hợp lệ. Index mới đọc lại bảng team/group mỗi feature pass, không giữ màu của player ID cũ sau khi bảng được recompute. Aim chỉ nhận ENEMY rõ ràng, không tự nhắm unknown hoặc ally.

Giới hạn scan: tối đa 1024 membership records / 8192 ID entries mỗi bảng. Vượt budget thì không dùng index không đầy đủ để đoán team; kết quả trở về unknown.

### Hiển thị có thể cấu hình, không chỉ đổi màu đường nối

Trong **Visuals → ESP / Teams, ESP / Display, ESP / Colors**:

- Bật/tắt riêng địch, đồng minh/squad, unknown, downed; chỉ cùng layer nếu muốn.
- Giới hạn khoảng cách 10–500 **world units**; mặc định 200. Không gọi world unit là mét.
- Đường nối, marker, label có prefix quan hệ; tùy chọn tên, khoảng cách, vũ khí đang cầm.
- Downed có tag `DOWNED`; khác layer có `OTHER LAYER`, layer thiếu có `LAYER ?`. Giữ màu quan hệ, dùng nét đứt để thể hiện trạng thái phụ.
- Legend ENEMY / ALLY-SQUAD / UNKNOWN và số entity được chọn sau filter, không phải tổng số người trong trận.
- Mục tiêu aim hiện tại có thể được đánh dấu vàng `#ffd166`, nhưng chỉ khi vẫn được phân loại ENEMY. Tắt highlight nếu muốn giữ nguyên màu địch.
- Mũi tên off-screen là opt-in, chỉ dùng entity active client đã nhận; không có enemy toàn bản đồ hoặc memory tracking đối tượng đã rời replication.
- Màu enemy/ally/unknown/target tùy chỉnh bằng color input; có clamp cho font, opacity và line width. Config cũ được bổ sung defaults, không tự bật master ESP.

Không vẽ HP, shield, ammo hay armor giả cho đối thủ. Marker là ký hiệu màn hình, **không phải hitbox chính xác**. Equipped weapon là type string đã có trong net state, không phải inventory đầy đủ.

### Tên và cleanup

[Player update đặt native nameText](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/player.ts#L851-L857). Script đọc text game đã đặt, không lấy tên đầy đủ khác từ playerInfo hay gọi getter lạ. Đã đọc package `@pixi/text@7.4.3` từ npm: Text lưu own `_text`, còn `.text` là accessor. Đây là đối chiếu dependency public, không chứng minh live dùng đúng artifact npm đó.

Tên/weapon label được loại control/bidi characters và giới hạn độ dài; canvas không dùng innerHTML. Không gọi setter PIXI TextStyle hay đổi style mỗi frame. Khi canvas tự vẽ tên, native nametag của entity được chọn được ẩn bằng reversible override để tránh text trùng. Khi filter, tắt ESP, chuyển match, Stop hoặc lỗi render, restore **giá trị mới nhất game đã ghi**, không snapshot cũ.

Bộ lọc áp dụng cho overlay/script overrides. Nametag/UI đồng đội vốn do game hiển thị vẫn được trả về hành vi gốc khi không được script chọn; filter không phải công cụ xóa toàn bộ UI gốc của game.

### Giới hạn công việc render

- Giữ overlay tối đa 30 Hz; không thêm blur, glow, animation, webfont, ảnh hay thư viện UI.
- Tối đa 256 player entries mỗi frame ESP; cache text measurement tối đa 256 keys, reset khi đổi match/dispose.
- Label thử bốn vị trí, clamp trong viewport và tránh rectangle đã dùng. Không đủ chỗ thì bỏ label, vẫn giữ marker/line nếu bật. Không bảo đảm mọi label đều xuất hiện trong cụm đông.
- Canvas dùng CSS coordinates, backing buffer theo DPR nhưng cap 2×. Không làm sai world-to-screen do nhân DPR hai lần.
- Save/restore Canvas2D state, kể cả khi render throw. Canvas2D thiếu không dừng input features; diagnostics báo `no-canvas`. Diagnostics chỉ xuất counter tổng hợp, không đưa model rows, tên hay vị trí vào JSON.

Đây là budget/cache, **chưa phải benchmark FPS hoặc cam kết không lag**.

## Kiểm tra

```sh
npm run check
# 79/79 offline tests + rebuild + syntax check

npm run check:upstream -- /path/to/survev-checkout
# 4 source-method scenarios; HEAD phải là commit 3edee7e8...
```

20 tests thêm trong đợt này: phân biệt squad/faction, unknown/conflicting/team-zero/budget, team recompute, filter/layer/downed/range, target highlight, text safety, off-screen geometry, label collision, DPR, renderer state/cache/error, config/menu persistence, native-name restore, Canvas2D fallback và privacy/lifecycle counters.

Harness source-method còn kiểm tra ESP với PlayerBarn.recomputeTeamData thật: enemy rõ ràng, ally cùng team khác group và unknown chưa có membership; aim không chọn ally/unknown. Cả dạng source thường lẫn esbuild minify + đổi tên m_* đều đạt. Đây vẫn không phải full Codefend pipeline, full Game.update/server hoặc live browser E2E.

## Phạm vi còn mở của “reborn hoàn toàn”

| Nhóm | Mốc hiện tại | Còn thiếu để gọi hoàn thiện |
|---|---|---|
| ESP / team / labels / lifecycle | Đã triển khai đợt này, tests đạt | Xác nhận live, visibility/layout thực tế và FPS |
| Aim / native nearby pickup / mobile Join | Giữ fixes 0.2.0, source-method checks đạt | Diagnostics/xác nhận live từ người dùng |
| Prediction / own cone | Base defs, chưa tính đầy đủ perk/recoil | Hợp đồng state và physics tốt hơn |
| Wallcheck | Conservative circle/AABB/height | AimLayer/stairwell/muzzle/penetration/ricochet |
| Grenade radius | Nominal radius preview | Fuse, landing/trajectory và occlusion thật |
| Layer Spoofer / Map Highlights / other flashlights | Chưa port, UI ghi rõ | Source contract và kiểm thử riêng, không gỡ nhãn pending để giả hoàn tất |

## Test lại ESP

1. Cài file 0.3.0 không minify, chỉ bật một bản script; vào trận rồi bật **Visuals → ESP / Teams → Enabled**.
2. Trong duo/squad/faction: kiểm tra màu đỏ/xanh/xám và nhãn SQUAD/ALLY; khác squad nhưng cùng phe phải vẫn xanh.
3. Thử tắt Show allies, Show unknown, Show downed; đổi màu; tắt ESP và kiểm tra nametag/UI gốc được phục hồi.
4. Chuyển tầng, zoom/resize và thử off-screen arrows; arrow không được giữ entity đã inactive/không còn trong pool active.
5. Nếu không đúng: Help → Copy diagnostics. Counter ESP và aim dùng chung semantics nhưng diagnostics không chứa tên/vị trí người chơi.
