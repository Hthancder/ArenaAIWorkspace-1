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

## Âm lượng và audio từ source cũ

Đối chiếu bổ sung nhánh `setting_load`/`setting_save` với ARM ghim: global
slot 66 dùng INI `sound/effect`, slot 75 dùng `sound/bgm`; cả hai có mặc định
0,5 khi key thiếu và khi tạo cài đặt mới. Source cũ dùng tên tương ứng
`global.setting_sound_effect` và `global.setting_bgm`; đây là đối chiếu theo
key và cách sử dụng, không phải chứng minh tên gốc YYC.

`audio_init` gán kết quả `audio_emitter_create` vào instance slot 216;
`audio_play` dùng cùng slot và global slot 66 cho `audio_emitter_gain`, sau đó
gọi `audio_play_sound_on`. Verifier ghim hash export, instruction và GOT, kiểm
hai nhánh mặc định, key INI cùng các fragment source. Đây là xác nhận một
phần source đã có, **không phải phục hồi script mới**; không gộp slot 66 với
slot 84 (`effect/soundeffect`), vì chưa chứng minh semantics slot 84.
Probe VM riêng thay INI và hai hàm audio bằng mock, kiểm giá trị, thứ tự gọi,
đối số và giá trị trả về; không kiểm thiết bị audio, âm lượng thực tế hay iOS.

Bốn export `particle_burst`, `_up`, `_up_size`, `_up_out` đọc global slot 49,
so với 0,5 và bỏ qua phần xử lý khi không lớn hơn ngưỡng. Source cũ bốn script
đã được bao bằng gate tương ứng, giữ nội dung cũ bên trong; điều này không
chứng minh các lời gọi và tham số bên trong hoàn toàn khớp native. Bộ kiểm
`tools/deadtown_settings_particle_evidence.py` ghim APK, hash export, chỉ dẫn
slot/đọc/ghi, chuỗi INI, mặc định và nhánh gate. Các phép quét ghi đè thanh
ghi/stack giải mã từng word ARM riêng để không dừng sớm ở literal pool; pool có
thể gây báo động giả, và phép quét không thay thế phân tích control-flow/alias.

Room Start `sys_global:Other:4` ARM32 tại `0x43b36c` đọc slot 83 và truyền
nguyên giá trị tới `texture_set_interpolation` qua hàm legacy. Source nay có
ứng viên event tương ứng, dùng alias tự đặt. Probe riêng chỉ thay hàm đó bằng
mock để kiểm tra đối số 0, 1 và 7, không xác minh GPU, interpolation thực tế,
thứ tự chuyển room trên thiết bị hay nguyên nhân vệt màu iOS.

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

## Khảo sát crosshair — chưa sửa source

`obj_player:Draw:64` ARM32 tại `0x5d2168` dài 37.228 byte; slot 85 được
lưu tại `[sp,#0x18]` và so sánh > 0,5 ở `0x5d7400`–`0x5d7418`. Nhánh
không lớn hơn nhảy qua một vùng có lời gọi `draw_line_crosshair` tại
`0x5d75a8`. Tuy nhiên một lời gọi cùng script đã xuất hiện trước gate tại
`0x5d4450`, nên không có cơ sở tắt toàn bộ event cũ khi setting tắt. Vùng
caller tương ứng chưa phục hồi; không thêm gate hay khẳng định hành vi GUI đã
khớp. Verifier ghim hash export, chuỗi instruction và địa chỉ relocation, quét
word ghi đè trực tiếp; đó không phải phân tích đầy đủ mọi đường nhánh hay stack
alias.

Script `draw_line_crosshair` còn thiếu nay có ứng viên riêng: ARM32 tại
`0x1cff00` lấy bốn tham số, gọi `point_direction` và `point_distance`, chọn
frame 1 khi khoảng cách vượt 100 (nhánh so sánh native dùng epsilon), ngược lại
frame 0; hai nhánh vẽ sprite native index 181 (`spr_crosshair`) tại hai tham số
đầu, xscale khoảng cách/100, yscale 1, góc từ `point_direction`, màu và alpha
lấy từ trạng thái vẽ. `tools/deadtown_crosshair_evidence.py` ghim hash export,
call relocation, hằng số, branch và tên/2 frame của sprite trong game data.
Source dùng tên sprite và biến local mới; riêng GML/runner/platform có thể khác
ở ngưỡng epsilon, số không hữu hạn, float và rendering. Chưa gắn script này vào
Draw GUI cũ vì các lời gọi và ngữ cảnh native chưa khôi phục. Probe VM dùng
mock cho phép tính và vẽ, đồng thời có hai ca riêng gọi `point_distance` và
`point_direction` thật trong runner desktop (ngang 50 và dọc 150 pixel); lệnh
vẽ vẫn mock. CI `45005225487` pass cả hai ca, kiểm frame, tỉ lệ và góc trong
đối số draw mock. Probe không chứng minh renderer hoặc caller event.

Kết quả CI cần xem riêng; chưa tạo IPA.
