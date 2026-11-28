# Thử đối kháng dùng code Survev pinned

**Lưu ý lịch sử:** các số bên dưới dùng benchmark trước khi mô phỏng omission của partial update. Benchmark hiện tại và kết quả sau khi sửa nằm tại `hieu-chinh-dung-som.vi.md`; không so trực tiếp hai ma trận.

## Phần thực và phần giả

Test sử dụng checkout sạch Survev commit `3edee7e8bd07fda8a63905aab4c45b595b684a80` tại https://github.com/survev/survev (GPL-3.0-or-later). Adapter kiểm tra đúng commit và không có thay đổi, dùng esbuild bundle code source **cục bộ** và thực thi trong Node. Không khởi động server hay kết nối game. Bundle nằm trong `.cache`, không commit source upstream.

Các phần thực thi từ source pinned:

- Khối di chuyển và đẩy khỏi vật cản trong `Player.update`, `Player.recalculateSpeed`, lớp `Grid` và geometry/collision gốc. Adapter trích khối và method, **không chạy toàn bộ `Player.update`**.
- `WeaponManager.fireWeapon`, `BulletBarn.fireBullet`/`Bullet.init`, `Bullet.update`/`checkForCollisions` cùng định nghĩa súng, đạn, spread, jitter pellet, recoil và geometry nguồn. Dùng MP5, AK-47, M870; shotgun tính trúng một phát khi ít nhất một pellet chạm target.
- Serialize/deserialize partial player từ `ObjectSerializeFns` và hướng/độ dài aim qua `InputMsg`/`BitStream` nguồn; đây không phải full `UpdateMsg`, sender hoặc WebSocket.

Test dựng game, player, đồng hồ và input giả, tick 100 Hz, snapshot xấp xỉ 33 Hz (lượng tử theo game tick), render 30/60/144 Hz, độ trễ và jitter giả lập. Input được sắp theo thời gian nhận, không đưa vị trí tương lai vào predictor. Tốc độ di chuyển của hai bên do source tính, có/không boost >=50; nguồn tính slowdown theo `shotSlowdownTimer` của người bắn và súng. Vật cản là AABB dựng thủ công với type `stone_01`, không phải hình/map thật. Lịch bắn thử 500 ms, kiểm tra cooldown và giảm timer thủ công, **không chạy đầy đủ `WeaponManager.update` hoặc `Player.handleInput`**. Player giả không nhận sát thương/chết, không có reload, target không bắn; duyệt đạn bằng `Bullet.update` và đếm bản ghi damage mà không áp dụng sát thương. Mô phỏng không có chọn mục tiêu, controller/smoothing, cơ chế ownership, `features.mjs` hay full Wallcheck. Khi có tường vẫn bắn thử, do đó đây không phải test quyết định bật/tắt aim của Wallcheck. Không có map thực, tầng/cầu thang, team, va chạm động khác, replication visibility, packet loss, queue server hay gameplay live.

Smoke test kiểm tra trúng mục tiêu không vật cản, tường chặn đạn, nhân vật va tường dừng lại, shotgun nhiều pellet, boost làm nhân vật chạy nhanh hơn, thời gian frame/packet ở ba FPS, và lặp lại kết quả theo seed. `npm test` chạy smoke khi checkout pinned có sẵn, nếu không sẽ skip rõ ràng.

## Kết quả một ma trận

9 cặp chuyển động, khoảng cách ban đầu 20/45 wu, 3 súng, 2 mức boost cho hai bên, 4 cặp down/up 30/30, 80/80, 30/120, 120/30 ms, 3 FPS, có/không tường, 3 seed cố định (thay đổi pha và RNG). So sánh `current` với ngắm trực tiếp vị trí snapshot: **51.840 phát/model**, cùng input, seed và lịch. Phát bắn cùng quỹ đạo tương quan, đây không phải kiểm định độc lập hay tỷ lệ trúng live.

| Nhóm | Direct | Predictor hiện tại |
|---|---:|---:|
| Tổng | 13,6% | 22,2% |
| Không tường | 22,7% | 33,3% |
| Có tường | 4,6% | 11,1% |
| Mục tiêu chạy thẳng | 4,6% | 40,9% |
| Mục tiêu đổi hướng 90° | 12,5% | 14,8% |
| Mục tiêu không đều, người bắn dừng/chạy | 17,7% | 15,5% |
| Mục tiêu chạy lùi, người bắn đổi hướng | 8,6% | 6,8% |
| MP5 / AK-47 / M870 | 12,9% / 14,6% / 13,1% | 22,6% / 21,8% / 22,4% |

Nhóm mục tiêu không đều và lùi chỉ ứng với một kiểu người bắn trong ma trận, không phải kết luận tổng quát về mọi kiểu di chuyển. Tường gây chặn cho khoảng 52,1% phát predictor trong nhóm có tường; với shotgun một phát có thể đồng thời có pellet chạm tường và pellet chạm mục tiêu. Trọng số của nhóm súng không bằng nhau vì cooldown M870 làm ít phát hơn. Tất cả súng đều chịu spread/recoil nguồn, nhưng không phải toàn bộ súng hay phụ kiện. Không thay runtime dựa chỉ vào các số này: cần kiểm tra regression đa dạng hơn và tích hợp sender/client thực tế trước khi đánh giá live.

## Chạy lại

```sh
npm ci
git clone --no-checkout https://github.com/survev/survev.git .cache/survev
git -C .cache/survev checkout 3edee7e8bd07fda8a63905aab4c45b595b684a80
node scripts/benchmark-source-duel.mjs --smoke
npm run benchmark:source
npm run check
```

Không clone đè checkout đã tồn tại; có thể truyền đường dẫn khác cho `node scripts/benchmark-source-duel.mjs /duong/dan/survev`. Source upstream là mã được thực thi trong test, chỉ dùng revision đã ghim và kiểm tra checkout sạch; không chạy script cài đặt của source.
