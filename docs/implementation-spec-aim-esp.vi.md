# SPEC TRIỂN KHAI — Aim, prediction, ESP tối giản và phối hợp feature

**Trạng thái:** ĐÃ CHỐT và ĐANG TRIỂN KHAI; đã có bản `0.5.0-preview.2` (hotfix sau báo lỗi live), chưa nghiệm thu toàn bộ P3/prediction. Xem tiến độ/bằng chứng ở §12 và `docs/reborn-0.5.0.vi.md`.
**Ngày ghi:** 2026-11-12.
**Baseline:** v0.4.0, commit `1431fec`.
**Branch phiên làm việc:** `arena/ee4a4f64-arenaaiworkspace-1`. Không tạo/chuyển branch khác.
**Mục đích:** tài liệu bền vững để tiếp tục triển khai sau khi context hội thoại bị rút gọn. Đọc file này trước khi sửa code; không coi một bản tóm tắt hội thoại là thay thế đầy đủ cho spec.

## 0. Chỉ dẫn cho người tiếp tục công việc

1. Kiểm tra `git status`, đọc spec và code hiện tại. Những mục dưới đây là yêu cầu, không phải mô tả tính năng đã làm.
2. User đã yêu cầu bắt đầu triển khai, sau đó yêu cầu dừng để ghi spec này trước. Trước lúc ghi, chỉ có đọc file; chưa có thay đổi gameplay từ lượt triển khai đó.
3. Giữ nguyên `references/duality-client.reference.js`; không import/thực thi nó trong build.
4. Lấy source public Survev làm cơ sở triển khai chính. Không dùng giả thuyết lệch build GitHub/live để trì hoãn sửa lỗi có bằng chứng.
5. Mỗi behavior cần có dữ liệu thật, điểm tích hợp thật và test thực thi phù hợp. Không thêm trạng thái/field không được client nhận rồi coi như có.
6. Không báo hoàn thành vì checkbox, chấm aim hoặc `aimState=applied` xuất hiện. Phải kiểm tra input cuối và tác động của các feature khi chạy cùng nhau.
7. Artifact phải readable, không minify; giữ menu nhẹ và tabs gốc. Không thêm framework, external assets, anti-debug hoặc hook global mới để giải quyết aim.
8. Chỉ commit/push branch hiện tại. User đã có yêu cầu commit/push từ các lượt trước; khi có delivery code thì chạy đầy đủ kiểm tra trước khi đẩy. File spec không đồng nghĩa code đã được triển khai.

## 1. Mục tiêu và điều không làm

### Mục tiêu

- Loại HUD/legend đếm địch–ta góc trên trái, bảng nền và tag SQUAD/ALLY/ENEMY/UNKNOWN quanh tên.
- Tên đồng đội màu xanh dương; tên địch màu đỏ. Unknown giữ cách hiển thị native, không tự coi là địch.
- Sửa aim thật sự tác động đúng vào input gửi tới server.
- Tách Aim Assist và Aim Lock với behavior/điều khiển khác nhau, dùng chung dữ liệu prediction.
- Ước lượng chuyển động theo snapshot, không theo render; thích nghi nhiều dạng chuyển động, không tối ưu riêng zigzag.
- Dùng thông số weapon/bullet/muzzle/modifier/timing thật, tránh lead và smoothing sai.
- Mọi feature nhất quán, tương thích với nhau; tắt/bật/cleanup không gây tác động xấu tới feature khác.
- Setting có ích, có tác động dễ hiểu; nhóm thành ngăn thu gọn đúng chức năng.

### Không làm

- Không hứa trúng tuyệt đối trước thao tác tương lai chưa quan sát được, random spread hoặc thông tin client không nhận.
- Không dùng giới hạn này làm lý do triển khai sơ sài. Phải tối ưu và đo cải thiện bằng code/source thật.
- Không thêm auto-fire/triggerbot, tự trì hoãn bắn để chờ aim, tự tìm ricochet để bắn, neural network/học combo zigzag.
- Không thêm bảng xác suất trúng giả, HUD kỹ thuật mới hoặc hàng chục slider hệ số lọc.
- Không làm mất các feature gốc đã khôi phục trong v0.4.0 để sửa aim.

## 2. Nguồn và bằng chứng đã nghiên cứu

Source pin đã đọc trực tiếp và tra qua GitHub API/Internet:
`https://github.com/survev/survev/tree/3edee7e8bd07fda8a63905aab4c45b595b684a80`

HEAD public tại thời điểm nghiên cứu trùng pin này. Source checkout dùng cho method-level tests: `/home/user/survev-reference` nếu còn tồn tại. Protocol baseline: 1028.

| Source | Dữ liệu/behavior cần triển khai dựa vào |
|---|---|
| `client/src/main.ts` khoảng 922–967 | Application gọi Game.update rồi input.flush; quan hệ native lifecycle. |
| `client/src/game.ts` khoảng 405–483 | PlayerBarn cập nhật trước camera/zoom, sau đó mới tính desktop input tương đối player và tâm viewport. |
| `client/src/game.ts` khoảng 491–564 | Tạo InputMsg, desktop/touch paths, normalize/clamp, Fire pressed/held. |
| `client/src/game.ts` khoảng 731–770 | Native diff detection, threshold hướng >0.1 độ, khoảng ngắm >0.5; timeout gửi input; prevInput lưu sau sender. |
| `client/src/game.ts` khoảng 1057–1076 | ACK timing, update receive interval. RTT không phải one-way latency chính xác. |
| `client/src/game.ts` khoảng 1118–1149 | Delete/full/partial objects được áp dụng rồi activePlayer/localData cập nhật. Không cần parser WebSocket mới. |
| `client/src/objects/player.ts` khoảng 59–79, 849–857 | Native nameText, TextStyle.fill mặc định 65535/cyan, name/visibility. |
| `client/src/objects/player.ts` khoảng 502–552, 790–820 | Update network state, `m_netData.m_pos`, `m_pos`, `m_visualPos`, facing và interpolation khác nhau. |
| `client/src/objects/player.ts` khoảng 2827–2869 | teamInfo/groupInfo; team và squad không phải cùng một khái niệm. |
| `shared/defs/gameObjects/gunDefs.ts` | gun → bulletType, spread, barrelLength/Offset, dualOffset, burst, range-related flags, toMouseHit. |
| `shared/defs/gameObjects/bulletDefs.ts` | Base speed/range/variance cho từng bullet; không dùng bảng đoán theo tên súng. |
| `shared/defs/gameObjects/perkDefs.ts` | bonus_9mm/high_velocity/bonus_assault và modifier khác; chỉ áp khi state/đường logic được xác thực. |
| `server/src/game/weaponManager.ts` khoảng 350–400 | Auto/single/burst và thời điểm thực sự fireWeapon; burst cập nhật theo từng viên. |
| `server/src/game/weaponManager.ts` khoảng 738–800, 838–949 | Muzzle position/clipping, actual direction, movement spread/recoil, speedMult, random deviations, shotPos/toMouseHit. |
| `server/src/game/objects/player.ts` khoảng 1512–1518, 2273–2289, 2342, 3357–3376 | Input to dirNew; direction update trước weapon update; stairs/aimLayer; Fire state. |
| `server/src/game/objects/player.ts` khoảng 4690–4765 | Speed phụ thuộc equip/attack, water, boost, downed/actions/perks; không áp fixed speed cho mọi đối thủ. |
| `server/src/game/objects/bullet.ts` khoảng 190–205, 475–555 | Effective bullet speed; player hit bằng segment-circle, pan riêng. |
| `shared/net/inputMsg.ts`, `shared/net/net.ts` khoảng 98–111 | Aim vector 10 bit MỖI THÀNH PHẦN x/y, không phải mã góc 10 bit; serialize/deserialize và server normalize phải được test. |
| `shared/net/objectSerializeFns.ts`, `shared/net/updateMsg.ts` | Player position quantization, full/partial fields; bullet metadata nhận sau khi bắn không dự đoán được kết quả random trước phát tiếp theo. |
| `config.ts` khoảng 39–41 | Default gameTps=100, netSyncTps=33; hai nhịp riêng, runtime phải đo chứ không hardcode default như sự thật. |

### Những điều đã xác minh không được diễn giải sai

- `aimDelay` xuất hiện trong gun definitions nhưng khi tìm source runtime tại pin này không thấy consumer. Không tự thêm một delay vì tên field.
- `fireDelay` không mặc nhiên là thời gian phải cộng vào mọi dự đoán trước viên tiếp theo. Không biết cooldown chính xác thì không bịa.
- Bullet speed: `baseSpeed * speedMult * (1 + varianceT * bulletDef.variance)`. Server mặc định `varianceT=1` nếu không truyền; không coi mọi variance là một random chưa biết. Spread/empowered effects thực sự random phải phân biệt riêng.
- Không tự trừ vận tốc người bắn khỏi vận tốc mục tiêu như thể bullet kế thừa shooter velocity. Shot origin tại thời điểm bắn và actual bullet construction mới là nguồn đúng.
- Điểm hiển thị nội suy không phải network snapshot mới. Hướng nhìn không phải hướng di chuyển.
- Unknown team không phải enemy; layer preview không phải authoritative gameplay layer.

## 3. Lỗi baseline v0.4.0 có bằng chứng trong repo (đã sửa đường input/tracker ở preview mới)

### 3.1 Smooth không hội tụ

`Features.pre` hiện blend từ physical mouse mỗi frame rồi restore cuối frame. Trạng thái điều khiển không được giữ liên tục.
Thí nghiệm công thức mặc định: mouse x=440, target x=464, dt=1/60, smooth=50 → applied x≈443.23796 MỖI frame nếu input/target không đổi, không tiến dần tới 464.

Yêu cầu: Assist và Lock có controller khác nhau; Lock giữ controlled direction xuyên frame, không reset bởi restore physical mouse. Reset khi release/mode/target invalid/blur. Không dùng một partial blend rồi gọi là Lock.

### 3.2 Tracker lấy mẫu render làm vận tốc rung giả

`Tracker.update` trong `src/core.mjs` đang được gọi theo `Features.pre`. Thí nghiệm read-only với tốc độ thật 12 world/s, snapshot 30Hz/render60Hz cho estimated vx: 11.08→8.39→12.18→9.22→12.81→9.70 khi chạy đều.

Yêu cầu: tracking theo network observations, không lấy frame không đổi position làm mẫu zero velocity. Không nhầm entity không có trong partial update với quan sát đứng yên.

### 3.3 Timing/camera

Features.pre chạy trước native PlayerBarn update và zoom update. Scale/position tính từ đầu frame có thể cũ so với native input cùng frame. Candidate FOV hiện dùng render project nhưng apply dùng player-relative aimPoint.

Yêu cầu: tách source state/world direction/render projection; input cuối không phụ thuộc stale zoom/camera shake. FOV và candidate selection phải thống nhất coordinate semantics đã định nghĩa và dựa input vật lý.

### 3.4 Tests cũ không chứng minh aim cuối

Test đổi mouse hoặc aimState=applied không chứng minh hướng cuối serialize/server. Phải giữ native input construction/diff/send/roundtrip trong test mới, không chỉ helper tương đương tự viết.

## 4. Kiến trúc gọn cần triển khai

### 4.1 Ba lớp state

1. **Nguồn:** game/server cung cấp, trước các override của script.
2. **Tính toán:** history, estimated velocity/error, profile, target, predicted point.
3. **Áp dụng:** aim direction/input commands/visual overrides.

Không lấy output đã bị mình sửa làm nguồn cho bước tiếp theo. Cụ thể layer spoof, zoom overrides và aim correction không được tạo feedback vào gameplay decisions.

### 4.2 Snapshot observation

- Ưu tiên một adapter scoped tại native game-update boundary đã deserialize và đã apply objects.
- Dùng fullObjects/partObjects/delObjIds và roster thật; không dựng parser raw socket khác.
- Position mới lấy từ network data đã áp dụng, không chờ render copy sang m_pos.
- Cùng packet dùng cùng receive timestamp; không giả định có timestamp server nếu source không cung cấp.
- Giữ identity reference + ID; xử lý delete/spawn/reused ID và match changes.
- Entity không nhận sample mới: tuổi observation tăng; không tự thêm một sample zero.
- Tham chiếu schema/adapter phải được chứng minh bằng AST/data flow và source scenario, kể cả rename/minify các trường m_* theo conventions hiện có.
- Không parse AST/scan graph trong vòng solver mỗi frame.

### 4.3 Một đường sửa input chính

Phương án đã chốt: một bộ điều phối InputMsg tại sender của game instance.

- Native InputMsg là nguồn intent người dùng cho Assist.
- Clone giữ prototype; preserve field không thuộc quyền feature.
- Aim chỉ sửa direction và distance khi thực sự cần đúng weapon semantics.
- Không dùng mouse mutation làm đường điều khiển aim song song.
- Dùng native input timeout để yêu cầu lượt gửi khi corrected output cần đổi mà physical input không đổi. Adapter phải nhận diện đúng data flow `diff || timeout<0` và reset timeout sau gửi; không chọn field theo tên/giá trị ngẫu nhiên.
- Không gửi packet ngoài native sender, không tạo loop WebSocket riêng.
- Không force packet mỗi frame nếu corrected output không đổi có ý nghĩa; so với output đã gửi thực tế, xét protocol quantization/threshold phù hợp.
- Recompute/apply cuối theo data có sẵn tại sender; không serialize một prediction từ scale cũ như thể là hướng chuẩn.
- Khi release/disable/target lost: phải bảo đảm hướng native được gửi trở lại kể cả chuột không di chuyển. Không chỉ ngừng override để server giữ last corrected direction.
- Không phá m_prevInputMsg/native diff behavior; test tình huống native lưu input gốc sau sender clone.
- Nếu scheduler contract thiếu, giải thích rõ và không giả vờ aim đang hoạt động đầy đủ.
- Khi Stop, best effort dùng native path hợp lệ để trả hướng nếu còn session; không tự phát network ngoài native. Luôn gỡ hooks/state. Không gửi khi đã disconnected/unsafe.

### 4.4 Chặn điều khiển khi không phù hợp

Death/downed, spectator, hidden/blur, nhập văn bản/menu capture, emote wheel, missing protocol/mapping, target invalid phải giải phóng điều khiển tương ứng. Không nuốt native click, không giữ Fire để chờ convergence. Không để action cũ chạy khi state trở lại hợp lệ.

## 5. Thuật toán tracking/prediction

### 5.1 State theo snapshot

History ngắn và bounded: position, receive timestamp, interval, estimated velocity và residual của dự đoán trước so với sample mới. Không lưu vô hạn.

- Dùng nhiều quan sát có trọng số theo độ mới, không chỉ derivative của hai sample rất gần nhau.
- Chống position quantization và jitter/packet bunching.
- Ngưỡng motion/turn có noise floor, không coi mọi rung nhỏ là đổi hướng.
- Chạy ổn định: lọc nhẹ để giảm noise.
- Đổi hướng rõ/dừng: tăng trọng số thông tin mới, giảm ảnh hưởng velocity cũ nhanh.
- Phân biệt outlier đơn lẻ và chuyển động thật. Reset khi gap/teleport/identity khác; không reset vì noise nhỏ.
- Không fit pattern trái–phải, không đoán chu kỳ zigzag, không dùng facing làm velocity.
- Một estimator đơn giản thích nghi; acceleration chỉ thêm nếu benchmark out-of-sample chứng minh có ích, không mặc định phức tạp tốt hơn.

### 5.2 Đồng bộ mốc thời gian

Trước interception, đưa shooter/target về cùng mốc ước lượng. Tách observation age, input transit estimate, known shot scheduling và bullet flight time. Không cộng RTT, interpolation, sample age lặp hai lần.

RTT/2 chỉ là heuristic có bound; không giả chính xác một chiều. Không cộng fireDelay vào tất cả shots. Không biết cooldown hiện tại thì không bịa. Config default tps chỉ để tham chiếu, runtime interval phải đo.

### 5.3 Weapon profile

Resolve gun→bulletType→defs runtime, không chép cứng vài gun.
- Base speed/range/variance, modifiers quan sát được và đúng điều kiện source.
- Barrel length/offset, dual/offhand khi biết được, muzzle clipping.
- Nếu offhand/state không biết chắc: đánh dấu approximation, không fabricate certainty.
- Spread/moveSpread/recoil/first-shot rules ảnh hưởng hit quality; không tự đảo random spread.
- toMouseHit cần correct aim distance, clamp/roundtrip theo source. Với gun bình thường không sửa distance vô cớ.
- Đổi weapon/perk/profile: invalidate cache thích hợp; equip request không phải equip ACK.
- Burst dùng hướng ở mỗi viên theo native fireWeapon, không freeze prediction của viên đầu.
- Bullet metadata nhận sau shot có thể dùng kiểm chứng profile, không tiết lộ random của shot tương lai.

### 5.4 Solver và độ không chắc chắn

Baseline solve: `|targetPos + targetVelocity*t - muzzlePos| = bulletSpeed*t` với nghiệm hợp lệ trong effective range.
- Số vòng muzzle/direction refinement nhỏ cố định; không loop convergence vô hạn.
- Shooter movement ảnh hưởng shot origin; không tự gắn inherited velocity cho bullet.
- Ưu tiên vùng trung tâm collider cho biên sai số; radius/scale thật khi có. Không thêm head aim không có collider source.
- Tách predicted intercept point khỏi controlled aim direction sau smoothing.
- Giữ estimate positional error từ residual, data age, motion instability và forecast duration; so với target radius để biết nghiệm đáng tin tới đâu.
- Không gắn percent hit chance chưa hiệu chuẩn.
- Không cắt thời gian bay thật (vd 400ms) xuống horizon ngắn (vd150ms) rồi vẫn gọi là interception chính xác.
- Nếu future horizon vượt độ tin cậy: behavior fallback phải explicit, conservative và test được; không silent fake short lead. Assist bớt quyết liệt hoặc nhường input; Lock không tiếp tục bám một extrapolation vô lý. Diagnostics phân biệt no solution/uncertain/stale.
- Không dùng luật máy móc “uncertain→giảm lead” khiến mọi shot xa aim thiếu; chọn behavior bằng benchmark và định nghĩa rõ.

### 5.5 Collision và target selection

- FOV/intent lấy physical/native input chưa sửa, không dùng corrected aim làm tâm chọn mới.
- Lọc active/dead/downed option, known enemy, gameplay layer/aim-layer hợp lệ.
- Gần cursor là ưu tiên mặc định; hysteresis nội bộ để không đổi target liên tục. Sticky không bám bất chấp invalid/wall/outside exit region.
- Chỉ solve/raycast tập ứng viên nhỏ cần thiết, không mọi entity mỗi frame.
- Kiểm tra muzzle→predicted point, không chỉ center→current target; kiểm tra range.
- Xét obstruction liên quan tới first hit; không coi đường đẹp trên overlay là chắc damage.
- Pan/other blockers phải được phân biệt với hit circle; không claim auto-bypass pan.
- Không tìm đường ricochet tự động trong scope này.
- Khi target đổi: reset/transition controller không kéo quán tính từ target trước.

## 6. Aim Assist và Aim Lock

Một mode duy nhất: Off / Assist / Lock; không hai checkbox chồng nhau.

### Assist
- Dùng native direction làm input gốc; correction có giới hạn trong FOV.
- Strength0 = native input không thay đổi. Tăng strength tăng ảnh hưởng theo chiều trực quan.
- Điều khiển theo góc/time, không pixel delta phụ thuộc FPS.
- Người dùng kéo khỏi vùng hỗ trợ phải thoát được; không giữ cứng/giành lại tự động.
- Không auto-fire.

### Lock
- Controlled direction có state riêng và hội tụ theo dt.
- Smooth không reset mỗi frame về physical direction; reset khi lifecycle/activation/target invalid.
- Không overshoot bất thường hoặc áp double smoothing.
- Đo controller lag riêng với solver error; không bù bằng một lead offset tùy tiện.

### Kích hoạt
Chọn Fire / giữ phím aim / cả hai. Default Fire để giữ thói quen hiện tại; trạng thái trong menu nói rõ khi chờ Fire/key/contract. Phân biệt mode với activation; migration/key toggle không được để hai state UI mâu thuẫn.

## 7. Tính nhất quán giữa feature — điều kiện bắt buộc

Một lượt điều phối dùng chung context: source state, actual weapon/slot, activation, protocol, lifecycle. Không để hook cuối tự thắng.

| Feature | Quyền tác động | Không tự ý tác động |
|---|---|---|
| Aim | Aim direction/distance cần thiết | Fire, movement, equip |
| Semi | Native pressed edge hợp lệ | Aim/movement/equip |
| Switch | Một equip request hợp lệ | Fire/aim |
| Melee | Aim/movement/equip trong melee authority đã định nghĩa | Giành ngoài phạm vi melee |
| Mobile Movement | Direction representation của movement | Aim/Fire/equip |
| Loot | Loot command | Aim/equip |
| ESP/X-Ray/Zoom/Map | Hiển thị riêng | Gameplay input |

### Arbitration cụ thể

- Aim+Switch: use actual equipped profile; invalidate khi confirmed change, không dựa request.
- Melee authority thắng gun aim trong phạm vi melee; thoát trả điều khiển, không để movement cũ.
- AutoMelee+Switch: không hai equip/frame. Melee giành equip thì hủy pending away/return.
- Người dùng manual equip/slot swap: hủy automatic pending sequence, không giành lại sau đó.
- Semi synthetic edge không được bị hiểu thành physical activation mới của feature khác. Fire user giữ nguyên, không delay để chờ aim.
- Mobile+Melee: một movement output theo authority; không cộng vector, không smooth hai lần; release không coast.
- Zoom chỉ ảnh hưởng render/transforms, không world interception.
- LayerSpoofer chỉ preview. Aim/wallcheck/loot dùng source gameplay layer, không layer property đã override. Preview khác tầng không tạo shot hợp lệ.
- Loot input không bị mất do equip/aim arbitration; input array vẫn tuân capacity native, không double add.
- Stale requests có expiration/invalidation; không chạy tiếp sau death/rejoin/manual changes.

### Ownership/cleanup/fault isolation

- Tắt feature chỉ gỡ overrides/state do feature đó sở hữu; không clear toàn bộ làm feature khác nhấp nháy.
- Không có Canvas/preview error không làm input features hỏng theo.
- Guard lỗi feature này không vô cớ gỡ authority/overrides của feature không liên quan.
- Bật/tắt theo thứ tự khác nhau, với cùng config cuối, phải cho behavior tương đương.
- Blur/hidden/death/spectator/rejoin/Stop reset state và giải phóng quyền đúng; không stale target, equip hoặc smoothing.

## 8. ESP tối giản

### UI/behavior bắt buộc

- Xóa legend/HUD đếm góc trái, không chỉ tắt default.
- Xóa relation/status label boxes, SQUAD/ALLY/ENEMY/UNKNOWN prefixes và nền sau tên.
- Đồng đội blue, địch red; unknown giữ native. Không selected-target gold name.
- Không ghép khoảng cách/weapon/downed/layer thành chuỗi cạnh tên mặc định.
- Ưu tiên native nameText; giữ nguyên nội dung tên, font, size, position. Không lộ tên khác với tên client hiện có.
- Native name style.fill=cyan/65535: không chỉ tint red lên cyan gây tối màu. Dùng validated TextStyle fill API, cập nhật khi cần, không recreate TextStyle per tick.
- Khôi phục native fill/visibility khi tắt/entity recycled/Stop, ownership-aware; không ghi đè later writer không còn thuộc mình.
- Player lines là optional riêng, default off; không ép bật cùng names.
- Xóa/ignore/migrate config cũ cho legend/tags/selected name/extra labels để chúng không trở lại sau reload.
- Các tùy chọn phức tạp khác phải có lý do giữ; không khôi phục clutter chỉ vì config legacy còn key.

## 9. Menu và config

Giữ Main / Visuals / Misc / Keybinds / Help. DOM thuần; nhóm `<details>` hoặc tương đương nhẹ, lưu trạng thái mở khi UI refresh; không re-render toàn panel mỗi lần kéo slider gây mất focus.

### Main
- **Aim — Chế độ & kích hoạt:** Off/Assist/Lock; activation; Assist strength HOẶC Lock smooth tùy mode.
- **Aim — Chọn mục tiêu:** FOV ghi rõ đơn vị; sticky; downed; wallcheck. Unknown/allies luôn loại, không nút aim teammate.
- **Aim — Dự đoán:** Off/Auto. Advanced mặc định đóng: latency Auto/Off; lead adjustment mặc định100%. Không thêm hàng loạt hệ số lọc/horizon sliders trùng lặp; horizon là internal trust limit, không giả cắt physical TOF.
- **Melee:** Melee Lock/AutoMelee.
- **Bắn & đổi súng:** Semi/AutoSwitch/UseOneGun.

### Visuals
- **Tên người chơi:** bật tên màu địch–ta; blue/red defaults.
- **Đường ESP:** player lines riêng, default off.
- **Hỗ trợ ngắm:** FOV circle và predicted dot; dot default off.
- **X-Ray**, **Trajectory/Flashlights**, **Zoom & Layer:** nhóm đúng chức năng, chỉ show settings phụ khi parent active.

### Misc / Keybinds / Help
- Misc: Loot, Movement, Map.
- Keybinds: binds và hold/toggle rõ ràng, typing/capture/blur an toàn.
- Help: diagnostics/Retry/Stop/reset controls hợp lý; trạng thái kỹ thuật chi tiết ở đây.
- Không trạng thái debug ngoài game HUD; menu có một status ngắn dễ hiểu.
- Config migration từ v0.4.0 phải explicit: legacy aim→mode thích hợp; không silently bật gameplay trên fresh config; loại settings HUD đã xóa. Strength/slider ranges validated và có ý nghĩa; không yêu cầu user tự tune noise covariance.

## 10. Hiệu năng

- Tracking tại update boundary, share result giữa render/input.
- Không parse AST/scan object graph/create TextStyle trong hot loop.
- Bounded history/cache/candidates/iterations/collision work; clear lifecycle.
- Không increase native input traffic chỉ để preview mượt; scheduler cần thực sự có output change/restore.
- Giảm preview trước khi ảnh hưởng input; không silently dùng gameplay state quá cũ.
- Đo frame/feature work trong điều kiện so sánh baseline. Không quảng cáo benchmark FPS từ thời gian một helper.

## 11. Kiểm thử và tiêu chí nghiệm thu

### A. Input thực thi (ưu tiên P1)

1. Target/physical mouse cố định: Lock phải hội tụ tới đúng direction, không partial blend lặp.
2. Assist strength0 phải native; strength tăng monotonic và người dùng kéo thoát được.
3. Target moving, physical cursor không đổi: native send được yêu cầu khi cần, không chờ timeout1s.
4. Release/toggle Off/lost target: direction native được gửi lại dù physical input không đổi.
5. Native PlayerBarn/zoom update trước input: final direction vẫn đúng, camera offset/shake không lẫn input.
6. Native InputMsg serialize/deserialize+server normalize; không chỉ helper giả hay assert mouse đổi.
7. Activation Fire/key/both; no synthetic Fire activation leakage; preserve Fire/movement/equip/physical current-old.
8. Emote wheel/typing/menu/blur/death/downed/spectator/rejoin không stale authority.
9. Native diff + prevInput + timeout behavior phải được chạy thật từ source trong source runner, không bỏ qua bước này bằng gọi sender tay rồi kết luận E2E.

### B. Tracking và prediction

- Đứng yên, bắt đầu/dừng; thẳng/ngang/chéo/tới/xa; cong/vòng; đảo90/180; đổi tốc độ; zigzag đều/không đều; hỗn hợp không theo quy luật; va tường/layer change.
- Snapshot33Hz hoặc biến thiên, render30/60/144Hz; packet jitter/bunching/gap; quantization; spawn/delete/reused IDs.
- Khoảng cách và weapon đa dạng, speed/perk/profile changes, muzzle/dual/toMouseHit/range.
- History model không nhìn sample tương lai. Dữ liệu chấm và dữ liệu tune tách nhau.
- So baseline hiện tại + không prediction + constant velocity đơn giản. Báo median/p95 positional/collider miss, recovery sau turn, overshoot, target churn, stale decisions và compute cost.
- Chấm từng nhóm, không lấy mean tổng che regression. Không chấp nhận chỉ tốt zigzag nhưng làm straight/stop/curves tệ rõ.
- Tách lỗi solver, controller, timing, quantization, spread/obstruction; hitrate không phải metric duy nhất.
- Acceleration/model phức tạp chỉ giữ nếu out-of-sample cải thiện đáng kể.

### C. Test phối hợp

- Aim+Zoom, Aim+Semi, Aim+Switch, Aim+Melee, Melee+Switch, Movement+Melee, Layer+Wallcheck/Loot, visuals+input.
- Tổ hợp Aim+Semi+Switch và Aim+Zoom+ESP+XRay.
- Manual equip trong automatic pending return, release giữa cycle, bật/tắt khác thứ tự.
- Assert input cuối/authority/cleanup/restore, không chỉ không crash.
- Canvas absent/preview exception không làm input ngừng.
- Config đổi giữa trận không clear override unrelated.

### D. ESP/menu

- Không legend/tag/box/prefix ngay cả legacy saved config bật chúng.
- Native names đúng blue/red, unknown không đổi, no duplicate labels, restore sau disable/Stop/recycle/team change.
- Không per-frame TextStyle reconstruction; không đổi name text.
- Controls đúng mode, conditional settings, group open/focus stable, key capture/storage/migration.

### E. Release

- `npm run check` + source runner trên pin; `git diff --check`.
- Build readable, version bump nhất quán, original reference unchanged.
- Ghi docs nguồn→implementation→evidence và known limitations; không gọi native-method scenarios là full live E2E.
- Nếu chưa live tested, nói đúng nhưng không dùng làm lý do trì hoãn source-backed fixes.
- Push current branch khi ready; present main `.user.js` và link docs/report.

## 12. Thứ tự thực hiện và ghi tiến độ

- [x] **P0:** native colored names, remove HUD/tag/config legacy clutter.
- [x] **P1:** input scheduling+sender coordination, activation/release, Lock convergence/Assist semantics; source-native roundtrip.
- [x] **P2:** snapshot adapter/estimator, weapon profile/modifiers/muzzle và source gameplay state.
- [ ] **P3:** core integration và movement-general benchmark đã chạy; CHƯA nghiệm thu đủ. Held-out benchmark còn median start-stop/p95 đảo hướng kém legacy; recovery mới là proxy, chưa đo churn/stale-decision đa mục tiêu hoặc browser feature-frame cost. Không lấy kết quả trung bình để đóng mục này.
- [x] **P4:** arbitration/ownership/fault isolation, menu grouping/migration và combination/lifecycle tests.
- [x] **P5 (packaging preview):** final `npm run check` 122/122, source runner 4/4, `git diff --check` pass; artifact readable/version0.5.0-preview.1, reference SHA256 không đổi. Implementation commit `702e80a` đã push current branch và `.user.js` đã present. Đóng packaging preview không đồng nghĩa nghiệm thu P3 hoặc live.

Khi triển khai, cập nhật các checkbox cùng bằng chứng và phạm vi thực sự đạt. Không đánh dấu một mục hoàn tất chỉ vì đã tạo module/setting. Nếu đổi quyết định kỹ thuật, ghi lý do/source/test ở phần dưới thay vì để spec và code mâu thuẫn.

### Nhật ký quyết định/thực thi

- 2026-11-12: Ghi spec tổng hợp theo yêu cầu user trước khi code. Baseline vẫn v0.4.0; lượt vừa bắt đầu triển khai chỉ đọc repo, chưa sửa gameplay. Chưa có kết quả test/benchmark cho spec mới.

- 2026-11-12, triển khai preview: `NativeNames` sửa fill blue/red và visible có restore; Canvas labels/HUD removed. Migration ép legacy clutter off; lines/dot default off. Kiểm thử cả Canvas absent/fault và latest native writes.
- P1: `Features.installSender/pre/processAim` dùng InputMsg clone + scheduler native. Không sửa physical mouse; final sender recompute sau zoom. `AimController` có Assist monotonic/0% và Lock convergent. Source runner chạy thật diff/timeout/prevInput/BitStream roundtrip trong 4 tổ hợp transform/loot.
- P2: adapter RX sau native apply, chỉ position-bearing IDs; delete/reuse/layer/identity cleanup. Weighted fit tối đa 6 samples/140ms; coalesced endpoint thay vì tiny-dt derivative. Effective gun/bullet/perk/variance/range, central muzzle clipping, client stair.downDir → server cardinal aimLayer, toMouseHit inversion. Dual hand, shotgun jitter/random spread/empowered45 không biết chắc trước viên tiếp theo; báo approximate, không bịa source state.
- Quyết định confidence sau diagnostic seeds 7301/99173/441019: tách fit residual (wu) và slope error (wu/s). Slope uncertainty lớn dùng fallback giảm flight lead, có state `reduced-lead-uncertainty` và solve lại flight time vật lý, KHÔNG cắt TOF. Stale age >150ms nhường native. Không thêm acceleration hoặc maneuver classifier. Final frozen holdout dùng seed 1847/82031/517991, report lưu riêng.
- P4: sender là nơi thêm equip; manual enum11–20/27/28 thắng (21/22 là scope, không weapon). Melee hủy Switch, tránh lặp equip khi chờ confirm; manual equip khóa auto-melee tới release Fire. Semi giữ physical activation riêng. Layer/loot/wallcheck dùng source layer; overlay fault riêng không clear names/zoom/input. Mode-dependent controls, collapsible advanced, slider focus/open-state tests.
- Bằng chứng preview: 122 offline tests; 4 expanded source-method scenarios; 12 movement families × 3 held-out seeds × 3 render rates × 2 snapshot cadences. Chi tiết/limitations ở `docs/reborn-0.5.0.vi.md` và `docs/aim-benchmark.vi.md`. Không live-tested. Những phase đã check là phạm vi implementation/tests nêu trên, không chứng minh tất cả tổ hợp client/server hoặc không có regression.

- 2026-11-12, hotfix `0.5.0-preview.2` sau phản hồi ESP/aim không hoạt động: tái hiện scheduler minified logical/comma không có IfStatement, hidden legacy nametags gate, names phụ thuộc aim/camera schema, optional prediction chặn direct aim và menu focus/unsupported wallcheck toggle. Đã sửa và thêm 7 regression tests (129/129), source-native scenarios4/4 được mở rộng bằng source name factory + PIXI7 Container/TextStyle thật và direct fallback trên serialized input. Không có runtime capture từ người dùng nên không khẳng định đây là toàn bộ nguyên nhân live. Xem `docs/hotfix-0.5.0-preview.2.vi.md`.
- Quyết định fallback mới: thiếu optional prediction contract/history ban đầu dùng vị trí hiện có (state explicit); thiếu definitions chỉ direct aim khi actual gun slot0/1 đã xác minh. Không đoán ballistics/unknown weapon. Known-stale history, protocol/team/layer/wallcheck/lifecycle guards vẫn giữ. Đây là sửa tính sẵn sàng cơ bản, không đóng P3 quality hoặc thay benchmark solver.
- Menu: toàn bộ Aim Assist/hỗ trợ ngắm ở Main; Visuals chỉ giữ visual features. Names có capability/status/count riêng không phụ thuộc Canvas/camera/weapon discovery, không tái thêm HUD/tag.
