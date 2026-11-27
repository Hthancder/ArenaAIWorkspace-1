# Rà soát aimbot và script công khai

## Tham khảo tĩnh

- [Survev-KrityHack](https://github.com/Drino955/Survev-Krityhack/tree/6b3d4b11c117fb286198d123a66c10e3edb084b3/src/plugins): dự đoán từ các khung hình render và tốc độ đạn, có fallback cố định khi thiếu định nghĩa. Dự án này tiếp tục dùng snapshot và định nghĩa đạn đã kiểm tra, không tự bịa tốc độ đạn.
- [waltertang27/Survev.io-aimbot, cheat.js](https://github.com/waltertang27/Survev.io-aimbot/blob/4abceea5cefa5c61da1859d68a49bb874da6cbea/cheat.js): chọn gần tâm màn hình và phát sự kiện chuột tổng hợp. Không chép cách hook prototype hoặc phát mousemove; chúng không giải quyết được quyền sở hữu native mouse và input sender của phiên bản source được kiểm tra.
- [aransaseelan/Survevio-Aimbot-Seethrough, mod.js](https://github.com/aransaseelan/Survevio-Aimbot-Seethrough/blob/0c6da4ec774e63335f55b6b4f6041770a460cfe5/mod.js): chọn mục tiêu gần con trỏ và phát sự kiện chuột; không chứng minh team/layer/cover hoặc trajectory. Chỉ tham khảo tĩnh, không chạy và không copy mã.
- `docs/duality_client.js` và source Survev pin `3edee7e8bd07fda8a63905aab4c45b595b684a80` vẫn là cơ sở đối chiếu chính. Không khẳng định script bên ngoài hay source pin phù hợp bản live hiện tại.

## Thay đổi

1. `SnapshotTracker` trước đây reset lịch sử nếu hai update được quan sát tại đúng cùng thời điểm `performance.now()`, dù code đã có nhánh gộp những update cách nhau dưới 8 ms. Giờ timestamp bằng nhau được gộp vào endpoint cuối cùng theo thứ tự, không chia cho thời gian 0; đồng hồ đi lùi vẫn reset, còn ước lượng tại thời điểm đi lùi bị từ chối. Nếu các snapshot thực sự bị dồn, khoảng thời gian server giữa chúng không biết được; phép fit này không tái tạo thời gian server và guard vận tốc/độ cũ vẫn có thể từ chối.
2. Khi Wallcheck bật **và Keep target tắt**, nếu ứng viên đầu bị chặn, thử các ứng viên còn lại trong giới hạn sẵn có thay vì bỏ aim ngay. Keep target vẫn chờ mục tiêu đang chọn như trước. Sender recheck chỉ kiểm tra đúng mục tiêu đã lập kế hoạch; nếu nó bị chặn hoặc mất hiệu lực thì trả input vật lý, không đổi target trong cùng packet và không bước smoothing thêm. Fire vẫn được giữ. Chỉ thử tối đa 6 ứng viên, ray smoothing vẫn có thể bị chặn, và các vật thể không được replicate không thể được kiểm tra.

## Kiểm thử và giới hạn

`npm run check`: 260 test đạt. Source fixture: 4 biến thể client, loot, 320 mô phỏng ném + 20 preview snowball, 568 cấu hình súng đều đạt. Benchmark aim và benchmark sự kiện chạy trên dữ liệu tổng hợp, có hồi quy khi đảo chiều/dừng; benchmark geometry Node registry 4000 vật thể median 0,829 ms, p95 1,158 ms mỗi solve (không phải FPS trình duyệt). Chưa kiểm tra trong trận live, chưa chứng minh hết giật hay tăng hitrate.
