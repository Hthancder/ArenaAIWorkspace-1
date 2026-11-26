# Kiểm tra quỹ đạo đạn theo tick source

## Điều source biết và client nhận

Ở source ghim `3edee7e8…`, `Game.update` cập nhật player trước bullet; `Bullet.update` tiến một đoạn theo `dt * speed` rồi kiểm tra đoạn đó với vị trí/hitbox player tại tick. Player partial serializer gửi vị trí và hướng 8-bit, không gửi lệnh di chuyển tương lai hay đồng hồ server ở đây. `WeaponManager.fireWeapon` dùng định nghĩa súng/đạn và perk, nhưng cũng có spread ngẫu nhiên, điều kiện first-shot và pellet jitter; single có thể buffer trong cửa sổ cooldown. Source là quy tắc, không phải bản ghi trạng thái server hay các phím đối thủ sẽ nhấn trong tương lai. Client/network/FPS làm quan sát chậm; RTT ước tính không cho biết chính xác độ trễ từng chiều. Những điểm này không chứng minh nguyên nhân hụt trong trận cụ thể.

Đã so sánh source public mới `08346fb6…`: `weaponManager.ts`, `bullet.ts`, `game.ts` và serializer liên quan giống bản ghim; `player.ts` khác một dòng kiểm tra loại vũ khí khi drop. Không chứng minh server live đang chạy phiên bản này.

## Kiểm thử tick

Chạy `node scripts/benchmark-tick-intercept.mjs .cache/survev`. Trích **`Bullet.update` thật** và dùng collaborator giả cho map, đối tượng đích, và kiểm tra đoạn/circle; không chạy game, network, wall hay toàn bộ `checkForCollisions`. Đo với tốc độ đạn 66/100/182, khoảng cách 20/50/100, radius 0,5/1, tick 30/60 Hz và 10 pha input; fixture cho predictor biết chính xác vị trí/vận tốc hiện tại, không cho biết tương lai. Các mốc đảo/đứng lại là input tổng hợp, không đo gameplay.

- Đi thẳng tốc độ 1, 2 hoặc 12: cả nghiệm hiện tại và hai nghiệm bù ±nửa tick đạt 360/360 ca trong fixture lý tưởng.
- Đảo hướng tốc độ 4 sau 150 ms: nghiệm hiện tại 89/360, bù +nửa tick 81/360, bù −nửa tick 98/360. Các số là kết quả mô phỏng collider giả, không phải hit rate thực.
- Hai quỹ đạo có cùng lịch sử và cùng 150 ms đầu nhưng sau đó đi thẳng hoặc đảo chiều có thể cách nhau hơn hai radius tại thời điểm đạn đến. Không có lựa chọn điểm ngắm duy nhất nào bảo đảm trúng cả hai nếu các hành động tương lai đó không quan sát được.

Thử nghiệm này chưa chỉ ra một bù tick giúp mọi tình huống, nên **không thay đổi predictor runtime** dựa vào nó. Cũng không nên hiểu nó là bằng chứng rằng bản hiện tại không có bug; vẫn cần telemetry cùng tình huống hụt để phân biệt snapshot, FOV, wallcheck, profile, sender, thời điểm bắn/cooldown, network và spread. Kết quả liên quan mục tiêu chậm và các thử nghiệm giảm lead khác nằm tại `docs/kiem-tra-giat-va-lead-cham.vi.md`.
