# 0.4.0 — sửa held fists / smoke, khôi phục các nhóm feature gốc

## Phạm vi và mức bằng chứng

Yêu cầu Reborn là tính năng gốc có hành vi thật, không chỉ menu. Bản này bổ sung implementation/control/lifecycle/tests cho các nhóm còn thiếu ở 0.3.0. **Chưa có kiểm chứng gameplay live trên survev.io; không tuyên bố hoàn tất live parity.** User đã xác nhận Semi punching và smoke lỗi ở 0.3.0; test cũ pass không phủ được các trường hợp đó.

Nguồn đã đọc trực tiếp:

- Gốc: `references/duality-client.reference.js`, giữ nguyên, không import vào build.
- Public source pin: `survev/survev@3edee7e8bd07fda8a63905aab4c45b595b684a80`, protocol 1028. Đây không phải bằng chứng bundle deployed giống source pin.
- `client/src/objects/smoke.ts`; `shared/defs/gameObjects/meleeDefs.ts`; `server/src/game/weaponManager.ts`; `client/src/map.ts`; `client/src/objects/building.ts`, `obstacle.ts`, `player.ts`; `server/src/game/objects/projectile.ts`, `bullet.ts`; `shared/gameConfig.ts`; `shared/defs/register.ts`.
- PIXI 7.4.3 `@pixi/display`: DisplayObject tạo own writable `alpha`. Không quy lỗi smoke cho prototype accessor: source package không ủng hộ giả thuyết đó.

## Hai lỗi user báo

### Semi không tự đấm khi giữ Fire

0.3.0 cố ý chỉ xét `type=gun, fireMode=single`, nên **fists không bao giờ có synthetic pressed edge**. Source fists có `autoAttack=false`, attack cooldown .25s; server `meleeUpdate` cần shootStart hoặc native autoAttack+shootHold, cooldown <0 và không đang melee animation.

0.4.0:

- `RepeatFire` nhận non-auto melee và gun single; native auto/burst/autoAttack không bị can thiệp, throwable bị loại để tránh cook/throw ngoài ý muốn.
- Gun theo fireDelay; melee thử lại tối đa 20 edge/s (không phải 20 đấm/s). Early edge vẫn bị server bỏ qua, không có cooldown bypass.
- Cùng frame đọc pressed nhiều lần trả cùng pulse. Không đảo `mouseButtons`/`mouseButtonsOld`; native click không bị nuốt.
- Dừng synthetic edge khi release, disabled, hidden, downed/dead, spectating hoặc chưa quan sát protocol khớp. Reset khi đổi weapon/bind/match.
- Source runner chuyển hero sang fists, giữ physical button với old=true, chạy 120 frame qua **native server `WeaponManager.update/meleeUpdate`**. Xác nhận có nhiều đấm được chấp nhận trong giới hạn cooldown; tắt Semi thì không phát thêm đấm.

### Khói không mờ

0.3.0 dựa vào generic traversal và không có smoke-source diagnostics; chưa chứng minh nguyên nhân trên deployed bundle. Có hai vấn đề source-backed được sửa: discovery không theo data-flow SmokeBarn, và opacity dùng phép nhân phần trăm khác gốc.

0.4.0:

- AST nhận diện method đọc pool bằng index, dùng fadeTicker/fadeDuration/posTarget/radTarget, ghi sprite alpha/tint/visible. Nhận diện **kể cả khi pool đang rỗng**, không dựa tên m_* hay chọn array đầu tiên.
- Mỗi visual frame lấy active particles hiện tại, bỏ particle destroyed; không chờ generic map traversal.
- Gốc dòng 11–26 dùng smoke **setting/1000**. Mức 50 = alpha cap .05; 0 = ẩn; 100 = .1, **không phải opacity 100%**. Tắt X-Ray để trả alpha game.
- `min(nativeAlpha, cap)` giữ native fade nếu thấp hơn cap; game vẫn ghi native alpha/tint vào raw state. Disable/Stop trả **giá trị native mới nhất**, không snapshot cũ.
- Darker Smokes đổi particle tint để native smoke renderer dùng public `sprite.tint` setter; không chọc `_tintRGB`.
- Diagnostics: `stats.xray.smokeSources`, `smokeActive`, `smokeModified`, `smokeUnsupported`, `darkened`; status menu hiển thị modified/active. Không lấy “đã bật checkbox” làm bằng chứng effect đã áp dụng.
- Source runner spawn particle sau discovery pool rỗng, chạy native SmokeBarn update nhiều lần: alpha vẫn .05, dark tint có tác dụng; tắt X-Ray rồi update trả .9/native tint. Chạy cả source thường và minify+rename m_*.

## Checklist gốc → implementation

“Có” dưới đây chỉ là implementation có evidence offline; **tất cả vẫn cần live verification**. Không có nhóm gameplay gốc nào chỉ còn nhãn “chưa port” trong menu 0.4.0. Điều đó không đồng nghĩa tương đương chính xác mọi hành vi/bug gốc.

| Gốc / vị trí tham chiếu | 0.4.0 / cải tiến và khác biệt |
|---|---|
| Aimbot, Use Smooth, slider, Target Knocked, Sticky, dot, FOV/circle, Wallcheck (UI 2830–2893; targeting 350+) | Giữ implementation; aim quanh physical cursor, chỉ khi Fire; shared enemy/ally/unknown classification. Smoothing theo dt; prediction base-speed intercept. Không mô phỏng toàn bộ perk/netcode. |
| Melee Lock + Auto Melee (UI 2894–2910; target logic 350–417) | Reach theo attack offset/rad + player radius source 1; native EquipMelee từ gun khi có enemy trong reach và giữ Fire. Mobile direction/aim override tạm; không tự quay lại gun sau melee. Server quyết định equip/attack. |
| Auto Switch + Use One Gun (2255–2310; UI 2911+) | Single/burst ammo change, hai gun hoặc cycle away/return; chờ quan sát equip trước khi return, timeout/release hủy. Một equip/frame; không gửi hai equip ngay cùng packet như gốc, không khẳng định reset cooldown. |
| Semi Auto | Held single và non-auto fists/melee; preserve native auto/burst/throwables; kiểm tra cả native melee server cooldown. |
| X-Ray master, Remove Ceilings, Darker Smokes, Smoke/Tree Opacity (11–26, UI 2920+) | Smoke source adapter + legacy alpha cap, tint reversible; ceiling theo building img.isCeiling, vegetation theo validated owner/type. Không giữ hack dò texture tên ceiling/snow hoặc ngoại lệ texture container của gốc. Đây là khác biệt chứ không cam kết mọi ceiling/seasonal snow đã phủ. |
| Layer Spoofer (1687–1742; keybind 3248+) | Hold T/rebind, local layer 0↔1 + alpha .5, theo latest native write, release/blur/hidden/disable/Stop restore; refuse descriptor không configurable/writable và layer khác 0/1. Không đổi tầng server. |
| Visible Nametags + Player ESP (105–123; UI 2970+) | Giữ team-aware Canvas labels/lines/markers, distance/weapon/downed/layer/filter/offscreen/legend/colors. Unknown không bị tô enemy; native text suppression reversible, không viết TextStyle mỗi tick, không giả HP. |
| Grenade ESP/danger zones (124–136; UI 2990+) | Active projectile type 9 + throwable/explosion defs, cùng layer, radius thật từ defs thay hardcode 13 mọi nade. Không giữ filter mơ hồ nhận nhầm smokeEmitter. Không biết fuse/occlusion/shrapnel, không gọi đây là vùng an toàn. |
| Grenade Trajectory (137–188; UI 3000) | Throw strength theo max mouse distance 18, speed/velZ defs, spawn height .5/gravity10.5/ground drag2.3; nét đứt open-air estimate, bounded samples. Không dùng hệ số 32.4/15 gốc. Không biết collision tương lai, perk, player velocity, remaining fuse; không phải prediction điểm nổ chính xác. |
| Own/Others Flashlight (189–201, 2082–2136; UI 3014–3023) | Own và enemy cone theo base spread/range, clip circle/AABB; chỉ active enemy đã nhận cùng layer. Tối đa 8 cone, 7 ray/cone và 256 obstacles; không bảo đảm bullet coverage nếu budget cắt hoặc collider unsupported. |
| Flashlight/Bullet Trajectory (202+; UI 3030) | Bounded ray path + tối đa 3 nominal reflections theo captured MapObjectDefs.reflectBullets. Cần map defs; thiếu thì dừng first hit, nét đứt. Không mô phỏng muzzle, người trúng đạn, xuyên phá, perk, range decay chính xác. Không claim ballistic/server prediction hoàn chỉnh. |
| Infinite Zoom (UI 3040) | Zoom-out slider **có giới hạn 1–3×** và reversible raw property; cố ý không giữ zoom vô hạn. Không tạo thêm received entity state. |
| Map Highlights / Smaller Trees (2229–2258; hook 3956–3975; UI 3050+) | Marker type/color/scale gốc; scoped getMinimapRender wrapper, clone record/shape tránh mutate shared MapObjectDefs.map.shapes; native renderMap khi config/map đổi, dispose redraw trả map. Không hook global Array.sort, không đổi collider gameplay. Smaller trees cap minimap scale 1.8. |
| Auto Loot (Join wrapper 3730+; UI 3060+) | Giữ mobile Join mode gốc (cần Join mới), thêm nearby native Loot/backoff cho ammo/heal/boost/throwable trong trận; không tự thay gun/gear, không fake pickup ACK. |
| Mobile Movement + Smooth (serializer 3735+; UI 3070+) | Direction easing theo elapsed dt, normalized vector/touchMoveLen số 255 thay boolean gốc; release dừng ngay, không trôi. Input clone giữ nguyên native snapshot. |
| Menu Main/Visuals/Misc/Keybinds/Help; menu/aim/sticky/layer keys, aim Hold (UI 3185–3270) | Giữ tabs/sidebar, controls gán phím thật, storage validation, cleanup/focus/blur, thêm diagnostics/Retry/Stop. DOM thuần, không animation/blur/font/ảnh ngoài. Key Sticky toggle policy không phải đóng băng entity bất chấp FOV/team validity. |
| Anti-debug, freeze/console spoof, font spoof, redirect/version/license gate, cookie spoof | **Chủ đích loại bỏ**, không phải gameplay cần phục hồi; không tái tạo hành vi phá trang để đạt “parity”. Gốc giữ riêng không sửa. |

## Kiểm tra đã chạy

- `npm run check`: **102/102** offline tests, build readable và `node --check`.
- `npm run check:upstream -- /home/user/survev-reference`: **4/4** scenarios: source thường / minify+m_* rename × mobile/nearby. Giữ checks Join/aim/team/loot; bổ sung native smoke update, native held fists/server cooldown, native minimap getter+render contract. Collaborators PIXI/network vẫn inert; không phải full game/server/browser E2E.
- Tests mới cover smoke ambiguity/empty pool/fade/descriptor restore; repeat eligibility/frame/reset; native melee equip codes/reach; single/burst/one-gun cycle; scoped map clone/redraw/dispose; ray circle/AABB/layer/dead/height/reflection; throw bounds; smooth movement/release; layer key typing/blur/restore; Canvas own/enemy/throw paths; game+map registry capture và controls thật.
- Không benchmark FPS live, không xác nhận anti-cheat, không có live gameplay test từ môi trường này.

## Kiểm tra live cần làm khi cài 0.4.0

1. Tắt script cũ, cài file readable mới, reload từ document-start. Mở Right Shift, vào trận mới để thấy Join protocol. Không chạy hai bản cùng lúc.
2. Semi: chọn fists, bật Semi, giữ Fire 2–3 giây. Mong đợi nhiều đấm theo cooldown; nhả/tắt phải dừng. Chọn auto gun/burst không được tạo kiểu bắn bất thường; không repeat grenade. Xem `stats.semi` nếu không chạy.
3. Khói: bật X-Ray trước/sau khi khói spawn, đặt 50 rồi 0; mong đợi particle rõ ràng giảm opacity/ẩn, tắt X-Ray trả normal. Xem `stats.xray`: source=0 là chưa khớp discovery; active>0/modified=0 là descriptor bị từ chối; modified>0 nhưng nhìn không đổi cần điều tra renderer/deployed effects khác, không kết luận đã sửa live.
4. Thử Auto Melee trong reach, ra xa/release; Use One Gun phải chờ native slot, không tự equip mãi khi release. Các request vẫn có thể bị server từ chối.
5. Hold T rồi thả/Alt-Tab/tắt: layer/alpha phải trở lại state game. Không kỳ vọng damage xuyên tầng.
6. Map markers bật/tắt phải redraw minimap; `mapHighlights.state` không được báo redrawn nếu không có record. Không redraw mỗi frame.
7. Bật own/enemy cones, bullet/throw path riêng; xem previews counts, ricochetDefinitions/truncatedObstacles/unsupportedColliders. Kiểm tra độ lệch hình học thực tế; **đừng dùng nominal preview làm bằng chứng điểm đạn/nổ chính xác**.
8. Thử join lại, spectator, death/revive, setting đổi giữa trận và Stop; không giữ hook/alpha/input/movement từ entity cũ.

Nếu sai: gửi **Help → Copy diagnostics**, version, trình duyệt/manager, feature/setting và bước tái hiện. Diagnostics chỉ số tổng/contract, không chứa cookie/token, tên hay vị trí người chơi. Không cần dump object game.
