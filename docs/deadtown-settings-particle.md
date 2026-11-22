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
Kết quả CI cần xem riêng; chưa tạo IPA.
