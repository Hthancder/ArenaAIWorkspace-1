# 0.5.0-preview.3 — diagnostics Lock và native object registry

Ngày2026-11-12. Phản hồi: **Aim Lock vẫn theo chuột, không tác động**; user cung cấp diagnostics bản preview.2.

## Kết luận từ JSON thực, không suy quá dữ liệu

- Capture thành công, initialized=true, protocol1028 khớp. Sender, scheduler, snapshot receiver, schema, definitions và local data đều true; không phải bằng chứng thiếu bootstrap/protocol.
- Snapshot được copy khi `inputBlockReason=dead`, `aimState=dead`, rejections rỗng. Đây là trạng thái lúc copy, **không giải thích được aim khi còn sống**. Không lấy trạng thái chết để phủ nhận báo lỗi của người dùng.
- `capabilities.wallcheck=false`, grenadeZones=false trong khi definitions/protocol/visuals đều true. Theo code, đây chỉ ra object creator/registry discovery thiếu hoặc ambiguous. Registry check chưa có trong `checks`, nên `missingContracts=[]` trước đó gây hiểu lầm.
- Nếu setting Wallcheck bật, `processAim` fail với `wallcheck-unavailable` trước khi chọn target, dù capability aim=true. DEFAULTS bật Wallcheck. Tuy nhiên JSON cũ không chứa config đã chọn nên **chưa chứng minh người dùng thực tế đang bật Wallcheck**.
- `nativeNames.eligible=0`, ESP culled3 là trạng thái sau chết; không đủ kết luận team mapping sai khi đang chơi. `featureMs=20.4` là một mẫu visual work, không phải FPS hay bằng chứng duy nhất cho giật.

## Sửa có source/data-flow thực

### Registry

Discovery cũ chọn game child chứa dictionary có `__id/__type`. Hai dictionary cùng có entity là đủ gây ambiguity và khóa wallcheck.

`discoverObjectRegistry` mới ưu tiên role thật trong `client/src/objects/objectPool.ts` tại pin3edee7e8:

- get-by-ID trả `this.table[id]`;
- delete-by-ID thực hiện `delete this.table[id]` trên **cùng table**;
- không gọi các methods để dò; đọc AST, chịu đổi tên `m_*`/minify;
- một candidate semantic thì dùng, nhiều candidate semantic vẫn fail closed;
- thiếu anchors giữ fallback shape cũ nhưng trả state rõ: missing/ambiguous/fallback/native.

Nhận diện được table rỗng theo native semantics, không đoán từ thứ tự Object.keys hay số lượng object. Diagnostics thêm `checks.objectRegistry` và `registry.state`; không xuất table/game references.

### Không để vật thể xa khóa toàn bộ aim

Code cũ trả blocked nếu toàn bộ obstacle list>1024, và muzzle clipping chỉ lấy1024 phần tử đầu. Khi registry phục hồi, map lớn có thể vẫn làm tất cả aim bị chặn hoặc bỏ qua muzzle obstacle nằm sau slice.

Broadphase circle/AABB lọc bằng segment bounding box và vùng probe muzzle trước khi tính narrow-phase budget. Unknown/invalid collider vẫn giữ để fail closed; không tự cho bắn xuyên. Không tắt Wallcheck tự động. Obstacle collection được share giữa solver và wallcheck trong cùng lượt tính, không rescan registry cho từng candidate. Coarse list filtering vẫn có cost theo số map objects; đây không phải tuyên bố đã có full spatial index hoặc measured FPS improvement.

## Evidence còn giữ sau chết/mở Help

Module `AimEvidence` lưu bounded local evidence:

- `lastLiveAttempt`: state, mode/activation, Wallcheck requested/available, prediction requested và rejection **counts** khi đủ lifecycle/input guards. Death/menu/typing không ghi đè.
- `lastGameplayForward`: native sender forward gần nhất lúc còn điều khiển, aimApplied, correctionDegrees tương đối giữa native/outgoing, Fire/movement flags preservation.
- `lastCorrection`: lần native forward có correction thực khác>0.01°; giữ sau chết hoặc packet restore.
- Tổng số native input forwards/corrections và scheduler requests; tối đa12 state transitions. Có ageMs, reset khi Join/game instance mới.
- `aimControls`: mode/activation và các yêu cầu Wallcheck/Prediction hiện tại.

**Không lưu raw packet/vector/position/player ID/name/token**, không telemetry ra ngoài. Correction được đo ở native sender boundary trước quantization; **không phải ACK, server-accepted direction hoặc proof of hit**. Các source scenarios riêng kiểm tra serializer/deserialize roundtrip, không đánh tráo hai loại bằng chứng.

Menu status phân biệt current state và last-live state. Không tạo HUD/label ngoài game.

## Kiểm chứng

- `npm run check`: **135/135 tests pass**.
- `npm run check:upstream -- .cache/survev`: **4/4 expanded scenarios pass**, pin3edee7e8, thường và minify+rename ×2loot modes.
- Source runner dùng **Creator.m_getObjById/m_deleteObj/m_updateObjPart thật**, thêm entity-shaped decoy gây ambiguity cho thuật toán cũ. Default Wallcheck bật vẫn nhận registry native, có obstacle thì từ chối, bỏ obstacle thì outgoing Lock direction đi qua actual native InputMsg/BitStream.
- Regression: semantic table rỗng/rename/ambiguity, getter safety, state history bounded/immutable/private, live Lock→death vẫn giữ correction và live wallcheck failure.
- Regression>1100 far obstacles không tiêu hết budget; near obstacle đặt sau phần tử1024 vẫn chặn.
- Readable build/syntax và `git diff --check` pass. Reference gốc không đổi.

## Chưa kết luận/sửa trong bản này

- Chưa có native sender evidence **từ máy người dùng lúc còn sống**. Không tuyên bố đã biết nguyên nhân duy nhất hoặc Lock live đã được sửa hoàn toàn.
- Không xoay model súng để giả làm Lock; không thay controller/smoothing hay thêm anti-snap ngẫu nhiên. Cần đường input hoạt động được xác minh trước khi nghiệm thu độ mượt.
- Prediction P3 quality vẫn mở như SPEC; không chạy lại/tune benchmark solver vì solver/controller không đổi.

## Cách kiểm tra tiếp

Thay `.user.js` version**0.5.0-preview.3**, reload ở document-start. Trong trận đang sống, bật Lock và activation đúng, có known enemy trong FOV; sau thử có thể copy diagnostics kể cả đã chết. Chỉ cần xem `aimControls`, `registry` và `aimEvidence` thay vì cố copy JSON ngay trong lúc giữ Fire.

Với preview.2, người dùng có thể chủ động tắt Wallcheck để kiểm tra nhánh chặn đã nêu; script không tự tắt setting đó. Nếu preview.3 vẫn lỗi, history sẽ phân biệt `wallcheck-unavailable`, `waiting-activation`, `no-candidate`/rejections, không tới native sender hoặc đã có correction — thay vì tất cả bị che bởi `dead`.

File cài: [`userscripts/duality-reborn.user.js`](../userscripts/duality-reborn.user.js).
