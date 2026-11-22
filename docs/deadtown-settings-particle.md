# Ứng viên cài đặt hiệu ứng và gate particle

Trong APK Android ghim, `setting_save` và `setting_load` cùng truy cập bảy
global slot thông qua các key INI dưới đây. Cả hai đường: key không tồn tại
khi đọc và thiết lập mới, đặt mặc định 1.

| Slot native | INI section/key | Alias ứng viên |
|---:|---|---|
| 82 | feedback/feedback | `__dt_setting_feedback` |
| 83 | effect/interpolate | `__dt_setting_interpolate` |
| 84 | effect/soundeffect | `__dt_setting_soundeffect` |
| 85 | effect/crosshair | `__dt_setting_crosshair` |
| 86 | effect/shadow | `__dt_setting_shadow` |
| 87 | left/finger | `__dt_setting_finger` |
| 49 | effect/particle | `__dt_setting_particle` |

Alias là tên mới, không phải tên GML gốc đã được khôi phục. Chỉ riêng phần
đọc/ghi/bắt đầu của bảy setting này được bổ sung; chưa chứng minh toàn bộ hai
script cũ khớp native. UI thiết lập tương ứng còn thiếu, nên không coi các
setting đã có chức năng UI hoàn chỉnh.

Bốn export `particle_burst`, `_up`, `_up_size`, `_up_out` đọc global slot 49,
so với 0,5 và bỏ qua phần xử lý khi không lớn hơn ngưỡng. Source cũ bốn script
đã được bao bằng gate tương ứng, giữ nội dung cũ bên trong; điều này không
chứng minh các lời gọi và tham số bên trong hoàn toàn khớp native. Bộ kiểm
`tools/deadtown_settings_particle_evidence.py` ghim APK, hash export, chỉ dẫn
slot/đọc/ghi, chuỗi INI, mặc định và nhánh gate.

Probe VM riêng dùng INI và particle mock: đối chiếu mặc định, đọc/ghi qua mock,
nhánh 0, 0,5 và 1 cùng thứ tự gọi trong bốn script. Mock không chứng minh tệp
save thật, hạt/rendering, thao tác UI, gameplay, compiler GameMaker hay iOS.

Bổ sung gate bóng cho ba Draw event `par_solid`, `par_vehicle`, `obj_parcel`:
ARM đọc slot 86, sau khi tính vị trí bóng thì chỉ gọi `draw_sprite_ext` màu
đen alpha 0,5 khi slot > 0,5; `draw_self` vẫn gọi ở cả hai nhánh. Ứng viên
chỉ bao lệnh vẽ bóng, giữ tính vị trí và `draw_self` bên ngoài. Ba Draw event
`par_action`, `par_action_move`, `par_action_door` cũng có gate slot 86 cho
lệnh vẽ bóng, nhưng không có `draw_self` trong source cũ; không thêm lệnh đó.
`par_building` có gate cùng slot cho bóng mái, hai lệnh vẽ mái và mask sau đó
vẫn ngoài gate. `obj_player` cũng gate cả hai nhánh bóng nhân vật sau khi tính
vị trí; các lệnh vẽ nhân vật phía sau vẫn ngoài gate. Bằng chứng ARM ghim từng
export và nhánh; probe chỉ lấy các fragment và thay lệnh vẽ bằng bộ đếm, không
kiểm toàn event, renderer hoặc hình ảnh trên thiết bị.

## Feedback hướng di chuyển

Trong `obj_player:Draw:0` ARM32 tại `0x5db2d8`, slot 82 được lấy từ
`g_pGlobal`, giữ qua bước vẽ outline, rồi so sánh với 0,5 ở `0x5db6cc`;
nhánh không lớn hơn bỏ qua khối feedback. Với giá trị hữu hạn lớn hơn 0,5,
native gọi `gp_connect_check` tại `0x5db714`, bỏ qua khối nếu kết quả lớn hơn
0,5, sau đó kiểm tra ngưỡng khoảng cách và vẽ `spr_player_move` tại `0x5dbb44`.
Ứng viên giữ khối khoảng cách/vẽ từ source cũ và chỉ bọc hai điều kiện mới;
chưa chứng minh mọi biểu thức trong khối hoặc so sánh sát epsilon khớp native.
Probe VM thay gamepad, vị trí và lệnh vẽ bằng mock/bộ đếm, kiểm tra không gọi
gamepad khi setting tắt, đồng thời kiểm tra các nhánh gamepad và khoảng cách.
Nó không kiểm controller thật hay thao tác hiển thị trên Android/iOS. Alias
slot 82 là tên tự đặt; `gp_connect_check` cũng là ứng viên với giới hạn riêng.

Kết quả CI cần xem riêng; chưa tạo IPA.
