# Duality Client Reborn — 0.5.0-preview.6

Userscript readable cho survev.io, menu DOM nhẹ, source-backed adapters và cleanup có ownership. **Đã kiểm thử offline/source-method; chưa xác nhận trong gameplay live.** Không bảo đảm tương thích mọi update, tránh phát hiện hoặc bắn trúng. Dùng trên máy chủ công cộng có thể vi phạm điều khoản game.

## Hotfix theo diagnostics Lock vẫn không tác động

Bản **0.5.0-preview.6** thêm **Human-like aim** thành toggle riêng mặc định tắt: Lock mặc định không bị giới hạn/làm chậm như mô phỏng người; prediction được giữ cho vị trí tương lai thay vì “đạn bám vào địch rồi trượt”. Giữ direct native mouse hook từ preview.5. Bản **0.5.0-preview.4** sửa ambiguity đã thấy trong diagnostics preview.3: khi Fire, `wallcheck-unavailable`, `ambiguous-native-id-table`, không có native input correction. Discovery mới dùng data flow `delObjIds` trong actual snapshot receiver để phân biệt world-object registry với các get/delete dictionary khác; deduplicate owner aliases. Không tắt Wallcheck, không chọn table đầu tiên, không giả xoay súng thay cho input.

Giữ bounded live evidence sau chết/mở Help, thêm số native/receiver candidates. Source integration có hai native get/delete tables và alias thật, Wallcheck bật, kiểm tra vật cản chặn rồi native serialized correction khi bỏ vật cản. [Hotfix registry preview.4](docs/hotfix-0.5.0-preview.4.vi.md) · [Direct mouse](docs/direct-native-mouse-0.5.0-preview.5.vi.md) · [Human-like aim / lead preview.6](docs/human-like-aim-lead-0.5.0-preview.6.vi.md). **Chưa xác nhận trên phiên live người dùng**; direct input có thể làm native gun/player rotation phản ánh correction hơn trước, competing table cụ thể trong live chưa được xác định từ JSON.

Bản preview.3 trước đó thêm broadphase wall/muzzle và `aimEvidence`; [phân tích cũ](docs/hotfix-0.5.0-preview.3.vi.md) là lịch sử, không phải bằng chứng đã sửa ambiguity.

## Hotfix trước đó sau báo lỗi ESP/aim

Bản `0.5.0-preview.2` sửa những đường lỗi đã tái hiện: scheduler bị minify thành `&&`, cờ legacy `nametags=false` còn chặn ESP nhưng không có control, names bị phụ thuộc aim/camera schema, và prediction optional khóa cả direct aim. **Đây chưa phải xác nhận đã giải quyết đúng mọi nguyên nhân trên máy người dùng.** [Chi tiết hotfix và kiểm chứng](docs/hotfix-0.5.0-preview.2.vi.md).

- Toàn bộ hỗ trợ ngắm (Assist strength, FOV circle, predicted dot) ở **Main**, không nằm trong Visuals.
- **Visuals → Player names → ESP — Native names** là switch duy nhất cho tên; không cần bật lines hoặc prediction.
- Status trong menu phân biệt lý do aim bị chặn, prediction fallback và số tên thực sự được đổi màu. Không thêm HUD ngoài game.

## File để cài

**[`userscripts/duality-reborn.user.js`](userscripts/duality-reborn.user.js)** — bundle độc lập, không minify; không cần npm hoặc CDN trên máy người dùng.

1. Tắt script Duality/Neko cũ để không tranh hook.
2. Dán toàn bộ `.user.js` vào Tampermonkey/Violentmonkey. Chạy ở **page/main world**, **document-start**; metadata gồm `@sandbox raw` và `@inject-into page`.
3. Reload survev.io; **Right Shift** mở/đóng menu. Gameplay features mặc định tắt.
4. Chọn mode/feature trong trận. Control bị khóa nghĩa là chưa đủ contract, không phải đã hoạt động.
5. **Help → Copy diagnostics** khi cần; diagnostics không xuất token Join, tên/vị trí người chơi hoặc object game. Nếu không có menu, tìm boot log `[Duality Reborn 0.5.0-preview.6]` và lỗi Console đầu tiên.

**Retry capture:** bắt lại Application trong 15 giây; nếu lỡ bootstrap item DB/Join thì cần reload. **Stop / cleanup:** gỡ hooks/overrides do bản này sở hữu, yêu cầu lượt input native để trả hướng nếu còn session; không phát network ngoài native. Reload để chạy lại sau Stop.

## Thay đổi chính

### Aim — Main

- **Off / Aim Assist / Aim Lock** độc quyền. Activation riêng: Fire, giữ aim key hoặc cả hai. Trong activation Fire, phím B giữ/toggle bật aim theo cấu hình Keybinds.
- **Assist strength 0%:** không sửa hướng. Tăng strength tăng lượng correction theo intent native; không có memory kéo ngược khi người dùng thoát FOV.
- **Lock:** mặc định chọn/kéo đến điểm lead ngay; không còn “Human-like aim” mặc định làm trễ. Human-like aim là toggle riêng, chỉ làm Lock mượt/chậm khi bật. Assist strength quyết định lực kéo của Aim Assist; 100% là gần Lock.
- FOV là bán kính **input pixels**, dùng intent chưa sửa; sticky có biên hysteresis. Unknown/allies không thành target.
- **Direct native mouse input** mặc định bật: trong một frame, script ghi vector native tạm thời theo cùng aim plan để Game/Player update đọc được; restore trước native flush, menu/blur/hidden, config change và Stop. FOV/selection vẫn dùng intent vật lý chưa sửa; không tạo DOM mouse event, không warp OS cursor, không thay Fire/movement. Native sender vẫn là lớp sửa cuối và giữ physical Fire/movement. Nếu không có `flush` contract, native mouse không bị khóa; sender correction vẫn chạy.
- Sender dùng cùng plan của frame nếu direct route đã chạy, tránh Lock tiến hai lần và tránh lệch giữa gun animation/hướng thật. Khi zoom native đổi trước thời điểm tạo InputMsg, sender vẫn có quyền cuối trên world direction và clone giữ prototype/prevInput. AimEvidence là forward evidence, không phải server ACK.
- Predict Auto lấy full/partial snapshots đã apply, không lấy render frames làm observation. Thiếu optional prediction contract thì direct aim dùng vị trí hiện có với trạng thái rõ ràng; thiếu definitions chỉ cho direct fallback khi đã xác minh actual gun slot0/1. Không tự đoán bullet speed hoặc weapon type. Bounded weighted fit, reset identity/layer/gap, xử lý packet bunching. Không fit riêng zigzag hoặc biết trước movement.
- Profile từ actual equipped gun/bullet/perks; effective speed/variance, range margin, muzzle/clipping, stair aim-layer và toMouseHit. Dual offhand/random spread/empowered effects không được giả là biết trước.
- Prediction Auto dùng snapshot/weapon defs, tắt được bằng Predict. Lead adjustment mặc định 100%, tối đa 200%; latency Auto dùng RTT/2 heuristic có giới hạn. Slope uncertainty cao dùng trạng thái **`reduced-lead-uncertainty`**; stale snapshot đã quan sát nhưng stale nhường native input. Không cắt flight time vật lý thành trust horizon.

### ESP — Visuals

**Player names → Enable team-colored names:** tên native đồng đội **blue**, địch **red**; unknown giữ native. Sửa TextStyle.fill, không nhân tint đỏ lên cyan. Giữ nội dung/font/position tên; restore fill/visibility theo ownership.

**Không còn** HUD góc trái, legend/counts, SQUAD/ALLY/ENEMY prefixes, label boxes, weapon/distance tags hoặc target-name màu vàng, kể cả config legacy. **Player lines** độc lập, default off; predicted dot default off. Không cần Canvas2D để đổi màu tên.

### Phối hợp feature

| Feature | Phạm vi / authority |
|---|---|
| Aim | Direction; toMouseLen chỉ khi gun.toMouseHit; không sửa Fire/movement/equip |
| Semi | Held single-fire + non-auto melee; không sửa current/old physical input; auto/burst dùng native hold |
| Switch / Use One Gun | Ammo/actual slot; một equip request, chờ confirmation; không reset cooldown server |
| Melee / Auto Melee | Giành aim/movement/equip trong reach; hủy pending Switch; manual equip thắng, không tranh lại trong cùng Fire hold |
| Mobile Movement | Một vector output; nhả phím dừng; melee movement thắng, không cộng vector |
| Loot | Native Loot supplies + backoff; mobile loot/doors cần Join mới; không giả inventory acknowledgment |
| Layer Spoofer | Local render preview; gameplay aim/wallcheck/loot dùng layer chưa override |
| ESP / X-Ray / Zoom / Map | Overrides riêng; đổi setting không clear toàn bộ; Canvas lỗi không gỡ names/zoom hoặc chặn input |

X-Ray giữ smoke alpha legacy (`50 → 0.05` mỗi particle), darker smoke/ceiling/vegetation. Map Highlights clone native minimap shapes. Flashlights/bullet/throw/grenade previews chỉ là ước lượng, không phải collision/hit/fuse guarantee. Zoom bounded 1–3×. Full feature set trước đó vẫn có implementation; xem [lịch sử 0.4.0](docs/reborn-0.4.0.vi.md).

## Bằng chứng và giới hạn

- **148 tests offline**: controller/solver/tracker, adapters, ownership, migration/menu, phối hợp input, lifecycle, smoke/melee/map và các regression cũ đã chuyển sang semantics mới.
- **4 source-method scenarios**: bản thường/minify + đổi tên `m_*` × 2 loot mode; chạy actual source snapshot receiver, native input expressions/normalization/diff/prevInput/timeout/send, InputMsg serialize/deserialize bằng BitStream và normalize hướng như server. Có stationary-cursor moving-target, direct native mouse restore/localRotation/updateRotation, post-pre zoom, Lock convergence, Assist strength/no-extra-send, missing-definitions direct wire fallback và native name factory với PIXI7 Container/TextStyle thật; smoke update, server melee cooldown và minimap vẫn chạy.
- **[Benchmark đa chuyển động](docs/aim-benchmark.vi.md)**: 12 nhóm × 3 held-out seeds × render 30/60/144Hz × regular/jitter-gap snapshots; so legacy-render, no-predict, simple CV. Có median/p95 miss, collider miss, overshoot, recovery proxy, fallback và solver CPU. **Không phải gameplay hitrate hoặc FPS.**
- Benchmark mới cải thiện straight/diagonal/curve/speed-change, không thắng mọi metric: median start-stop và một số p95 đảo hướng vẫn kém legacy. Không tuyên bố đã nghiệm thu toàn bộ yêu cầu prediction; chi tiết và phần còn mở trong [báo cáo triển khai](docs/reborn-0.5.0.vi.md) và [SPEC](docs/implementation-spec-aim-esp.vi.md).

Source pin: [`survev/survev@3edee7e8bd07fda8a63905aab4c45b595b684a80`](https://github.com/survev/survev/tree/3edee7e8bd07fda8a63905aab4c45b595b684a80), protocol **1028**. AST discovery chịu một số rename/field changes nhưng không bất biến với mọi inline/obfuscation/rewrite. Thiếu contract liên quan thì fail closed và có diagnostics. Không dùng chênh lệch HEAD/live làm lý do hoãn source-backed fixes.

Item capture/Join phải được quan sát; unknown protocol không được tự nới gate. Bootstrap dùng hai global hooks tạm thời có timeout (`.call`, `Object.keys`); không tuyên bố zero overhead. Runtime không tải payload/version gate/telemetry ngoài. `references/duality-client.reference.js` **giữ nguyên**, không import/execute trong build.

## Phát triển

Node.js 22:

```sh
npm ci
npm run check
npm run check:upstream -- /path/to/survev-checkout
npm run benchmark:aim              # in report ra stdout
npm run benchmark:aim -- --write    # ghi docs/aim-benchmark.vi.md
```

`pretest` build lại artifact readable. Source runner yêu cầu checkout đúng pin; không vendor source upstream vào repo. Collaborators/assets/sockets được thay bằng fixtures inert; không gọi đây là full-game/live E2E.

- `src/core.mjs`: safe traversal, AST roles, bootstrap, math, historical Tracker giữ cho baseline.
- `src/aim.mjs`, `aim-adapters.mjs`, `aim-geometry.mjs`: observations, timing, controller, interception, source geometry.
- `src/native-names.mjs`, `esp.mjs`: reversible native names và optional lines; không vẽ labels/HUD.
- `src/mouse-input.mjs`: direct native `mousePos` frame transaction, raw physical intent separation và ownership restore.
- `src/features.mjs`: lifecycle, sender coordinator, feature arbitration/overrides.
- `src/effects.mjs`, `repeat-fire.mjs`, `weapon-switch.mjs`, `map-highlights.mjs`, `previews.mjs`: features phụ và state machines.
- `src/menu.mjs`, `main.mjs`: menu/config/controller; `scripts/build.mjs`: readable bundle.
- `docs/implementation-spec-aim-esp.vi.md`: spec và tiến độ; `docs/reborn-0.5.0.vi.md`: evidence/giới hạn hiện tại.

Parser Acorn dùng MIT; license được nhúng vào artifact.
