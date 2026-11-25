# X-Ray & ESP — đối chiếu mã nguồn mới nhất, 0.5.0-preview.8

Ngày 2026-11-24. Phân tích & sửa đổi dựa trên clone mới nhất `.cache/survev-latest` @ `08346fb6` (2026-11-23). Diff gameplay so với pin hiện tại (`3edee7e8`) gần như nil — chỉ `shared/defs/maps/cobaltDefs.ts` đổi 1 dòng — nên audit này áp dụng được cho cả hai bản.

## 1. X-Ray: vì sao object hoạt động object không

### Source truth (latest)

- `shared/defs/mapObjects/obstacles/obstacleDefs.ts`: mọi obstacle def đều có thể mang cờ `isTree?` / `isBush?` (boolean, đã kiểm chứng).
- `shared/defs/mapObjects/obstacles/mapObstacleDefs.ts`: `createBush` đặt `isBush: true`; toàn bộ bush là `bush_*` **trừ hai type `brush_01sv` và `brush_02sv`** (cùng `createBush`, cũng `isBush: true`). `createTree` đặt `isTree: true` cho mọi `tree_*` và `tree_interior_*`.
- `client/src/objects/obstacle.ts`: client `Obstacle` **chỉ copy `isBush`** (`this.isBush = !!def.isBush`), không có field `isTree`; không cull theo khoảng cách trong update pool/map.
- Ceilings nằm trong `Building.imgs[i].isCeiling` (SPA: `m_buildingPool`), không phải def của obstacle.

### Lỗi cũ

Phân loại fade trong `scanEffects()` và `post()` dùng regex `^(tree|bush|table|stairs)[_-]` → **bỏ sót `brush_01sv`, `brush_02sv`** (bụi thường thấy ngoài bờ biển map mới) và mọi vegetation type tương lai không khớp tiền tố. Đây chính là "có object hoạt động, có object không".

### Sửa đổi (source-honest)

`src/xray.mjs` (mới) — `fadeObjectKind(type, definitions)`:

1. Nếu đã capture được merged `ObstacleDefs` registry (đã có sẵn qua `captureDefinitions(..., onMapDefs)`, expose là `engine.mapDefinitions`, heuristic `tree_01`/`stone_01`):
   - có def cho `type` → **def là chuẩn**: `isBush === true || isTree === true` → `vegetation`; không có cờ → không fade (kể cả type khớp regex);
   - không có def cho `type` (registry cũ hoặc map lạ) → fallback regex.
2. Không có registry → fallback regex mới: `^(tree|bush|brush)[_-]` → `vegetation`; `^(table|stairs)[_-]` → `furniture`.

`src/features.mjs`: `scanEffects()` dùng helper này (vẫn cap 2048 entries/mảng, depth 4, budget 12000, rescan 500ms); `post()` không còn regex trùng lặp. Áp alpha `min(raw, treeOpacity/100)` như cũ; ceilings và smoke không đổi đường đi; toggle `xray`/`ceilings`/`treeOpacity` giữ nguyên ngữ nghĩa và ownership cleanup.

### Giới hạn đã biết (cố ý không làm thêm)

- `table_*`/`stairs_*` không có def flag tương ứng (`category: "furniture"` / không category, chỉ `zIdx`/`collision` khác) → giữ regex như cũ; `table_06..09` (control panels) fade như tên gọi furniture, đúng hành vi trước đây.
- `smallest trees` của Map Highlights giữ nguyên `^tree[_-]` (minimap, ngoài scope báo lỗi X-Ray).
- Không có loot/container/peek mới nào được đưa vào fade; không fake "thấy xuyên tường" ngoài sprite fade.

## 2. ESP: "phải gần mới phát hiện" — sự thật từ source

Bản này ESP = **native name recolor** (`NativeNames`, không có distance check) + **optional lines/overlay** (`buildEspFrame`). Cả hai chỉ nhìn vào `m.barn` — pool entity **đã được server gửi xuống**.

- Server `server/src/game/client.ts` (latest): chỉ replicate object trong `collider.createAabbExtents(player.pos, { width: zoom + 4, height: (zoom + 4) / (16 / 9) })`, tức nửa-extent `±(zoom+4)` ngang, `±(zoom+4)/(16/9)` dọc; entity rơi khỏi vùng → `delObjIds`. Không có nhánh interest radius nào khác trong source.
- `zoom` server lerp về `scopeZoomRadius[scope]` (desktop: 1x=28, 2x=36, 4x=48, 8x=68, **15x=104**; mobile: 32/40/48/64/88), bị kẹp xuống theo zoom region trong công trình và theo lowest zoom; **InputMsg không chứa trường zoom** → client không thể tự nới hợp pháp.
- Hậu quả đo được: đứng 1x → entity trong ~±32 × ±18; 15x scope → ~±108 × ±60.75; trong nhà → thu hẹp theo zoom region. ESP không thể vẽ player mà server chưa replicate — không có "ESP siêu xa" nào từ phía client ngoài việc chọn scope lớn hơn (vanilla) — và bản này không giả vờ điều đó.

### Sửa đổi thực tế

1. `espMaxDistance` mặc định **200 → 500** (đúng slider max) và fallback khi thiếu config trong `buildEspFrame` cũng 200 → 500: lines overlay không còn giới hạn nhân tạo phía client; ràng buộc thật là server interest area.
2. `espOffscreen` **vẫn khóa `false`** như quyết định ownership cũ (offscreen arrows/HUD đã bị xóa có chủ đích); không bật lại trá hình.
3. Menu: thêm hint (không phải setting) giải thích bound; hint cho X-Ray classification. Không thêm setting mới — đúng nguyên tắc "chỉ setting ảnh hưởng lớn".
4. Audit xác nhận names ESP vốn **không** bị distance cull — đã chạm bound tối đa mà replication cho phép.

### Cách dùng thực tế để thấy xa hơn (vanilla, hợp pháp)

- Giữ scope zoom lớn (8x/15x) khi cần soi xa; zoom vào bằng chuột phải như bình thường. ESP đi theo vùng server replicate.
- Ngoài công trình mới được lợi; trong nhà/tầng hầm range bị kẹp theo zoom region của building — không toggle nào đổi được.
- Nếu "gần mới thấy" vẫn còn sau khi scope 15x: kiểm tra `espSameLayerOnly` (mặc định tắt — player tầng khác vẫn hiện dashed), `espShowEnemies/Unknown`, và diagnostics (`stats.esp.culled/drawn`) để phân biệt "không replicate" với "bị lọc".

## 3. Kiểm chứng

- `npm run build` OK; `npm run check` → **153/153 PASS** (thêm `tests/xray-esp-audit.test.mjs`: unit `fadeObjectKind` (regex fallback brush_*/defs authoritative/def flagless thắng regex), engine-level brush_02sv + registry-driven `shrub_09`, ESP default/fallback 500 với player ở 250 units; `tests/esp.test.mjs` cập nhật 200→500).
- `node scripts/check-upstream.mjs .cache/survev` → **4/4 PASS** (pin `3edee7e8`, match cũ).
- Pin→latest gameplay diff ≈ nil (`cobaltDefs.ts` 1 dòng).
- **Chưa live-test**; không tuyên bố tránh phát hiện/anti-cheat. ESP xa hơn 15x-scope replication là không thể từ client.

## 4. Files thay đổi

- Mới: `src/xray.mjs`, `tests/xray-esp-audit.test.mjs`, doc này.
- Sửa: `src/features.mjs` (import + scan/post), `src/menu.mjs` (default 500, hint rows), `src/esp.mjs` (fallback 500), `tests/esp.test.mjs` (expectation), `README.md`, `userscripts/duality-reborn.user.js` (bundle tái build từ source).
