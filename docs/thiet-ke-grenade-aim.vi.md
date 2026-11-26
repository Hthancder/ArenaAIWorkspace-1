# Grenade Aim — bản thử nghiệm

Trong **Main → Grenade Aim (thử nghiệm)** chọn một chế độ độc lập, mặc định Off:

- **Preview:** chỉ vẽ đường và vùng nổ danh định, không sửa input.
- **Assist:** kéo hướng và lực ném về nghiệm; dùng `Lực Assist bom (%)` riêng.
- **Lock:** đặt hướng và lực theo nghiệm danh định.

Assist/Lock có thể chọn **Giữ Fire** hoặc **Cầm bom**. Chế độ giữ Fire tiếp tục dùng fuse ước lượng cho gói nhả đang chờ gửi, sau đó trả quyền input. Chế độ cầm bom giả định ném ngay với fuse đầy khi chưa giữ. Mặc định người chơi tự giữ và nhả; tùy chọn tự thả chỉ hoạt động trong Lock, mặc định tắt và không bao giờ tự bắt đầu giữ Fire. Grenade timer tùy chọn độc lập.

FOV bom có thanh riêng; cấu hình cũ lần đầu được chuyển từ FOV súng. Trong khi giữ Fire, nhấn **Alt trái** (đổi được tại Keybinds → Hủy hỗ trợ bom lần này) để trả input ngắm về native cho đến khi gói nhả Fire được chuyển đi. Phím không tự nhả và không chặn xử lý phím của game; nếu trùng keybind game hãy đổi. Phím chỉ có tác dụng khi đang cầm slot bom và đã bật một chế độ Grenade Aim. Đây là cơ chế ưu tiên thủ công, không bảo đảm an toàn với fuse/mạng.

## Giới hạn quan trọng

Mọi kết quả là **ước lượng, chưa xác nhận server**; không dùng timer hoặc chỉ báo làm thời điểm giữ/nhả an toàn, không bảo đảm trúng hay tránh tự nổ. Thời gian fuse khi giữ dựa trên cạnh Fire chuyển cho sender, không phải xác nhận cook server. Mạng, tick, dự đoán mục tiêu, bề mặt, collider, góc/lực lượng tử và server live có thể khác. Đường nét đứt và chữ `ước lượng / chưa xác nhận` không chứng minh đường đi hay vụ nổ.

Mô hình hiện chỉ nhận throwable cookable, không va chạm nổ, không playerCollision, không heavyType, không force-max, không fuseVariance và aimDistance bằng 0; thực tế chủ yếu frag và MIRV nếu định nghĩa capture hợp lệ. Smoke, bom va chạm, vật biến hình và fuse đặc biệt không hỗ trợ. `amped_explosives`, thiếu perk, thiếu snapshot vận tốc mới (bao gồm người ném), thiếu contract map/terrain, target, vật cản, fuse hoặc loại bom thì không điều khiển. Danh sách vật thể chỉ gồm dữ liệu client đã nhận.

Mô hình dùng trọng lực/drag mặt đất phẳng theo source và dự đoán mục tiêu theo vận tốc hiện tại; không đoán tương lai đổi hướng. Kiểm tra đường đi 2D bảo thủ, coi vật cản trên đường là chặn, không tính nảy hoặc ném vượt vật thấp; surface được lấy từ `getGroundSurface` client tại các điểm rời rạc, không bảo đảm trùng `isOnWater` server, có thể bỏ sót vùng nước mỏng hoặc dữ liệu chưa nhân bản. Target có thể không có nghiệm hay nằm ngoài FOV. Thiếu thông tin thì trả input gốc; **Help → Refresh diagnostics → grenadeAim.last** giữ trạng thái lần thử cuối và tuổi của nó khi mở menu. Source server ghim gửi vị trí người chơi khi vị trí hoặc hướng thay đổi, nên đứng yên thường không có snapshot riêng. Grenade Aim có tracker riêng: sau khi đã biết người chơi, nếu các world update đầy đủ đến liên tục (cách nhau không quá 150 ms) mà không đề cập người đó, nó suy luận tạm thời vị trí không đổi; update thiếu, gián đoạn, xóa hoặc thay đối tượng thì xóa suy luận. Đây không phải xác nhận đồng hồ server: backlog, culling hay triển khai live khác source vẫn có thể gây sai, và nếu điều kiện không đạt thì Lock/tự thả vẫn có thể không hoạt động. Tracker súng không dùng suy luận này.

## Va chạm và nảy theo source

Có nảy tường: trong `server/src/game/objects/projectile.ts` của source ghim, với vật chắn cùng layer, còn sống, đủ cao và còn va chạm, bom không nổ khi chạm sẽ đổi hướng theo phản xạ qua pháp tuyến; tốc độ được nhân `max(1 + dot, 0.15)`. Server còn sửa vị trí khỏi vật cản, xử lý chiều cao/vật ở dưới, và kiểm tra đường quét tùy vận tốc. Ném cũng có bước chặn đoạn từ người đến bàn tay. Nảy không được mô phỏng trong solver hiện tại: đường đi chạm collider bị từ chối thay vì dự đoán cú nảy, vì hình học, vật cản và trạng thái server trên client có thể thiếu hoặc khác. Việc từ chối này chỉ áp dụng với đối tượng client quan sát được, không chứng minh đường thực sự trống.

Kiểm tra terrain lấy thêm mẫu giữa các điểm mô phỏng, cách nhau không quá 0,5 đơn vị, với giới hạn chi phí. Mẫu rời rạc vẫn có thể bỏ sót nước rất hẹp; `getGroundSurface` client cũng chưa chứng minh luôn khớp `isOnWater` server. Chỉ nhận các loại mặt đất đã biết từ source ghim; loại mới/không rõ bị từ chối. Đây không phải wallcheck hoặc mô phỏng nảy bảo đảm an toàn.

## Tự thả thử nghiệm

Chỉ bật riêng **Tự thả** khi muốn thử: cần Lock, cạnh Fire vật lý đã được gửi, scheduler ghi được, fuse cục bộ, RTT gần đây không quá 160 ms, vận tốc mới đủ mẫu, đối tượng giữ ổn định tối thiểu 200 ms, và nghiệm đường đi hợp lệ. Kiểm tra cùng hướng/lực tại fuse danh định và ±80 ms, từ chối tốc độ người ném hoặc mục tiêu lớn hơn 4 đơn vị/giây, mép bản đồ, va chạm hoặc terrain không rõ. Trong mô hình, bom phải nằm trên mặt đất trong vùng 0,75 đơn vị quanh mục tiêu liên tục từ 0,03 đến 0,5 giây trước nổ. Scheduler yêu cầu gửi tối đa khoảng 30 lần/giây trong lúc chờ, tùy FPS/mạng. Các ngưỡng là điều kiện bảo thủ thử nghiệm, không phải bằng chứng trúng.

Sau khi gửi gói nhả, script tiếp tục giữ `shootStart` và `shootHold` bằng false cho đến khi người chơi thực sự nhả Fire, tránh bắt đầu cook lại. Mất nghiệm sau khi đã chọn mục tiêu, đổi mục tiêu hoặc thao tác hủy thì nhường điều khiển hết lần giữ; nhấn Alt trái để hủy ngay. Khi không có cửa sổ hợp lệ, script không ép nhả: **bạn phải tự nhả kịp**, nếu không server vẫn có thể tự ném hoặc bom nổ. Cạnh Fire và RTT chỉ là dữ liệu client, không chứng minh server đã nhận cook hoặc fuse thực; các biến động mạng ngoài ±80 ms và thay đổi mục tiêu không thể loại trừ. Chưa kiểm chứng live, không dùng như cơ chế an toàn. `Help → Refresh diagnostics → grenadeAim.autoThrow.last` hiển thị pha và lý do ẩn danh gần nhất.

## Kiểm thử và nguồn

`node scripts/check-grenade-upstream.mjs .cache/survev` so sánh 320 quỹ đạo phẳng với `WeaponManager.throwThrowable` và `Projectile.update` của source `3edee7e8...`, với collaborators giả. `scripts/check-upstream.mjs` kiểm tra Lock và tự thả qua scheduler và InputMsg serializer source (terrain, snapshot và RTT giả), các chế độ minified, và độ lượng tử hóa input. Unit test bao gồm nhả một lần, chống cook lại, mất nghiệm, hủy, equip, thiếu terrain và kiểm tra đường. Không có kiểm thử live, không xác nhận server đã cook hay các điều kiện game mới nhất hoặc mọi terrain/đối tượng/perk.
