# Survev source pass 2 — sửa theo render và server semantics

Ngày: 2026-11-12. Artifact: **compatibility preview 0.1.1**.

Đã fetch lại repo public; `FETCH_HEAD` vẫn là `3edee7e8bd07fda8a63905aab4c45b595b684a80`. Đây **không phải** xác nhận commit đang deploy trên survev.io. Không truy cập game live, không chạy trận hay benchmark FPS.

## Những chỗ đã sửa

### 1. ESP theo vị trí render, không trộn với tracking

Player copy vị trí mạng vào `m_pos`, nhưng nội suy thành `m_visualPos`; `render()` project `m_visualPos` rồi đặt `container.position`:

- [Player update/interpolation](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/player.ts#L790-L822)
- [Player render](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/player.ts#L1328-L1336)

Implementation mới nhận diện AST luồng `camera.<projection>(this.<vector>)` → `container.position.set(screen.x, screen.y)`. Không chọn vector đầu tiên hay gọi thử render. Đường ESP dùng vector này khi contract rõ ràng; thiếu/ambiguous thì fallback vị trí mạng. Tracker/prediction vẫn dùng vị trí mạng, không tính vận tốc từ sprite nội suy. Diagnostics có `interpolatedOverlay` cho biết mapping có nhận diện được luồng này không.

Giới hạn: vẫn cần anchor `render`, `container.position.set`, dạng call/biến phù hợp và phép chiếu camera đã nhận diện. Đây là structural matching giới hạn, không phải phân tích data-flow/control-flow đầy đủ qua mọi scope hoặc kiểu minify. Chưa xác nhận pixel alignment live.

### 2. Wallcheck bỏ vật cản thấp theo ngưỡng đã khảo sát

- [GameConfig bullet.height = 0.25](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/shared/gameConfig.ts#L308-L312)
- [Bullet bỏ obstacle thấp khi tạo collision path](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/objects/bullet.ts#L293-L307)
- [Muzzle clipping, layer và ngoại lệ stairwell](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/weaponManager.ts#L750-L810)

Wallcheck chỉ bỏ obstacle `height < 0.25` sau khi quan sát Join protocol **1028**. Height/layer thiếu hoặc không hợp lệ vẫn xử lý bảo thủ. Không biến bài kiểm tra segment tâm-player thành mô phỏng đạn đầy đủ: chưa dựng muzzle offset, aimLayer trên cầu thang, destructibility/penetration, ricochet hay special bullet effects.

### 3. Vòng bán kính nổ không nhận nhầm loot / object đã free

- [Enum ObjectType: Projectile = 9, Loot = 3](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/shared/net/objectSerializeFns.ts#L5-L19)
- [Projectile fields và dữ liệu update](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/projectile.ts#L28-L117)
- [Server smoke special-case và explosion raycasts](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/objects/explosion.ts#L48-L137)

Chỉ nhận entity `__type === 9`, `active === true`, cùng layer, có throwable/explosion defs hợp lệ và radius hữu hạn dương. Gate protocol 1028 được áp dụng cả ở helper lẫn capability UI; bỏ riêng `explosion_smoke` theo nhánh server thay vì regex tên throwable.

Đổi nhãn thành **Nominal Explosion Radius**: vòng ở vị trí mạng hiện tại, dùng `rad.max` trong defs. Không phải landing prediction, fuse countdown, vùng chắc chắn gây damage hoặc ranh giới an toàn; damage thực tế còn raycast/occlusion, shrapnel và các luật server. Không lấy `projectile.rad` làm blast radius vì client dùng nó như radius nhỏ cho visual collision.

### 4. Mobile loot có cả auto-open doors

[Server mobile interaction](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/objects/player.ts#L2025-L2101) có điều kiện alive/not downed/drop ticker, xét loại loot, capacity/gear quality/perk và mở cửa đóng. Nhãn UI nay nói rõ **loot / doors on next join**. Không hứa nhặt mọi item hoặc hoạt động như một field `autoLoot` độc lập.

## Những gì source cho thấy nhưng chưa giả lập thêm

[Weapon spread/perks](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/weaponManager.ts#L845-L884): movement/recoil ảnh hưởng spread; bonus_9mm/high_velocity/bonus_assault đổi speed/range, còn bonus_45 có nhánh ngẫu nhiên. Prediction và own-cone hiện vẫn dùng base bullet/gun defs, không có hợp đồng đã xác nhận để đọc đầy đủ perk/recoil state live. Không thêm multiplier đoán mò; không gọi cone là spread thực tế. Grenade trajectory vẫn chưa port.

## Kiểm tra

`npm run check`: **43/43 offline tests pass**, kèm build lại bundle và `node --check` artifact. Bảy regression tests mới bao phủ render-position matching (không thực thi, có decoy/ambiguity), fallback, đường ESP vs tracker, grenade filtering/protocol gate và wall-height threshold. Tests dùng fixtures giả; không phải capture từ live, không phải kiểm thử toàn bộ physics/game integration.
