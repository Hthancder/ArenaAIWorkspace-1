# Hotfix 0.5.0-preview.2 — ESP, vị trí hỗ trợ ngắm và aim bị khóa

**Báo lỗi người dùng:** ESP không hoạt động, mục Aim Assist sai vị trí, aimbot không hoạt động.
**Ngày:** 2026-11-12. **Không có capture/diagnostics từ runtime của người dùng**, vì vậy các lỗi tái hiện dưới đây là nguyên nhân đã chứng minh trong implementation, không khẳng định đây là toàn bộ nguyên nhân của báo lỗi live.

## Các lỗi tái hiện và sửa

### 1. Scheduler aim không chịu được dạng minify phổ biến

Code cũ chỉ tìm `timer < 0` bên trong AST `IfStatement`. Minifier có thể biến native scheduling thành:

```js
this.timer -= dt;
(diff || this.timer < 0) && (this.send(), this.timer = 1, this.prev = msg);
```

Test chạy esbuild thực sự tạo dạng này: adapter cũ trả `null`, làm capability Aim bị khóa. Adapter mới đọc binary comparison độc lập statement, hỗ trợ `0 > timer` và `timer = timer - dt`; vẫn yêu cầu cùng field có decrement/reset và từ chối ambiguity. Không đoán field theo giá trị hiện tại, không tự mở socket hoặc bỏ protocol guard.

### 2. ESP có master switch legacy không còn control

`NativeNames.sync` yêu cầu cả `esp` lẫn `nametags`. Saved config `nametags=false` làm bật ESP trong menu vẫn không đổi tên, nhưng menu đã bỏ checkbox nametags nên không sửa được qua UI.

- `esp` nay là master switch duy nhất của native names; migration bỏ hiệu lực cờ nametags cũ.
- Native names không còn phụ thuộc camera/weapon/aim schema: chỉ cần roster, active player và native text contract. Capability `names` riêng với overlay `visuals`.
- Unknown giữ native, blue/red không đổi; không tạo Canvas labels/HUD.
- Thêm counts/state của overrides thực sự áp dụng, không lấy `EspRenderer.drawn` làm bằng chứng tên đã hiện.

Đã kiểm tra lại public source: client dùng `pixi.js-legacy ^7.4.3`; DisplayObject7.4.3 khởi tạo `visible` là own writable field, Text có inherited `style` getter với own `_style`, TextStyle chuẩn hóa số65535 thành chuỗi `#00ffff`. Không tự quy nguyên nhân cho inherited visibility khi source không có bằng chứng.

### 3. Optional prediction làm khóa direct aim

Code cũ fail ngay khi thiếu weapon profile hoặc snapshot adapter, ngay cả khi actual gun slot và vị trí mục tiêu đã có.

- Profile có, thiếu prediction contract/history ban đầu: dùng direct solve vào vị trí hiện có, state `direct-prediction-unavailable` / `direct-awaiting-snapshot`.
- Definitions chưa capture nhưng actual local weapon slot0/1 đã xác minh: direct center aim, state `direct-missing-definitions`, approximate=true. Không bịa speed, range, muzzle hoặc future velocity.
- Unknown slot, known melee/throwable không bị giả thành gun. Protocol/activation/team/layer/wallcheck/death/spectator guards vẫn giữ.
- History đã có nhưng stale vẫn bị từ chối, không âm thầm thay stale prediction bằng mục tiêu cũ.
- Nếu wallcheck được lưu bật nhưng contract thiếu, checkbox cũ disabled khiến người dùng không tắt được. Nay cho **tắt** trạng thái đang bật, không cho bật lại nếu contract vẫn thiếu; không tự bypass wallcheck.

Đây không phải sửa chất lượng prediction/P3; solver và benchmark movement-general trước đó không đổi.

### 4. Menu/focus và vị trí hỗ trợ ngắm

- Assist strength / Lock smooth ở Main theo mode; chuyển FOV circle và predicted dot từ Visuals về **Main → Aim — Hỗ trợ ngắm**.
- Visuals giữ names/lines/X-Ray/Zoom/previews; không để nhóm Aim helpers lẫn ở đó.
- Menu key có thể đóng chính slider/select của userscript đang focus, thay vì bị generic typing guard nuốt. Khi đóng, blur control để không giữ gameplay trong trạng thái typing/menu-open.
- Không cho menu key chạy xuyên native chat/text input ngoài userscript; key capture vẫn có ưu tiên riêng.
- Status ngắn trong menu: lý do Aim dừng cụ thể, prediction state và ESP applied count. Không thêm HUD ngoài game.

## Kiểm chứng

```sh
npm ci
npm run check
npm run check:upstream -- .cache/survev
git diff --check
git diff --quiet HEAD -- references/duality-client.reference.js
```

Kết quả: **129/129 tests**, **4/4 expanded source-method scenarios**, readable build/syntax và whitespace pass; original reference không đổi.

Regression tests mới bao gồm:

- Scheduler logical/comma do esbuild minify thật và reversed comparison; vẫn fail closed khi ambiguous.
- Legacy nametags=false, ESP không cần aim/camera schema, diagnostics applied count.
- **PIXI7 Container và TextStyle thật**, inherited style API, native visibility writes, không tái tạo style mỗi tick và restore đúng normalized fill. Dependencies PIXI chỉ ở dev/tests, không vào userscript bundle.
- Direct outgoing aim khi thiếu prediction/definitions, giữ movement/Fire/native input, không giả gun khi actual throwable/unknown protocol.
- Chọn Assist slider → đóng bằng menu key → outgoing aim trở lại; Main/Visuals layout và tắt wallcheck đang thiếu contract.

Source runner còn trích chạy **createPlayerNameText thật từ source client**, dùng Container/TextStyle thật và Text shell không GPU: xác nhận enemy red/ally blue/unknown cyan, native visibility bị rewrite không làm mất ESP, text giữ nguyên và disable restore. Trong cùng 4 scenario có direct fallback thực sự qua native InputMsg/BitStream khi definitions bị gỡ. Các test native diff/timeout/prevInput/Lock/Assist/zoom/restore, smoke và server melee vẫn pass.

**Không phải live E2E:** không khởi động renderer WebGL/toàn game/server. Nếu hotfix vẫn không chạy trong trận, status/diagnostics mới là bằng chứng cần lấy tiếp; không kết luận “đã hoạt động live” chỉ vì các test trên pass. P3 prediction acceptance trong SPEC vẫn mở.

## File cài

[`userscripts/duality-reborn.user.js`](../userscripts/duality-reborn.user.js), metadata **0.5.0-preview.2**. Tắt bản cũ, thay toàn bộ artifact rồi reload với script ở document-start; không chỉ Retry trên trang đã lỡ Join/bootstrap.

## Nguồn đã đọc lại

- [Client dependencies ở pin](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/package.json)
- [Native name factory và update visibility](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/player.ts)
- [Game native input/diff/scheduler](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/game.ts)
- Registry npm packages `@pixi/display@7.4.3`, `@pixi/text@7.4.3`: DisplayObject constructor, Text.style/_style và TextStyle.fill implementation được đọc và dùng trong test.
